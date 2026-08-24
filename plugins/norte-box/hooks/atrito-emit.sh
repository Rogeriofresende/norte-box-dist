#!/usr/bin/env bash
# atrito-emit.sh — PACOTE DE ATRITO (observar a 1a usuaria externa, NRT-_990210).
# Roda em UserPromptSubmit (por ULTIMO na cadeia, depois dos gates) e PostToolUse.
# Enfileira 1 evento SO-ROTULOS em $HOME/.norte-box/atrito-queue.jsonl:
#   { atrito: {cmd?, travas?, erro?}, ts }
# ZERO conteudo — mesmo Modelo A do medidor. NUNCA o texto livre, args, mensagem de gate ou stack.
#
# O QUE CAPTURA:
#   - cmd:   o VERBO de um /norte-box:<verbo> por ALLOWLIST FECHADA (args descartados).
#   - travas: os ROTULOS dos gates que barraram NESTE tick (breadcrumb deixado pelos gates).
#   - erro:  1 BIT (true) quando o tool_response tem forma de erro (PostToolUse).
#
# LEIS (iguais ao telemetry-emit):
#   - FAIL-OPEN: exit 0 SEMPRE. Qualquer erro -> deixa passar, nunca trava o trabalho.
#   - KILL-SWITCH: NORTE_ATRITO_OFF=1 -> nao captura NADA (a caixa dela segue igual).
#   - Modo privado / sem consent -> nao enfileira (a Norte nao ve este trabalho).
#   - Consome stdin como DADO, nunca executa. Nao escreve fora de $HOME/.norte-box.
#   - ADITIVO: NAO toca a fila do medidor (telemetry-queue.jsonl). Fila propria.
# Portabilidade macOS bash 3.2.
set -u

# --- KILL-SWITCH da captura nova inteira (fail-open) ---
[ "${NORTE_ATRITO_OFF:-0}" = "1" ] && exit 0

STATE_DIR="${HOME}/.norte-box"
QUEUE="${STATE_DIR}/atrito-queue.jsonl"
BREADCRUMBS="${STATE_DIR}/atrito-breadcrumbs.jsonl"
BC_CURSOR="${STATE_DIR}/atrito-breadcrumbs.cursor"
ENABLED_FLAG="${STATE_DIR}/telemetry.enabled"

# Consome stdin sempre (evita SIGPIPE). E DADO, jamais comando.
_stdin="$(cat 2>/dev/null || true)"

_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)"
# Carrega a lib do atrito (allowlist cmd + gates + breadcrumb).
if [ -n "${_SELF_DIR:-}" ] && [ -f "${_SELF_DIR}/_atrito.sh" ]; then
  . "${_SELF_DIR}/_atrito.sh"
