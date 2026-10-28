#!/usr/bin/env bash
# Teste da caixa 0.3.59 (/fios-soltos) — roda num HOME de mentira; nada publicado, nada enviado.
set -u
NOVO="${NB_CAIXA:-$(cd "$(dirname "$0")" && pwd)}"
T="$(mktemp -d /tmp/nbfios.XXXXXX)"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  OK   %s\n' "$1"; }
nok() { FAIL=$((FAIL+1)); printf '  FALHA %s\n' "$1"; }
HM="$T/home"; H="$HM/.norte-box"; mkdir -p "$H"
printf 'compartilhavel\n' > "$H/modo"
printf '{"versao":"5","hash":"teste"}' > "$H/consent.json"
printf '{"invite_id":"teste-0359","ingest_token":"tok-teste"}' > "$H/identity.json"
: > "$H/telemetry.enabled"
printf 'NORTE_BOX_TELEMETRY_URL=http://127.0.0.1:9/ingest\n' > "$H/.env"
export CLAUDE_CODE_SESSION_ID="sessao-de-teste-0359"
Q() { cat "$H/telemetry-queue.jsonl" 2>/dev/null; }
roda() { HOME="$HM" bash "$NOVO/bin/nb-fios-soltos" "$@"; }
espera_res() { # passo resultado
  sleep 0.8
  if Q | jq -e --arg p "$1" --arg r "$2" 'select(.kind=="passo" and .passo.habilidade=="fios-soltos" and .passo.passo==$p and .passo.resultado==$r)' >/dev/null 2>&1
  then ok "passo $1 → $2"; else nok "passo $1 → $2 (fila: $(Q | tail -1))"; fi
}

# --- bilhetes de mentira ---
P="$T/proj/norte-out/handoffs"; mkdir -p "$P"
cat > "$P/site-loja-20261020-1000.md" <<'MD'
---
fio: x
---
## Objetivo (1 frase)
Site da loja no ar.
## Onde estamos (mapa: [x] feito / [ ] pendente)
- [x] pagina inicial
- [ ] formulario de contato
## Proximo passo (1, concreto)
ligar o formulario
MD
cat > "$P/site-loja-20261025-1000.md" <<'MD'
## Objetivo (1 frase)
Site da loja no ar.
## Onde estamos (mapa: [x] feito / [ ] pendente)
- [x] pagina inicial
- [x] formulario de contato
- [ ] trocar a foto do topo
- [ ] ⚠ nao achei no disco: fotos/topo.jpg (o bilhete marcava feito, mas o disco nao mostra) — era: foto nova
## Pedidos do usuario nesta conversa (todos, com status)
- [pendente] mandar o link pro socio
- [feito] logo novo
## Proximo passo (1, concreto)
trocar a foto do topo
MD
cat > "$P/planilha-20261026-0900.md" <<'MD'
## Objetivo (1 frase)
Planilha de custos.
## Onde estamos (mapa: [x] feito / [ ] pendente)
- [x] tudo feito
## Proximo passo (1, concreto)
nada
MD
printf 'texto solto sem molde\n' > "$P/solto-20261026-0900.md"
printf 'site-loja-20261025-1000.md\n' > "$P/.ja-visto"
touch -t 202610200000 "$P/site-loja-20261020-1000.md"; touch -t 202610250000 "$P/site-loja-20261025-1000.md"
VAZ="$T/vazio/norte-out"; mkdir -p "$VAZ/handoffs"

