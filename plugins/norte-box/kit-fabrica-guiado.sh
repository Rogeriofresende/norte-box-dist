#!/usr/bin/env bash
# kit-fabrica-guiado.sh — a versao "APERTA ENTER E ASSISTE" da FABRICA DE KITS (NRT-_990148, fatia 1).
#
# POR QUE ESTE ARQUIVO EXISTE:
#   A fabrica tem varios passos (abrir rascunho -> escrever linhas -> preview com token -> aprovar -> rodar).
#   Em vez de a pessoa copiar-colar comandos, este guiado CONDUZ PELA MAO: cria uma casa de mentira, abre um
#   rascunho REAL, INJETA um checklist de exemplo (2 linhas), mostra o PREVIEW com o TOKEN, APROVA por token,
#   lista o kit (origem 🟡), e por fim RODA o kit num doc de amostra ate o selo 🟢 do MOTOR REAL. ZERO
#   copiar-colar; a casa de mentira some sozinha no fim (a prova de Ctrl-C).
#
# COMO ELE FAZ (sem gambiarra):
#   - Cria um $HOME descartavel em /tmp (mktemp -d).
#   - Aponta o plugin pra arvore LIMPA (git archive HEAD) — nunca a arvore suja.
#   - Roda os comandos REAIS (nb-kit-rascunho / nb-kit-aprovar / nb-kit-rodar) com HOME/PATH por dentro.
#   - EXTRAI o token do proprio preview (nao inventa) e usa no aprovar — igual a pessoa faria.
#   - trap ... EXIT apaga a casa de mentira MESMO com Ctrl-C.
#   - Banner de fecho HONESTO: 🟢 so se todos os passos passaram; senao avisa qual quebrou.
#
# USO (a pessoa):  bash kit-fabrica-guiado.sh    (aperta Enter a cada passo)
# USO (a suite):   bash kit-fabrica-guiado.sh --auto   (ou stdin nao-tty)  -> nao espera Enter.
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
LAB="$(mktemp -d "${TMPDIR:-/tmp}/kit-fabrica-guiado.XXXXXX")"
_limpa() { rm -rf "$LAB" 2>/dev/null; }
trap '_limpa' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

FAKEHOME="$LAB/casa"
PLUGTREE="$LAB/plugin"
mkdir -p "$FAKEHOME/.norte-box" "$PLUGTREE"

# HOOK DE TESTE (so em teste): expoe onde ficou a casa, pra a suite provar a auto-limpeza.
if [ "${NB_GUIADO_TEST_MARK:-0}" = "1" ]; then
  printf 'NB_GUIADO_CASA=%s\n' "$FAKEHOME"
  if [ "${NB_GUIADO_TEST_HANG:-0}" = "1" ]; then
    [ -n "${NB_GUIADO_TEST_CASA_OUT:-}" ] && printf '%s' "$FAKEHOME" > "$NB_GUIADO_TEST_CASA_OUT" 2>/dev/null || true
    sleep 30
  fi
fi

# De onde sai o plugin que o guiado roda (em ordem de preferencia, SEMPRE isolado numa arvore descartavel):
#   1) HEAD do repo (arvore commitada limpa) — o ideal, quando a fabrica ja esta na branch/HEAD.
#   2) arvore de trabalho DESTE worktree (a branch da peca, pre-commit) — copia so o subdir plugins/norte-box.
# Nunca roda direto de $_here (a arvore viva do worktree); sempre de uma COPIA em /tmp que some no fim. O
# passo 2 e' honesto: e' o codigo DA PECA sendo entregue (o worktree dedicado dela), nao uma arvore aleatoria.
( cd "$_repo" && git archive HEAD plugins/norte-box ) | tar -x -C "$PLUGTREE" 2>/dev/null || true
_NB_BINDIR="$PLUGTREE/plugins/norte-box/bin"
_ORIGEM="HEAD (arvore commitada)"
if [ ! -f "$_NB_BINDIR/nb-kit-rascunho" ]; then
  # o HEAD ainda nao tem a fabrica (peca nova, pre-commit): copia o subdir do plugin DESTE worktree pra COPIA.
  rm -rf "$PLUGTREE" 2>/dev/null; mkdir -p "$PLUGTREE/plugins"
  cp -R "$_here" "$PLUGTREE/plugins/norte-box" 2>/dev/null || true
  _ORIGEM="worktree da peca (pre-commit)"
