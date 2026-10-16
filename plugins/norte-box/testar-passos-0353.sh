#!/usr/bin/env bash
# Teste da caixa 0.3.53 (todas as etapas do /obrigado marcadas pelo PROGRAMA) — roda SÓ no Mac,
# num HOME de mentira; nada publicado. Compara com a 0.3.52 (commit f1edd1e).
set -u
NOVO=~/norte-box-dist-nrt995031/plugins/norte-box
T=/tmp/nb0353/run-$(date +%s)
N=0
mkdir -p "$T/old"
git -C ~/norte-box-dist-nrt995031 archive f1edd1e plugins/norte-box | tar -x -C "$T/old"
VELHO="$T/old/plugins/norte-box"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  OK   %s\n' "$1"; }
nok() { FAIL=$((FAIL+1)); printf '  FALHA %s\n' "$1"; }
ms() { perl -MTime::HiRes=time -e 'printf "%d",time()*1000'; }

PORT=18753
prep_home() { # [interno|interno-falha]
  N=$((N+1)); HM="$T/home$N"; mkdir -p "$HM/.norte-box"
  local H="$HM/.norte-box"
  printf 'compartilhavel\n' > "$H/modo"
  printf '{"versao":"5","hash":"teste"}' > "$H/consent.json"
  printf '{"invite_id":"teste-0353","ingest_token":"tok-teste"}' > "$H/identity.json"
  : > "$H/telemetry.enabled"
  printf 'NORTE_BOX_TELEMETRY_URL=http://127.0.0.1:%s/ingest\n' "$PORT" > "$H/.env"
  if [ "${1:-}" = interno ] || [ "${1:-}" = interno-falha ]; then
    mkdir -p "$HM/.claude/scripts" "$HM/.claude/handoffs"
    local rc=0; [ "$1" = interno-falha ] && rc=3
    printf '#!/usr/bin/env bash\necho "registro: conversa movida pra Concluida"\nexit %s\n' "$rc" > "$HM/.claude/scripts/norte-concluir-conversa.sh"
    chmod +x "$HM/.claude/scripts/norte-concluir-conversa.sh"
  fi
}
Q() { cat "$HM/.norte-box/telemetry-queue.jsonl" 2>/dev/null; }
esperar() { sleep 0.7; }
export CLAUDE_CODE_SESSION_ID="sessao-de-teste-0353"

mk_proj() { # cria projeto com norte-out/handoffs e 1 bilhete antigo + 1 novo
  N=$((N+1)); P="$T/proj$N"; D="$P/norte-out/handoffs"; mkdir -p "$D"
  printf -- '---\nobjetivo: antigo\nfio: NRT-_1\n---\n# velho\n' > "$D/painel-20261014-1200.md"
  ( cd "$D" && ln -sf painel-20261014-1200.md ULTIMO.md )
  NOVOB="$D/painel-20261015-1100.md"
  printf -- '---\nobjetivo: painel de uso melhor\nfio: NRT-_1\n---\n# novo\n' > "$NOVOB"
}
aponta_ultimo() { ( cd "$D" && ln -sf "$(basename "$NOVOB")" ULTIMO.md ); }
conta() { esperar; Q | jq -c --arg h "$1" --arg p "$2" --arg r "$3" 'select(.kind=="passo" and .passo.habilidade==$h and .passo.passo==$p and .passo.resultado==$r)' 2>/dev/null | wc -l | tr -d ' '; }
tem() { local n; n=$(conta "$1" "$2" "$3"); [ "$n" -ge 1 ] && ok "$1 · $2 → $3" || nok "$1 · $2 → $3 (fila: $(Q | jq -c '.passo' 2>/dev/null | tr '\n' ' '))"; }

