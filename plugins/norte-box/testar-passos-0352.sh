#!/usr/bin/env bash
# Teste da caixa 0.3.52 (marca passos) — roda SÓ no Mac, num HOME de mentira; nada publicado.
set -u
NOVO=~/norte-box-dist-nrt995031/plugins/norte-box
T=/tmp/nb0352/run-$(date +%s)
N=0
mkdir -p "$T/old"
git -C ~/norte-box-dist-nrt995031 archive origin/main plugins/norte-box | tar -x -C "$T/old"
VELHO="$T/old/plugins/norte-box"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  OK   %s\n' "$1"; }
nok() { FAIL=$((FAIL+1)); printf '  FALHA %s\n' "$1"; }

PORT=18752
prep_home() {
  N=$((N+1)); HM="$T/home$N"; mkdir -p "$HM/.norte-box"
  H="$HM/.norte-box"
  printf 'compartilhavel\n' > "$H/modo"
  printf '{"versao":"5","hash":"teste"}' > "$H/consent.json"
  printf '{"invite_id":"teste-0352","ingest_token":"tok-teste"}' > "$H/identity.json"
  : > "$H/telemetry.enabled"
  printf 'NORTE_BOX_TELEMETRY_URL=http://127.0.0.1:%s/ingest\n' "$PORT" > "$H/.env"
}
Q() { cat "$HM/.norte-box/telemetry-queue.jsonl" 2>/dev/null; }
esperar() { sleep 0.6; }
export CLAUDE_CODE_SESSION_ID="sessao-de-teste-0352"

# fixtures de bilhete
mk_bilhetes() {
  N=$((N+1)); FX="$T/fx$N"; mkdir -p "$FX/um/handoffs" "$FX/dois/handoffs" "$FX/vazio/handoffs"
  printf -- '---\nobjetivo: painel de uso melhor\nfio: NRT-_1\n---\n# b\n' > "$FX/um/handoffs/painel-20261014-1200.md"
  printf -- '---\nfio: NRT-_1\n---\n# sem objetivo\n' > "$FX/dois/handoffs/assunto-a-20261014-1200.md"
  printf -- '---\nfio: NRT-_2\n---\n# outro\n' > "$FX/dois/handoffs/assunto-b-20261014-1201.md"
}

echo "== 1. A saída de cada programa ficou IGUAL à da caixa de hoje (0.3.51)?"
prep_home; mk_bilhetes
compara() { # nome args...
  local n="$1"; shift
  mk_bilhetes; local a; a="$(HOME=$HM bash "$VELHO/bin/$n" "$@" 2>&1)"; local ra=$?
  mk_bilhetes; local b; b="$(HOME=$HM bash "$NOVO/bin/$n" "$@" 2>&1)"; local rb=$?
  if [ "$a" = "$b" ] && [ "$ra" = "$rb" ]; then ok "$n $(basename "${1:-}") — mesma saída e mesmo código ($rb)"; else nok "$n $*"; printf 'velho=[%s]%s\nnovo=[%s]%s\n' "$a" "$ra" "$b" "$rb"; fi
}
compara nb-retomar-alvo "$FX/um"
compara nb-retomar-alvo "$FX/dois"
compara nb-retomar-alvo "$FX/vazio"
compara nb-retomar-adota "$FX/um/handoffs/painel-20261014-1200.md"
compara nb-retomar-adota ""
compara nb-bilhete-validade "$FX/um/handoffs/painel-20261014-1200.md"
compara nb-bilhete-validade "$FX/nao-existe.md"
compara nb-bilhete-validade
compara nb-bilhete-objetivo "$FX/um/handoffs/painel-20261014-1200.md"
compara nb-bilhete-objetivo "$FX/dois/handoffs/assunto-a-20261014-1200.md"
compara nb-bilhete-objetivo "$FX/nao-existe.md"

