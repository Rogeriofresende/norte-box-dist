#!/usr/bin/env bash
# _atrito.sh — biblioteca do PACOTE DE ATRITO (observar a 1a usuaria, NRT-_990210).
# NAO e um hook (nome com _ inicial, fora do hooks.json). E sourceada por atrito-emit.sh e
# pelos gates (secret-guard/consent-gate/confirmar-antes) pra deixar o breadcrumb de trava.
#
# O QUE O PACOTE CAPTURA (so rotulos + bits, ZERO conteudo — mesmo Modelo A do medidor):
#   - cmd:   o VERBO de um /norte-box:<verbo> por ALLOWLIST FECHADA. Args descartados. Fora da
#            allowlist -> NADA (nunca o texto livre da pessoa).
#   - trava: o ROTULO do gate que barrou (secret-guard/consent-gate/confirmar-antes) por
#            allowlist fechada. Nunca a mensagem do gate.
#   - erro:  1 BIT (true) quando o tool_response tem forma de erro. Nunca o texto/stack.
#
# Portabilidade macOS bash 3.2. Le como DADO, nunca executa input.

# --- ALLOWLIST FECHADA de comandos do norte-box (dos commands/*.md + skills slash-invocaveis).
# Casada por igualdade EXATA (espacos-cercados). Qualquer verbo fora daqui -> descartado.
_NB_ATRITO_CMD_ALLOW=" compartilhar consent convite doctor login modo projeto regras resposta retomar telemetry time continuar norte-projeto norte-retomar norte-resposta "

# --- ALLOWLIST FECHADA de rotulos de gate (trava). Fora daqui -> "outro-gate" (nunca a msg). ---
_NB_ATRITO_GATE_ALLOW=" secret-guard consent-gate confirmar-antes "

# _atrito_cmd_da_allowlist <prompt-cru>
#   Ecoa SO o verbo se o prompt COMECA com "/norte-box:<verbo>" E <verbo> esta na allowlist.
#   Senao ecoa vazio. NUNCA ecoa args nem texto livre. Trim de espaco inicial primeiro.
_atrito_cmd_da_allowlist() {
  local _p="$1" _first _verb
  # trim do inicio (a pessoa pode digitar " /norte-box:...")
  _p="${_p#"${_p%%[![:space:]]*}"}"
  # tem que comecar EXATAMENTE com /norte-box:
  case "$_p" in
    /norte-box:*) : ;;
    *) printf ''; return 0 ;;
  esac
  # 1o token (ate o 1o espaco/tab/nova-linha) = "/norte-box:<verbo>"; corta os args fora
  _first="${_p%%[[:space:]]*}"
  _verb="${_first#/norte-box:}"
  # o verbo pode vir com args colados por argumento posicional? nao: paramos no espaco acima.
  # sanidade: verbo so pode ser [a-z-] (senao descarta). Corta qualquer sujeira apos.
  case "$_verb" in
    *[!a-z-]*)
      # remove tudo do 1o caractere invalido em diante (defensivo)
      _verb="$(printf '%s' "$_verb" | sed 's/[^a-z-].*$//')"
      ;;
  esac
  [ -z "$_verb" ] && { printf ''; return 0; }
  case "$_NB_ATRITO_CMD_ALLOW" in
    *" $_verb "*) printf '%s' "$_verb" ;;   # na allowlist -> ecoa o verbo
    *)            printf '' ;;               # fora -> nada (nunca o texto)
  esac
  return 0
}

# _atrito_gate_rotulo <rotulo-cru> -> ecoa o rotulo se na allowlist, senao "outro-gate".
_atrito_gate_rotulo() {
  case "$_NB_ATRITO_GATE_ALLOW" in
    *" $1 "*) printf '%s' "$1" ;;
    *)        printf 'outro-gate' ;;
  esac
}

# _atrito_breadcrumb <rotulo-do-gate>
#   Chamado PELOS GATES quando barram/avisam. Grava SO o rotulo (colapsado por allowlist) + ts
#   em $HOME/.norte-box/atrito-breadcrumbs.jsonl. Fail-open total (nunca trava o gate).
#   Respeita o kill-switch e o modo (nao grava rastro se a captura esta off / modo privado).
_atrito_breadcrumb() {
  [ "${NORTE_ATRITO_OFF:-0}" = "1" ] && return 0
  local _dir="${HOME}/.norte-box" _g
  _g="$(_atrito_gate_rotulo "${1:-outro-gate}")"
  mkdir -p "$_dir" 2>/dev/null || return 0
  command -v jq >/dev/null 2>&1 || return 0
  local _ts _line
  _ts="$(date -u +%FT%TZ 2>/dev/null || echo unknown)"
  _line="$(jq -cn --arg g "$_g" --arg ts "$_ts" '{g:$g, ts:$ts}' 2>/dev/null || true)"
  [ -z "$_line" ] && return 0
  printf '%s\n' "$_line" >> "$_dir/atrito-breadcrumbs.jsonl" 2>/dev/null || true
  return 0
}
