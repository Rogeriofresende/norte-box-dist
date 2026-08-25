#!/usr/bin/env bash
# diario-gravar.sh — Stop hook do norte-box: ANEXA uma linha ao "diario do que construimos".
#
# O QUE FAZ: no fim de cada sessao, guarda UMA linha LOCAL numa lista viva (diario.jsonl) —
#   "o que voce pediu · o que eu fiz · provado?(🟢/🟡) · quando".
# Reusa exatamente o que o situacao-gravar.sh ja capta: a 1a fala do usuario (= o que ele pediu) e o
# SELO honesto do estado real. Assim, ao abrir a caixa, da pra VER o historico do que ja foi feito.
#
# DIFERENCA pro situacao-gravar (que SOBRESCREVE a fichinha do "onde paramos"): este e APPEND-ONLY —
# uma linha por sessao, o historico so cresce. Os dois convivem: fichinha = a foto de agora; diario =
# o filme do que ja construimos.
#
# HONESTO POR PADRAO: o selo de cada linha reusa a regra unica do passo 1 (via _situacao.sh). Default
# 🟡 NAO-PROVADO; 🟢 so com artefato de prova real. Nunca inventa verde.
#
# PRIVADO POR PADRAO: o diario e LOCAL, NUNCA enviado. Este hook nao toca telemetria/rede. So guarda o
# ROTULO do que foi pedido (a 1a fala), nunca o trabalho/conteudo da conversa.
#
# LEIS (iguais aos outros hooks do box):
#   - FAIL-OPEN: exit 0 SEMPRE. Nunca trava/atrasa o Claude.
#   - Consome stdin como DADO, nunca executa. Nao escreve fora de $HOME/.norte-box.
#   - Sem jq / sem transcript / sem 1a fala -> nao anexa (fail-open), sai limpo.
#   - Kill-switch: NORTE_DIARIO=0 desliga. Vazio/1 = ligado.
set -u

# Kill-switch explicito. Vazio/1 = ligado; 0 = desligado (consome stdin e sai).
if [ "${NORTE_DIARIO:-1}" = "0" ]; then
  cat >/dev/null 2>&1 || true
  exit 0
fi

_stdin="$(cat 2>/dev/null || true)"

# Carrega as libs (fichinha = selo honesto; diario = append/leitura). Fonte unica.
_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)"
_load() { # $1 = nome do arquivo lib
  if [ -n "${_SELF_DIR:-}" ] && [ -f "${_SELF_DIR}/$1" ]; then . "${_SELF_DIR}/$1"; return 0; fi
  if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/hooks/$1" ]; then . "${CLAUDE_PLUGIN_ROOT}/hooks/$1"; return 0; fi
  return 1
}
# _situacao.sh e opcional (so pro selo); _diario.sh e obrigatorio (a peca principal).
_load "_situacao.sh" 2>/dev/null || true
_load "_diario.sh"   2>/dev/null || exit 0
command -v _norte_diario_anexar >/dev/null 2>&1 || exit 0
command -v jq >/dev/null 2>&1 || exit 0

# Caminho do transcript (o Stop hook fornece transcript_path).
_transcript="$(printf '%s' "$_stdin" | jq -r '.transcript_path // empty' 2>/dev/null || true)"
[ -n "$_transcript" ] || exit 0
[ -f "$_transcript" ] || exit 0

# Chave estavel da sessao pra idempotencia (anti double-fire: o Stop dispara N vezes -> 1 linha so).
# Preferido: session_id do payload do Stop. Fallback: transcript_path (arquivo e 1 por sessao, unico).
_sessao="$(printf '%s' "$_stdin" | jq -r '.session_id // empty' 2>/dev/null || true)"
[ -n "$_sessao" ] || _sessao="$_transcript"

# "O que voce pediu" = a 1a fala do usuario nesta sessao (deterministico, nao inventado). Mesmo criterio
# do situacao-gravar. So o TEXTO da 1a mensagem; nada do trabalho subsequente entra.
_pediu="$(jq -rs '
  [ .[] | select(.type=="user") ] | .[0]
  | (.message.content)
  | if type=="array" then (map(select(.type=="text") | .text) | join(" "))
    elif type=="string" then .
    else "" end
' "$_transcript" 2>/dev/null || true)"

# Sem 1a fala legivel (ex: sessao so-comando) -> nao anexa linha vazia (fail-open).
[ -n "$_pediu" ] || exit 0

# Normaliza: 1 linha, aparada, cap de tamanho (a linha do diario e curta; nao guardamos dump).
_pediu="$(printf '%s' "$_pediu" | tr '\n\r\t' '   ' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | cut -c1-240)"
[ -n "$_pediu" ] || exit 0

# "o que fiz" e "decisao": a gravacao automatica nao sabe RESUMIR o trabalho (bash nao le intencao).
# Ficam vazios aqui — a linha ja e util com pedido + selo + data. A skill /norte-box:continuar (que
# pede o resumo ao modelo) e o lugar de enriquecer isso depois, se quisermos.
NB_DIA_PEDIU="$_pediu" NB_DIA_FIZ="" NB_DIA_DECISAO="" NB_DIA_SESSAO="$_sessao" _norte_diario_anexar || exit 0
exit 0
