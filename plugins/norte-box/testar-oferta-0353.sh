#!/usr/bin/env bash
# Teste do conserto 0.3.53 (NRT-_996894): ABRIR a conversa (hook bilhete-oferta) NAO marca "achou_bilhete";
# usar o /norte-retomar de verdade (skill chama nb-retomar-alvo) continua marcando. Roda num HOME de mentira.
set -u
NOVO=~/norte-box-dist-nrt995031/plugins/norte-box
T=/tmp/nb0353oferta/run-$(date +%s); mkdir -p "$T"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  OK   %s\n' "$1"; }
nok() { FAIL=$((FAIL+1)); printf '  FALHA %s\n' "$1"; }
export CLAUDE_CODE_SESSION_ID="sessao-de-teste-oferta"
unset NORTE_SEAT NORTE_SEAT_AUTO NORTE_BILHETE_OFERTA NORTE_BOX_PASSO   # simula conversa comum de cliente (fora do assento)

HM="$T/home"; H="$HM/.norte-box"; mkdir -p "$H"
printf 'compartilhavel\n' > "$H/modo"
printf '{"versao":"5","hash":"teste"}' > "$H/consent.json"
printf '{"invite_id":"teste-oferta","ingest_token":"tok-teste"}' > "$H/identity.json"
: > "$H/telemetry.enabled"
printf 'NORTE_BOX_TELEMETRY_URL=http://127.0.0.1:18799/ingest\n' > "$H/.env"

P="$T/proj"; mkdir -p "$P"; git -C "$P" init -q
DIR="$(cd "$P" && HOME=$HM bash "$NOVO/bin/nb-resolve-outdir")"
mkdir -p "$DIR/handoffs"
printf -- '---\nobjetivo: painel\n---\n# a\n' > "$DIR/handoffs/painel-$(date +%Y%m%d-%H%M).md"
printf -- '---\nobjetivo: outro\n---\n# b\n' > "$DIR/handoffs/outro-$(date +%Y%m%d-%H%M).md"

conta() { sleep 1; grep -c '"passo":"achou_bilhete"' "$H/telemetry-queue.jsonl" 2>/dev/null || true; }

echo "== 1. Abrir 5 conversas (hook de abertura)"
for i in 1 2 3 4 5; do
  printf '{"cwd":"%s","source":"startup"}' "$P" | HOME=$HM CLAUDE_PLUGIN_ROOT="$NOVO" bash "$NOVO/hooks/bilhete-oferta.sh" >/dev/null 2>&1
done
n="$(conta)"; [ "${n:-0}" = 0 ] && ok "abrir 5 conversas → 0 marcas de achou_bilhete" || nok "abrir conversa marcou $n vezes"

echo "== 2. O hook continua oferecendo o bilhete (resposta não mudou)"
out="$(printf '{"cwd":"%s","source":"startup"}' "$P" | HOME=$HM CLAUDE_PLUGIN_ROOT="$NOVO" NORTE_BILHETE_OFERTA_HORAS=12 bash "$NOVO/hooks/bilhete-oferta.sh" 2>/dev/null)"
alvo="$(NORTE_BOX_PASSO=0 HOME=$HM bash "$NOVO/bin/nb-retomar-alvo" "$DIR" 43200)"
case "$alvo" in AMBIGUO*|ALVO*) ok "programa ainda decide o bilhete: $(printf '%s' "$alvo" | head -1)";; *) nok "programa não decidiu: [$alvo]";; esac

echo "== 3. Usar o /norte-retomar de verdade (como a skill chama)"
HOME=$HM bash "$NOVO/bin/nb-retomar-alvo" "$DIR" >/dev/null
n="$(conta)"; [ "${n:-0}" = 1 ] && ok "retomada real → 1 marca de achou_bilhete" || nok "retomada real marcou ${n:-0} (esperado 1)"

echo
echo "RESULTADO: $PASS ok · $FAIL falha(s)"
[ "$FAIL" = 0 ]
