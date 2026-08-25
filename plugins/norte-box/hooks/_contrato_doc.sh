#!/usr/bin/env bash
# _contrato_doc.sh — FONTE UNICA do PORTAO "documento→checklist" (tipo juridico) do Norte-box.
# ADITIVO ao _provar.sh (codigo roda) e ao portao planilha (planilha confere): aqui a entrega e um PAR
# de TEXTO — um DOCUMENTO (o texto a conferir) + um CHECKLIST (a lista de itens que ele TEM que cobrir).
# O motor confere ITEM A ITEM, sem rodar codigo do cliente: a conferencia e do PROPRIO Norte-box.
#
# A ideia (padaria): antes de dizer "o documento cobre tudo", a caixa CONFERE de verdade cada item do
# checklist contra o texto do documento, e so pinta 🟢 PROVADO quando a conferencia fecha. Sem prova ->
# continua 🟡 NAO-PROVADO dizendo QUAL item falhou e por que.
#
# FORMATO DO CHECKLIST (uma linha por item; linhas vazias e comecadas por '#' sao ignoradas):
#   <descricao> :: <ancora>          -> o item so CONFERE se <ancora> (texto literal) existir no documento.
#   NAO: <descricao> :: <ancora>     -> o item AFIRMA que <ancora> esta AUSENTE. Se <ancora> APARECER no
#                                       documento, o checklist CONTRADIZ a fonte -> ALUCINACAO -> reprova.
#   <descricao>                      -> sem "::": a ancora e a PROPRIA descricao (o texto tem que aparecer).
# A comparacao de ancora e por SUBSTRING, sem diferenciar maiuscula/minuscula nem acento (dobra o texto pra
# uma forma comparavel). "Achar no texto" e a prova de COBERTURA; "afirmar ausencia do que existe" e a
# prova ANTI-ALUCINACAO.
#
# SELO (mesma lei honesta dos outros portoes): PROVADO so quando COBERTURA completa E zero item orfao E
# zero contradicao. O selo le o RESULTADO REAL (o exit do motor + a prova gravada), nunca a presenca de
# arquivo. Reusa o marcador provado:true do _provar.sh (prova.artefato dentro da arvore controlada +
# vinculo A3 pelo hash do CONTEUDO do documento conferido) — trocar a prova por uma de outro documento
# nao abre verde.
#
# LEIS (nao-negociaveis, iguais aos outros passos):
#   - PRIVADO POR PADRAO: a prova mora em $HOME/.norte-box/provas/<sessao>/; NUNCA sai da maquina. Sem rede.
#   - HONESTO POR PADRAO (fail-honest): so escreve provado:true quando a conferencia REALMENTE fechou.
#     Item orfao / contradicao / arquivo ausente -> mantem amarelo e devolve o motivo real.
#   - KILL-SWITCH: NORTE_CONTRATO_DOC=0 desliga o portao (volta ao comportamento de hoje).
#   - Portabilidade macOS (bash 3.2). Precisa de jq pra marcar o selo; sem jq, confere e reporta mas nao
#     grava verde (degrada sem travar). Nao usa dado como comando (set -u; sem eval).
set -u

# _norte_contrato_dobra <texto> — ecoa o texto numa forma COMPARAVEL: minuscula + acentos comuns pt-BR
# rebaixados pra letra base. Assim "Endereço" casa "endereco". So pra COMPARAR ancora — nunca pra exibir.
_norte_contrato_dobra() {
  # tr faz minuscula ASCII; o sed troca os acentos pt-BR mais comuns (bash 3.2 nao tem ${x,,} unicode).
  printf '%s' "${1:-}" \
    | tr 'A-Z' 'a-z' \
    | sed \
      -e 's/á/a/g;s/à/a/g;s/â/a/g;s/ã/a/g;s/ä/a/g' \
      -e 's/é/e/g;s/è/e/g;s/ê/e/g;s/ë/e/g' \
      -e 's/í/i/g;s/ì/i/g;s/î/i/g;s/ï/i/g' \
      -e 's/ó/o/g;s/ò/o/g;s/ô/o/g;s/õ/o/g;s/ö/o/g' \
      -e 's/ú/u/g;s/ù/u/g;s/û/u/g;s/ü/u/g' \
      -e 's/ç/c/g' \
      -e 's/Á/a/g;s/À/a/g;s/Â/a/g;s/Ã/a/g' \
      -e 's/É/e/g;s/Ê/e/g;s/Í/i/g;s/Ó/o/g;s/Ô/o/g;s/Õ/o/g;s/Ú/u/g;s/Ç/c/g'
}