elif [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/hooks/_atrito.sh" ]; then
  . "${CLAUDE_PLUGIN_ROOT}/hooks/_atrito.sh"
fi
command -v _atrito_cmd_da_allowlist >/dev/null 2>&1 || exit 0   # sem lib -> fail-open

# --- MODO/CONSENT (fail-closed, mesmo gate do medidor): so o compartilhavel com aceite captura.
#     Privado NAO enfileira (a Norte nao ve este trabalho — nem os rotulos). ---
if [ -n "${_SELF_DIR:-}" ] && [ -f "${_SELF_DIR}/_modo.sh" ]; then
  . "${_SELF_DIR}/_modo.sh"
elif [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/hooks/_modo.sh" ]; then
  . "${CLAUDE_PLUGIN_ROOT}/hooks/_modo.sh"
fi
command -v _norte_pode_enviar >/dev/null 2>&1 || exit 0   # sem leitor de modo -> fail-CLOSED
_norte_pode_enviar || exit 0

# --- Desligamento (mesma flag do medidor): sem flag -> nao captura ---
[ -f "$ENABLED_FLAG" ] || exit 0

command -v jq >/dev/null 2>&1 || exit 0
mkdir -p "$STATE_DIR" 2>/dev/null || exit 0

# --- Detecta o evento pelo campo PRESENTE ---
_prompt_raw="$(printf '%s' "$_stdin"        | jq -r '.prompt // empty' 2>/dev/null || true)"
_tool_response_raw="$(printf '%s' "$_stdin" | jq -c '.tool_response // empty' 2>/dev/null || true)"
_has_tool="$(printf '%s' "$_stdin"          | jq -r 'has("tool_name") or has("tool_input") or has("tool_response")' 2>/dev/null || echo false)"

# ============================================================================
# 1) CMD — so o verbo, por allowlist fechada. Args e texto livre NUNCA entram.
# ============================================================================
_cmd=""
if [ -n "$_prompt_raw" ]; then
  _cmd="$(_atrito_cmd_da_allowlist "$_prompt_raw")"
fi
_prompt_raw=""   # descarta o prompt EXPLICITAMENTE (defesa em profundidade)

# ============================================================================
# 3) ERRO — 1 bit. Le SO a ESTRUTURA do tool_response (nunca o texto):
#    .is_error==true  OU  (objeto E tem chave "error")  OU  .success==false.
#    So booleano/estrutura entra na decisao; nada de texto sobe.
# ============================================================================
_erro="false"
if [ -n "$_tool_response_raw" ]; then
  _erro="$(printf '%s' "$_tool_response_raw" | jq -r '
      if type=="object" then
        (((.is_error // false) == true) or (has("error")) or ((.success // true) == false))
      else false end' 2>/dev/null || echo false)"
  case "$_erro" in true) : ;; *) _erro="false" ;; esac
fi
_tool_response_raw=""   # descarta o tool_response (pode ter stack/PII) — so o bit sobreviveu

# ============================================================================
# 2) TRAVAS — dobra os breadcrumbs deixados PELOS GATES neste tick (so-rotulos).
#    Le do cursor pra frente; avanca o cursor. Best-effort: se 2 prompts colidirem
#    no mesmo tick, agrega (nao perde, nao vaza). So captura travas junto do prompt.
# ============================================================================
_travas_json="null"
# (leitura de breadcrumbs so no evento de prompt — trava vem de UserPromptSubmit, nao de PostToolUse)
if [ "$_has_tool" != "true" ] && [ -f "$BREADCRUMBS" ]; then
  _bc_total="$(wc -l < "$BREADCRUMBS" 2>/dev/null | tr -d ' ')"; case "$_bc_total" in ''|*[!0-9]*) _bc_total=0 ;; esac
  _bc_cur=0; [ -f "$BC_CURSOR" ] && _bc_cur="$(cat "$BC_CURSOR" 2>/dev/null | tr -d ' ')"
  case "$_bc_cur" in ''|*[!0-9]*) _bc_cur=0 ;; esac
  [ "$_bc_cur" -gt "$_bc_total" ] && _bc_cur=0   # arquivo rotacionou -> reseta
  if [ "$_bc_total" -gt "$_bc_cur" ]; then
    # rotulos novos (apos o cursor), unicos, como array jq. So o campo .g (rotulo), nada mais.
    _travas_json="$(tail -n +"$((_bc_cur + 1))" "$BREADCRUMBS" 2>/dev/null \
      | jq -r 'select(type=="object") | .g // empty' 2>/dev/null \
      | awk '!seen[$0]++' \
      | jq -R . 2>/dev/null | jq -s -c '.' 2>/dev/null || echo null)"
    case "$_travas_json" in '['*']') : ;; *) _travas_json="null" ;; esac
    [ "$_travas_json" = "[]" ] && _travas_json="null"
    printf '%s' "$_bc_total" > "$BC_CURSOR" 2>/dev/null || true   # avanca o cursor
  fi
fi

# --- Nada capturado (sem cmd da allowlist, sem trava, sem erro) -> nao enfileira ruido ---
if [ -z "$_cmd" ] && [ "$_travas_json" = "null" ] && [ "$_erro" != "true" ]; then
  exit 0
fi

_ts="$(date -u +%FT%TZ 2>/dev/null || echo unknown)"

# --- Monta o objeto atrito SO com o que foi capturado (campos ausentes = null, jq os omite via
#     to_entries|... nao — mantemos simples: incluimos so os presentes). jq escapa tudo. ---
_line="$(jq -cn \
  --arg cmd    "${_cmd:-}" \
  --argjson travas "${_travas_json:-null}" \
  --argjson erro "${_erro:-false}" \
  --arg ts     "$_ts" \
  '{atrito: (
      ( if $cmd != "" then {cmd:$cmd} else {} end )
      + ( if $travas != null then {travas:$travas} else {} end )
      + ( if $erro == true then {erro:true} else {} end )
    ), ts:$ts, kind:"atrito"}' 2>/dev/null || true)"

[ -z "$_line" ] && exit 0

printf '%s\n' "$_line" >> "$QUEUE" 2>/dev/null || exit 0
exit 0
