#!/usr/bin/env bash
# _ja_tentei.sh — O "JA TENTEI ISSO?" (busca nos bilhetes ANTIGOS do proprio usuario, por termos) do
# Norte-box (GAP 5 fatia 1, NRT-_990148). Sourceado pelo helper bin/nb-ja-tentei. Rode ANTES de comecar um
# trabalho: passa as PALAVRAS do que voce vai fazer e a peca mostra os bilhetes de handoff ANTIGOS que
# casam com essas palavras — pra voce nao re-resolver algo que ja tentou (e talvez ja descobriu que nao
# deu, ou como deu).
#
# O BURACO QUE ESTA PECA FECHA: a pessoa senta pra atacar um problema ("vou consertar o scraper do OLX")
# sem lembrar que ha 3 semanas ja mexeu nisso e deixou um bilhete de "onde paramos". O historico existe
# (em ~/.claude/handoffs), mas ninguem varre ANTES de comecar — o custo e re-descobrir do zero. Esta peca e
# a varredura barata: casa as palavras do trabalho de agora × os bilhetes locais, ranqueia por RECENCIA, e
# mostra os 5 mais novos que batem, com data + nome + uma linha de amostra. Uma PISTA pra abrir o bilhete
# certo, nao um veredito.
#
# MOLDURA HONESTA (o Val cobra — NAO overclaim, esta na copy da linha tambem):
#   - A peca so casa PALAVRA (string fixa, sem entender o assunto). Ela NAO le/entende o conteudo do bilhete
#     nem julga se e o MESMO problema. "Casou" = a palavra aparece no arquivo, nada mais.
#   - Casamento por acaso e possivel (um bilhete que menciona "olx" de passagem casa com a busca "olx").
#     Por isso e PISTA pra CONFERIR o bilhete, NUNCA a conclusao de que "ja resolvi, pode pular".
#   - So olha os bilhetes LOCAIS do proprio usuario (~/.claude/handoffs). Nao le notes/, nem git, nem
#     MEMORY.md, nem nada da rede — isso e escopo de outra fatia. Ausencia de match NAO prova que e novo.
#
# LEIS (nao-negociaveis, iguais aos outros passos):
#   - LOCAL, ZERO REDE: le so os *.md de um diretorio local (os bilhetes do PROPRIO usuario). NUNCA sai da
#     maquina, nada de telemetria/rede aqui (nenhum cliente HTTP, socket ou similar).
#   - FAIL-OPEN (NUNCA trava, NUNCA erro): dir inexistente/vazio, sem termo util, sem match -> mensagem
#     honesta no stdout e exit 0. A peca so INFORMA; jamais impede o trabalho de comecar. exit 0 SEMPRE.
#   - DADO E DADO, NUNCA COMANDO: os termos vem de "$@" e sao SO argumentos de `grep -F` (string fixa: um
#     termo com .*[ / $(...) NUNCA vira regex nem comando). `--` antes do termo (um termo com "-" nao vira
#     flag). `set -u`, sem eval, `set -f` no tokenizador (o "*" do dado nao expande).
#   - Portabilidade macOS (bash 3.2, SEM arrays associativos/mapfile/readarray/${v^^}). SEM jq.
#
# KILL-SWITCH do mecanismo: NORTE_JA_TENTEI=0 -> a peca fica INERTE (nada no stdout, exit 0), como se nao
# existisse.
#
# ENV (pro teste apontar pra uma fixture): NB_JA_TENTEI_DIR=<dir> troca o diretorio de bilhetes
# (default: $HOME/.claude/handoffs).
set -u

# --- kill-switch: NORTE_JA_TENTEI=0 -> inerte (nada no stdout). ---
_njt_desligado() {
  case "${NORTE_JA_TENTEI:-1}" in
    0|no|nao|off|false) return 0 ;;
    *) return 1 ;;
  esac
}

# _njt_dir — ecoa o diretorio de bilhetes (env NB_JA_TENTEI_DIR ou o default ~/.claude/handoffs). So texto.
_njt_dir() {
  printf '%s' "${NB_JA_TENTEI_DIR:-$HOME/.claude/handoffs}"
}

