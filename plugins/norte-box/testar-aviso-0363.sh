#!/usr/bin/env bash
# Teste da caixa 0.3.63 (anota quando a conversa nova mostra o bilhete) — HOME de mentira; nada publicado, nada enviado.
T="$(mktemp -d /tmp/nbaviso.XXXXXX)"; CX="${NB_CAIXA:-$(cd "$(dirname "$0")" && pwd)}"; RODADA="${RODADA:-$(date +%s)}"
unset NORTE_SEAT NORTE_SEAT_AUTO NORTE_BOX_PASSO NORTE_BILHETE_OFERTA CLAUDE_PLUGIN_ROOT
export CLAUDE_CODE_SESSION_ID="sess-teste-aviso"
prep() { # $1 = nome do cenario (pasta nova a cada rodada, nunca apaga nada)
  H="$T/run-$RODADA/$1/home"; P="$T/run-$RODADA/$1/proj"; mkdir -p "$H/.norte-box" "$P/norte-out/handoffs"
  echo compartilhavel > "$H/.norte-box/modo"
  echo '{"versao":"5","aceito":true,"hash":"teste"}' > "$H/.norte-box/consent.json"
  echo '{"invite_id":"convite-teste"}' > "$H/.norte-box/identity.json"
  : > "$H/.norte-box/telemetry.enabled"
}
bil() { # $1 nome, $2 assunto, $3 minutos atras
  f="$P/norte-out/handoffs/$1"; printf -- '---\nobjetivo: segredo-do-cliente %s\n---\n# Session Handoff: %s\n\ntexto sigiloso do cliente\n' "$2" "$2" > "$f"
  touch -t "$(date -v-"$3"M +%Y%m%d%H%M.%S)" "$f"
}
abre() { ( cd "$P" && printf '{"source":"startup","cwd":"%s"}' "$P" | HOME="$H" NORTE_OUT_DIR="$P/norte-out" bash "$CX/hooks/bilhete-oferta.sh" ); }
fila() { cat "$H/.norte-box/telemetry-queue.jsonl" 2>/dev/null; }
mostra() { echo "== $1"; echo "   tela: $(abre | jq -r '.systemMessage // "(nada na tela)"' 2>/dev/null)"; echo "   anotou: $(fila | tail -1 | jq -c '.passo' 2>/dev/null)"; }

prep novo;    bil 2026-11-09-1000-assunto-a.md "Assunto A" 10;                                       mostra "1 novo (10 min)"
              echo "== 2 ja visto (abre de novo, mesma pasta)"; abre >/dev/null; echo "   anotou: $(fila | tail -1 | jq -c '.passo')"
prep velho;   bil 2026-11-08-1000-assunto-v.md "Assunto V" 1200;                                     mostra "3 velho (20 h)"
prep varios;  bil 2026-11-09-1000-assunto-a.md "Assunto A" 30; bil 2026-11-09-1001-assunto-b.md "Assunto B" 20; mostra "4 varios"
prep nenhum;                                                                                        mostra "5 nenhum"
echo "== PRIVACIDADE: texto do bilhete na fila?"; grep -rl "segredo\|sigiloso\|Assunto" "$T/run-$RODADA"/*/home/.norte-box/telemetry-queue.jsonl 2>/dev/null && echo "   VAZOU" || echo "   nao (0 arquivos com texto)"
echo "== CODIGO bate com o /continuar?"; prep liga; bil 2026-11-09-1000-assunto-a.md "Assunto A" 5
  cp "$P/norte-out/handoffs/2026-11-09-1000-assunto-a.md" "$P/norte-out/handoffs/ULTIMO.md"
  ( cd "$P" && HOME="$H" bash "$CX/bin/nb-passo" bilhete ponteiro --confere "$P/norte-out/handoffs/ULTIMO.md" "$P/norte-out/handoffs/2026-11-09-1000-assunto-a.md" )
  c1=$(fila | tail -1 | jq -r '.passo.bilhete'); abre >/dev/null; c2=$(fila | tail -1 | jq -r '.passo.bilhete')
  echo "   /continuar: $c1 · aviso: $c2 · $([ -n "$c1" ] && [ "$c1" = "$c2" ] && echo IGUAL || echo DIFERENTE)"
echo "== DESLIGAR (NORTE_BOX_PASSO_AVISO=0)"; prep off; bil 2026-11-09-1000-assunto-a.md "Assunto A" 5
  export NORTE_BOX_PASSO_AVISO=0; abre >/dev/null; unset NORTE_BOX_PASSO_AVISO; echo "   linhas na fila: $(fila | wc -l | tr -d ' ')"
echo "== MODO PRIVADO (sem envio)"; prep priv; echo privado > "$H/.norte-box/modo"; bil 2026-11-09-1000-assunto-a.md "Assunto A" 5; abre >/dev/null; echo "   linhas na fila: $(fila | wc -l | tr -d ' ')"
echo "== TEMPO da abertura (10x)"; prep tempo; s=$(python3 -c 'import time;print(time.time())'); for i in 1 2 3 4 5 6 7 8 9 10; do abre >/dev/null; done; e=$(python3 -c 'import time;print(time.time())'); python3 -c "print('   media: %.0f ms por abertura'%(($e-$s)*100))"
echo "== NAO PERDE: 25 aberturas, leitura na hora"; n=0; for i in $(seq 1 25); do prep perde$i; bil 2026-11-09-1000-assunto-a.md "Assunto A" 10; abre >/dev/null; [ "$(fila | wc -l | tr -d ' ')" = 1 ] && n=$((n+1)); done; echo "   $n de 25 anotadas na hora"
echo "== TEMPERO: mesmo bilhete em 2 computadores"; prep pcA; bil 2026-11-09-1000-assunto-a.md "Assunto A" 10; abre >/dev/null; cA=$(fila | jq -r .passo.bilhete)
  prep pcB; bil 2026-11-09-1000-assunto-a.md "Assunto A" 10; abre >/dev/null; cB=$(fila | jq -r .passo.bilhete)
  sem=$(printf 'norte-bilhete:2026-11-09-1000-assunto-a.md' | shasum -a 256 | cut -c1-16)
  echo "   pc A: $cA · pc B: $cB · $([ "$cA" != "$cB" ] && echo DIFERENTES || echo IGUAIS)"; echo "   adivinhar pelo nome, sem o tempero: $sem · $([ "$sem" != "$cA" ] && echo "NAO acerta" || echo ACERTA)"
  echo "   tempero sai na fila? $(grep -c "$(cat $H/.norte-box/bilhete-tempero)" $H/.norte-box/telemetry-queue.jsonl) vezes"
echo "== SEM shasum (usa a 2a forma)"; mkdir -p $T/semsha; for b in bash jq openssl cut cat date mkdir grep basename dirname find head sed awk rm tr python3 stat touch cp wc od mv env printf readlink ls sort git; do p=$(command -v $b 2>/dev/null) && ln -sf "$p" $T/semsha/$b; done
  prep semsha; bil 2026-11-09-1000-assunto-a.md "Assunto A" 10; ( PATH=$T/semsha; abre >/dev/null ); echo "   anotou: $(fila | tail -1 | jq -c .passo)"
echo "== DESLIGAR GERAL (NORTE_BOX_PASSO=0, 0.3.64)"; prep geral; bil 2026-11-09-1000-assunto-a.md "Assunto A" 10; ( export NORTE_BOX_PASSO=0; abre >/dev/null ); echo "   linhas na fila: $(fila | wc -l | tr -d ' ')"
