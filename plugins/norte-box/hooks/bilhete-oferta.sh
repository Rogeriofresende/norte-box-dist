#!/usr/bin/env bash
# bilhete-oferta.sh — SessionStart hook do norte-box: OFERECE retomar o bilhete salvo (conserto 0.3.41).
#
# POR QUE: fora do assento da Norte o /continuar NAO troca a conversa sozinho (so salva o bilhete). A
# pessoa abria uma conversa nova e nada lembrava que tinha um bilhete esperando — ela ficava sem saber
# de onde voltar. Agora, ao abrir conversa NOVA (ou /clear) num projeto com bilhete recente ainda nao
# visto, aparece UMA linha: "Tem bilhete de <assunto> (ha N min) — rode /norte:retomar pra continuar".
#
# LIMITES (anti-ruido — quem roda varias conversas em paralelo no mesmo projeto):
#   - so em abertura nova ou /clear (nunca em resume/compact);
#   - so bilhete com menos de 24h;
#   - cada bilhete e oferecido UMA vez so (e nunca depois de retomado) — marca em handoffs/.ja-visto;
#   - 2+ assuntos recentes -> uma linha so, pedindo /norte:retomar (que lista e pergunta);
#   - dentro do assento (NORTE_SEAT) nao aparece: la o /handon ja retoma sozinho.
# Kill-switch: NORTE_BILHETE_OFERTA=0.
# LEIS: FAIL-OPEN (exit 0 sempre) · so le o disco local + 1 linha no .ja-visto · stdin e DADO, nunca executa.
set -u

[ "${NORTE_BILHETE_OFERTA:-1}" = "0" ] && exit 0
[ -n "${NORTE_SEAT:-}${NORTE_SEAT_AUTO:-}" ] && exit 0

_in="$(cat 2>/dev/null || true)"
_src="$(printf '%s' "$_in" | jq -r '.source // empty' 2>/dev/null || true)"
case "${_src:-startup}" in startup|clear) ;; *) exit 0 ;; esac
_cwd="$(printf '%s' "$_in" | jq -r '.cwd // empty' 2>/dev/null || true)"
[ -n "${_cwd:-}" ] && cd "$_cwd" 2>/dev/null

_root="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." 2>/dev/null && pwd)}"
DIR="$(bash "$_root/bin/nb-resolve-outdir" 2>/dev/null)" || exit 0
[ -d "$DIR/handoffs" ] || exit 0
VISTO="$DIR/handoffs/.ja-visto"

_alvo="$(bash "$_root/bin/nb-retomar-alvo" "$DIR" 86400 2>/dev/null || true)"
_linha=""
case "$_alvo" in
  ALVO\ *)
    _f="${_alvo#ALVO }"
    _b="$(basename "$_f")"
    grep -qxF "$_b" "$VISTO" 2>/dev/null && exit 0
    _min=$(( ( $(date +%s) - $(stat -L -f %m "$_f" 2>/dev/null || stat -L -c %Y "$_f" 2>/dev/null || date +%s) ) / 60 ))
    _ass="$(grep -m1 -E '^# ' "$_f" 2>/dev/null | sed -E 's/^# +(Handoff|Session Handoff) *[—:-]* *//')"
    [ -n "$_ass" ] || _ass="${_b%.md}"
    _linha="📌 Tem um bilhete salvo: \"$_ass\" (há ${_min} min). Pra continuar de onde parou, rode /norte:retomar."
    printf '%s\n' "$_b" >> "$VISTO" 2>/dev/null || true
    ;;
  AMBIGUO*)
    _novos=0
    while IFS=$'\t' read -r _tag _f _slug _data; do
      [ "$_tag" = "CANDIDATO" ] || continue
      _b="$(basename "$_f")"
      grep -qxF "$_b" "$VISTO" 2>/dev/null && continue
      _novos=$((_novos + 1)); printf '%s\n' "$_b" >> "$VISTO" 2>/dev/null || true
    done <<EOF
$_alvo
EOF
    [ "$_novos" -gt 0 ] || exit 0
    _linha="📌 Tem $_novos bilhete(s) salvo(s) de assuntos diferentes nas últimas 24h. Pra continuar um deles, rode /norte:retomar (ele lista e você escolhe)."
    ;;
  *) exit 0 ;;
esac

_ctx="$(printf '=== 📌 BILHETE ESPERANDO (mostre ao usuario, 1 linha, do jeito que esta) ===\n%s\nNAO retome sozinho: so ofereca. Se a pessoa pedir outra coisa, siga o pedido dela.\n=== fim ===' "$_linha")"
jq -n --arg ctx "$_ctx" --arg msg "$_linha" '{
  "systemMessage": $msg,
  "hookSpecificOutput": { "hookEventName": "SessionStart", "additionalContext": $ctx }
}' 2>/dev/null || true
exit 0