echo "== 2. Cada passo foi marcado com o resultado certo?"
espera_res() { # habilidade passo resultado
  esperar
  if Q | jq -e --arg h "$1" --arg p "$2" --arg r "$3" 'select(.kind=="passo" and .passo.habilidade==$h and .passo.passo==$p and .passo.resultado==$r)' >/dev/null 2>&1
  then ok "$1 · $2 → $3"; else nok "$1 · $2 → $3 (fila: $(Q | tail -1))"; fi
}
prep_home; mk_bilhetes
HOME=$HM bash "$NOVO/bin/nb-retomar-alvo" "$FX/um" >/dev/null;   espera_res norte-retomar achou_bilhete ok
HOME=$HM bash "$NOVO/bin/nb-retomar-alvo" "$FX/dois" >/dev/null; espera_res norte-retomar achou_bilhete ambiguo
HOME=$HM bash "$NOVO/bin/nb-retomar-alvo" "$FX/vazio" >/dev/null; espera_res norte-retomar achou_bilhete vazio
printf -- '---\nfio: NRT-_9\nrelay: false\n---\n' > "$FX/ref.md"
HOME=$HM bash "$NOVO/bin/nb-retomar-adota" "$FX/ref.md" >/dev/null; espera_res norte-retomar sentou_conversa nao_pedido
printf -- '---\nfio: NRT-_9\nrelay: true\n---\n' > "$FX/relay.md"
HOME=$HM bash "$NOVO/bin/nb-retomar-adota" "$FX/relay.md" >/dev/null; espera_res norte-retomar sentou_conversa nao_se_aplica
HOME=$HM bash "$NOVO/bin/nb-bilhete-validade" "$FX/nao-existe.md" >/dev/null; espera_res norte-retomar aviso_vencido nao_sei
HOME=$HM bash "$NOVO/bin/nb-bilhete-objetivo" "$FX/um/handoffs/painel-20261014-1200.md" >/dev/null; espera_res continuar bilhete_com_objetivo ok
HOME=$HM bash "$NOVO/bin/nb-bilhete-objetivo" "$FX/dois/handoffs/assunto-a-20261014-1200.md" >/dev/null; espera_res continuar bilhete_com_objetivo sem_objetivo
HOME=$HM bash "$NOVO/bin/nb-passo" --sou obrigado
HOME=$HM bash "$NOVO/bin/nb-bilhete-objetivo" "$FX/nao-existe.md" >/dev/null; espera_res obrigado bilhete_com_objetivo sem_bilhete
( cd "$FX/um/handoffs" && ln -sf painel-20261014-1200.md ULTIMO.md )
HOME=$HM bash "$NOVO/bin/nb-passo" bilhete ponteiro --confere "$FX/um/handoffs/ULTIMO.md" "$FX/um/handoffs/painel-20261014-1200.md"; espera_res obrigado ponteiro ok
HOME=$HM bash "$NOVO/bin/nb-passo" bilhete ponteiro --confere "$FX/um/handoffs/ULTIMO.md" "$FX/dois/handoffs/assunto-a-20261014-1200.md"; espera_res obrigado ponteiro aponta_outro
HOME=$HM bash "$NOVO/bin/nb-passo" obrigado onde_estou --saida "SO-BILHETE"; espera_res obrigado onde_estou so_bilhete
HOME=$HM bash "$NOVO/bin/nb-passo" obrigado fechou_registro --rc 0; espera_res obrigado fechou_registro ok
HOME=$HM bash "$NOVO/bin/nb-passo" obrigado fechou_registro --rc 1; espera_res obrigado fechou_registro falhou

echo "== 3. Nada de conteúdo sobe (sem caminho, sem texto do bilhete)?"
if Q | grep -q -e "/tmp" -e "painel de uso" -e "NRT-_" -e "sessao-de-teste"; then nok "achei conteúdo na fila"; else ok "fila só com rótulos ($(Q | wc -l | tr -d ' ') linhas)"; fi
CH="$(Q | jq -c 'select(.kind=="passo") | keys' | sort -u | tr '\n' ' ')"
[ "$CH" = '["invite_id","kind","passo","run_id","ts","versao"] ' ] && ok "só os campos combinados: $CH" || nok "campos: $CH"
Q | jq -r 'select(.kind=="passo") | .versao' | sort -u | grep -qx '0.3.52' && ok "versão 0.3.52 em todo passo" || nok "versão"
printf '  exemplo de linha: %s\n' "$(Q | tail -1)"

echo "== 4. Portões: quem não aceitou não manda nada"
for caso in privado sem-consent desligado kill; do
  prep_home; mk_bilhetes
  case $caso in
    privado) printf 'privado\n' > "$HM/.norte-box/modo" ;;
    sem-consent) rm -f "$HM/.norte-box/consent.json" ;;
    desligado) rm -f "$HM/.norte-box/telemetry.enabled" ;;
  esac
  if [ $caso = kill ]; then NORTE_BOX_PASSO=0 HOME=$HM bash "$NOVO/bin/nb-retomar-alvo" "$FX/um" >/dev/null
  else HOME=$HM bash "$NOVO/bin/nb-retomar-alvo" "$FX/um" >/dev/null; fi
  esperar; n=$(Q | wc -l | tr -d ' ')
  [ "$n" = 0 ] && ok "$caso → 0 linhas na fila" || nok "$caso → $n linhas"
done

