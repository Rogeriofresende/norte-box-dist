#!/usr/bin/env bash
# aplicar-guiado.sh — a versao "APERTA ENTER E ASSISTE" do teste do APLICAR+DESFAZER (NRT-_990212).
#
# POR QUE ESTE ARQUIVO EXISTE:
#   O sombra-guiado.sh ja conduz o CEO pela mao no ENSAIO (a Sombra, que NAO toca o arquivo). Esta fatia
#   deixa a caixa APLICAR de verdade — e este guiado mostra isso trabalhando: ensaia, aplica no arquivo
#   REAL (le do disco pra PROVAR que mudou), desfaz (le e prova que voltou), e sente a TRAVA (o arquivo
#   mudou "por fora" desde o ensaio -> a caixa RECUSA aplicar por cima). ZERO copiar-colar, ZERO export/cd/rm.
#
# COMO ELE FAZ (sem gambiarra):
#   - Cria um $HOME descartavel em /tmp (mktemp -d), pre-semeia config.txt (saudacao: ola mundo).
#   - Aponta o plugin pra arvore LIMPA (git archive HEAD) — nunca a arvore suja.
#   - Roda o nb-sombra / nb-aplicar / nb-desfazer REAIS (as libs provadas, red-teamadas pelo Val) com
#     HOME/PATH setados POR DENTRO. Le o RECIBO que o ensaio gera e o recibo-aplic que o aplicar imprime.
#   - Depois de aplicar/desfazer, LE o arquivo do disco e mostra o conteudo REAL — a prova viva.
#   - FILTRA so o ruido de diagnostico do diff/recibo (--- /, +++ /, @@, NB_SOMBRA_ARQUIVO=, NB_APLICAR_RECIBO=)
#     — nunca as linhas -/+ de conteudo (que sao o valor). Mesmo filtro do sombra-guiado.
#   - trap ... EXIT apaga a casa de mentira MESMO se o CEO apertar Ctrl-C (a prova de interrupcao).
#   - Banner de fecho HONESTO: reflete se algum passo saiu do trilho (nao pinta 🟢 fixo).
#
# USO (o CEO):  bash aplicar-guiado.sh
#   Ele aperta Enter a cada passo e le. Nao digita mais nada.
# USO (a suite/teste):  bash aplicar-guiado.sh --auto   (ou stdin nao-tty)  -> nao espera Enter.
#
# NAO TOCA hooks/_sombra.sh, hooks/_aplicar.sh nem bin/nb-* (as LEIs red-teamadas). So le/roda.
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
#   simples sem -p espera o Enter; erro/EOF nao trava (|| true) — o furo que o Val ja pegou no sombra.
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
  echo "ERRO: rode este comando de dentro do worktree git da branch do Aplicar." >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# 2) casa de mentira descartavel + AUTO-LIMPEZA a prova de interrupcao (trap EXIT)
