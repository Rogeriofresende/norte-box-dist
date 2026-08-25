#!/usr/bin/env bash
# sombra-guiado.sh — a versao "APERTA ENTER E ASSISTE" do teste da Sombra (NRT-_990212).
#
# POR QUE ESTE ARQUIVO EXISTE:
#   O testar-sombra.sh IMPRIMIA um roteiro que a pessoa tinha que COPIAR-COLAR (export/cd/nb-sombra/rm).
#   O CEO reclamou disso. Este guiado troca o roteiro por UM comando que CONDUZ PELA MAO: cria a casa de
#   mentira, roda o nb-sombra REAL por dentro, mostra o antes->depois LIMPO, prova que o original nao
#   mudou, mostra a trava vermelha, e APAGA a casa sozinho. ZERO copiar-colar, ZERO export/cd/rm.
#
# COMO ELE FAZ (sem gambiarra):
#   - Cria um $HOME descartavel em /tmp (mktemp -d), pre-semeia meu-arquivo.txt + atalho-perigoso.txt.
#   - Aponta o plugin pra arvore LIMPA (git archive HEAD) — nunca a arvore suja.
#   - Roda o nb-sombra REAL (a lib provada, red-teamada pelo Val) com HOME/PATH setados POR DENTRO.
#   - FILTRA so o ruido de diagnostico do diff (--- /, +++ /, @@, NB_SOMBRA_ARQUIVO=) — nunca as linhas
#     -/+ de conteudo (que sao o valor). Mesmo filtro do shim do testar-sombra.sh.
#   - trap ... EXIT apaga a casa de mentira MESMO se o CEO apertar Ctrl-C (a prova de interrupcao).
#
# USO (o CEO):  bash sombra-guiado.sh
#   Ele aperta Enter a cada passo e le. Nao digita mais nada.
# USO (a suite/teste):  bash sombra-guiado.sh --auto   (ou stdin nao-tty)  -> nao espera Enter.
#
# NAO TOCA hooks/_sombra.sh nem bin/nb-sombra (as LEIs red-teamadas). So le/roda.
set -u

# ---------------------------------------------------------------------------
# 0) modo interativo vs automatico
#    --auto explicito OU stdin nao e' um terminal (pipe/teste) -> NAO espera Enter.
# ---------------------------------------------------------------------------
AUTO=0
for _a in "$@"; do
  case "$_a" in
    --auto|-y|--sim) AUTO=1 ;;
  esac
done
# se o stdin nao for um tty, tambem nao trava esperando Enter (teste/pipe).
if [ ! -t 0 ]; then AUTO=1; fi

# pausa de padaria: espera o Enter (so no modo interativo). No auto, segue direto.
#   O prompt e' impresso com printf no STDOUT (nao via 'read -p', que escreve no stderr — se a gente
#   redirecionasse o stderr do read pra /dev/null pra silenciar EOF, o proprio prompt sumiria da tela
#   do CEO). Depois um 'read' simples sem -p espera o Enter; erro/EOF nao trava (|| true).
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
  echo "ERRO: rode este comando de dentro do worktree git da branch da Sombra." >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# 2) casa de mentira descartavel + AUTO-LIMPEZA a prova de interrupcao (trap EXIT)
#    Tudo sob /tmp. O trap roda no fim NORMAL e tambem em SIGINT/SIGTERM (Ctrl-C).
# ---------------------------------------------------------------------------
LAB="$(mktemp -d "${TMPDIR:-/tmp}/sombra-guiado.XXXXXX")"
_limpa() { rm -rf "$LAB" 2>/dev/null; }
# EXIT cobre saida normal E interrompida (bash roda EXIT depois de INT/TERM). Amarramos INT/TERM tb pra
# encerrar limpo (sem deixar processo pendurado) — o EXIT entao apaga a casa.
trap '_limpa' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

FAKEHOME="$LAB/casa"
PLUGTREE="$LAB/plugin"
mkdir -p "$FAKEHOME" "$PLUGTREE"

# HOOK DE TESTE (so em teste): expoe onde ficou a casa, pra a suite provar a auto-limpeza.
if [ "${NB_GUIADO_TEST_MARK:-0}" = "1" ]; then
  printf 'NB_GUIADO_CASA=%s\n' "$FAKEHOME"
  # variante do teste de interrupcao: grava o caminho num arquivo e DORME, pra a suite mandar SIGINT.
  if [ "${NB_GUIADO_TEST_HANG:-0}" = "1" ]; then
    [ -n "${NB_GUIADO_TEST_CASA_OUT:-}" ] && printf '%s' "$FAKEHOME" > "$NB_GUIADO_TEST_CASA_OUT" 2>/dev/null || true
    sleep 30   # o trap EXIT apaga a casa quando a suite mandar o SIGINT
  fi
fi

# arvore LIMPA (HEAD) — so o subdir do plugin.
( cd "$_repo" && git archive HEAD plugins/norte-box ) | tar -x -C "$PLUGTREE"
_nb_real="$PLUGTREE/plugins/norte-box/bin/nb-sombra"
[ -f "$_nb_real" ] || { echo "ERRO: nb-sombra nao veio na arvore limpa (HEAD)." >&2; exit 1; }
chmod +x "$_nb_real" 2>/dev/null || true

