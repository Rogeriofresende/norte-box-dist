#!/usr/bin/env bash
# kit-fabrica-rodar-guiado.sh — a versao "APERTA ENTER E ASSISTE" da FATIA 2 da FABRICA DE KITS:
# "aprovou -> roda logo num doc de teste" (NRT-_990148, fatia 2).
#
# POR QUE ESTE ARQUIVO EXISTE:
#   A fatia 2 fecha o ciclo: em vez de aprovar o kit e SO DEPOIS descobrir se ele funciona, a pessoa aprova E
#   ja testa na hora num documento de VERDADE. Este guiado conduz pela mao: cria uma casa de mentira, grava um
#   contrato-exemplo REAL (FORA da pasta da caixa — pra respeitar o portao anti-prova-circular), abre um
#   rascunho, redige 3 linhas, mostra o preview com o token, e no APERTA-ENTER dispara o --rodar no doc bom pra
#   a pessoa VER o 🟢 nascer do MOTOR REAL. Depois um 2o ato: um doc que FALTA uma ancora -> 🟡 honesto (e o
#   kit continua salvo). ZERO copiar-colar; a casa de mentira some sozinha no fim (a prova de Ctrl-C).
#
# COMO ELE FAZ (sem gambiarra):
#   - Cria um $HOME descartavel em /tmp (mktemp -d).
#   - Aponta o plugin pra arvore LIMPA (git archive HEAD) — ou, pre-commit, o subdir do worktree da peca.
#   - Roda os comandos REAIS (nb-kit-rascunho / nb-kit-aprovar --rodar) com HOME/PATH por dentro.
#   - EXTRAI o token do proprio preview (nao inventa) e usa no aprovar — igual a pessoa faria.
#   - Grava os documentos de teste FORA de ~/.norte-box/ (num "quintal" da casa) — o portao anti-circular exige.
#   - trap ... EXIT apaga a casa de mentira MESMO com Ctrl-C.
#   - Banner de fecho HONESTO: 🟢 so se os dois atos se comportaram como o esperado (bom fecha, ruim amarela).
#
# USO (a pessoa):  bash kit-fabrica-rodar-guiado.sh    (aperta Enter a cada passo)
# USO (a suite):   bash kit-fabrica-rodar-guiado.sh --auto   (ou stdin nao-tty)  -> nao espera Enter.
#
# NAO TOCA hooks/_kit_fabrica.sh nem os bins (as LEIs). So le/roda.
set -u

# ---------------------------------------------------------------------------
# 0) modo interativo vs automatico
# ---------------------------------------------------------------------------
AUTO=0
for _a in "$@"; do
  case "$_a" in --auto|-y|--sim) AUTO=1 ;; esac
done
if [ ! -t 0 ]; then AUTO=1; fi

_enter() { # <mensagem>
  printf '%s' "$1"
  if [ "$AUTO" = "1" ]; then
    printf '\n'
  else
    IFS= read -r _lixo || true
    printf '\n'
  fi
}

# ---------------------------------------------------------------------------
# 1) localiza a arvore LIMPA do plugin (git archive HEAD; NUNCA a arvore suja)
# ---------------------------------------------------------------------------
_here="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"   # .../plugins/norte-box
_repo="$(cd "$_here" && git rev-parse --show-toplevel 2>/dev/null || true)"
if [ -z "${_repo:-}" ]; then
  echo "ERRO: rode este comando de dentro do worktree git da branch da fabrica." >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# 2) casa de mentira descartavel + AUTO-LIMPEZA a prova de interrupcao (trap EXIT)
# ---------------------------------------------------------------------------
LAB="$(mktemp -d "${TMPDIR:-/tmp}/kit-fabrica-rodar-guiado.XXXXXX")"
_limpa() { rm -rf "$LAB" 2>/dev/null; }
trap '_limpa' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