# _norte_contrato_ancora_fraca <ancora-JA-DOBRADA> — ecoa "1" se a ancora e FRACA demais pra conferir
# (FURO A do Val): comprimento util < 3 depois de tirar espacos, OU e uma stop-word isolada (a, e, o, de,
# da, do, no, na, um, uma, os, as, com, sem, por, que, ...). Ancora fraca casa em qualquer texto -> nao
# prova nada. Recebe o texto JA dobrado (minuscula/sem acento) pra comparar stop-word de forma estavel.
_norte_contrato_ancora_fraca() {
  local _a; _a="$(printf '%s' "${1:-}" | tr -d '[:space:]')"
  # comprimento util minimo: < 3 chars sem espaco = ancora trivial.
  [ "${#_a}" -lt 3 ] && { printf '1'; return 0; }
  # stop-words pt-BR isoladas (a ancora INTEIRA e a stop-word) — nao conferem nada de especifico.
  case "$_a" in
    a|e|o|as|os|um|uma|uns|de|da|do|das|dos|no|na|nos|nas|em|com|sem|por|que|se|ao|aos|ou|the|and|of|to|for|is|it)
      printf '1'; return 0 ;;
  esac
  printf '0'
}

# _norte_contrato_cobertura_suja <doc-dobrado> <ancora-dobrada> — ecoa "1" se a ancora positiva CASA no
# documento MAS esta ADJACENTE a uma negacao numa janela CURTA antes da ancora (FURO B do Val): "nao ha
# clausula de foro" contem "foro", mas afirma a AUSENCIA. Olha os ~40 chars imediatamente antes de cada
# ocorrencia da ancora; se algum trecho tiver uma palavra de negacao, a cobertura e SUSPEITA (nao limpa).
# 100% local (awk/sed), sem rede. Retorna "0" se a cobertura e limpa em pelo menos uma ocorrencia.
_norte_contrato_cobertura_suja() {
  local _docd="${1:-}" _ancd="${2:-}"
  [ -n "$_ancd" ] || { printf '0'; return 0; }
  # quebra o documento em ocorrencias: tudo ANTES de cada ocorrencia da ancora vira uma "cauda" (o contexto
  # a esquerda). Se QUALQUER ocorrencia tiver cauda LIMPA (sem negacao nos ~40 chars finais), a cobertura
  # existe de verdade -> "0". So marca suja ("1") se TODAS as ocorrencias vierem coladas numa negacao.
  # negacoes cobertas: nao, não, sem, inexiste, inexistente, nenhum(a), nao ha, nao possui, nao existe,
  # nao tem, nao consta, nao preve, nao contem, ausencia de, isento de.
  local _tmpd
  _tmpd="$(printf '%s' "$_docd" | awk -v anc="$_ancd" '
    BEGIN{ n=length(anc); if(n==0){print "LIMPA"; exit} suja=0; tem=0 }
    {
      s=$0; pos=index(s, anc);
      while(pos>0){
        tem=1;
        start=pos-40; if(start<1) start=1;
        ctx=substr(s, start, pos-start);           # ~40 chars imediatamente antes da ancora
        if(ctx ~ /(^| )(nao|sem|inexiste|inexistente|nenhum|nenhuma|isento|ausencia)( |$)/ ||
           ctx ~ /nao (ha|possui|existe|tem|consta|preve|contem|há)/ ||
           ctx ~ /(ausencia|isento) de/){
          suja=1;
        } else {
          print "LIMPA"; exit;                       # achou uma ocorrencia LIMPA -> cobertura vale
        }
        rest=substr(s, pos+n);
        base=pos+n; s=rest; pos=index(s, anc);
        if(pos>0) pos=pos;                           # continua varrendo a mesma linha
      }
    }
    END{ if(tem==1 && suja==1) print "SUJA"; else print "LIMPA" }
  ')"
  case "$_tmpd" in
    SUJA) printf '1' ;;
    *)    printf '0' ;;
  esac
}

