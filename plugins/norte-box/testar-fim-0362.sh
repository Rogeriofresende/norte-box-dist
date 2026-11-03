#!/usr/bin/env bash
# Teste da caixa 0.3.62 (o "terminou" não se perde) — roda num HOME de mentira; nada publicado, nada enviado.
set -u
NOVO="${NB_CAIXA:-$(cd "$(dirname "$0")" && pwd)}"
HOOK="$NOVO/hooks/telemetry-stop.sh"
T="$(mktemp -d /tmp/nbfim.XXXXXX)"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  OK   %s\n' "$1"; }
nok() { FAIL=$((FAIL+1)); printf '  FALHA %s\n' "$1"; }
HM="$T/home"; H="$HM/.norte-box"; mkdir -p "$H"
printf 'compartilhavel\n' > "$H/modo"
printf '{"versao":"5","hash":"teste"}' > "$H/consent.json"
printf '{"invite_id":"teste-0362","ingest_token":"tok-teste"}' > "$H/identity.json"
: > "$H/telemetry.enabled"
Q="$H/telemetry-queue.jsonl"
export NB_FIM_PAUSA=0.3
U='{"type":"user","message":{"role":"user","content":"faz X"}}'
TU='{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"t1","name":"Bash","input":{}}]}}'
TR='{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t1","content":"ok"}]}}'
TX='{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Pronto, fiz o segredo-xyz."}]}}'
entrada() { printf '{"transcript_path":"%s","session_id":"s%s%s"}' "$1" "$RANDOM" "$RANDOM"; }
roda() { entrada "$1" | HOME="$HM" CLAUDE_PLUGIN_ROOT="$NOVO" bash "$HOOK"; }
roda_bg() { entrada "$1" > "$T/in-$2.json"; HOME="$HM" CLAUDE_PLUGIN_ROOT="$NOVO" bash "$HOOK" < "$T/in-$2.json" & }
linhas() { local n; n="$(grep -c . "$Q" 2>/dev/null)"; printf '%s' "${n:-0}"; }
fim1() { head -1 "$Q" 2>/dev/null | jq -r '.fim // "-"'; }
pend() { find "$H" -maxdepth 1 -name 'fim-pendente-*.json' | wc -l | tr -d ' '; }

echo "== 1. Resposta já gravada"
printf '%s\n%s\n%s\n%s\n' "$U" "$TU" "$TR" "$TX" > "$T/c.jsonl"; : > "$Q"; roda "$T/c.jsonl"
[ "$(linhas)" = 1 ] && [ "$(fim1)" = com_texto ] && ok "1 fim anotado: com_texto" || nok "esperava 1 fim com_texto (fila: $(cat "$Q"))"

echo "== 2. Resposta gravada atrasada (o caso que hoje some)"
printf '%s\n%s\n%s\n' "$U" "$TU" "$TR" > "$T/c.jsonl"; : > "$Q"
( sleep 0.8; printf '%s\n' "$TX" >> "$T/c.jsonl" ) & roda "$T/c.jsonl"; wait
[ "$(linhas)" = 1 ] && [ "$(fim1)" = com_texto ] && ok "não sumiu: com_texto, tentativas=$(head -1 "$Q" | jq -r .tentativas)" || nok "atrasada (fila: $(cat "$Q"))"

echo "== 3. Resposta nunca chega"
printf '%s\n%s\n%s\n' "$U" "$TU" "$TR" > "$T/c.jsonl"; : > "$Q"; roda "$T/c.jsonl"
[ "$(linhas)" = 1 ] && [ "$(fim1)" = sem_texto ] && ok "anotado sem_texto (não some calado)" || nok "nunca chega (fila: $(cat "$Q"))"
[ "$(pend)" = 0 ] && ok "nenhum provisório sobrando" || nok "sobrou provisório: $(pend)"

echo "== 4. Conversa fechada no meio da espera"
for sig in HUP TERM; do
  printf '%s\n%s\n%s\n' "$U" "$TU" "$TR" > "$T/c.jsonl"; : > "$Q"
  roda_bg "$T/c.jsonl" a; p=$!; sleep 0.6; kill -s "$sig" "$p" 2>/dev/null; wait "$p" 2>/dev/null; sleep 0.2
  [ "$(fim1)" = fechou_no_meio ] && [ "$(pend)" = 0 ] && ok "$sig: anotado na hora fechou_no_meio" || nok "$sig (fila: $(cat "$Q"), provisórios $(pend))"
done
printf '%s\n%s\n%s\n' "$U" "$TU" "$TR" > "$T/c.jsonl"; : > "$Q"
roda_bg "$T/c.jsonl" a; p=$!; sleep 0.6; kill -s KILL "$p" 2>/dev/null; wait "$p" 2>/dev/null
find "$H" -maxdepth 1 -name 'fim-pendente-*.json' -exec touch -t 202601010000 {} \;
printf '%s\n%s\n%s\n%s\n' "$U" "$TU" "$TR" "$TX" > "$T/d.jsonl"; roda "$T/d.jsonl"
[ "$(grep -c '"fechou_no_meio"' "$Q")" = 1 ] && [ "$(grep -c '"com_texto"' "$Q")" = 1 ] && [ "$(pend)" = 0 ] \
  && ok "KILL: a próxima resposta recolheu o fechou_no_meio" || nok "KILL (fila: $(cat "$Q"), provisórios $(pend))"

echo "== 5. Duas conversas terminando juntas"
: > "$Q"
printf '%s\n%s\n%s\n' "$U" "$TU" "$TR" > "$T/e.jsonl"; ( sleep 1; printf '%s\n' "$TX" >> "$T/e.jsonl" ) &
printf '%s\n%s\n%s\n%s\n' "$U" "$TU" "$TR" "$TX" > "$T/f.jsonl"
roda_bg "$T/e.jsonl" e; sleep 0.2; roda_bg "$T/f.jsonl" f; wait
[ "$(linhas)" = 2 ] && [ "$(pend)" = 0 ] && ok "2 fins, sem duplicar" || nok "esperava 2 (fila: $(cat "$Q"))"

echo "== 6. Privacidade"
grep -q 'segredo-xyz\|Pronto' "$Q" && nok "texto da resposta foi pra fila" || ok "nenhum texto da resposta na fila (só números e rótulos)"
printf 'privado\n' > "$H/modo"; : > "$Q"
printf '%s\n%s\n%s\n%s\n' "$U" "$TU" "$TR" "$TX" > "$T/c.jsonl"; roda "$T/c.jsonl"
[ "$(linhas)" = 0 ] && [ "$(pend)" = 0 ] && ok "modo privado: nada anotado" || nok "modo privado anotou algo"
printf 'compartilhavel\n' > "$H/modo"; rm -f "$H/telemetry.enabled"; : > "$Q"; roda "$T/c.jsonl"
[ "$(linhas)" = 0 ] && ok "medidor desligado: nada anotado" || nok "desligado anotou algo"

echo
echo "RESULTADO: $PASS ok · $FAIL falha"
[ "$FAIL" = 0 ]