fi
NB_RASC="$_NB_BINDIR/nb-kit-rascunho"
NB_APROV="$_NB_BINDIR/nb-kit-aprovar"
NB_RODAR="$_NB_BINDIR/nb-kit-rodar"
for _b in "$NB_RASC" "$NB_APROV" "$NB_RODAR"; do
  [ -f "$_b" ] || { echo "ERRO: $(basename "$_b") nao foi encontrado (nem no HEAD, nem no worktree da peca)." >&2; exit 1; }
  chmod +x "$_b" 2>/dev/null || true
done

# fichinha minima (o motor da estreia consulta a arvore .norte-box; a fichinha nao atrapalha).
if command -v jq >/dev/null 2>&1; then
  jq -cn '{objetivo:"CRIAR UM KIT NA FABRICA", entregou:"uma descricao", proximo:"P", provado:false, prova:{artefato:"",entrega:""}, ultima_atualizacao:"t"}' > "$FAKEHOME/.norte-box/situacao.json" 2>/dev/null || true
fi

NOME="conferir-contrato"
CHK="$FAKEHOME/.norte-box/rascunhos/$NOME/checklist.txt"
DOC="$FAKEHOME/contrato-de-amostra.txt"

# doc de amostra que COBRE as 2 ancoras do exemplo (pra o run fechar 🟢 de verdade).
cat > "$DOC" <<'DOCEOF'
CONTRATO DE PRESTACAO DE SERVICOS
1. PARTES: CONTRATANTE e CONTRATADA, qualificadas no preambulo.
3. VALOR: R$ 5.000,00 mensais, pagos ate o dia 5.
DOCEOF

# helpers: rodam os comandos REAIS por dentro (HOME=casa).
_rasc()  { HOME="$FAKEHOME" bash "$NB_RASC"  "$@" 2>&1; }
_aprov() { HOME="$FAKEHOME" bash "$NB_APROV" "$@" 2>&1; }
_rodar() { HOME="$FAKEHOME" bash "$NB_RODAR" "$@" 2>&1; }

# placar honesto (o banner de fecho depende dele).
STEP_FAIL=0
_marca_falha() { STEP_FAIL=$((STEP_FAIL+1)); }

# ===========================================================================
#  O ROTEIRO GUIADO — a pessoa so aperta Enter e le.
# ===========================================================================
cat <<'EOF'

