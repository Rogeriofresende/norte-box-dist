#!/usr/bin/env bash
# Teste do conserto A (nb-ponteiro-reaponta) — HOME de mentira, nada publicado. VELHO=0.3.55, NOVO=conserto.
set -u
VELHO=$(mktemp -d)/v; mkdir -p "$VELHO"; git -C ~/norte-box-dist-nrt997988 archive origin/main plugins/norte-box | tar -x -C "$VELHO"; VELHO="$VELHO/plugins/norte-box"
NOVO=~/norte-box-dist-nrt997988/plugins/norte-box
T=/tmp/nb-7988/conserto-$(date +%s); mkdir -p "$T"; N=0; PASS=0; FAIL=0
export CLAUDE_CODE_SESSION_ID="sessao-teste-conserto" NORTE_OBJETIVO_FONTE=/nao/existe
prep() { N=$(mktemp -d "$T/c.XXXX"); N=${N##*/}; HM="$T/home$N"; H="$HM/.norte-box"; mkdir -p "$H"
  printf 'compartilhavel\n' > "$H/modo"; printf '{"versao":"5","hash":"teste"}' > "$H/consent.json"
  printf '{"invite_id":"teste","ingest_token":"t"}' > "$H/identity.json"; : > "$H/telemetry.enabled"
  printf 'NORTE_BOX_TELEMETRY_URL=http://127.0.0.1:1/ingest\n' > "$H/.env"
  D="$T/proj$N/norte-out/handoffs"; mkdir -p "$D"; printf -- '# velho\n\n## Objetivo (1 frase)\nassunto antigo\n' > "$D/antigo-20261021-100000.md"; }
ponteiro() { if [ "$1" = atalho ]; then ln -sf "$(basename "$2")" "$D/ULTIMO.md"; else rm -f "$D/ULTIMO.md"; cp "$2" "$D/ULTIMO.md"; fi; }
conf() { HOME=$HM bash "$CX/bin/nb-bilhete-objetivo" "$1" obrigado > "$T/saida-$N-$(basename "$1")"; sleep 1.2; }
res() { grep '"ponteiro"' "$H/telemetry-queue.jsonl" 2>/dev/null | tail -1 | grep -oE '"resultado":"[a-z_]+"' | cut -d'"' -f4; }
qual() { if [ -L "$D/ULTIMO.md" ]; then readlink "$D/ULTIMO.md"; else for f in "$D"/*.md; do [ "$(basename "$f")" != ULTIMO.md ] && cmp -s "$f" "$D/ULTIMO.md" && { basename "$f"; return; }; done; echo "copia-velha"; fi; }
SEM='# Handoff — painel\ndata: 2026-10-21 12:11\n\n## Objetivo (1 frase)\n\n## Onde estamos\n- [ ] x\n'
COM='# Handoff — painel\ndata: 2026-10-21 12:12\n\n## Objetivo (1 frase)\nfechar o painel de uso\n\n## Onde estamos\n- [ ] x\n'
B1N=painel-20261021-121115.md; B2N=painel-20261021-121208.md
edita() { python3 -c "import sys;p=sys.argv[1];t=open(p).read().replace('## Objetivo (1 frase)\n','## Objetivo (1 frase)\nfechar o painel de uso\n',1);open(p,'w').write(t)" "$1"; }
caso() { # $1 caso $2 jeito -> imprime "res2 | ULTIMO aponta pra"
  prep; B1="$D/$B1N"
  case "$1" in
   duas_janelas) printf -- "$SEM" > "$B1"; ponteiro "$2" "$B1"; conf "$B1"            # janela 1 salva sem objetivo
                 sleep 1; printf -- "$COM" > "$D/$B2N"; ponteiro "$2" "$D/$B2N"; conf "$D/$B2N"  # janela 2 salva depois
                 edita "$B1"; conf "$B1" ;;                                          # janela 1 corrige o seu
   nome_sem_data) B1="$D/painel.md"; printf -- "$SEM" > "$B1"; ponteiro "$2" "$B1"; conf "$B1"; printf -- "$COM" > "$D/$B2N"; conf "$D/$B2N" ;;
   *) printf -- "$SEM" > "$B1"; ponteiro "$2" "$B1"; conf "$B1"
      case "$1" in
        normal) : ;;
        edita_mesmo) edita "$B1"; conf "$B1" ;;
        edita_e_aponta) edita "$B1"; ponteiro "$2" "$B1"; conf "$B1" ;;
        bilhete_novo) printf -- "$COM" > "$D/$B2N"; conf "$D/$B2N" ;;
        desligado) printf -- "$COM" > "$D/$B2N"; NORTE_PONTEIRO_REAPONTA=0 conf "$D/$B2N" ;;
      esac ;;
  esac
  echo "$(res) | $(qual)"
}
confere() { # $1 rotulo $2 obtido $3 esperado
  if [ "$2" = "$3" ]; then PASS=$((PASS+1)); printf '  OK    %-34s %s\n' "$1" "$2"; else FAIL=$((FAIL+1)); printf '  FALHA %-34s obtido=[%s] esperado=[%s]\n' "$1" "$2" "$3"; fi; }
for j in atalho copia; do
  for c in normal edita_mesmo edita_e_aponta bilhete_novo; do
    CX=$VELHO; v=$(caso $c $j); CX=$NOVO; n=$(caso $c $j)
    esp="ok | $B1N"; [ "$c" = bilhete_novo ] && esp="ok | $B2N"
    printf '  [0.3.55: %-30s]' "$v"; confere "$c/$j" "$n" "$esp"
  done
  CX=$NOVO; confere "duas_janelas/$j (não atropela)" "$(caso duas_janelas $j | cut -d'|' -f2 | tr -d ' ')" "$B2N"
done
CX=$NOVO; confere "desligado (kill) atalho" "$(caso desligado atalho)" "aponta_outro | $B1N"
CX=$NOVO; confere "nome sem data: não mexe" "$(caso nome_sem_data atalho)" "aponta_outro | painel.md"
# a saida pro usuario (OBJETIVO:/SEM OBJETIVO) nao muda
diff <(cd "$T" && ls saida-* >/dev/null && cat  /dev/null) /dev/null >/dev/null
s1=$(HOME=$T/x NORTE_BOX_PASSO=0 bash "$VELHO/bin/nb-bilhete-objetivo" "$(ls "$T"/proj*/norte-out/handoffs/$B1N | head -1)"); s2=$(HOME=$T/x NORTE_BOX_PASSO=0 bash "$NOVO/bin/nb-bilhete-objetivo" "$(ls "$T"/proj*/norte-out/handoffs/$B1N | head -1)")
confere "saída pro usuário igual" "$s2" "$s1"
[ -n "$(find "$T" -name "*.lock" -o -name "*.tmp")" ] && FAIL=$((FAIL+1)) || { PASS=$((PASS+1)); echo "  OK    sem trava ou temporário esquecido"; }
echo "PASSOU $PASS · FALHOU $FAIL"
