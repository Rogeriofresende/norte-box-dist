#!/usr/bin/env bash
# _bilhete_selo.sh — O SELO DO BILHETE (memoria entre sessoes que nao mente) do Norte-box (NRT-_990429).
# Sourceado pelo helper bin/nb-bilhete-selo (e, via Passo 2.5, pela skill /continuar antes de gravar).
#
# O BURACO QUE ESTA PECA FECHA: a skill /continuar salva um bilhete de "onde paramos" com linhas
#   - [x] <passo feito, com prova no disco (arquivo/commit/teste)>
# na secao "## Onde estamos". HOJE o "so marque [x] com prova" e SO um CONSELHO ao modelo — NADA
# verifica. Um bilhete pode JURAR "[x] feito: PR #42 aberto" ou "[x] pronto: soma.py" sem NENHUM
# commit/arquivo no disco, e a /norte-retomar le como verdade. E o furo do RELATO FABRICADO: um agente
# jura "feito/testado/PR" sem prova; a proxima sessao confia. Este e o mesmo furo que ja mordeu a Norte
# (subagente que FABRICOU um build inteiro com "8/8 testes" e "preview real", tudo inexistente).
#
# O QUE ESTA PECA FAZ: recebe o TEXTO do bilhete (rascunho) e, pra CADA linha "- [x] ..." da secao
# "## Onde estamos", EXTRAI a referencia de artefato citada e CONFERE no disco (no cwd do projeto):
#   - CAMINHO DE ARQUIVO (token com "/" ou terminando em .py/.js/.ts/.sh/.md/.json/.html/.csv/.txt/...):
#     `test -e` no cwd. Existe -> mantem [x] + "✓ conferido: existe". Nao existe -> REBAIXA pra
#     "- [ ] ⚠ nao achei no disco: <ref>" ANTES de gravar (o NUCLEO da peca — mata o "soma.py" fabricado).
#   - COMMIT (hex de 7..40, ou "commit <sha>"): `git cat-file -e <sha>^{commit}` no repo do cwd.
#     Existe -> mantem [x] + "✓ conferido". Nao existe -> REBAIXA (mata o "PR #42" com sha inventado).
#   - PR #N / referencia que NAO da pra conferir localmente -> marca 🟡 "nao-verificavel" (FAIL-OPEN:
#     NAO rebaixa o que nao da pra checar, mas TAMBEM nao abencoa). Honesto.
#   - [x] SEM nenhum artefato conferivel (vago, "implementei a logica") -> MANTEM a linha mas ANEXA
#     "(sem prova no disco pra conferir)". Honesto: nao pune, nao abencoa.
#
# MOLDURA HONESTA (licao das pecas anteriores — NAO overclaim): esta peca so atesta que "o arquivo/
# commit CITADO existe E o bilhete o cita". NAO atesta que o trabalho foi feito CERTO — um artefato
# real mas IRRELEVANTE passa (existe soma.py, mas soma.py pode estar vazio/errado). A copy diz so isso.
# O selo mata a MENTIRA OBVIA (citou algo que nem existe), nao mede corretude.
#
# LEIS (nao-negociaveis):
#   - LOCAL, ZERO REDE: le e escreve so o disco local (o cwd do projeto do usuario). O bilhete e o
#     conteudo do PROPRIO projeto do usuario e NUNCA sai da maquina — nada de telemetria/rede aqui.
#   - FAIL-HONEST (fail-CLOSED da confianca): so mantem [x] quando o artefato citado EXISTE de fato.
#     Na duvida do que da pra checar, marca 🟡 nao-verificavel (nem rebaixa nem abencoa).
#   - FAIL-OPEN da sessao: se ESTA peca quebra (sem git, erro de parse, sem os utilitarios), NAO trava
#     o /continuar — devolve o rascunho anotado como nao-verificavel e segue. A peca nunca prende o bilhete.
#   - DADO E DADO, NUNCA COMANDO: a referencia extraida vira ARGUMENTO de `test -e` / `git cat-file -e`.
#     Um payload de shell / path traversal DENTRO da ref NUNCA e executado. `set -u`, sem eval, sem
#     expandir a ref como comando. Path traversal que ESCAPA o projeto (../.. , caminho absoluto fora
#     do cwd) NAO abencoa nada de fora: e marcado 🟡 nao-verificavel (fora do escopo do projeto).
#   - Portabilidade macOS (bash 3.2, SEM arrays associativos/mapfile/${v^^}). jq disponivel mas nao e
#     necessario aqui (a peca so mexe em texto).
#
# KILL-SWITCH: NORTE_BILHETE=0 desliga a peca (inerte: devolve o rascunho INTACTO, como hoje).
set -u