echo "== 5. DERRUBANDO a medição: a habilidade continua igual e rápida?"
prep_home; mk_bilhetes
ESPERADO="$(HOME=$HM bash "$VELHO/bin/nb-retomar-alvo" "$FX/um")"
# 5a fila impossível de gravar (vira uma pasta)
rm -f "$HM/.norte-box/telemetry-queue.jsonl"; mkdir -p "$HM/.norte-box/telemetry-queue.jsonl"
s="$(HOME=$HM bash "$NOVO/bin/nb-retomar-alvo" "$FX/um")"; r=$?
[ "$s" = "$ESPERADO" ] && [ $r = 0 ] && ok "fila quebrada → mesma resposta, código 0" || nok "fila quebrada"
rmdir "$HM/.norte-box/telemetry-queue.jsonl"
# 5b marcador quebrado / travado
mkdir -p "$T/quebrado"; cp -R "$NOVO/." "$T/quebrado/"
printf '#!/usr/bin/env bash\nexit 7\n' > "$T/quebrado/bin/nb-passo"
s="$(HOME=$HM bash "$T/quebrado/bin/nb-retomar-alvo" "$FX/um")"; r=$?
[ "$s" = "$ESPERADO" ] && [ $r = 0 ] && ok "marcador dando erro → mesma resposta" || nok "marcador dando erro"
printf '#!/usr/bin/env bash\nsleep 20\n' > "$T/quebrado/bin/nb-passo"
t0=$(perl -MTime::HiRes=time -e 'printf "%d",time()*1000')
s="$(HOME=$HM bash "$T/quebrado/bin/nb-retomar-alvo" "$FX/um")"
t1=$(perl -MTime::HiRes=time -e 'printf "%d",time()*1000')
[ "$s" = "$ESPERADO" ] && [ $((t1-t0)) -lt 2000 ] && ok "marcador TRAVADO 20s → respondeu em $((t1-t0)) ms" || nok "marcador travado ($((t1-t0)) ms)"
pkill -f "$T/quebrado/bin/nb-passo" 2>/dev/null
rm -f "$T/quebrado/bin/nb-passo"
s="$(HOME=$HM bash "$T/quebrado/bin/nb-retomar-alvo" "$FX/um")"
[ "$s" = "$ESPERADO" ] && ok "marcador APAGADO → mesma resposta" || nok "marcador apagado"

echo "== 6. ENVIO: servidor fora do ar não perde nada; voltou, chega"
prep_home; mk_bilhetes
HOME=$HM bash "$NOVO/bin/nb-retomar-alvo" "$FX/um" >/dev/null
HOME=$HM bash "$NOVO/bin/nb-retomar-alvo" "$FX/dois" >/dev/null
esperar
t0=$(perl -MTime::HiRes=time -e 'printf "%d",time()*1000')
HOME=$HM bash "$NOVO/hooks/telemetry-drain.sh" </dev/null; r=$?
t1=$(perl -MTime::HiRes=time -e 'printf "%d",time()*1000')
cur="$(cat $HM/.norte-box/telemetry-queue.cursor 2>/dev/null || echo 0)"
[ $r = 0 ] && [ "${cur:-0}" = 0 ] && ok "servidor DESLIGADO → dreno saiu em $((t1-t0)) ms, nada perdido (2 passos seguem na fila)" || nok "servidor desligado (rc=$r cursor=$cur)"
python3 - "$PORT" "$T/recebido.jsonl" <<'PY' &
import http.server, sys
port, out = int(sys.argv[1]), sys.argv[2]
class H(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        n = int(self.headers.get('Content-Length', 0)); b = self.rfile.read(n)
        open(out, 'ab').write(b + b'\n'); self.send_response(200); self.end_headers(); self.wfile.write(b'{"ok":true}')
    def log_message(self, *a): pass
http.server.HTTPServer(('127.0.0.1', port), H).serve_forever()
PY
SRV=$!; sleep 0.8
HOME=$HM bash "$NOVO/hooks/telemetry-drain.sh" </dev/null
sleep 0.5; kill $SRV 2>/dev/null
n=$(jq -c '.[]? // . | select(.kind=="passo")' "$T/recebido.jsonl" 2>/dev/null | wc -l | tr -d ' ')
[ "$n" = 2 ] && ok "servidor LIGADO → os 2 passos chegaram ($(jq -c '.[]? // . | select(.kind=="passo") | .passo.resultado' "$T/recebido.jsonl" | tr '\n' ' '))" || nok "chegaram $n passos (recebido: $(head -c 300 $T/recebido.jsonl 2>/dev/null))"

echo "== 7. Velocidade: quanto a marcação custa por chamada"
prep_home; mk_bilhetes
med() { local b="$1" t0 t1; t0=$(perl -MTime::HiRes=time -e 'printf "%d",time()*1000'); for i in 1 2 3 4 5 6 7 8 9 10; do HOME=$HM bash "$b/bin/nb-retomar-alvo" "$FX/um" >/dev/null; done; t1=$(perl -MTime::HiRes=time -e 'printf "%d",time()*1000'); echo $(( (t1-t0)/10 )); }
mv=$(med "$VELHO"); mn=$(med "$NOVO")
printf '  hoje (0.3.51): %s ms por chamada · 0.3.52: %s ms por chamada\n' "$mv" "$mn"
[ $((mn - mv)) -lt 150 ] && ok "custo extra $((mn-mv)) ms (menos de 0,15 s)" || nok "custo extra $((mn-mv)) ms"

echo
echo "RESULTADO: $PASS ok · $FAIL falha(s)"
[ $FAIL = 0 ]