FAKEHOME="$LAB/casa"
PLUGTREE="$LAB/plugin"
mkdir -p "$FAKEHOME/.norte-box" "$PLUGTREE"
# o "quintal": onde moram os documentos de teste da pessoa — FORA de ~/.norte-box (portao anti-circular).
QUINTAL="$FAKEHOME/documentos"; mkdir -p "$QUINTAL"

# HOOK DE TESTE (so em teste): expoe onde ficou a casa, pra a suite provar a auto-limpeza.
if [ "${NB_GUIADO_TEST_MARK:-0}" = "1" ]; then
  printf 'NB_GUIADO_CASA=%s\n' "$FAKEHOME"
  if [ "${NB_GUIADO_TEST_HANG:-0}" = "1" ]; then
    [ -n "${NB_GUIADO_TEST_CASA_OUT:-}" ] && printf '%s' "$FAKEHOME" > "$NB_GUIADO_TEST_CASA_OUT" 2>/dev/null || true
    sleep 30
  fi
fi

# De onde sai o plugin que o guiado roda (SEMPRE isolado numa arvore descartavel que some no fim):
#   1) HEAD do repo (arvore commitada limpa) — o ideal, quando a fatia ja esta na branch/HEAD.
#   2) arvore de trabalho DESTE worktree (a branch da peca, pre-commit) — copia so o subdir plugins/norte-box.
( cd "$_repo" && git archive HEAD plugins/norte-box ) | tar -x -C "$PLUGTREE" 2>/dev/null || true
_NB_BINDIR="$PLUGTREE/plugins/norte-box/bin"
_ORIGEM="HEAD (arvore commitada)"
# a fatia 2 vive no nb-kit-aprovar (que ganhou --rodar); se o HEAD nao tiver o bin, cai pro worktree da peca.
if [ ! -f "$_NB_BINDIR/nb-kit-aprovar" ] || ! grep -q -- '--rodar' "$_NB_BINDIR/nb-kit-aprovar" 2>/dev/null; then
  rm -rf "$PLUGTREE" 2>/dev/null; mkdir -p "$PLUGTREE/plugins"
  cp -R "$_here" "$PLUGTREE/plugins/norte-box" 2>/dev/null || true
  _NB_BINDIR="$PLUGTREE/plugins/norte-box/bin"
  _ORIGEM="worktree da peca (pre-commit)"
fi
NB_RASC="$_NB_BINDIR/nb-kit-rascunho"
NB_APROV="$_NB_BINDIR/nb-kit-aprovar"
for _b in "$NB_RASC" "$NB_APROV"; do
  [ -f "$_b" ] || { echo "ERRO: $(basename "$_b") nao foi encontrado (nem no HEAD, nem no worktree da peca)." >&2; exit 1; }
  chmod +x "$_b" 2>/dev/null || true
done

# fichinha minima (o motor da estreia consulta a arvore .norte-box; a fichinha nao atrapalha).
if command -v jq >/dev/null 2>&1; then
  jq -cn '{objetivo:"CRIAR UM KIT E TESTAR NA HORA", entregou:"uma descricao", proximo:"P", provado:false, prova:{artefato:"",entrega:""}, ultima_atualizacao:"t"}' > "$FAKEHOME/.norte-box/situacao.json" 2>/dev/null || true
fi

NOME="conferir-contrato"
CHK="$FAKEHOME/.norte-box/rascunhos/$NOME/checklist.txt"
# doc BOM (cobre as 3 ancoras) e doc RUIM (falta o valor) — AMBOS no quintal (fora da caixa).
DOC_BOM="$QUINTAL/contrato-de-verdade.txt"
DOC_RUIM="$QUINTAL/contrato-incompleto.txt"

cat > "$DOC_BOM" <<'DOCEOF'
CONTRATO DE PRESTACAO DE SERVICOS
1. PARTES: CONTRATANTE e CONTRATADA, qualificadas no preambulo.
3. VALOR: R$ 5.000,00 mensais, pagos ate o dia 5.
5. FORO: fica eleita a clausula de foro eleito da Comarca de Brasilia/DF.
DOCEOF