# --- kill-switch: NORTE_BILHETE=0 -> inerte (passthrough do rascunho, exatamente como hoje). ---
_nbs_desligado() {
  case "${NORTE_BILHETE:-1}" in
    0|no|nao|off|false) return 0 ;;
    *) return 1 ;;
  esac
}

# _nbs_repo_ok — 0 se o cwd esta dentro de um repo git utilizavel (pra conferir commit). Fail-open:
# se `git` nao existe ou nao e repo, os checks de commit viram 🟡 nao-verificavel (nunca travam).
_nbs_repo_ok() {
  command -v git >/dev/null 2>&1 || return 1
  git rev-parse --git-dir >/dev/null 2>&1 || return 1
  return 0
}

# _nbs_e_traversal <ref> — 0 (SIM, escapa o projeto) se a ref e um caminho absoluto OU contem ".."
# de subida. DADO E DADO: nao executamos nada; so decidimos NAO abencoar um `test -e` que apontaria
# pra fora da arvore do projeto (ex: ../../etc/passwd existe de verdade, mas nao e prova do trabalho
# DESTE projeto). Escapou -> 🟡 nao-verificavel (fora de escopo), nunca ✓ conferido.
_nbs_e_traversal() {
  local _r="${1:-}"
  case "$_r" in
    /*) return 0 ;;                 # caminho absoluto = fora do escopo do projeto
    *../*|*/..|..) return 0 ;;      # sobe de nivel = pode escapar o projeto
    *) return 1 ;;
  esac
}