# _njt_stopword <token-minusculo> — 0 (SIM, e stopword) se o token e uma palavra comum PT/EN que nao ajuda a
# casar (vira ruido: casaria com quase todo bilhete). Comparacao de token INTEIRO, nunca substring. So a
# forma (nao toca disco/rede). O chamador ja passou o token em minusculo.
_njt_stopword() {
  case "${1:-}" in
    # PT
    para|com|que|dos|das|uma|uns|umas|isso|esse|essa|esses|essas|este|esta|estes|estas|\
    pra|por|per|nos|nas|num|numa|aos|ate|sem|sob|sobre|entre|mais|menos|muito|pouco|\
    ele|ela|eles|elas|seu|sua|seus|suas|meu|minha|nao|sim|foi|era|ser|ter|tem|fez|faz|\
    mas|nem|ou|se|ja|la|ca|de|do|da|no|na|em|ao|as|os) return 0 ;;
    # EN
    the|and|for|with|that|this|these|those|from|into|onto|over|under|about|\
    was|were|are|been|being|has|have|had|did|does|not|but|nor|yet|its|his|her|\
    you|your|our|out|off|per|via) return 0 ;;
    *) return 1 ;;
  esac
}

# _njt_uteis <termos...> — ecoa, UM POR LINHA, os termos UTEIS (>=3 chars e nao-stopword), em minusculo,
# DEDUPADOS, na ordem de chegada. DADO E DADO: os termos entram por "$@" e nunca sao avaliados como comando;
# aqui so filtramos e minusculizamos (tr, sem ${v^^} — bash 3.2). set -u ativo.
_njt_uteis() {
  local _t _low _vistos=""
  for _t in "$@"; do
    [ -n "$_t" ] || continue
    # minusculiza (tr, portavel bash 3.2 — nada de ${v,,}/${v^^}).
    _low="$(printf '%s' "$_t" | tr 'ABCDEFGHIJKLMNOPQRSTUVWXYZ' 'abcdefghijklmnopqrstuvwxyz')"
    # descarta termos com menos de 3 chars.
    [ "${#_low}" -ge 3 ] || continue
    # descarta stopwords comuns PT/EN.
    _njt_stopword "$_low" && continue
    # dedupe: guarda em _vistos cercado por " | " pra casar o token inteiro (nao substring).
    case " $_vistos " in
      *" $_low "*) ;;                        # ja visto -> pula
      *) _vistos="$_vistos $_low"; printf '%s\n' "$_low" ;;
    esac
  done
  return 0
}

# _njt_mtime <arquivo> — ecoa o mtime em segundos-epoch (BSD `stat -f %m` do macOS OU GNU `stat -c %Y` do
# Linux). Ecoa 0 se nenhum funcionar (fail-open: entra no fim do ranking, nunca trava). So le metadado local.
_njt_mtime() {
  local _f="${1:-}" _m=""
  [ -n "$_f" ] || { printf '0'; return 0; }
  _m="$(stat -f %m "$_f" 2>/dev/null || true)"       # BSD/macOS
  if [ -z "$_m" ]; then
    _m="$(stat -c %Y "$_f" 2>/dev/null || true)"     # GNU/Linux
  fi
  case "$_m" in
    ''|*[!0-9]*) printf '0' ;;
    *) printf '%s' "$_m" ;;
  esac
  return 0
}

# _njt_data_de <epoch> — ecoa a data legivel (YYYY-MM-DD HH:MM) de um epoch. Trata BSD (-r) e GNU (-d @).
# Ecoa "?" se nao der (fail-open). So formatacao local.
_njt_data_de() {
  local _e="${1:-0}" _d=""
  case "$_e" in ''|*[!0-9]*) _e=0 ;; esac
  [ "$_e" -gt 0 ] || { printf '?'; return 0; }
  _d="$(date -r "$_e" '+%Y-%m-%d %H:%M' 2>/dev/null || true)"           # BSD/macOS
  if [ -z "$_d" ]; then
    _d="$(date -d "@$_e" '+%Y-%m-%d %H:%M' 2>/dev/null || true)"        # GNU/Linux
  fi
  [ -n "$_d" ] && printf '%s' "$_d" || printf '?'
  return 0
}

