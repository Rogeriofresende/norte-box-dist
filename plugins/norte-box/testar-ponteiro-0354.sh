#!/usr/bin/env bash
# Teste da conta do ponteiro (0.3.54 em preparo · NRT-_997029) — roda SÓ no Mac, num HOME de
# mentira; nada publicado. Compara a 0.3.53 publicada (origin/main 12837db) com a de agora.
# Pergunta: o passo "ponteiro" diz se o ULTIMO.md APONTA pro bilhete salvo (não se o texto é igual)?
set -u
NOVO=~/norte-box-dist-nrt995031/plugins/norte-box
T=/tmp/nb0354/run-$(date +%s)
N=0
mkdir -p "$T/old"
git -C ~/norte-box-dist-nrt995031 archive 12837db plugins/norte-box | tar -x -C "$T/old"
VELHO="$T/old/plugins/norte-box"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  OK    %s\n' "$1"; }
nok() { FAIL=$((FAIL+1)); printf '  FALHA %s\n' "$1"; }

prep_home() {
  N=$((N+1)); HM="$T/home$N"; mkdir -p "$HM/.norte-box"
  local H="$HM/.norte-box"
  printf 'compartilhavel\n' > "$H/modo"
  printf '{"versao":"5","hash":"teste"}' > "$H/consent.json"
  printf '{"invite_id":"teste-0354","ingest_token":"tok-teste"}' > "$H/identity.json"
  : > "$H/telemetry.enabled"
  printf 'NORTE_BOX_TELEMETRY_URL=http://127.0.0.1:18754/ingest\n' > "$H/.env"
}
export CLAUDE_CODE_SESSION_ID="sessao-de-teste-0354"
export NORTE_OBJETIVO_FONTE=/nao/existe

# $1 caixa · $2 jeito do ponteiro (atalho|copia) · $3 pra onde (novo|antigo) · $4 forma do bilhete
#   forma: secao  = bilhete sai só com "## Objetivo" (a caixa escreve objetivo: depois — caso Ygor)
#          pronto = bilhete já sai com objetivo: (nada é reescrito)
#          semfm  = bilhete sem cabeçalho e com "## Objetivo"
resultado() {
  prep_home
  N=$((N+1)); D="$T/proj$N/norte-out/handoffs"; mkdir -p "$D"
  printf -- '---\nobjetivo: antigo\nfio: NRT-_1\n---\n# velho\n' > "$D/painel-20261014-1200.md"
  B="$D/painel-20261017-1100.md"
  case "$4" in
    secao)  printf -- '---\nfio: NRT-_1\n---\n# novo\n\n## Objetivo\npainel de uso melhor\n' > "$B" ;;
    pronto) printf -- '---\nobjetivo: painel de uso melhor\nfio: NRT-_1\n---\n# novo\n' > "$B" ;;
    semfm)  printf -- '# novo\n\n## Objetivo\npainel de uso melhor\n' > "$B" ;;
  esac
  local alvo; [ "$3" = novo ] && alvo="$(basename "$B")" || alvo=painel-20261014-1200.md
  case "$2" in
    atalho)   ( cd "$D" && ln -sf "$alvo" ULTIMO.md ) ;;
    cadeia)   ( cd "$D" && ln -sf "$alvo" meio.lnk && ln -sf meio.lnk ULTIMO.md ) ;;
    absoluto) ln -sf "/private$D/$alvo" "$D/ULTIMO.md" ;;
    quebrado) ( cd "$D" && ln -sf nao-existe.md ULTIMO.md ) ;;
    *)        cp "$D/$alvo" "$D/ULTIMO.md" ;;
  esac
  HOME=$HM bash "$1/bin/nb-bilhete-objetivo" "$B" obrigado >/dev/null
  sleep 0.8
  jq -r 'select(.kind=="passo" and .passo.passo=="ponteiro") | .passo.resultado' "$HM/.norte-box/telemetry-queue.jsonl" 2>/dev/null | tail -1
}

caso() { # nome · jeito · alvo · forma · esperado-antes · esperado-depois
  local a d; a=$(resultado "$VELHO" "$2" "$3" "$4"); d=$(resultado "$NOVO" "$2" "$3" "$4")
  local linha; linha=$(printf '%-46s antes=%-13s depois=%-13s' "$1" "${a:-nada}" "${d:-nada}")
  if [ "$a" = "$5" ] && [ "$d" = "$6" ]; then ok "$linha"; else nok "$linha (esperado antes=$5 depois=$6)"; fi
}

echo "== Conta do ponteiro: 0.3.53 publicada (antes) × caixa de teste (depois)"
caso "cópia certa, objetivo escrito depois (Ygor)"    copia  novo   secao  aponta_outro ok
caso "cópia certa, sem cabeçalho (objetivo depois)"   copia  novo   semfm  aponta_outro ok
caso "cópia certa, objetivo já pronto"                copia  novo   pronto ok           ok
caso "cópia de bilhete ANTIGO"                         copia  antigo secao  aponta_outro aponta_outro
caso "atalho certo (seu Mac)"                          atalho novo   secao  ok           ok
caso "atalho pro bilhete ANTIGO"                       atalho antigo secao  aponta_outro aponta_outro
caso "atalho em cadeia (atalho de atalho)"             cadeia novo   secao  ok           ok
caso "atalho com caminho /private/tmp"                 absoluto novo secao  ok           ok
caso "atalho quebrado"                                 quebrado novo secao  falhou       falhou
echo
echo "== Resultado: $PASS OK · $FAIL FALHA"
[ "$FAIL" = 0 ]