#    Tudo sob /tmp. O trap roda no fim NORMAL e tambem em SIGINT/SIGTERM (Ctrl-C).
# ---------------------------------------------------------------------------
LAB="$(mktemp -d "${TMPDIR:-/tmp}/aplicar-guiado.XXXXXX")"
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
_nb_sombra="$PLUGTREE/plugins/norte-box/bin/nb-sombra"
_nb_aplicar="$PLUGTREE/plugins/norte-box/bin/nb-aplicar"
_nb_desfazer="$PLUGTREE/plugins/norte-box/bin/nb-desfazer"
for _b in "$_nb_sombra" "$_nb_aplicar" "$_nb_desfazer"; do
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
#   Guardam a saida CRUA (com os marcadores) em variaveis, pra a gente pescar recibo/recibo-aplic.
# ---------------------------------------------------------------------------
_RAW=""      # saida crua do ultimo bin (com os marcadores) — pra pescar caminhos
_filtra() {  # le stdin, tira so o ruido de diagnostico, imprime o resto (o que o CEO ve)
  grep -v -E '^   (--- /|\+\+\+ /|@@ )|^NB_SOMBRA_ARQUIVO=|^NB_APLICAR_RECIBO='
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
_desfazer_real() { # <recibo-aplic>  -> mostra saida limpa, guarda crua em _RAW, retorna rc
  local _rc
  _RAW="$(HOME="$FAKEHOME" bash "$_nb_desfazer" "$@" 2>&1)"; _rc=$?
  printf '%s\n' "$_RAW" | _filtra
  return $_rc
}
# pesca o caminho do RECIBO do ensaio (a partir da linha NB_SOMBRA_ARQUIVO= na saida crua):
_recibo_de_raw() { printf '%s' "$_RAW" | grep -m1 '^NB_SOMBRA_ARQUIVO=' | sed 's/^NB_SOMBRA_ARQUIVO=//'; }
# pesca o recibo-aplic que o aplicar imprimiu (linha NB_APLICAR_RECIBO=):
_recaplic_de_raw() { printf '%s' "$_RAW" | grep -m1 '^NB_APLICAR_RECIBO=' | sed 's/^NB_APLICAR_RECIBO=//'; }

# acumulador de honestidade: vira 1 se QUALQUER passo saiu do trilho (banner de fecho reflete isso).
DEU_RUIM=0

# ===========================================================================
#  O ROTEIRO GUIADO — o CEO so aperta Enter e le.
# ===========================================================================
cat <<'EOF'

======================================================================
  TESTE DO APLICAR + DESFAZER — aperta Enter e assiste.
  Voce vai VER a caixa ENSAIAR, depois APLICAR de verdade (so porque
  VOCE mandou), CONFERIR que mudou no disco, DESFAZER (voltar), e por
  fim sentir a TRAVA que barra aplicar por cima de algo que mudou.
  Tudo numa "casa de mentira" que some sozinha no fim. Eu conduzo —
  voce nao precisa digitar, copiar nem apagar nada.
======================================================================

Ja preparei uma casa de faz-de-conta com um arquivo dentro:
  config.txt  ->  saudacao: ola mundo

EOF

# --- PASSO 1: mostrar o arquivo de verdade ---
_enter "Aperte Enter pra VER o arquivo como ele esta agora... "
echo
echo "--- config.txt AGORA (lido direto do disco da casa) ------------------"
cat "$ALVO"
echo "---------------------------------------------------------------------"
echo

# --- PASSO 2: ENSAIAR (a Sombra — ainda NAO muda nada de verdade) ---
_enter "Aperte Enter pra eu ENSAIAR a troca ('ola mundo' -> 'bom dia')... "
echo
echo "--- ENSAIO (a caixa mexe numa COPIA, nunca no seu arquivo) -----------"
_sombra_real "$ALVO" "ola mundo" "bom dia" guiado
_rc_ensaio=$?
RECIBO="$(_recibo_de_raw).recibo"
echo "---------------------------------------------------------------------"
if [ "$_rc_ensaio" != "0" ] || [ ! -f "$RECIBO" ]; then
  DEU_RUIM=1
  echo
  echo "⚠ o ensaio nao terminou verde como eu esperava (codigo $_rc_ensaio)."
  echo "  Nao vou fingir que deu certo. Ainda assim vou apagar a casa de mentira no fim."
fi
echo "Isto foi so um ENSAIO — o seu arquivo continua 'saudacao: ola mundo'."
echo "Ainda NAO mudei nada de verdade."
echo

# --- PASSO 3: APLICAR (agora muda no arquivo REAL — e a gente prova) ---
_enter "Aperte Enter pra eu APLICAR de verdade (so porque VOCE mandou)... "
echo
echo "--- APLICAR (agora sim, no arquivo de verdade) ----------------------"
if [ -f "$RECIBO" ]; then
  _aplicar_real "$RECIBO"
  _rc_aplicar=$?
  RECAPLIC="$(_recaplic_de_raw)"
else
  _rc_aplicar=1; RECAPLIC=""
  echo "🟡 nao tenho o recibo do ensaio — nao ha o que aplicar."
fi
echo "---------------------------------------------------------------------"
if [ "$_rc_aplicar" != "0" ]; then DEU_RUIM=1; fi
echo
echo "--- config.txt DEPOIS (lido de novo, direto do disco) ---------------"
cat "$ALVO"
echo "---------------------------------------------------------------------"
if grep -qxF 'saudacao: bom dia' "$ALVO"; then
  echo "Viu? AGORA mudou de verdade: 'saudacao: bom dia'. So mudou porque"
  echo "VOCE mandou aplicar — e eu guardei um backup do jeito que estava antes."
else
  DEU_RUIM=1
  echo "⚠ eu esperava ver 'saudacao: bom dia' aqui e nao vi. Nao vou fingir."
fi
echo

# --- PASSO 4: DESFAZER (volta ao original — e a gente prova) ---
_enter "Aperte Enter pra eu DESFAZER e voltar o arquivo pro original... "
echo
echo "--- DESFAZER (restaura o backup do original) ------------------------"
if [ -n "$RECAPLIC" ] && [ -f "$RECAPLIC" ]; then
  _desfazer_real "$RECAPLIC"
  _rc_desfazer=$?
else
  _rc_desfazer=1
  echo "🟡 nao tenho o recibo-de-aplicacao — nao ha o que desfazer."
fi
echo "---------------------------------------------------------------------"
if [ "$_rc_desfazer" != "0" ]; then DEU_RUIM=1; fi
echo
echo "--- config.txt DEPOIS DE DESFAZER (lido do disco) -------------------"
cat "$ALVO"
echo "---------------------------------------------------------------------"
if grep -qxF 'saudacao: ola mundo' "$ALVO"; then
  echo "Voltou pro original: 'saudacao: ola mundo'. Sempre da pra desfazer."
else
  DEU_RUIM=1
  echo "⚠ eu esperava ver o arquivo de volta em 'saudacao: ola mundo' e nao vi."
fi
echo

# --- PASSO 5: A TRAVA (armadilha nº1) — mudou por fora desde o ensaio -> RECUSA ---
_enter "Aperte Enter pra ver a TRAVA de seguranca em acao... "
echo
echo "Vou ensaiar de novo e, logo depois, simular OUTRA PESSOA (ou outro"
echo "programa) mexendo no arquivo 'por fora'. Ai eu tento APLICAR o ensaio"
echo "velho — e a caixa deve se RECUSAR, porque o arquivo mudou."
echo
echo "--- ENSAIO 2 (numa copia, como antes) -------------------------------"
_sombra_real "$ALVO" "ola mundo" "bom dia" trava
_rc_ensaio2=$?
RECIBO2="$(_recibo_de_raw).recibo"
echo "---------------------------------------------------------------------"
if [ "$_rc_ensaio2" != "0" ] || [ ! -f "$RECIBO2" ]; then DEU_RUIM=1; fi
# alguem mexe no arquivo POR FORA, depois do ensaio:
printf 'linha nova que outra pessoa escreveu\n' >> "$ALVO"
ALVO_MUDADO_ANTES="$(cat "$ALVO")"
echo
echo "(pronto: 'outra pessoa' acabou de adicionar uma linha no config.txt)"
echo
echo "--- TENTATIVA DE APLICAR O ENSAIO VELHO (a caixa deve RECUSAR) -------"
if [ -f "$RECIBO2" ]; then
  _aplicar_real "$RECIBO2"
  _rc_trava=$?
else
  _rc_trava=2
  echo "🟡 nao tenho o recibo do ensaio 2."
fi
echo "---------------------------------------------------------------------"
# AQUI o vermelho e o resultado CERTO: exit 1 (recusou) e' o sucesso do passo.
if [ "$_rc_trava" = "1" ]; then
  echo "🔴 a caixa RECUSOU aplicar — 'o arquivo mudou desde o ensaio'. Isso"
  echo "e' o certo: ela se recusa a escrever por cima de algo que mudou."
else
  DEU_RUIM=1
  echo "⚠ eu esperava a caixa RECUSAR (por conta da mudanca) e ela nao recusou."
fi
echo
echo "--- config.txt AGORA (provando que a caixa NAO encostou) ------------"
cat "$ALVO"
echo "---------------------------------------------------------------------"
if [ "$(cat "$ALVO")" = "$ALVO_MUDADO_ANTES" ]; then
  echo "Intocado: a linha da 'outra pessoa' continua la e nada foi trocado."
  echo "A trava e' de verdade — nao promessa: ela barra por conta propria."
else
  DEU_RUIM=1
  echo "⚠ o arquivo mudou depois da recusa — isso NAO devia acontecer."
fi
echo

# --- PASSO 6: fechar + auto-limpeza (o CEO nao roda rm) ---
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
  echo "  Acabou 🟢. Voce viu: a caixa ENSAIA, APLICA so quando VOCE manda,"
  echo "  o arquivo MUDA de verdade, o DESFAZER volta ao original, e a TRAVA"
  echo "  barra aplicar por cima de algo que mudou. Nada tocou o seu computador."
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