echo "== 1. O que aparece na lista"
OUT="$(NORTE_BOX_PASSO=0 roda "$T/proj/norte-out" 3650)"
printf '%s\n' "$OUT" | grep -c '^FIO' | grep -qx 1 && ok "só 1 assunto com coisa aberta (site-loja)" || nok "assuntos: $(printf '%s\n' "$OUT" | grep '^FIO')"
printf '%s\n' "$OUT" | grep -q 'formulario de contato' && nok "item fechado no bilhete novo voltou" || ok "o que o bilhete novo fechou NÃO volta (formulario de contato)"
printf '%s\n' "$OUT" | grep -q $'pendente\ttrocar a foto do topo' && ok "item pendente do bilhete novo aparece" || nok "faltou item pendente"
printf '%s\n' "$OUT" | grep -q $'conferir\t' && ok "item 'não achei no disco' vira 'conferir'" || nok "faltou conferir"
printf '%s\n' "$OUT" | grep -q 'mandar o link pro socio' && ok "pedido pendente aparece" || nok "faltou pedido pendente"
printf '%s\n' "$OUT" | grep -q 'logo novo' && nok "pedido feito apareceu" || ok "pedido feito NÃO aparece"
printf '%s\n' "$OUT" | grep -q 'planilha' && nok "assunto sem nada aberto apareceu" || ok "assunto todo feito NÃO aparece (planilha)"
printf '%s\n' "$OUT" | grep '^ITEM' | awk -F'\t' '$2 !~ /:[0-9]+$/' | grep -q . && nok "item sem fonte" || ok "todo item vem com arquivo:linha"
printf '%s\n' "$OUT" | grep -q $'^FIO\tsite-loja\t[0-9]*\t3\tsim\t' && ok "conta 3 abertos e sabe que já foi retomado" || nok "linha FIO: $(printf '%s\n' "$OUT" | grep '^FIO')"
printf '%s\n' "$OUT" | grep -q $'^RESUMO\t4\t3\t1\t3\t1$' && ok "resumo: 4 bilhetes, 3 assuntos, 1 com aberto, 3 itens, 1 sem molde" || nok "resumo: $(printf '%s\n' "$OUT" | grep '^RESUMO')"
OUT30="$(NORTE_BOX_PASSO=0 roda "$T/proj/norte-out" 0)"
printf '%s\n' "$OUT30" | grep -q '^ANTIGOS' && ok "assunto mais velho que a janela vira só contagem (ANTIGOS)" || nok "janela: $OUT30"

echo "== 2. Não grava nada"
ANTES="$(cd "$T" && find . -type f -exec shasum {} \; | sort)"
HOME="$HM" NORTE_BOX_PASSO=0 bash "$NOVO/bin/nb-fios-soltos" "$T/proj/norte-out" >/dev/null
DEPOIS="$(cd "$T" && find . -type f -exec shasum {} \; | sort)"
[ "$ANTES" = "$DEPOIS" ] && ok "nenhum arquivo mudou depois de rodar" || nok "algum arquivo mudou"
printf '%s\n' "$OUT" | grep -qx 'GRAVOU nada' && ok "o próprio programa confere: GRAVOU nada" || nok "sem a linha GRAVOU nada"

echo "== 3. Cada passo foi marcado (sem conteúdo)"
: > "$H/telemetry-queue.jsonl"
roda "$T/proj/norte-out" 3650 >/dev/null
espera_res achou_bilhetes ok
espera_res leu_molde alguns_sem_molde
espera_res listou ok
espera_res nao_gravou ok
Q | grep -qE 'site-loja|foto|socio|formulario' && nok "texto do bilhete vazou pra fila" || ok "nenhum texto do bilhete na fila (só rótulos)"
: > "$H/telemetry-queue.jsonl"
roda "$VAZ" >/dev/null
espera_res achou_bilhetes vazio
espera_res listou nao_se_aplica
: > "$H/telemetry-queue.jsonl"
HOME="$HM" NORTE_BOX_PASSO=0 bash "$NOVO/bin/nb-fios-soltos" "$T/proj/norte-out" >/dev/null; sleep 0.8
[ -s "$H/telemetry-queue.jsonl" ] && nok "NORTE_BOX_PASSO=0 ainda marcou" || ok "desligar (NORTE_BOX_PASSO=0) não marca nada"
rm -f "$H/consent.json"; : > "$H/telemetry-queue.jsonl"
roda "$T/proj/norte-out" >/dev/null; sleep 0.8
[ -s "$H/telemetry-queue.jsonl" ] && nok "marcou sem consentimento" || ok "sem consentimento não marca nada"

echo
echo "RESULTADO: $PASS ok · $FAIL falha"
[ "$FAIL" = 0 ]