# _norte_contrato_cobertura_vazia <doc-dobrado> <ancora-dobrada> — ecoa "1" se a ancora positiva CASA no
# documento MAS vem SEGUIDA de um marcador de nao-preenchido TERMINAL numa janela CURTA DEPOIS dela, na
# MESMA LINHA (residuo do FURO B, simetrico: a negacao vem ANTES da ancora; o marcador de vazio vem DEPOIS).
# Ex: "clausula de foro: (nao preenchido)" contem "clausula de foro", mas a exigencia esta ESCRITA e VAZIA.
# Olha os ~50 chars imediatamente depois de cada ocorrencia da ancora; o marcador so conta se vier COLADO
# (entre a ancora e o marcador so pode haver separadores [ \t:=().\[\]-]). 100% local (awk/sed), sem rede.
#
# REGRA DO MARCADOR TERMINAL (FURO da Val, NRT-_990380): o marcador so marca VAZIA quando for TERMINAL —
# depois dele, ate o fim da janela/linha, NAO sobra conteudo substantivo (so separadores/pontuacao/espaco).
# Se sobrar CONTINUACAO util (>= 3 chars nao-separadores depois do marcador), a clausula esta PREENCHIDA ->
# cobertura LIMPA. Assim "foro: a definir em comum acordo entre as partes" (continua) = LIMPA, mas
# "foro: a definir" (seco) = VAZIA. Cuidado: o ")" de "(nao preenchido)" e pontuacao/separador, NAO conta
# como continuacao.
# Retorna "1" SO se TODAS as ocorrencias vierem seguidas de marcador TERMINAL de vazio; "0" se QUALQUER
# ocorrencia e limpa (resgate por ocorrencia — igual a suja). NAO trata "ancora no fim da linha, sem nada
# depois" como vazio (titulo de clausula com o texto na linha seguinte e padrao legitimo).
# KILL-SWITCH granular: NORTE_CONTRATO_VAZIO=0 -> retorna "0" direto (desliga so esta defesa).
# LIMITE CONHECIDO (honesto): marcador na LINHA SEGUINTE (fora da janela same-line) ainda escapa — igual ao
# limite da defesa de negacao. Isso e "leitura de sentido" (NLP), adiada de proposito. Nao finge resolver.
_norte_contrato_cobertura_vazia() {
  # kill-switch granular: desliga SO esta defesa -> volta ao comportamento de hoje.
  case "${NORTE_CONTRATO_VAZIO:-1}" in
    0|no|nao|off|false) printf '0'; return 0 ;;
  esac
  local _docd="${1:-}" _ancd="${2:-}"
  [ -n "$_ancd" ] || { printf '0'; return 0; }
  # marcadores de nao-preenchido (JA em forma DOBRADA — minuscula/sem acento, pois o doc ja passou pela
  # dobra). NAO inclui "na" cru (perigoso em pt). O casamento e: ancora + so separadores + marcador.
  # separadores permitidos entre a ancora e o marcador: espaco, tab, : = ( ) . [ ] -
  local _vazio
  _vazio="$(printf '%s' "$_docd" | awk -v anc="$_ancd" '
    BEGIN{
      n=length(anc); if(n==0){print "LIMPA"; exit} vazio=0; tem=0;
      # separadores COLADOS aceitos entre a ancora e o marcador de PALAVRA (0+): [ \t:=().[]-]
      # (inclui [ ] porque marcadores tipo "[preencher aqui]" vem entre colchetes).
      sep="^[ \t:=().[\\]-]*";
      # separadores pro marcador CHECKBOX "[ ]" — SEM colchetes (senao o proprio [ ] seria comido como
      # separador e o marcador nunca casaria). So espaco/tab/: = ( ) . - antes do "[ ]".
      sepcb="^[ \t:=().-]*";
      # descascador de CONTINUACAO: tudo que NAO conta como conteudo util depois do marcador. Inclui
      # separadores, pontuacao e fecha-colchete/parentese (o ")" de "(nao preenchido)" nao e continuacao).
      cont_strip="^[ \t:=().[\\]<>{}_,;!?*/|\"-]*";
    }
    # conta os chars UTEIS que sobram DEPOIS do marcador (a "tail"). >= 3 = continuacao real (preenchido).
    function tem_continuacao(tail,   c){
      sub(cont_strip, "", tail);   # descasca separadores/pontuacao COLADOS logo apos o marcador
      # o que sobrou e conteudo util? conta so os nao-separadores (uma palavra real tem >= 3 chars).
      gsub(/[ \t:=().[\]<>{}_,;!?*\/|"-]/, "", tail);
      c = length(tail);
      return (c >= 3) ? 1 : 0;
    }
    {
      s=$0; pos=index(s, anc);
      while(pos>0){
        tem=1;
        # janela CURTA (~50 chars) DEPOIS da ancora, na MESMA linha.
        after=substr(s, pos+n, 50);
        # descasca os separadores COLADOS logo depois da ancora; o resto tem que COMECAR num marcador.
        rest_after=after; sub(sep, "", rest_after);
        # trecho pro checkbox: descasca separadores SEM colchetes -> o "[ ]" fica visivel.
        cb_after=after; sub(sepcb, "", cb_after);
        hit=0; mk="";   # mk = a regex do marcador que casou (pra achar a tail DEPOIS dele).
        # marcadores checados no INICIO do trecho ja sem separadores (colado a ancora).
        if(rest_after ~ /^nao preenchido/){ hit=1; mk="^nao preenchido"; }
        else if(rest_after ~ /^a preencher/){ hit=1; mk="^a preencher"; }
        else if(rest_after ~ /^a definir/){ hit=1; mk="^a definir"; }
        else if(rest_after ~ /^preencher aqui/){ hit=1; mk="^preencher aqui"; }
        else if(rest_after ~ /^pendente/){ hit=1; mk="^pendente"; }
        else if(rest_after ~ /^tbd/){ hit=1; mk="^tbd"; }
        else if(rest_after ~ /^n\/a/){ hit=1; mk="^n\\/a"; }
        else if(rest_after ~ /^n\/d/){ hit=1; mk="^n\\/d"; }
        else if(rest_after ~ /^xxx/){ hit=1; mk="^xxx+"; }        # come todos os x (xxx, xxxx...)
        else if(rest_after ~ /^___/){ hit=1; mk="^_+"; }          # come todos os underscores (___ e +)
        else if(cb_after ~ /^\[ *\]/){ hit=1; }                   # [ ] (checkbox vazia) — tratado abaixo
        if(hit==1){
          # REGRA DO MARCADOR TERMINAL: so e VAZIA se, depois do marcador, NAO sobrar continuacao util.
          if(mk != ""){
            tail=rest_after; sub(mk, "", tail);   # o que vem DEPOIS do marcador de palavra
          } else {
            # checkbox "[ ]": a tail e o que vem depois do "]".
            tail=cb_after; sub(/^\[ *\]/, "", tail);
          }
          if(tem_continuacao(tail)==1){
            print "LIMPA"; exit;                 # marcador NAO-terminal (tem conteudo depois) -> preenchido
          }
          vazio=1;                               # marcador TERMINAL -> cobertura vazia
        } else {
          print "LIMPA"; exit;                   # achou uma ocorrencia LIMPA -> cobertura vale
        }
        # avanca pra a proxima ocorrencia na mesma linha.
        s=substr(s, pos+n); pos=index(s, anc);
      }
    }
    END{ if(tem==1 && vazio==1) print "VAZIA"; else print "LIMPA" }
  ')"
  case "$_vazio" in
    VAZIA) printf '1' ;;
    *)     printf '0' ;;
  esac
}