# _njt_amostra <arquivo> <termo> — ecoa a 1a linha do arquivo que CONTEM <termo> (grep -i -F, dado e dado),
# aparada e truncada em ~120 chars. Ecoa vazio se nenhuma linha bate (nao deveria acontecer se casou, mas
# fail-open). So le TEXTO local.
_njt_amostra() {
  local _f="${1:-}" _termo="${2:-}" _linha=""
  [ -n "$_f" ] && [ -f "$_f" ] || { printf ''; return 0; }
  # -F string fixa (o termo NUNCA vira regex), -i sem-caixa, -m1 so a 1a, -- termo como dado (nunca flag).
  _linha="$(grep -i -F -m1 -- "$_termo" "$_f" 2>/dev/null || true)"
  [ -n "$_linha" ] || { printf ''; return 0; }
  # apara espacos/tab do inicio (marcadores de markdown ficam, tudo bem — e so amostra) e \r do CRLF.
  _linha="$(printf '%s' "$_linha" | tr -d '\r' | sed 's/^[[:space:]]*//')"
  # trunca em ~120 chars (portavel: cut por bytes; um bilhete e ASCII/UTF-8, so uma amostra).
  if [ "${#_linha}" -gt 120 ]; then
    _linha="$(printf '%s' "$_linha" | cut -c1-120)…"
  fi
  printf '%s' "$_linha"
  return 0
}