======================================================================
  FABRICA DE KITS — aperta Enter e assiste.
  Voce vai VER a caixa transformar uma DESCRICAO ("conferir se um
  contrato tem partes e valor") em um KIT reusavel — com um PREVIEW
  antes de aprovar, e um selo VERDE que so aparece de verdade no fim.
  Eu conduzo — voce nao precisa digitar, copiar nem apagar nada.
======================================================================

EOF
printf '  (rodando o plugin a partir de: %s)\n\n' "$_ORIGEM"

# --- PASSO 1: abrir o rascunho (ganha o caminho) ---
_enter "Aperte Enter pra eu ABRIR um rascunho de kit chamado 'conferir-contrato'... "
echo
echo "--- ABRINDO O RASCUNHO ----------------------------------------------"
out="$(_rasc "$NOME")"; rc=$?
printf '%s\n' "$out"
echo "---------------------------------------------------------------------"
[ "$rc" = "0" ] || { echo "⚠ o rascunho nao abriu como eu esperava (codigo $rc)."; _marca_falha; }
echo "Repare: ele me deu o CAMINHO de um arquivo. E ali que as exigencias sao escritas."
echo "(esta vazio agora — por isso ainda nao ha token de aprovacao)"
echo

# --- PASSO 2: o agente REDIGE 2 linhas de exemplo no rascunho ---
_enter "Aperte Enter pra eu ESCREVER 2 exigencias de exemplo no rascunho... "
echo
mkdir -p "$(dirname "$CHK")" 2>/dev/null
cat > "$CHK" <<'CHKEOF'
Identifica as partes :: CONTRATANTE
Fixa o valor :: R$ 5.000,00
CHKEOF
echo "--- O QUE EU ESCREVI (formato: descricao :: ancora) -----------------"
cat "$CHK"
echo "---------------------------------------------------------------------"
echo "Cada linha e uma exigencia. A ANCORA (depois do '::') e o texto que o"
echo "documento bom precisa conter — e o que a conferencia vai procurar."
echo

# --- PASSO 3: preview -> mostra numerado + emite o TOKEN ---
_enter "Aperte Enter pra ver o PREVIEW com o TOKEN de aprovacao... "
echo
echo "--- PREVIEW ---------------------------------------------------------"
out="$(_rasc "$NOME")"
printf '%s\n' "$out"
echo "---------------------------------------------------------------------"
TOKEN="$(printf '%s' "$out" | grep -m1 'nb-kit-aprovar' | sed -E 's/.*--confirmo *([A-Za-z0-9]+).*/\1/')"
if [ -n "$TOKEN" ]; then
  echo "O TOKEN ($TOKEN) e destes bytes exatos. Se eu editasse o rascunho agora,"
  echo "ele mudaria e o token velho deixaria de valer — a aprovacao recusaria."
else
  echo "⚠ nao saiu token no preview (o formato nao conferiu?)."; _marca_falha
fi
echo

# --- PASSO 4: aprovar com o token (a "assinatura" da pessoa) ---
_enter "Aperte Enter pra eu APROVAR o rascunho com esse token... "
echo
echo "--- APROVANDO -------------------------------------------------------"
if [ -n "$TOKEN" ]; then
  out="$(_aprov "$NOME" --confirmo "$TOKEN")"; rc=$?
  printf '%s\n' "$out"
  [ "$rc" = "0" ] || { echo "⚠ a aprovacao nao fechou verde (codigo $rc)."; _marca_falha; }
else
  echo "(sem token, nao da pra aprovar — pulando)"; rc=2; _marca_falha
fi
echo "---------------------------------------------------------------------"
echo "O kit foi SALVO reusando o mesmo motor do kit-criar. Repare na ORIGEM:"
echo "ela e 🟡 — a fabrica AINDA NAO PROVOU nada. O verde vem so no proximo passo."
echo

# --- PASSO 5: listar o kit (origem 🟡) ---
_enter "Aperte Enter pra VER o kit no catalogo (origem 🟡)... "
echo
echo "--- CATALOGO (nb-kits) ----------------------------------------------"
NB_KITS="$PLUGTREE/plugins/norte-box/bin/nb-kits"
if [ -x "$NB_KITS" ]; then
  HOME="$FAKEHOME" bash "$NB_KITS" 2>&1
else
  echo "(nb-kits nao disponivel nesta arvore — pulando a listagem)"
fi
echo "---------------------------------------------------------------------"
echo

# --- PASSO 6: RODAR o kit num doc de amostra -> selo 🟢 do MOTOR REAL ---
_enter "Aperte Enter pra RODAR o kit num contrato de amostra (aqui nasce o 🟢 de verdade)... "
echo
echo "--- RODANDO O KIT (nb-kit-rodar) ------------------------------------"
out="$(_rodar "$NOME" "$DOC")"; rc=$?
printf '%s\n' "$out"
echo "---------------------------------------------------------------------"
if [ "$rc" = "0" ] && printf '%s' "$out" | grep -qi 'ENTREGA PROVADA'; then
  echo "AGORA sim: o 🟢 veio do MOTOR REAL conferindo o documento — nao da fabrica."
else
  echo "⚠ o run nao fechou verde (codigo $rc)."; _marca_falha
fi
echo

# --- PASSO 7: fechar + auto-limpeza ---
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
  echo "  🟢 Acabou e TUDO passou: descricao -> rascunho -> preview (token) ->"
  echo "  aprovar -> kit 🟡 -> rodar -> 🟢 do motor real. Nada tocou seu computador."
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