# _norte_contrato_conferir <documento> <checklist>
#   O NUCLEO. Le o documento e o checklist e confere item a item, SEM rodar codigo do cliente.
#   Imprime, no stdout, um relatorio linha-a-linha:
#     OK      <descricao>          -> item coberto (ancora achada) / ausencia confirmada (NAO:)
#     ORFAO   <descricao>          -> COBERTURA falhou: a ancora nao existe no documento
#     SUSPEIT <descricao>          -> cobertura suja (FURO B: ancora colada numa negacao ANTES dela) OU
#                                      cobertura vazia (FURO E: ancora seguida de marcador de nao-preenchido)
#     ALUC    <descricao>          -> ANTI-ALUCINACAO: o checklist afirma ausencia de algo que EXISTE (contradiz a fonte)
#   e uma ultima linha RESUMO: total=<n> ok=<n> orfaos=<n> aluc=<n>.
#   RETORNO: 0 se TODOS os itens conferiram (0 orfao, 0 suspeita, 0 aluc); 1 se qualquer item falhou;
#   2 se pre-condicao falhou (arquivo ausente / mesmo arquivo doc==checklist / ancora fraca / checklist
#   sem nenhum item valido).
_norte_contrato_conferir() {
  local _doc="${1:-}" _chk="${2:-}"
  if [ -z "$_doc" ] || [ ! -f "$_doc" ]; then
    printf 'ERRO: o documento indicado nao existe.\n'; return 2
  fi
  if [ -z "$_chk" ] || [ ! -f "$_chk" ]; then
    printf 'ERRO: o checklist indicado nao existe.\n'; return 2
  fi
  # FURO C do Val: doc==checklist (mesmo arquivo) faz cada ancora casar a si mesma -> verde vazio. Recusa
  # quando o CANONICO (realpath) dos dois for o mesmo (pega tambem symlink e caminho relativo pro mesmo alvo).
  local _cdoc _cchk
  if command -v _norte_realpath >/dev/null 2>&1; then
    _cdoc="$(_norte_realpath "$_doc" 2>/dev/null || printf '%s' "$_doc")"
    _cchk="$(_norte_realpath "$_chk" 2>/dev/null || printf '%s' "$_chk")"
  else
    _cdoc="$_doc"; _cchk="$_chk"
  fi
  if [ "$_cdoc" = "$_cchk" ]; then
    printf 'ERRO: o documento e o checklist sao o MESMO arquivo — cada item casaria a si mesmo (verde vazio). Aponte dois arquivos diferentes.\n'
    return 2
  fi
  # dobra o documento inteiro UMA vez (comparacao case/acento-insensivel por substring).
  local _docdobra
  _docdobra="$(_norte_contrato_dobra "$(cat "$_doc" 2>/dev/null)")"

  local _total=0 _ok=0 _orfaos=0 _suspeita=0 _aluc=0
  local _linha _neg _desc _ancora _ancdobra
  # le o checklist linha a linha (IFS vazio preserva espacos; -r nao interpreta barra).
  while IFS= read -r _linha || [ -n "$_linha" ]; do
    # ignora linha vazia (so espacos) e comentario '#'
    case "$_linha" in
      ''|'#'*) continue ;;
    esac
    # so-espacos -> ignora
    case "$(printf '%s' "$_linha" | tr -d '[:space:]')" in '') continue ;; esac

    # prefixo NAO: (afirma AUSENCIA). Aceita "NAO:" no comeco, com espaco opcional depois.
    _neg=0
    case "$_linha" in
      NAO:*|nao:*|Nao:*|'NÃO:'*|'não:'*|'Não:'*)
        _neg=1
        _linha="$(printf '%s' "$_linha" | sed -E 's/^[Nn][Aa][ÃãOo]{0,1}[Oo]{0,1}: *//; s/^[Nn][ÃãAa][Oo]: *//')"
        ;;
    esac

    # separa "descricao :: ancora"; sem "::", a ancora e a propria descricao.
    if printf '%s' "$_linha" | grep -q '::'; then
      _desc="$(printf '%s' "$_linha" | sed 's/ *::.*$//')"
      _ancora="$(printf '%s' "$_linha" | sed 's/^[^:]*:: *//')"
    else
      _desc="$_linha"; _ancora="$_linha"
    fi
    # tira espacos das pontas da ancora e da descricao
    _ancora="$(printf '%s' "$_ancora" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    _desc="$(printf '%s' "$_desc" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    [ -n "$_ancora" ] || continue   # item sem ancora util -> nao conta

    _ancdobra="$(_norte_contrato_dobra "$_ancora")"

    # FURO A do Val: ancora FRACA (curta demais / stop-word isolada) casa em qualquer texto -> nao prova
    # nada. Um item com ancora fraca torna o CHECKLIST INVALIDO (nao da pra conferir com honestidade).
    if [ "$(_norte_contrato_ancora_fraca "$_ancdobra")" = "1" ]; then
      printf 'ERRO: ancora fraca demais pra conferir: "%s" (item "%s"). Use uma ancora especifica (>= 3 chars, nao pode ser stop-word).\n' "$_ancora" "$_desc"
      return 2
    fi

    _total=$((_total+1))

    # a ancora existe no documento?
    if printf '%s' "$_docdobra" | grep -qF -- "$_ancdobra"; then
      if [ "$_neg" -eq 1 ]; then
        # o checklist AFIRMOU ausencia, mas a ancora APARECE -> contradiz a fonte -> alucinacao.
        _aluc=$((_aluc+1)); printf 'ALUC  %s (o documento CONTEM "%s", mas o checklist afirma que NAO)\n' "$_desc" "$_ancora"
      elif [ "$(_norte_contrato_cobertura_suja "$_docdobra" "$_ancdobra")" = "1" ]; then
        # FURO B do Val: a ancora positiva SO aparece colada numa negacao ("nao ha ... foro") -> a fonte
        # NEGA o item, nao o cobre. Cobertura suja -> nao conta como limpa (derruba o verde).
        _suspeita=$((_suspeita+1)); printf 'SUSPEIT %s (o documento so cita "%s" DENTRO de uma negacao — a fonte NEGA, nao cobre)\n' "$_desc" "$_ancora"
      elif [ "$(_norte_contrato_cobertura_vazia "$_docdobra" "$_ancdobra")" = "1" ]; then
        # FURO E (NRT-_990380): a exigencia esta ESCRITA mas VAZIA ("clausula de foro: (nao preenchido)").
        # A ancora casa, mas vem seguida de marcador de nao-preenchido -> nao cobre. Reusa o status SUSPEIT
        # e o contador de suspeita (nao muda o formato do RESUMO nem o runtime do _estreia.sh).
        _suspeita=$((_suspeita+1)); printf 'SUSPEIT %s (a exigencia esta ESCRITA mas VAZIA — "%s" seguida de marcador de nao-preenchido)\n' "$_desc" "$_ancora"
      else
        _ok=$((_ok+1)); printf 'OK    %s\n' "$_desc"
      fi
    else
      if [ "$_neg" -eq 1 ]; then
        # afirmou ausencia e de fato esta ausente -> confere.
        _ok=$((_ok+1)); printf 'OK    %s (ausencia confirmada)\n' "$_desc"
      else
        # deveria estar coberto e nao esta -> orfao (cobertura falhou).
        _orfaos=$((_orfaos+1)); printf 'ORFAO %s (o documento NAO cobre "%s")\n' "$_desc" "$_ancora"
      fi
    fi
  done < "$_chk"

  if [ "$_total" -eq 0 ]; then
    printf 'ERRO: o checklist nao tem nenhum item valido pra conferir.\n'; return 2
  fi
  printf 'RESUMO: total=%s ok=%s orfaos=%s suspeitas=%s aluc=%s\n' "$_total" "$_ok" "$_orfaos" "$_suspeita" "$_aluc"
  if [ "$_orfaos" -eq 0 ] && [ "$_suspeita" -eq 0 ] && [ "$_aluc" -eq 0 ]; then
    return 0
  fi
  return 1
}