# _njt_casa <dir> <termos-uteis-um-por-linha> — ecoa, UM POR LINHA, os arquivos .md de <dir> que casam com
# TODOS os termos uteis (AND). Estrategia (bash 3.2, sem arrays associativos): a lista de candidatos comeca
# como TODOS os *.md do dir e vai sendo FILTRADA termo a termo com `grep -l -i -F -- <termo> <candidatos...>`
# (o resultado de um vira a entrada do proximo). Zero candidatos em qualquer passo -> resultado vazio (nenhum
# arquivo casa TODOS). DADO E DADO: -F string fixa + -- antes do termo. Nomes de arquivo com espaco: NAO ha
# risco de word-split porque os candidatos sao passados via posicionais ("$@"), nunca re-split de string.
_njt_casa() {
  local _dir="${1:-}"; shift
  # 1) candidatos iniciais = todos os *.md do dir (glob seguro; se nao houver, nullglob-ish via teste -f).
  #    set -f OFF aqui: precisamos do glob de *.md expandir. Mas os NOMES resultantes sao caminhos reais
  #    do disco, nao dado-do-usuario — o dado-do-usuario (termos) so entra depois via grep -F.
  local _cand=() _f
  for _f in "$_dir"/*.md; do
    [ -f "$_f" ] || continue          # sem match, o glob fica literal -> o teste -f descarta
    _cand+=("$_f")
  done
  [ "${#_cand[@]}" -gt 0 ] || { return 0; }   # dir sem .md -> nada a casar

  # 2) filtra termo a termo (AND). Cada passo: grep -l lista os que contem ESTE termo, dentre os candidatos.
  local _termo _out _novos
  local _oldifs="$IFS"
  while IFS= read -r _termo || [ -n "$_termo" ]; do
    [ -n "$_termo" ] || continue
    # grep -l -i -F -- <termo> <candidatos...>: DADO E DADO (F string fixa; -- termo nunca vira flag).
    # Se algum candidato tem espaco no nome, ele vai como um posicional inteiro (aspas nos "${_cand[@]}").
    _out="$(grep -l -i -F -- "$_termo" "${_cand[@]}" 2>/dev/null || true)"
    # reconstroi a lista de candidatos a partir das linhas de _out (uma por caminho). IFS=\n pra nao
    # quebrar caminho com espaco (grep -l emite um caminho por linha).
    _novos=()
    IFS='
'
    for _f in $_out; do
      [ -n "$_f" ] && _novos+=("$_f")
    done
    IFS="$_oldifs"
    _cand=("${_novos[@]:-}")
    # se _novos veio vazio, "${_novos[@]:-}" injeta um "" — limpa isso pra a contagem ficar honesta.
    if [ "${#_cand[@]}" -eq 1 ] && [ -z "${_cand[0]}" ]; then
      _cand=()
    fi
    [ "${#_cand[@]}" -gt 0 ] || { return 0; }   # zero apos este termo -> nenhum arquivo casa TODOS
  done <<EOF
$(printf '%s\n' "$@")
EOF

  # 3) ecoa os sobreviventes (casaram TODOS os termos), um por linha.
  for _f in "${_cand[@]}"; do
    [ -n "$_f" ] && printf '%s\n' "$_f"
  done
  return 0
}

# _norte_ja_tentei <termos...> — o CORACAO da peca. Filtra os termos uteis, casa (AND) nos bilhetes locais,
# ranqueia por mtime desc, corta em 5 e ecoa a moldura + os itens. SEMPRE exit 0 (fail-open).
#   - kill-switch NORTE_JA_TENTEI=0 -> inerte: nada no stdout, exit 0.
#   - dir inexistente/vazio -> "sem bilhetes ainda (nada pra comparar)".
#   - so stopwords/curtos -> "me da uma palavra mais especifica".
#   - nenhum casou -> "nenhum bilhete casou ... pode ser novo mesmo".
_norte_ja_tentei() {
  if _njt_desligado; then
    return 0   # inerte: nada no stdout.
  fi

  local _dir; _dir="$(_njt_dir)"
  # os termos crus, so pra ecoar na busca (a copy mostra o que o usuario pediu).
  local _busca; _busca="$*"

  # FONTE: dir precisa existir e ter ao menos 1 .md.
  if [ -z "$_dir" ] || [ ! -d "$_dir" ]; then
    printf 'sem bilhetes ainda (nada pra comparar) — pasta de bilhetes ainda nao existe (%s).\n' "$_dir"
    return 0
  fi
  # tem algum .md? (glob literal se nao houver -> teste -f descarta).
  local _tem=0 _f
  for _f in "$_dir"/*.md; do
    if [ -f "$_f" ]; then _tem=1; break; fi
  done
  if [ "$_tem" -eq 0 ]; then
    printf 'sem bilhetes ainda (nada pra comparar) — nenhum bilhete .md em %s.\n' "$_dir"
    return 0
  fi

  # TERMOS UTEIS (>=3 chars, sem stopword, dedupados, minusculos).
  local _uteis; _uteis="$(_njt_uteis "$@")"
  if [ -z "$_uteis" ]; then
    printf 'me da uma palavra mais especifica — os termos que voce passou sao muito curtos ou comuns demais pra buscar.\n'
    return 0
  fi
  # o 1o termo util (pra escolher a linha de amostra por arquivo).
  local _primeiro_termo; _primeiro_termo="$(printf '%s\n' "$_uteis" | head -n1)"

  # CASAMENTO (AND entre termos).
  local _casaram; _casaram="$(_njt_casa "$_dir" $_uteis)"
  if [ -z "$_casaram" ]; then
    printf 'nenhum bilhete casou com "%s" — pode ser novo mesmo, ou voce usou outras palavras na epoca.\n' "$_busca"
    return 0
  fi

  # RANQUEIA por mtime desc: monta "<mtime>\t<arquivo>" e ordena numerico reverso. Conta o total ANTES do corte.
  local _pareado="" _m
  local _oldifs="$IFS"
  IFS='
'
  for _f in $_casaram; do
    [ -n "$_f" ] || continue
    _m="$(_njt_mtime "$_f")"
    _pareado="${_pareado}${_m}	${_f}
"
  done
  IFS="$_oldifs"
  # total que casaram (M) e ordenacao (recente primeiro).
  local _M; _M="$(printf '%s' "$_pareado" | grep -c '	' 2>/dev/null || echo 0)"
  case "$_M" in ''|*[!0-9]*) _M=0 ;; esac
  # sort -rn pela 1a coluna (mtime); corta em 5.
  local _top5; _top5="$(printf '%s' "$_pareado" | sort -t'	' -k1,1 -rn | head -n 5)"

  # SAIDA: 1a linha sempre a moldura honesta.
  printf '▲ ja tentei? — pista textual, nao veredito (confira o bilhete antes de decidir)\n'

  local _linha _epoch _arq _base _data _amostra _n=0
  IFS='
'
  for _linha in $_top5; do
    [ -n "$_linha" ] || continue
    _epoch="${_linha%%	*}"          # antes do 1o TAB
    _arq="${_linha#*	}"             # depois do 1o TAB
    _n=$((_n+1))
    _base="$(basename "$_arq")"
    _data="$(_njt_data_de "$_epoch")"
    _amostra="$(_njt_amostra "$_arq" "$_primeiro_termo")"
    printf '%s. [%s] %s\n' "$_n" "$_data" "$_base"
    [ -n "$_amostra" ] && printf '   %s\n' "$_amostra"
  done
  IFS="$_oldifs"

  # RODAPE honesto.
  printf '(%s de %s casaram · busca: "%s" · so casamento de palavras nos SEUS bilhetes locais)\n' "$_n" "$_M" "$_busca"
  return 0
}