cat > "$DOC_RUIM" <<'DOCEOF'
CONTRATO DE PRESTACAO DE SERVICOS
1. PARTES: CONTRATANTE e CONTRATADA, qualificadas no preambulo.
5. FORO: fica eleita a clausula de foro eleito da Comarca de Brasilia/DF.
DOCEOF

# helpers: rodam os comandos REAIS por dentro (HOME=casa).
_rasc()  { HOME="$FAKEHOME" bash "$NB_RASC"  "$@" 2>&1; }
_aprov() { HOME="$FAKEHOME" bash "$NB_APROV" "$@" 2>&1; }

# placar honesto (o banner de fecho depende dele).
STEP_FAIL=0
_marca_falha() { STEP_FAIL=$((STEP_FAIL+1)); }

# ===========================================================================
#  O ROTEIRO GUIADO — a pessoa so aperta Enter e le.
# ===========================================================================
cat <<'EOF'

======================================================================
  FABRICA DE KITS · FECHAR O CICLO — aperta Enter e assiste.
  Voce vai VER a caixa APROVAR um kit E, na mesma hora, TESTA-LO num
  documento de VERDADE seu. O selo VERDE que aparece vem do MOTOR REAL
  conferindo o documento — nunca da aprovacao. Depois, um 2o ato: um
  documento que FALTA um item -> 🟡 honesto (e o kit continua salvo).
  Eu conduzo — voce nao precisa digitar, copiar nem apagar nada.
======================================================================

EOF
printf '  (rodando o plugin a partir de: %s)\n\n' "$_ORIGEM"

# --- PASSO 1: abrir o rascunho e redigir 3 linhas ---
_enter "Aperte Enter pra eu ABRIR um rascunho 'conferir-contrato' e ESCREVER 3 exigencias... "
echo
echo "--- ABRINDO O RASCUNHO ----------------------------------------------"
out="$(_rasc "$NOME")"; rc=$?
printf '%s\n' "$out"
echo "---------------------------------------------------------------------"
[ "$rc" = "0" ] || { echo "⚠ o rascunho nao abriu como eu esperava (codigo $rc)."; _marca_falha; }
mkdir -p "$(dirname "$CHK")" 2>/dev/null
cat > "$CHK" <<'CHKEOF'
Identifica as partes :: CONTRATANTE
Fixa o valor :: R$ 5.000,00
Elege o foro :: foro eleito
CHKEOF
echo
echo "--- O QUE EU ESCREVI (formato: descricao :: ancora) -----------------"
cat "$CHK"
echo "---------------------------------------------------------------------"
echo "Cada linha e uma exigencia. A ANCORA (depois do '::') e o texto que o"
echo "documento bom precisa conter — e o que a conferencia vai procurar."
echo

# --- PASSO 2: preview -> pega o token ---
_enter "Aperte Enter pra ver o PREVIEW com o TOKEN de aprovacao... "
echo
echo "--- PREVIEW ---------------------------------------------------------"
out="$(_rasc "$NOME")"
printf '%s\n' "$out"
echo "---------------------------------------------------------------------"
TOKEN="$(printf '%s' "$out" | grep -m1 'nb-kit-aprovar' | sed -E 's/.*--confirmo *([A-Za-z0-9]+).*/\1/')"
if [ -n "$TOKEN" ]; then
  echo "O TOKEN ($TOKEN) e destes bytes exatos. Vou usa-lo pra aprovar E ja testar."
else
  echo "⚠ nao saiu token no preview (o formato nao conferiu?)."; _marca_falha
fi
echo

