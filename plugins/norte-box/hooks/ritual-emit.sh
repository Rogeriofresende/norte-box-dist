#!/usr/bin/env bash
# ritual-emit.sh — OBSERVADOR EM SOMBRA do norte-box (NRT-_746, fatia 1). Hook async de
# PostToolUse + UserPromptSubmit. Objetivo UNICO: PROVAR que a caixa enxerga o FORMATO de um
# ritual repetido (mandato -> teste/review -> pr) — 100% LOCAL, log-only.
#
# ============================================================================================
# MODO SOMBRA PURO (o ponto inteiro desta fatia):
#   - SEM conteudo: le tool_input/prompt SO pra classificar a FORMA num rotulo fechado; o texto
#     e descartado no mesmo passo (mesmo Modelo A do medidor/atrito).
#   - SEM enviar NADA: nenhum caminho de POST/curl/wget/http. Nem "tipo+contagem" saem da maquina
#     nesta fatia. O placar mora SO em ~/.norte-box/ e so o proprio dono ve (comando /norte-box:ritual).
#   - SEM sugerir, SEM agir: so conta e cala.
#
# POR QUE NAO DEPENDE DE MODO/CONSENT (diferente do telemetry/atrito): aqueles ENVIAM (drain),
# entao precisam de modo=compartilhavel + consent. Este NAO envia nada — o gate certo aqui e o
# OPT-IN PROPRIO por flag-arquivo (fail-closed): sem a flag, nao observa. Isso mantem o padrao
# "so observa com permissao" sem acoplar o observador local ao pipeline de envio.
#
# LEIS: exit 0 SEMPRE (fail-open), stdout vazio, async:true. Consome stdin como DADO, nunca
# executa. Escreve SO em $HOME/.norte-box. bash 3.2.
set -u

# --- KILL-SWITCH (sai na 1a linha, antes de qualquer trabalho) ---
[ "${NORTE_RITUAL_OFF:-0}" = "1" ] && exit 0

STATE_DIR="${HOME}/.norte-box"
ENABLED_FLAG="${STATE_DIR}/ritual-observador.enabled"

# --- OPT-IN FAIL-CLOSED: sem a flag-arquivo -> nao observa (a caixa segue igual) ---
[ -f "$ENABLED_FLAG" ] || exit 0

# Consome stdin sempre (evita SIGPIPE). E DADO, jamais comando.
_stdin="$(cat 2>/dev/null || true)"

# Sem jq nao da pra classificar com seguranca -> fail-open.
command -v jq >/dev/null 2>&1 || exit 0

# Carrega a lib (classificacao + maquina de estados + assinatura).
_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)"
if [ -n "${_SELF_DIR:-}" ] && [ -f "${_SELF_DIR}/_ritual.sh" ]; then
  . "${_SELF_DIR}/_ritual.sh"
elif [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/hooks/_ritual.sh" ]; then
  . "${CLAUDE_PLUGIN_ROOT}/hooks/_ritual.sh"
fi
command -v _nb_ritual_classifica >/dev/null 2>&1 || exit 0   # sem lib -> fail-open

mkdir -p "$STATE_DIR" 2>/dev/null || exit 0

# --- session_id -> run_id HASHEADO (cru nunca gravado). Sem run_id -> nada a escopar -> sai. ---
_session_raw="$(printf '%s' "$_stdin" | jq -r '.session_id // empty' 2>/dev/null || true)"
_run_id="$(_nb_ritual_run_id "$_session_raw")"
_session_raw=""   # descarta o cru EXPLICITAMENTE
[ -z "$_run_id" ] && exit 0

# --- Detecta o evento pelo campo PRESENTE (nao confia so em hook_event_name) ---
_prompt_raw="$(printf '%s' "$_stdin" | jq -r '.prompt // empty' 2>/dev/null || true)"
_tool="$(printf '%s' "$_stdin"       | jq -r '.tool_name // empty' 2>/dev/null || true)"

# ------------------------------------------------------------------------------------
# Extrai SO o campo estrutural necessario por tool, passa pra lib, e DESCARTA o texto.
# Nada do conteudo cru sobrevive apos a classificacao (defesa em profundidade).
# ------------------------------------------------------------------------------------
_marco=""
if [ -n "$_prompt_raw" ]; then
  # UserPromptSubmit: passa SO o 1o token do prompt (args descartados aqui, nunca chegam na lib).
  _p="${_prompt_raw#"${_prompt_raw%%[![:space:]]*}"}"      # trim inicial
  _first_token="${_p%%[[:space:]]*}"                        # 1o token
  _prompt_raw=""; _p=""                                     # descarta o resto do prompt
  _marco="$(_nb_ritual_classifica '' "$_first_token")"
  _first_token=""
elif [ -n "$_tool" ]; then
  case "$_tool" in
    Write|Edit|MultiEdit|NotebookEdit)
      _fp="$(printf '%s' "$_stdin" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)"
      _marco="$(_nb_ritual_classifica "$_tool" "$_fp")"
      _fp="" ;;
    Bash)
      _cmd="$(printf '%s' "$_stdin" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"
      _marco="$(_nb_ritual_classifica "Bash" "$_cmd")"
      _cmd="" ;;
    Skill)
      # nome da skill: chaves possiveis (.skill / .name) — igualdade EXATA na lib.
      _sk="$(printf '%s' "$_stdin" | jq -r '.tool_input.skill // .tool_input.name // empty' 2>/dev/null || true)"
      _marco="$(_nb_ritual_classifica "Skill" "$_sk")"
      _sk="" ;;
    *)
      # tool desconhecido / MCP / custom -> nunca classifica
      _marco="" ;;
  esac
fi
# a partir daqui o stdin cru nao e mais necessario — descarta.
_stdin=""; _tool=""

# Nada classificavel -> nao registra ruido.
[ -z "$_marco" ] && exit 0

# --- timestamp (ms) do marco ---
_ts_ms="$(_nb_ritual_now_ms)"
case "$_ts_ms" in ''|*[!0-9]*) exit 0 ;; esac

# --- housekeeping best-effort (apaga estados velhos), 1x sem custo relevante ---
_nb_ritual_housekeeping 2>/dev/null || true

# --- REGISTRA o 1o-visto do marco no estado do run ---
_nb_ritual_registra_marco "$_run_id" "$_marco" "$_ts_ms" 2>/dev/null || true

# --- No marco `pr`: FECHA a assinatura (confere marcos + ordem, anota no placar) ---
if [ "$_marco" = "pr" ]; then
  _nb_ritual_fecha_pr "$_run_id" "$_ts_ms" 2>/dev/null || true
fi

exit 0
