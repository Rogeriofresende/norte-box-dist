#!/usr/bin/env bash
# freio-guiado.sh — a versao "APERTA ENTER E ASSISTE" do teste do FREIO (NRT-_990212, "trava-mestra das acoes").
#
# POR QUE ESTE ARQUIVO EXISTE:
#   O sombra-guiado.sh e o aplicar-guiado.sh ja conduzem o CEO pela mao no ENSAIO e no APLICAR/DESFAZER.
#   Esta fatia mostra o FREIO DE MAO trabalhando: com a caixa NORMAL (freio solto) ela consegue agir; ai a
#   gente PUXA o freio e VE as acoes (ensaiar/aplicar) se RECUSAREM sozinhas, provando pelo disco que o
#   arquivo continua intocado; e por fim SOLTA o freio e ve a caixa VOLTAR a agir. ZERO copiar-colar, ZERO
#   export/cd/rm — o guiado conduz.
#
# COMO ELE FAZ (sem gambiarra):
#   - Cria um $HOME descartavel em /tmp (mktemp -d), pre-semeia config.txt (saudacao: ola mundo).
#   - Aponta o plugin pra arvore LIMPA (git archive HEAD) — nunca a arvore suja.
#   - Roda o nb-freio / nb-sombra / nb-aplicar REAIS (as pecas provadas, red-teamadas pelo Val) com
#     HOME/PATH setados POR DENTRO. Le o 🛑/🟢 do freio e le o config.txt do disco pra PROVAR o intocado.
#   - FILTRA so o ruido de diagnostico do diff/recibo (--- /, +++ /, @@, NB_SOMBRA_ARQUIVO=, NB_APLICAR_RECIBO=)
#     — nunca as linhas -/+ de conteudo (que sao o valor). Mesmo filtro dos outros guiados.
#   - trap ... EXIT apaga a casa de mentira MESMO se o CEO apertar Ctrl-C (a prova de interrupcao).
#   - Banner de fecho HONESTO: so pinta 🟢 se TODOS os passos foram verdes; senao sem 🟢 e exit != 0.
#
# USO (o CEO):  bash freio-guiado.sh
#   Ele aperta Enter a cada passo e le. Nao digita mais nada.
# USO (a suite/teste):  bash freio-guiado.sh --auto   (ou stdin nao-tty)  -> nao espera Enter.
#
# NAO TOCA hooks/_freio.sh, hooks/_sombra.sh, hooks/_aplicar.sh nem bin/nb-* (as LEIs red-teamadas). So le/roda.
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
#   O prompt e' impresso com printf no STDOUT (nao via 'read -p', que escreve no stderr). Depois um 'read'
#   simples sem -p espera o Enter; erro/EOF nao trava (|| true) — o furo que o Val ja pegou nos guiados.
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
  echo "ERRO: rode este comando de dentro do worktree git da branch do Freio." >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# 2) casa de mentira descartavel + AUTO-LIMPEZA a prova de interrupcao (trap EXIT)
#    Tudo sob /tmp. O trap roda no fim NORMAL e tambem em SIGINT/SIGTERM (Ctrl-C).
# ---------------------------------------------------------------------------
LAB="$(mktemp -d "${TMPDIR:-/tmp}/freio-guiado.XXXXXX")"
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
_nb_freio="$PLUGTREE/plugins/norte-box/bin/nb-freio"
_nb_sombra="$PLUGTREE/plugins/norte-box/bin/nb-sombra"
_nb_aplicar="$PLUGTREE/plugins/norte-box/bin/nb-aplicar"
for _b in "$_nb_freio" "$_nb_sombra" "$_nb_aplicar"; do
  [ -f "$_b" ] || { echo "ERRO: $(basename "$_b") nao veio na arvore limpa (HEAD)." >&2; exit 1; }
  chmod +x "$_b" 2>/dev/null || true
done

# ---------------------------------------------------------------------------
# 3) PRE-SEMEIA o arquivo de exemplo DENTRO da casa (o CEO nao cria nada)
# ---------------------------------------------------------------------------
ALVO="$FAKEHOME/config.txt"
printf 'saudacao: ola mundo\n' > "$ALVO"