# /obrigado SÓ com as linhas que a IA PRECISA rodar (as que dão resposta) — nenhuma linha "silenciosa".
obrigado_so_bilhete() { # $1 = raiz da caixa ; $2 = nova|velha
  if [ "$2" = nova ]; then
    aponta_ultimo
    HOME=$HM bash "$1/bin/nb-bilhete-objetivo" "$NOVOB" obrigado >/dev/null
    HOME=$HM bash "$1/bin/nb-obrigado-onde" >/dev/null
  else
    aponta_ultimo
    HOME=$HM bash "$1/bin/nb-bilhete-objetivo" "$NOVOB" >/dev/null
    ONDE="$(if [ -x "$HM/.claude/scripts/norte-concluir-conversa.sh" ]; then echo INTERNO; else echo SO-BILHETE; fi)"
  fi
}

echo "== 1. A resposta de cada programa ficou IGUAL à da 0.3.52?"
prep_home; mk_proj
a="$(HOME=$HM bash "$VELHO/bin/nb-bilhete-objetivo" "$NOVOB")"; b="$(HOME=$HM bash "$NOVO/bin/nb-bilhete-objetivo" "$NOVOB")"
[ "$a" = "$b" ] && ok "objetivo (/continuar) — mesma resposta: $b" || nok "objetivo: [$a] x [$b]"
b2="$(HOME=$HM bash "$NOVO/bin/nb-bilhete-objetivo" "$NOVOB" obrigado)"
[ "$a" = "$b2" ] && ok "objetivo (/obrigado) — mesma resposta" || nok "objetivo obrigado: [$a] x [$b2]"
a="$(HOME=$HM bash "$VELHO/bin/nb-bilhete-objetivo" "$T/nao-existe.md")"; b="$(HOME=$HM bash "$NOVO/bin/nb-bilhete-objetivo" "$T/nao-existe.md" obrigado)"
[ "$a" = "$b" ] && ok "objetivo sem bilhete — mesma resposta: $b" || nok "objetivo sem bilhete"
for modo in so interno; do
  [ $modo = interno ] && prep_home interno || prep_home
  a="$(if [ "${NORTE_OBRIGADO_INTERNO:-1}" != "0" ] && [ -x "$HM/.claude/scripts/norte-concluir-conversa.sh" ]; then echo "INTERNO"; else echo "SO-BILHETE"; fi)"
  b="$(HOME=$HM bash "$NOVO/bin/nb-obrigado-onde")"
  [ "$a" = "$b" ] && ok "onde estou — mesma resposta da linha antiga: $b" || nok "onde: [$a] x [$b]"
done
for modo in interno interno-falha; do
  prep_home $modo
  a="$(HOME=$HM "$HM/.claude/scripts/norte-concluir-conversa.sh" --bilhete x)"; ra=$?
  b="$(HOME=$HM bash "$NOVO/bin/nb-obrigado-fechar" x)"; rb=$?
  [ "$a" = "$b" ] && [ $ra = $rb ] && ok "fechar no registro — mesma resposta e mesmo código ($rb)" || nok "fechar: [$a]$ra x [$b]$rb"
done

echo "== 2. ANTES × DEPOIS: um /obrigado onde a IA só roda o que precisa (pula as linhas silenciosas)"
prep_home; mk_proj; obrigado_so_bilhete "$VELHO" velha; esperar
v="$(Q | jq -r 'select(.kind=="passo") | .passo.habilidade+" · "+.passo.passo' | sort -u | tr '\n' ';')"
prep_home; mk_proj; obrigado_so_bilhete "$NOVO" nova; esperar
n="$(Q | jq -r 'select(.kind=="passo") | .passo.habilidade+" · "+.passo.passo' | sort -u | tr '\n' ';')"
printf '  0.3.52 anotou: %s\n  0.3.53 anotou: %s\n' "${v:-nada}" "$n"
tem obrigado bilhete_com_objetivo ok
tem obrigado ponteiro ok
tem obrigado onde_estou so_bilhete
case "$v" in *ponteiro*) nok "0.3.52 não deveria anotar o ponteiro sem a linha silenciosa" ;; *) ok "0.3.52 sem a linha silenciosa: ponteiro NÃO anotado (o buraco de hoje)" ;; esac

