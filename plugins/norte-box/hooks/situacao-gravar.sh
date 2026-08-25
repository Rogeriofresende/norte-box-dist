#!/usr/bin/env bash
# situacao-gravar.sh — Stop hook do norte-box: grava a FICHINHA de situacao no fim da sessao.
#
# O QUE FAZ: no fim de cada turno/sessao, guarda um cartaozinho LOCAL com o objetivo em palavras
# cruas (a 1a fala da pessoa nesta sessao), pra que a PROXIMA abertura mostre "de onde viemos" e
# a pessoa nunca fique no branco. A fichinha mora em $HOME/.norte-box/situacao.json.
#
# HONESTO POR PADRAO: grava SEMPRE provado=false (selo 🟡 NAO-PROVADO). O verde so viria de um
# artefato de prova real — que ainda nao existe (o motor de prova/Val de bolso nao foi construido).
# De proposito: "um amarelo honesto vale mais que um verde que mente".
#
# PRIVADO POR PADRAO: a fichinha e LOCAL, NUNCA enviada. Este hook nao toca telemetria/rede — ele
# roda INDEPENDENTE do modo (privado ou compartilhavel): a memoria da pessoa e dela, sempre. So
# guardamos o ROTULO do objetivo (a fala que abre a sessao), nao o trabalho.
#
# LEIS (iguais aos outros hooks do box):
#   - FAIL-OPEN: exit 0 SEMPRE. Nunca trava/atrasa o Claude.
#   - Consome stdin como DADO, nunca executa. Nao escreve fora de $HOME/.norte-box.
#   - Sem jq / sem transcript -> nao grava (fail-open), sai limpo.
set -u

_stdin="$(cat 2>/dev/null || true)"

# Carrega a lib da fichinha (fonte unica de read/write).
_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)"
if [ -n "${_SELF_DIR:-}" ] && [ -f "${_SELF_DIR}/_situacao.sh" ]; then
  . "${_SELF_DIR}/_situacao.sh"
elif [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/hooks/_situacao.sh" ]; then
  . "${CLAUDE_PLUGIN_ROOT}/hooks/_situacao.sh"
else
  exit 0
fi
command -v _norte_situacao_gravar >/dev/null 2>&1 || exit 0
command -v jq >/dev/null 2>&1 || exit 0

# Caminho do transcript (o Stop hook fornece transcript_path).
_transcript="$(printf '%s' "$_stdin" | jq -r '.transcript_path // empty' 2>/dev/null || true)"
[ -n "$_transcript" ] || exit 0
[ -f "$_transcript" ] || exit 0

# Objetivo em PALAVRAS CRUAS = a 1a fala do usuario nesta sessao (o que ele pediu). Deterministico,
# nao inventado. So o TEXTO da 1a mensagem; nada do trabalho subsequente entra na fichinha.
_objetivo="$(jq -rs '
  [ .[] | select(.type=="user") ] | .[0]
  | (.message.content)
  | if type=="array" then (map(select(.type=="text") | .text) | join(" "))
    elif type=="string" then .
    else "" end
' "$_transcript" 2>/dev/null || true)"

# Sem 1a fala legivel (ex: sessao so-comando) -> nao sobrescreve a fichinha existente (fail-open).
[ -n "$_objetivo" ] || exit 0

# Normaliza: 1 linha, aparada, cap de tamanho (o cartao e curto; nao guardamos um dump). So o rotulo.
_objetivo="$(printf '%s' "$_objetivo" | tr '\n\r\t' '   ' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | cut -c1-240)"
[ -n "$_objetivo" ] || exit 0

# entregou/proximo: a gravacao automatica nao sabe RESUMIR o que foi feito (bash nao le a intencao).
# Deixamos vazios aqui — a skill /norte-box:continuar (que pede o resumo ao modelo) e o lugar certo
# pra enriquecer isso depois. O importante do 1.1 (nunca ficar no branco) ja e coberto pelo objetivo.
NB_SIT_OBJETIVO="$_objetivo" NB_SIT_ENTREGOU="" NB_SIT_PROXIMO="" _norte_situacao_gravar || exit 0
exit 0
