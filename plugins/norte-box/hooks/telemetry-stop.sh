#!/usr/bin/env bash
# telemetry-stop.sh - Stop hook do norte-box: mede o TAMANHO da resposta da IA (pro medidor).
#
# MODELO A (numeros por padrao): a resposta da IA e parte do CUSTO (tokens de saida), entao
# medimos o TAMANHO dela pra cobrar justo — mas NUNCA GRAVAMOS nem ENVIAMOS o texto da resposta.
# Este hook le a ultima fala do assistente no transcript SO pra CONTAR chars/tokens e descarta
# o texto no mesmo passo. O evento que sobe carrega SO {uso:{comandos,tokens,ms,bytes}} — zero
# conteudo. Antes este hook enfileirava a resposta INTEIRA em prosa (o "ver tudo"); no Modelo A
# a Norte NAO ve o que a IA respondeu, so o quanto ela respondeu.
#
# LEIS (iguais aos outros hooks):
#   - FAIL-OPEN: exit 0 SEMPRE. Nunca trava/atrasa o Claude.
#   - So mede se a coleta esta LIGADA (telemetry.enabled) e o modo permite enviar.
#   - NUMEROS POR PADRAO: nenhum campo de conteudo (response) no evento.
#   - Consome stdin como DADO, nunca executa. Nao escreve fora de $HOME/.norte-box.
set -u

STATE_DIR="${HOME}/.norte-box"
QUEUE="${STATE_DIR}/telemetry-queue.jsonl"
ENABLED_FLAG="${STATE_DIR}/telemetry.enabled"

_stdin="$(cat 2>/dev/null || true)"

# --- MODO (Fase 2, fail-closed): so quem PODE ENVIAR mede a resposta. Privado NAO enfileira,
#     e compartilhavel-na-mao SEM consent tambem NAO (furo MEDIO, Val). MESMO gate do emit/drain:
#     _norte_pode_enviar = modo=compartilhavel E consent aceito na versao vigente. ---
_SELF_DIR_M="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)"
if [ -n "${_SELF_DIR_M:-}" ] && [ -f "${_SELF_DIR_M}/_modo.sh" ]; then
  . "${_SELF_DIR_M}/_modo.sh"
elif [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/hooks/_modo.sh" ]; then
  . "${CLAUDE_PLUGIN_ROOT}/hooks/_modo.sh"
fi
if ! command -v _norte_pode_enviar >/dev/null 2>&1; then exit 0; fi
_norte_pode_enviar || exit 0

# Desligado / sem jq -> nao emite (fail-open).
[ -f "$ENABLED_FLAG" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0
mkdir -p "$STATE_DIR" 2>/dev/null || exit 0

# Caminho do transcript (o Stop hook fornece transcript_path).
_transcript="$(printf '%s' "$_stdin" | jq -r '.transcript_path // empty' 2>/dev/null || true)"
[ -n "$_transcript" ] || exit 0
[ -f "$_transcript" ] || exit 0

# Extrai a ULTIMA fala do assistente: todos os blocos de texto do ultimo item type=="assistant".
# Usado SO pra MEDIR o tamanho — o texto e descartado logo abaixo, nunca vai pra fila.
_resp_raw="$(jq -rs '
  [ .[] | select(.type=="assistant") ] | last
  | (.message.content // [])
  | map(select(.type=="text") | .text) | join("\n")
' "$_transcript" 2>/dev/null || true)"
[ -n "$_resp_raw" ] || exit 0

# invite_id (mesma logica do emit): id opaco da pessoa, nunca token.
_invite_id="$(jq -r '.invite_id // .sub // empty' "${STATE_DIR}/identity.json" 2>/dev/null || true)"
[ -z "$_invite_id" ] && _invite_id="$(jq -r '.hash // empty' "${STATE_DIR}/consent.json" 2>/dev/null || true)"
[ -z "$_invite_id" ] && _invite_id="anon"

# Mede o tamanho e DESCARTA o texto (defesa em profundidade: nenhuma linha abaixo pode reusa-lo).
_chars="$(printf '%s' "$_resp_raw" | wc -c | tr -d ' ')"; [ -z "$_chars" ] && _chars=0
_resp_raw=""
_tokens_aprox=$(( _chars / 4 ))
_ts="$(date -u +%FT%TZ 2>/dev/null || echo unknown)"

# Evento SO-NUMEROS (kind:"medidor"). Sem campo `response` nem qualquer conteudo — Modelo A.
_line="$(jq -cn \
  --arg invite_id "$_invite_id" \
  --arg event     "AssistantResponse" \
  --arg ts        "$_ts" \
  --argjson tokens "${_tokens_aprox:-0}" \
  --argjson bytes  "${_chars:-0}" \
  '{invite_id:$invite_id, kind:"medidor", event:$event, tool:"", ts:$ts,
    uso:{comandos:0, tokens:$tokens, ms:null, bytes:$bytes}}' 2>/dev/null || true)"

[ -z "$_line" ] && exit 0
printf '%s\n' "$_line" >> "$QUEUE" 2>/dev/null || exit 0
exit 0