# ---------------------------------------------------------------------------
# helpers: rodam os bins REAIS por dentro (HOME=casa) e FILTRAM so o ruido de diagnostico
#   (--- /, +++ /, @@, NB_SOMBRA_ARQUIVO=, NB_APLICAR_RECIBO=) — nunca as linhas -/+ de conteudo.
#   Guardam a saida CRUA (com os marcadores) em variaveis, pra pescar recibo etc.
# ---------------------------------------------------------------------------
_RAW=""      # saida crua do ultimo bin (com os marcadores) — pra pescar caminhos
_filtra() {  # le stdin, tira so o ruido de diagnostico, imprime o resto (o que o CEO ve)
  grep -v -E '^   (--- /|\+\+\+ /|@@ )|^NB_SOMBRA_ARQUIVO=|^NB_APLICAR_RECIBO='
}
_freio_real() {  # <puxar|soltar|status>  -> mostra saida limpa, guarda crua em _RAW, retorna rc
  local _rc
  _RAW="$(HOME="$FAKEHOME" bash "$_nb_freio" "$@" 2>&1)"; _rc=$?
  printf '%s\n' "$_RAW" | _filtra
  return $_rc
}
_sombra_real() { # <arquivo> <de> <para> [sessao]  -> mostra saida limpa, guarda crua em _RAW, retorna rc
  local _rc
  _RAW="$(HOME="$FAKEHOME" bash "$_nb_sombra" "$@" 2>&1)"; _rc=$?
  printf '%s\n' "$_RAW" | _filtra
  return $_rc
}
_aplicar_real() { # <recibo>  -> mostra saida limpa, guarda crua em _RAW, retorna rc
  local _rc
  _RAW="$(HOME="$FAKEHOME" bash "$_nb_aplicar" "$@" 2>&1)"; _rc=$?
  printf '%s\n' "$_RAW" | _filtra
  return $_rc
}
# pesca o caminho do RECIBO do ensaio (a partir da linha NB_SOMBRA_ARQUIVO= na saida crua):
_recibo_de_raw() { printf '%s' "$_RAW" | grep -m1 '^NB_SOMBRA_ARQUIVO=' | sed 's/^NB_SOMBRA_ARQUIVO=//'; }

# acumulador de honestidade: vira 1 se QUALQUER passo saiu do trilho (banner de fecho reflete isso).
DEU_RUIM=0

# ===========================================================================
#  O ROTEIRO GUIADO — o CEO so aperta Enter e le.
# ===========================================================================
cat <<'EOF'

======================================================================
  TESTE DO FREIO DE MAO — aperta Enter e assiste.
  A caixa tem um FREIO DE MAO: voce PUXA e ela NAO MEXE EM NADA (nem
  ensaia, nem aplica) ate voce SOLTAR. Voce vai VER a caixa normal
  agir, depois PUXAR o freio e ver as acoes se RECUSAREM sozinhas
  (o arquivo fica intocado), e por fim SOLTAR e ver ela VOLTAR ao
  normal. Tudo numa "casa de mentira" que some sozinha no fim. Eu
  conduzo — voce nao precisa digitar, copiar nem apagar nada.
======================================================================

Ja preparei uma casa de faz-de-conta com um arquivo dentro:
  config.txt  ->  saudacao: ola mundo

EOF

# --- PASSO 1: a caixa NORMAL (freio solto) consegue agir ---
_enter "Aperte Enter pra ver a caixa NORMAL (freio solto) conseguir agir... "
echo
echo "--- FREIO agora (deve estar SOLTO) ----------------------------------"
_freio_real status
echo "---------------------------------------------------------------------"
echo
echo "--- ENSAIO de teste (a caixa mexe numa COPIA, nunca no seu arquivo) --"
_sombra_real "$ALVO" "ola mundo" "bom dia" solto
_rc_ensaio1=$?
echo "---------------------------------------------------------------------"
if [ "$_rc_ensaio1" != "0" ]; then
  DEU_RUIM=1
  echo
  echo "⚠ o ensaio com o freio solto nao terminou verde (codigo $_rc_ensaio1)."
  echo "  Nao vou fingir que deu certo. Ainda assim vou apagar a casa no fim."
else
  echo "Com o freio SOLTO a caixa conseguiu ENSAIAR (🟢). Ela esta normal."
fi
echo

# --- PASSO 2: PUXAR o freio ---
_enter "Aperte Enter pra eu PUXAR o freio de mao... "
echo
echo "--- PUXAR o freio ---------------------------------------------------"
_freio_real puxar
_rc_puxar=$?
echo "---------------------------------------------------------------------"
if [ "$_rc_puxar" != "0" ]; then
  DEU_RUIM=1
  echo "⚠ eu esperava o freio PUXAR (🛑) e nao consegui (codigo $_rc_puxar)."
fi
echo
echo "--- FREIO agora (deve estar PUXADO) ---------------------------------"
_freio_real status
_st_puxado="$_RAW"
echo "---------------------------------------------------------------------"
if printf '%s' "$_st_puxado" | grep -qi 'puxado'; then
  echo "O freio esta PUXADO (🛑). Agora a caixa NAO deve mexer em NADA."
else
  DEU_RUIM=1
  echo "⚠ eu esperava o status dizer 'puxado' e nao disse."
fi
echo