echo "== 3. /obrigado na tela da Norte (fecha no registro)"
prep_home interno; mk_proj; aponta_ultimo
HOME=$HM bash "$NOVO/bin/nb-bilhete-objetivo" "$NOVOB" obrigado >/dev/null
HOME=$HM bash "$NOVO/bin/nb-obrigado-onde" >/dev/null
GH="$HM/.claude/handoffs/grande.md"; printf -- '---\nobjetivo: x\n---\n' > "$GH"
HOME=$HM bash "$NOVO/bin/nb-bilhete-objetivo" "$GH" obrigado >/dev/null
HOME=$HM bash "$NOVO/bin/nb-obrigado-fechar" "$GH" >/dev/null
tem obrigado onde_estou interno
tem obrigado fechou_registro ok
c=$(conta obrigado ponteiro ok); [ "$c" = 1 ] && ok "ponteiro anotado 1 vez só (o bilhete grande não conta de novo)" || nok "ponteiro anotado $c vezes"
prep_home interno-falha
HOME=$HM bash "$NOVO/bin/nb-obrigado-fechar" "$GH" >/dev/null; r=$?
tem obrigado fechou_registro falhou
[ $r = 3 ] && ok "registro falhou → código 3 devolvido igual" || nok "código $r"

echo "== 4. /continuar: o ponteiro é conferido de verdade"
prep_home; mk_proj; aponta_ultimo; HOME=$HM bash "$NOVO/bin/nb-bilhete-objetivo" "$NOVOB" >/dev/null
tem continuar ponteiro ok
prep_home; mk_proj; HOME=$HM bash "$NOVO/bin/nb-bilhete-objetivo" "$NOVOB" >/dev/null
tem continuar ponteiro aponta_outro
prep_home; mk_proj; rm -f "$D/ULTIMO.md"; HOME=$HM bash "$NOVO/bin/nb-bilhete-objetivo" "$NOVOB" >/dev/null
tem continuar ponteiro falhou
prep_home; mk_proj; aponta_ultimo; HOME=$HM bash "$NOVO/bin/nb-bilhete-objetivo" "$NOVOB" >/dev/null
c=$(conta obrigado ponteiro ok); [ "$c" = 0 ] && ok "/continuar não é confundido com /obrigado" || nok "/continuar virou obrigado"

echo "== 5. Nada de conteúdo sobe"
if Q | grep -q -e "/tmp" -e "painel de uso" -e "NRT-_" -e "sessao-de-teste" -e "Concluida"; then nok "achei conteúdo na fila"; else ok "fila só com rótulos"; fi
CH="$(Q | jq -c 'select(.kind=="passo") | keys' | sort -u | tr '\n' ' ')"
[ "$CH" = '["invite_id","kind","passo","run_id","ts","versao"] ' ] && ok "só os campos combinados" || nok "campos: $CH"
Q | jq -r 'select(.kind=="passo") | .versao' | sort -u | grep -qx '0.3.53' && ok "versão 0.3.53 em todo passo" || nok "versão"

echo "== 6. Portões: quem não aceitou não manda nada"
for caso in privado sem-consent desligado kill; do
  prep_home interno; mk_proj; aponta_ultimo
  case $caso in
    privado) printf 'privado\n' > "$HM/.norte-box/modo" ;;
    sem-consent) rm -f "$HM/.norte-box/consent.json" ;;
    desligado) rm -f "$HM/.norte-box/telemetry.enabled" ;;
  esac
  export NORTE_BOX_PASSO=1; [ $caso = kill ] && export NORTE_BOX_PASSO=0
  HOME=$HM bash "$NOVO/bin/nb-bilhete-objetivo" "$NOVOB" obrigado >/dev/null
  HOME=$HM bash "$NOVO/bin/nb-obrigado-onde" >/dev/null
  HOME=$HM bash "$NOVO/bin/nb-obrigado-fechar" x >/dev/null
  unset NORTE_BOX_PASSO
  esperar; n=$(Q | wc -l | tr -d ' ')
  [ "$n" = 0 ] && ok "$caso → 0 linhas" || nok "$caso → $n linhas"