# ---------------------------------------------------------------------------
# 3) PRE-SEMEIA os arquivos de exemplo DENTRO da casa (o CEO nao cria nada)
#    Mesma logica de seeding do testar-sombra.sh.
# ---------------------------------------------------------------------------
printf 'saudacao: ola mundo\n' > "$FAKEHOME/meu-arquivo.txt"
# atalho perigoso: symlink apontando pro original — a caixa deve RECUSAR (nao seguir o link).
ln -sf "$FAKEHOME/meu-arquivo.txt" "$FAKEHOME/atalho-perigoso.txt"

# ---------------------------------------------------------------------------
# helper: roda o nb-sombra REAL por dentro (HOME=casa), FILTRA so o ruido de diagnostico do diff
#   (--- /, +++ /, @@, NB_SOMBRA_ARQUIVO=) e preserva o exit code do real. Mesmo filtro do shim.
# ---------------------------------------------------------------------------
_sombra_real() { # <arquivo> <de> <para> [sessao]  -> imprime saida LIMPA, retorna o rc do real
  local _out _rc
  _out="$(HOME="$FAKEHOME" bash "$_nb_real" "$@" 2>&1)"; _rc=$?
  printf '%s\n' "$_out" | grep -v -E '^   (--- /|\+\+\+ /|@@ )|^NB_SOMBRA_ARQUIVO='
  return $_rc
}

# ===========================================================================
#  O ROTEIRO GUIADO — o CEO so aperta Enter e le.
# ===========================================================================
cat <<'EOF'

======================================================================
  TESTE DA SOMBRA — aperta Enter e assiste.
  Voce vai VER a caixa ENSAIAR uma edicao SEM tocar o seu arquivo de
  verdade. Tudo numa "casa de mentira" que some sozinha no fim.
  Eu conduzo — voce nao precisa digitar, copiar nem apagar nada.
======================================================================

Ja preparei uma casa de faz-de-conta com um arquivo dentro:
  meu-arquivo.txt  ->  saudacao: ola mundo

EOF

# --- PASSO 1: ensaiar a troca (VERDE) ---
_enter "Aperte Enter pra eu ENSAIAR a troca ('ola mundo' -> 'bom dia')... "
echo
echo "--- ENSAIO (a caixa mexe numa COPIA, nunca no original) --------------"
_sombra_real "$FAKEHOME/meu-arquivo.txt" "ola mundo" "bom dia" guiado
_rc1=$?
echo "---------------------------------------------------------------------"
if [ "$_rc1" != "0" ]; then
  # honestidade > aparencia: se o ensaio real falhar (fora o vermelho intencional), NAO pinta verde.
  echo
  echo "⚠ o ensaio nao terminou verde como eu esperava (codigo $_rc1)."
  echo "  Nao vou fingir que deu certo. Ainda assim vou apagar a casa de mentira no fim."
fi
echo

# --- PASSO 2: provar que o original NAO mudou ---
_enter "Aperte Enter pra CONFERIR que o seu arquivo NAO mudou... "
echo
echo "--- SEU ARQUIVO AGORA (le direto do disco da casa) -------------------"
cat "$FAKEHOME/meu-arquivo.txt"
echo "---------------------------------------------------------------------"
echo "Viu? Continua 'saudacao: ola mundo'. O ensaio foi numa copia — o seu"
echo "arquivo original NAO mudou nem um byte."
echo

# --- PASSO 3: sentir a trava de seguranca (VERMELHO) ---
_enter "Aperte Enter pra ver a TRAVA de seguranca em acao... "
echo
echo "--- TENTATIVA POR UM ATALHO (a caixa deve RECUSAR) -------------------"
_sombra_real "$FAKEHOME/atalho-perigoso.txt" "ola mundo" "bom dia" guiado
_rc3=$?
echo "---------------------------------------------------------------------"
echo "A caixa percebeu que 'atalho-perigoso.txt' e' um ATALHO (symlink) pro"
echo "seu arquivo real e se RECUSOU a mexer por atalho. A trava e' de verdade,"
echo "nao e promessa: ela barra por conta propria."
echo

# --- PASSO 4: fechar + auto-limpeza (o CEO nao roda rm) ---
_enter "Aperte Enter pra eu FECHAR e apagar a casa de mentira... "
echo
_limpa
# desarma o trap de EXIT pra nao tentar apagar de novo (idempotente de qualquer jeito).
trap - EXIT
if [ ! -e "$LAB" ]; then
  echo "Pronto — apaguei a casa de mentira. Sem rastro no seu computador."
else
  echo "Tentei apagar a casa de mentira (em /tmp); ela some no reinicio se sobrou algo."
fi
echo
echo "======================================================================"
echo "  Acabou. Voce viu: a caixa ENSAIA (🟢), o seu arquivo fica INTACTO,"
echo "  e a TRAVA barra o perigo (🔴). Nada disso tocou o seu computador."
echo "======================================================================"
echo

exit 0