# _norte_contrato_doc_provar <documento> <checklist> [sessao]
#   O PORTAO completo: confere (nucleo acima), grava a prova LOCAL na arvore controlada e — SO se a
#   conferencia fechou (exit 0) — marca provado:true na fichinha (o UNICO caminho pro 🟢). Fail-honest.
#   RETORNO: 0 PROVOU / 1 NAO PROVOU (item falhou) / 2 nao deu pra provar (pre-condicao / kill-switch).
#   Depende de _provar.sh (sourceado ao lado): usa _norte_provas_raiz, _norte_provar_slug,
#   _norte_provar_marcar_provado. Depende de _situacao.sh: _norte_prova_hash_arquivo (vinculo A3).
_norte_contrato_doc_provar() {
  local _doc="${1:-}" _chk="${2:-}" _sess="${3:-}"
  # kill-switch: NORTE_CONTRATO_DOC=0 desliga -> volta ao comportamento de hoje.
  case "${NORTE_CONTRATO_DOC:-1}" in
    0|no|nao|off|false)
      printf '🟡 o portao "documento confere" nao esta ligado nesta maquina (NORTE_CONTRATO_DOC=0).\n'
      return 2 ;;
  esac
  if [ -z "$_doc" ] || [ ! -f "$_doc" ]; then
    printf '🟡 nao consegui provar: o documento indicado nao existe.\n'; return 2
  fi
  if [ -z "$_chk" ] || [ ! -f "$_chk" ]; then
    printf '🟡 nao consegui provar: o checklist indicado nao existe.\n'; return 2
  fi

  # confere ITEM A ITEM (nucleo).
  local _relatorio _rc
  _relatorio="$(_norte_contrato_conferir "$_doc" "$_chk")"; _rc=$?
  if [ "$_rc" -eq 2 ]; then
    printf '🟡 nao consegui provar: %s\n' "$(printf '%s' "$_relatorio" | tail -1)"
    return 2
  fi

  # arvore CONTROLADA das provas (mesma do motor — a unica que o selo aceita).
  local _raiz _sslug _dir _ts _prova
  if command -v _norte_provas_raiz >/dev/null 2>&1; then _raiz="$(_norte_provas_raiz)"; else _raiz="${HOME}/.norte-box/provas"; fi
  if command -v _norte_provar_slug >/dev/null 2>&1; then _sslug="$(_norte_provar_slug "${_sess:-sessao}")"; else _sslug="sessao"; fi
  [ -n "$_sslug" ] || _sslug="sessao"
  _ts="$(date -u +%Y%m%dT%H%M%SZ 2>/dev/null || echo t)"
  _dir="${_raiz}/${_sslug}"
  mkdir -p "$_dir" 2>/dev/null || { printf '🟡 nao consegui gravar a prova (disco nao gravavel).\n'; return 2; }
  _prova="${_dir}/prova-${_ts}.txt"

  # vinculo A3 (anti-reuso): hash do CONTEUDO do DOCUMENTO conferido. Trocar a prova por uma de OUTRO
  # documento faz o hash divergir -> o selo mantem amarelo.
  local _ehash=""
  if command -v _norte_prova_hash_arquivo >/dev/null 2>&1; then
    _ehash="$(_norte_prova_hash_arquivo "$_doc" 2>/dev/null || true)"
  fi
  # FURO D do Val (auditoria): a prova tambem grava o HASH do CHECKLIST (contra QUAL lista o verde foi
  # dado) e o RESUMO (total/ok/orfaos/suspeitas/aluc). O entrega_hash (documento) continua intacto (A3).
  local _chkhash=""
  if command -v _norte_prova_hash_arquivo >/dev/null 2>&1; then
    _chkhash="$(_norte_prova_hash_arquivo "$_chk" 2>/dev/null || true)"
  fi
  local _resumo=""
  _resumo="$(printf '%s' "$_relatorio" | grep -E '^RESUMO:' | head -1 | sed 's/^RESUMO: *//')"

  # grava a prova LOCAL (mesmo cabecalho do motor pra o selo/"Ver rodar" lerem igual).
  {
    printf 'PROVA norte-box (portao documento->checklist)\n'
    printf 'quando: %s\n' "$(date -u +%FT%TZ 2>/dev/null || echo t)"
    printf 'tipo: doc+checklist\n'
    printf 'exit: %s\n' "$_rc"
    printf 'entrega_hash: %s\n' "$_ehash"
    printf 'checklist_hash: %s\n' "$_chkhash"
    printf 'resumo: %s\n' "$_resumo"
    printf '---- saida (conferencia item a item) ----\n'
    printf '%s\n' "$_relatorio"
  } > "$_prova" 2>/dev/null

  if [ "$_rc" -eq 0 ]; then
    # PROVOU: so aqui escreve o verde (o marcador re-valida arvore+symlink; o selo re-valida no read).
    if command -v _norte_provar_marcar_provado >/dev/null 2>&1; then
      _norte_provar_marcar_provado "$_prova" "$_ehash" 2>/dev/null || true
    fi
    printf '✅ conferi assim: passei o checklist item a item no documento e TODOS conferiram.\n'
    printf '   conferido:\n'
    printf '%s\n' "$_relatorio" | sed 's/^/   /' | head -30
    printf 'NB_PROVA_ARTEFATO=%s\n' "$_prova"
    return 0
  else
    # NAO PROVOU: fichinha continua amarela; a prova guarda QUAL item falhou.
    printf '🟡 ainda nao provei: o documento NAO cobre o checklist inteiro (ou o checklist contradiz a fonte).\n'
    printf '   o que falhou:\n'
    printf '%s\n' "$_relatorio" | grep -E '^(ORFAO|SUSPEIT|ALUC|RESUMO)' | sed 's/^/   /' | head -30
    printf 'NB_PROVA_ARTEFATO=%s\n' "$_prova"
    return 1
  fi
}