# --- PASSO 3: aprovar E RODAR no doc BOM -> 🟢 do MOTOR REAL ---
_enter "Aperte Enter pra eu APROVAR e, na mesma hora, TESTAR num contrato de VERDADE (aqui nasce o 🟢)... "
echo
echo "--- APROVANDO + RODANDO (nb-kit-aprovar --rodar) --------------------"
echo "  documento de teste (fora da caixa): $DOC_BOM"
echo
if [ -n "$TOKEN" ]; then
  out="$(_aprov "$NOME" --confirmo "$TOKEN" --rodar "$DOC_BOM")"; rc=$?
  printf '%s\n' "$out"
  echo "---------------------------------------------------------------------"
  if [ "$rc" = "0" ] && printf '%s' "$out" | grep -qi 'ENTREGA PROVADA'; then
    echo "AGORA sim: o kit foi SALVO e, no mesmo passo, o 🟢 veio do MOTOR REAL"
    echo "conferindo o documento — nao da aprovacao. Ciclo fechado na hora."
  else
    echo "⚠ o aprovar+rodar no doc bom nao fechou verde (codigo $rc)."; _marca_falha
  fi
else
  echo "(sem token, nao da pra aprovar — pulando)"; _marca_falha
fi
echo

# --- PASSO 4: 2o ato — um doc que FALTA uma ancora -> 🟡 honesto (kit ja existe, versao nova = outro nome) ---
_enter "Aperte Enter pro 2o ato: um contrato que FALTA o valor -> aqui a caixa e HONESTA (🟡)... "
echo
echo "--- APROVANDO + RODANDO num doc INCOMPLETO (outro nome de kit) -------"
echo "  documento de teste (falta 'R\$ 5.000,00'): $DOC_RUIM"
echo
NOME2="conferir-contrato-v2"
CHK2="$FAKEHOME/.norte-box/rascunhos/$NOME2/checklist.txt"
_rasc "$NOME2" >/dev/null 2>&1
mkdir -p "$(dirname "$CHK2")" 2>/dev/null
cat > "$CHK2" <<'CHKEOF'
Identifica as partes :: CONTRATANTE
Fixa o valor :: R$ 5.000,00
CHKEOF
out="$(_rasc "$NOME2")"
TOKEN2="$(printf '%s' "$out" | grep -m1 'nb-kit-aprovar' | sed -E 's/.*--confirmo *([A-Za-z0-9]+).*/\1/')"
if [ -n "$TOKEN2" ]; then
  out="$(_aprov "$NOME2" --confirmo "$TOKEN2" --rodar "$DOC_RUIM")"; rc=$?
  printf '%s\n' "$out"
  echo "---------------------------------------------------------------------"
  if [ "$rc" = "1" ] && printf '%s' "$out" | grep -qi 'NAO-PROVADA'; then
    echo "Repare na honestidade: o teste deu 🟡 (o documento nao cobre o valor),"
    echo "MAS o kit FICOU salvo — o teste e informacao, nao desfaz o salvar."
  else
    echo "⚠ o 2o ato nao se comportou como o esperado (codigo $rc; esperava 🟡/exit 1)."; _marca_falha
  fi
else
  echo "(sem token no 2o rascunho — pulando)"; _marca_falha
fi
echo

# --- PASSO 5: fechar + auto-limpeza ---
_enter "Aperte Enter pra eu FECHAR e apagar a casa de mentira... "
echo
_limpa
trap - EXIT
if [ ! -e "$LAB" ]; then
  echo "Pronto — apaguei a casa de mentira. Sem rastro no seu computador."
else
  echo "Tentei apagar a casa de mentira (em /tmp); ela some no reinicio se sobrou algo."
fi
echo
echo "======================================================================"
if [ "$STEP_FAIL" -eq 0 ]; then
  echo "  🟢 Acabou e os dois atos se comportaram: doc BOM -> aprovar+rodar ->"
  echo "  🟢 do motor real; doc RUIM -> 🟡 honesto (kit continua salvo). O verde"
  echo "  nunca veio da aprovacao — sempre do motor. Nada tocou seu computador."
  echo "======================================================================"
  echo
  exit 0
else
  echo "  🟡 Acabou, mas $STEP_FAIL passo(s) NAO fecharam como eu esperava."
  echo "  Nao vou pintar de verde o que nao provou. Veja os avisos acima."
  echo "======================================================================"
  echo
  exit 1
fi