done

echo "== 7. DERRUBANDO a anotação: o /obrigado continua igual e rápido?"
mkdir -p "$T/quebrado"; cp -R "$NOVO/." "$T/quebrado/"
for jeito in erro travado apagado; do
  prep_home interno; mk_proj; aponta_ultimo
  case $jeito in
    erro) printf '#!/usr/bin/env bash\nexit 7\n' > "$T/quebrado/bin/nb-passo" ;;
    travado) printf '#!/usr/bin/env bash\nsleep 20\n' > "$T/quebrado/bin/nb-passo" ;;
    apagado) rm -f "$T/quebrado/bin/nb-passo" ;;
  esac
  t0=$(ms)
  o1="$(HOME=$HM bash "$T/quebrado/bin/nb-bilhete-objetivo" "$NOVOB" obrigado)"
  o2="$(HOME=$HM bash "$T/quebrado/bin/nb-obrigado-onde")"
  o3="$(HOME=$HM bash "$T/quebrado/bin/nb-obrigado-fechar" x)"; r3=$?
  t1=$(ms)
  if [ "$o1" = "OBJETIVO: painel de uso melhor" ] && [ "$o2" = INTERNO ] && [ "$o3" = "registro: conversa movida pra Concluida" ] && [ $r3 = 0 ] && [ $((t1-t0)) -lt 3000 ]
  then ok "anotação $jeito → as 3 etapas responderam igual em $((t1-t0)) ms"; else nok "anotação $jeito ($((t1-t0)) ms · [$o1][$o2][$o3]$r3)"; fi
  pkill -f "$T/quebrado/bin/nb-passo" 2>/dev/null
done
prep_home interno; mk_proj; aponta_ultimo
rm -f "$HM/.norte-box/telemetry-queue.jsonl"; mkdir -p "$HM/.norte-box/telemetry-queue.jsonl"
o="$(HOME=$HM bash "$NOVO/bin/nb-obrigado-onde")$(HOME=$HM bash "$NOVO/bin/nb-obrigado-fechar" x)"; r=$?
[ "$o" = "INTERNOregistro: conversa movida pra Concluida" ] && [ $r = 0 ] && ok "fila impossível de gravar → mesma resposta" || nok "fila quebrada [$o]"
rmdir "$HM/.norte-box/telemetry-queue.jsonl"

echo "== 8. ENVIO: servidor fora do ar não perde nada; voltou, chega"
prep_home interno; mk_proj; aponta_ultimo
HOME=$HM bash "$NOVO/bin/nb-bilhete-objetivo" "$NOVOB" obrigado >/dev/null
HOME=$HM bash "$NOVO/bin/nb-obrigado-onde" >/dev/null
HOME=$HM bash "$NOVO/bin/nb-obrigado-fechar" x >/dev/null
esperar
t0=$(ms); HOME=$HM bash "$NOVO/hooks/telemetry-drain.sh" </dev/null; r=$?; t1=$(ms)
cur="$(cat $HM/.norte-box/telemetry-queue.cursor 2>/dev/null || echo 0)"
nf=$(Q | jq -c 'select(.kind=="passo")' | wc -l | tr -d ' ')
[ $r = 0 ] && [ "${cur:-0}" = 0 ] && ok "servidor DESLIGADO → dreno saiu em $((t1-t0)) ms, $nf etapas seguem guardadas" || nok "servidor desligado (rc=$r cursor=$cur)"
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
[ "$n" = "$nf" ] && ok "servidor LIGADO → as $n etapas chegaram ($(jq -r '.[]? // . | select(.kind=="passo") | .passo.passo' "$T/recebido.jsonl" | sort -u | tr '\n' ' '))" || nok "chegaram $n de $nf"

echo
echo "RESULTADO: $PASS ok · $FAIL falha(s)"
[ $FAIL = 0 ]