# --- PASSO 3: com o freio PUXADO, as acoes RECUSAM — e o arquivo fica intocado ---
_enter "Aperte Enter pra eu TENTAR agir com o freio puxado (as acoes devem RECUSAR)... "
echo
ANTES="$(cat "$ALVO")"
echo "--- TENTATIVA 1: ENSAIAR com o freio puxado (deve RECUSAR) ----------"
_sombra_real "$ALVO" "ola mundo" "bom dia" puxado
_rc_ens_bloq=$?
echo "---------------------------------------------------------------------"
# AQUI o 🛑 e a recusa sao o resultado CERTO: rc=1 (recusou) e' o sucesso do passo.
if [ "$_rc_ens_bloq" = "1" ] && printf '%s' "$_RAW" | grep -qi 'freio esta puxado'; then
  echo "A caixa RECUSOU ENSAIAR — 'o freio esta puxado'. Certinho."
else
  DEU_RUIM=1
  echo "⚠ eu esperava a caixa RECUSAR o ensaio por conta do freio, e nao recusou (codigo $_rc_ens_bloq)."
fi
echo
echo "--- TENTATIVA 2: APLICAR com o freio puxado (deve RECUSAR) ----------"
# passamos um recibo qualquer: o freio barra ANTES de o aplicar sequer olhar o recibo.
_aplicar_real "$FAKEHOME/.norte-box/sombra/nao-importa.recibo"
_rc_apl_bloq=$?
echo "---------------------------------------------------------------------"
if [ "$_rc_apl_bloq" = "1" ] && printf '%s' "$_RAW" | grep -qi 'freio esta puxado'; then
  echo "A caixa RECUSOU APLICAR tambem — 'o freio esta puxado'. Certinho."
else
  DEU_RUIM=1
  echo "⚠ eu esperava a caixa RECUSAR o aplicar por conta do freio, e nao recusou (codigo $_rc_apl_bloq)."
fi
echo
echo "--- SEU config.txt AGORA (lido direto do disco da casa) -------------"
cat "$ALVO"
echo "---------------------------------------------------------------------"
if [ "$(cat "$ALVO")" = "$ANTES" ] && grep -qxF 'saudacao: ola mundo' "$ALVO"; then
  echo "Intocado: continua 'saudacao: ola mundo'. Puxei o freio e a caixa"
  echo "nao mexe em NADA — nem um byte. A trava e' de verdade, nao promessa."
else
  DEU_RUIM=1
  echo "⚠ o arquivo mudou com o freio puxado — isso NAO devia acontecer."
fi
echo

# --- PASSO 4: SOLTAR o freio -> a caixa VOLTA a agir ---
_enter "Aperte Enter pra eu SOLTAR o freio e ver a caixa voltar ao normal... "
echo
echo "--- SOLTAR o freio --------------------------------------------------"
_freio_real soltar
_rc_soltar=$?
echo "---------------------------------------------------------------------"
if [ "$_rc_soltar" != "0" ]; then
  DEU_RUIM=1
  echo "⚠ eu esperava o freio SOLTAR (🟢) e nao consegui (codigo $_rc_soltar)."
fi
echo
echo "--- FREIO agora (deve estar SOLTO de novo) --------------------------"
_freio_real status
_st_solto="$_RAW"
echo "---------------------------------------------------------------------"
if printf '%s' "$_st_solto" | grep -qi 'solto'; then
  echo "O freio esta SOLTO de novo (🟢)."
else
  DEU_RUIM=1
  echo "⚠ eu esperava o status dizer 'solto' e nao disse."
fi
echo
echo "--- ENSAIO de novo (a caixa deve VOLTAR a agir) ---------------------"
_sombra_real "$ALVO" "ola mundo" "bom dia" voltou
_rc_ensaio2=$?
echo "---------------------------------------------------------------------"
if [ "$_rc_ensaio2" = "0" ]; then
  echo "Soltei e ela VOLTOU ao normal: a caixa ENSAIOU de novo (🟢)."
else
  DEU_RUIM=1
  echo "⚠ eu esperava a caixa voltar a ENSAIAR depois de soltar, e nao voltou (codigo $_rc_ensaio2)."
fi
echo

# --- PASSO 5: fechar + auto-limpeza (o CEO nao roda rm) ---
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
# banner de fecho HONESTO: so pinta 🟢 se TUDO foi como esperado.
if [ "$DEU_RUIM" = "0" ]; then
  echo "======================================================================"
  echo "  Acabou 🟢. Voce viu: com o freio SOLTO a caixa age; voce PUXA o freio"
  echo "  e as acoes se RECUSAM sozinhas (o arquivo fica intocado); voce SOLTA"
  echo "  e ela VOLTA ao normal. Nada disso tocou o seu computador de verdade."
  echo "======================================================================"
  echo
  exit 0
else
  echo "======================================================================"
  echo "  Acabou — mas algum passo NAO saiu como eu esperava (veja os ⚠ acima)."
  echo "  Nao vou pintar de verde o que nao ficou verde. A casa de mentira foi"
  echo "  apagada do mesmo jeito; nada tocou o seu computador de verdade."
  echo "======================================================================"
  echo
  exit 1
fi