# _nbs_parece_caminho <token> — 0 se o token PARECE um caminho de arquivo: tem "/" OU termina numa
# extensao conhecida de artefato. So a forma do token (nao toca o disco aqui).
_nbs_parece_caminho() {
  local _t="${1:-}"
  case "$_t" in
    */*) return 0 ;;
    *.py|*.js|*.ts|*.tsx|*.jsx|*.mjs|*.cjs|*.sh|*.bash|*.md|*.json|*.html|*.htm|*.css|*.csv|*.txt|*.yml|*.yaml|*.toml|*.sql|*.go|*.rs|*.rb|*.java|*.c|*.h|*.cpp|*.php) return 0 ;;
    *) return 1 ;;
  esac
}

# _nbs_e_commit <token> — 0 se o token e um sha de commit plausivel: 7..40 hex puros. So a forma.
_nbs_e_commit() {
  local _t="${1:-}" _n
  case "$_t" in
    *[!0-9a-fA-F]*) return 1 ;;   # tem char que nao e hex -> nao e sha
  esac
  _n=${#_t}
  [ "$_n" -ge 7 ] && [ "$_n" -le 40 ]
}

# _nbs_confere_uma <tipo> <valor> — confere UMA ref no disco. Ecoa "ok" | "nao" | "naover".
#   path   -> test -e no cwd (traversal fora do projeto -> naover, nunca ok).
#   commit -> git cat-file -e <sha>^{commit} (sem git -> naover).
# So le o disco. DADO E DADO: <valor> e argumento de test -e / git cat-file, NUNCA comando.
_nbs_confere_uma() {
  local _tipo="${1:-}" _val="${2:-}"
  case "$_tipo" in
    path)
      if _nbs_e_traversal "$_val"; then printf 'naover\n'; return 0; fi
      if [ -e "./$_val" ] || [ -e "$_val" ]; then printf 'ok\n'; else printf 'nao\n'; fi
      ;;
    commit)
      if _nbs_repo_ok; then
        if git cat-file -e "${_val}^{commit}" >/dev/null 2>&1; then printf 'ok\n'; else printf 'nao\n'; fi
      else
        printf 'naover\n'
      fi
      ;;
    *) printf 'naover\n' ;;
  esac
  return 0
}

# _nbs_avaliar_linha <corpo-da-linha> — avalia TODAS as referencias de artefato citadas no corpo (o
# que vem depois do "- [x] ") e devolve UM veredito em "estado|ref_visivel", com a regra
# "O PIOR HONESTO VENCE" (anti-fabricacao):
#   nao    -> ALGUM artefato conferivel (caminho/commit) foi CITADO e NAO existe no disco. GANHA de
#             tudo: um PR nao-verificavel na MESMA linha NAO resgata um arquivo/commit fabricado.
#             (ref_visivel = o primeiro que faltou.) -> a skill REBAIXA a linha.
#   ok     -> tem PELO MENOS UM conferivel e TODOS os conferiveis existem. -> mantem [x] "✓ conferido".
#   naover -> nao ha nenhum conferivel, mas ha ref que nao da pra checar local (PR, traversal, sem git).
#             -> mantem [x] "🟡 nao-verificavel".
#   vago   -> nenhuma ref (nem conferivel, nem PR). -> mantem [x] "(sem prova no disco pra conferir)".
# So le TEXTO+disco. Tokeniza por espaco/pontuacao comum (sem regex de shell perigoso, sem eval).
_nbs_avaliar_linha() {
  local _corpo="${1:-}"
  local _prev="" _w _clean _r
  local _falta_ref="" _tem_ok=0 _tem_naover=0
  # normaliza separadores comuns em espaco pra tokenizar. set -f desliga glob (o "*" do dado nao expande).
  set -f
  # shellcheck disable=SC2086
  set -- $(printf '%s' "$_corpo" | tr ',();:[]"'"'"'`<>' '           ')
  set +f

  for _w in "$@"; do
    _clean="$_w"
    # (a) commit rotulado: "commit <sha>" | "sha <sha>".
    case "$_prev" in
      commit|Commit|COMMIT|sha|SHA|Sha)
        _clean="$(printf '%s' "$_w" | tr -d '#')"
        if _nbs_e_commit "$_clean"; then
          _r="$(_nbs_confere_uma commit "$_clean")"
          case "$_r" in
            ok) _tem_ok=1 ;;
            nao) [ -z "$_falta_ref" ] && _falta_ref="$_clean" ;;
            naover) _tem_naover=1 ;;
          esac
          _prev="$_w"; continue
        fi
        ;;
    esac
    # (b) PR/pull-request #N -> nao-verificavel local.
    case "$_w" in
      \#[0-9]*) _tem_naover=1; _prev="$_w"; continue ;;
    esac
    # (c) token que parece caminho de arquivo.
    if _nbs_parece_caminho "$_w"; then
      _r="$(_nbs_confere_uma path "$_w")"
      case "$_r" in
        ok) _tem_ok=1 ;;
        nao) [ -z "$_falta_ref" ] && _falta_ref="$_w" ;;
        naover) _tem_naover=1 ;;
      esac
      _prev="$_w"; continue
    fi
    # (d) sha solto (7..40 hex) — so conta como commit se NAO parece uma palavra comum. Ja cobrimos
    # o rotulado em (a); aqui pega "entregue em a1b2c3d4e5" sem rotulo. Exige repo pra virar conferivel.
    if _nbs_e_commit "$_w"; then
      _r="$(_nbs_confere_uma commit "$_w")"
      case "$_r" in
        ok) _tem_ok=1 ;;
        nao) [ -z "$_falta_ref" ] && _falta_ref="$_w" ;;
        naover) _tem_naover=1 ;;
      esac
    fi
    _prev="$_w"
  done

  # O PIOR HONESTO VENCE.
  if [ -n "$_falta_ref" ]; then printf 'nao|%s\n' "$_falta_ref"; return 0; fi
  if [ "$_tem_ok" -eq 1 ]; then printf 'ok|\n'; return 0; fi
  if [ "$_tem_naover" -eq 1 ]; then printf 'naover|\n'; return 0; fi
  printf 'vago|\n'
  return 0
}

# _nbs_despir_nota <resto> — recupera o texto ORIGINAL do passo, removendo QUALQUER nota que ESTA
# peca escreve. LOSSLESS: devolve exatamente o texto que o usuario/modelo escreveu, sem a nota.
#
# POR QUE EXISTE (o coracao do fix NRT-_990429-furo): a idempotencia ANTIGA pulava a linha por
# SUBSTRING de texto livre ("✓ conferido: existe" / "nao achei no disco" ...). Mas esse texto e
# 100% controlado pelo modelo — bastava ele ESCREVER "✓ conferido: existe" numa linha cujo arquivo
# NAO existe pra a conferencia ser PULADA e o [x] forjado sobreviver. O RELATO FABRICADO de volta.
# A cura: a nota NUNCA vem do texto; vem SEMPRE do disco. Pra isso, primeiro DESPIMOS a nota
# (recuperando o passo original), depois RE-AVALIAMOS o original pelo disco e reescrevemos a nota
# CORRETA por cima. Um "✓" escrito a mao num arquivo inexistente VIRA rebaixado; um rebaixamento
# mentiroso num arquivo que existe VOLTA pra ✓. A nota reflete o disco, nunca o que estava escrito.
#
# Formatos de nota que a peca produz (removidos aqui, na ordem — o mais especifico primeiro):
#   (nao)    resto inteiro = "⚠ nao achei no disco: <ref> (...) — era: <ORIGINAL>"  -> original apos " — era: ".
#   (ok)     "<ORIGINAL> — ✓ conferido: existe"
#   (naover) "<ORIGINAL> — 🟡 nao-verificavel (nao da pra conferir aqui)"
#   (vago)   "<ORIGINAL> (sem prova no disco pra conferir)"
#   (forja inversa) marcador de rebaixamento FORJADO a mao no fim de uma linha [x]:
#            "<ORIGINAL> — ⚠ nao achei no disco: <ref>" (nao e o formato real da peca) -> remove o sufixo.
# So mexe em TEXTO. Sem rede, sem eval.
_nbs_despir_nota() {
  local _r="${1:-}"
  # (nao) rebaixamento REAL da peca: o passo original esta apos a ULTIMA " — era: ".
  case "$_r" in
    "⚠ nao achei no disco: "*" — era: "*) printf '%s' "${_r##* — era: }"; return 0 ;;
  esac
  # (ok)
  case "$_r" in
    *" — ✓ conferido: existe") printf '%s' "${_r% — ✓ conferido: existe}"; return 0 ;;
  esac
  # (naover)
  case "$_r" in
    *" — 🟡 nao-verificavel (nao da pra conferir aqui)") printf '%s' "${_r% — 🟡 nao-verificavel (nao da pra conferir aqui)}"; return 0 ;;
  esac
  # (vago)
  case "$_r" in
    *" (sem prova no disco pra conferir)") printf '%s' "${_r% (sem prova no disco pra conferir)}"; return 0 ;;
  esac
  # (forja inversa) sufixo de rebaixamento forjado a mao no fim de uma linha ainda marcada [x].
  # % (nao %%) remove o MENOR sufixo -> ancora na ULTIMA ocorrencia " — ⚠ nao achei no disco: ".
  case "$_r" in
    *" — ⚠ nao achei no disco: "*) printf '%s' "${_r% — ⚠ nao achei no disco: *}"; return 0 ;;
  esac
  printf '%s' "$_r"
}

# _norte_bilhete_selar — LE o rascunho do bilhete no stdin e ESCREVE no stdout a VERSAO CONFERIDA.
#   - kill-switch NORTE_BILHETE=0 -> passthrough intacto.
#   - mexe nas linhas "- [x] ..." DENTRO da secao "## Onde estamos" (ate a proxima "## ") E TAMBEM
#     nas "- [ ] ⚠ nao achei no disco: ..." que a PROPRIA peca ja rebaixou (pra re-avaliar: se o
#     arquivo passou a existir, PROMOVE de volta pra [x] ✓).
#   - fora da secao, ou linhas que nao sao esses dois tipos, passam INTACTAS.
#   - fail-open: qualquer erro inesperado -> devolve o que der; nunca trava (o /continuar precisa gravar).
#   - A NOTA E FUNCAO PURA DO DISCO, NUNCA DO TEXTO: pra cada linha, DESPE a nota que a peca teria
#     escrito (recupera o passo original), RE-AVALIA o original pelo disco e reescreve a nota CORRETA
#     por cima. Isso MATA o furo do "✓ conferido" escrito a mao num arquivo inexistente (o relato
#     fabricado) e torna a idempotencia NATURAL (2a passada despe a propria nota, re-avalia o MESMO
#     disco, produz a MESMA nota — sem duplicar).
# Ecoa no STDERR um resumo curto (conferidas/rebaixadas/nao-verificaveis/vagas) pra a skill mostrar.
_norte_bilhete_selar() {
  if _nbs_desligado; then
    cat
    printf '🟡 selo do bilhete desligado (NORTE_BILHETE=0): gravei o rascunho como esta.\n' >&2
    return 0
  fi

  local _in
  _in="$(cat 2>/dev/null)" || { printf '%s' ""; return 0; }

  local _n_ok=0 _n_nao=0 _n_naover=0 _n_vago=0
  local _dentro=0
  local _linha _pre _resto _vered _estado _refvis

  # processa linha a linha. IFS vazio + read -r preserva espacos e barras invertidas.
  # (o "|| [ -n ... ]" garante que a ultima linha sem \n final tambem seja processada.)
  while IFS= read -r _linha || [ -n "$_linha" ]; do
    # controle de secao: entra em "## Onde estamos", sai em qualquer outro cabecalho "## ".
    case "$_linha" in
      "## Onde estamos"*|"##Onde estamos"*)
        _dentro=1; printf '%s\n' "$_linha"; continue ;;
      "## "*|"##"[!#]*)
        _dentro=0; printf '%s\n' "$_linha"; continue ;;
    esac

    if [ "$_dentro" -ne 1 ]; then
      printf '%s\n' "$_linha"; continue
    fi

    # dentro da secao: mexe em item de checklist MARCADO "- [x] ..." (aceita "- [X]" e o traco
    # com/sem espaco) OU numa linha "- [ ] ⚠ nao achei no disco: ..." que a PROPRIA peca ja rebaixou
    # (pra re-avaliar: se o arquivo passou a existir, promove de volta). _pre = o prefixo ate o "] "
    # (preserva indentacao/traco); _resto = o texto do passo. So casa linha que COMECA com traco de
    # bullet (nao qualquer "[x]" solto). Um "[ ]" comum (TODO nunca feito) NAO casa aqui -> passa intacto.
    case "$_linha" in
      "- [x] "*|"- [X] "*|"-[x] "*|"-[X] "*|"  - [x] "*|"  - [X] "*)
        _pre="${_linha%%] *}] "
        _resto="${_linha#*] }"
        ;;
      "- [ ] ⚠ nao achei no disco: "*|"-[ ] ⚠ nao achei no disco: "*|"  - [ ] ⚠ nao achei no disco: "*)
        _pre="${_linha%%] *}] "
        _resto="${_linha#*] }"
        ;;
      *)
        printf '%s\n' "$_linha"; continue ;;
    esac

    # A NOTA E FUNCAO PURA DO DISCO, NUNCA DO TEXTO (o fix do furo do relato fabricado):
    #   1. DESPE qualquer nota que a peca teria escrito -> recupera o passo ORIGINAL (lossless).
    #   2. RE-AVALIA o original pelo disco (SEMPRE — nunca confia na nota que estava la).
    #   3. reescreve a nota CORRETA por cima, e normaliza o prefixo pra [x] (o disco decide o estado,
    #      nao o "[x]"/"[ ]" que estava escrito). Um "✓" a mao num arquivo inexistente vira rebaixado;
    #      um rebaixamento mentiroso num arquivo que existe volta pra ✓. Idempotencia = NATURAL.
    local _orig _prelimpo _pren
    _orig="$(_nbs_despir_nota "$_resto")"
    _prelimpo="$(printf '%s' "$_pre" | sed 's/\[[ xX]\]/[x]/')"

    _vered="$(_nbs_avaliar_linha "$_orig")"
    _estado="${_vered%%|*}"
    _refvis="${_vered#*|}"

    case "$_estado" in
      ok)
        printf -- '%s%s — ✓ conferido: existe\n' "$_prelimpo" "$_orig"
        _n_ok=$((_n_ok+1)) ;;
      nao)
        # O NUCLEO DA PECA: citou artefato que NAO existe no disco -> REBAIXA pra [ ] ⚠ ANTES de gravar.
        # troca "[x]" por "[ ]" no prefixo normalizado, preservando indentacao/traco.
        _pren="$(printf '%s' "$_prelimpo" | sed 's/\[[xX]\]/[ ]/')"
        printf -- '%s⚠ nao achei no disco: %s (o bilhete marcava feito, mas o disco nao mostra) — era: %s\n' "$_pren" "$_refvis" "$_orig"
        _n_nao=$((_n_nao+1)) ;;
      naover)
        printf -- '%s%s — 🟡 nao-verificavel (nao da pra conferir aqui)\n' "$_prelimpo" "$_orig"
        _n_naover=$((_n_naover+1)) ;;
      vago|*)
        printf -- '%s%s (sem prova no disco pra conferir)\n' "$_prelimpo" "$_orig"
        _n_vago=$((_n_vago+1)) ;;
    esac
  done <<EOF
$_in
EOF

  printf 'selo do bilhete: %s conferidas ✓, %s rebaixadas ⚠, %s nao-verificaveis 🟡, %s sem prova.\n' \
    "$_n_ok" "$_n_nao" "$_n_naover" "$_n_vago" >&2
  return 0
}
