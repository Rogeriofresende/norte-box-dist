#!/usr/bin/env bash
# instalar-barrinha.sh - liga a barrinha do Norte-box no seu Claude Code, com SEGURANCA.
#
# Um PLUGIN nao declara statusLine sozinho: quem manda na barra e o settings.json do usuario.
# Este instalador faz esse passo UMA VEZ, do jeito certo:
#   1. Acha o settings.json ($HOME/.claude/settings.json por padrao; override por 1o argumento).
#   2. Se JA existe uma statusLine configurada -> NAO sobrescreve calado: mostra o que tem,
#      faz backup, e SO troca se voce confirmar (ou passar --forcar).
#   3. Faz BACKUP com timestamp antes de qualquer escrita (settings.json.bak.<epoch>).
#   4. Escreve o bloco statusLine apontando pro norte-statusline deste plugin.
#
# LEIS do Norte-box: fail-open no que e cosmetico, mas este passo MEXE no settings do usuario,
# entao aqui e o oposto de calado -> pede confirmacao e faz backup. Requer jq (parse seguro).
# NAO roda em nenhum hook; e um comando manual, rodado pelo dono da maquina.
#
# Uso:
#   bash instalar-barrinha.sh                 # settings padrao, com confirmacao
#   bash instalar-barrinha.sh --forcar        # troca statusLine existente sem perguntar
#   bash instalar-barrinha.sh /caminho/settings.json [--forcar]
set -u

# --- Resolve caminho do script (pra apontar a barra pro binario CERTO) ---
HERE="$(cd "$(dirname "$0")" && pwd)"
BARRA="$HERE/norte-statusline"

# --- Argumentos ---
SETTINGS=""
FORCAR=""
for a in "$@"; do
  case "$a" in
    --forcar) FORCAR=1 ;;
    *) [ -z "$SETTINGS" ] && SETTINGS="$a" ;;
  esac
done
[ -n "$SETTINGS" ] || SETTINGS="$HOME/.claude/settings.json"

echo "== Instalar a barrinha do Norte-box =="
echo "   barra : $BARRA"
echo "   alvo  : $SETTINGS"
echo

# --- Pre-requisitos ---
if ! command -v jq >/dev/null 2>&1; then
  echo "ERRO: preciso do 'jq' pra editar o settings.json com seguranca (parse real, sem regex)."
  echo "      macOS: brew install jq"
  exit 1
fi
if [ ! -x "$BARRA" ]; then
  echo "ERRO: nao achei o binario da barra executavel em: $BARRA"
  exit 1
fi

mkdir -p "$(dirname "$SETTINGS")" 2>/dev/null || true

# settings.json pode nao existir ainda -> comeca de {}
if [ ! -f "$SETTINGS" ]; then
  echo "(settings.json nao existe ainda; vou criar um novo com so a statusLine.)"
  printf '{}\n' > "$SETTINGS"
fi

# --- Valida que o settings.json atual e JSON (senao NAO mexo) ---
if ! jq -e . "$SETTINGS" >/dev/null 2>&1; then
  echo "ERRO: $SETTINGS nao e um JSON valido. Nao vou mexer nele. Corrija manualmente antes."
  exit 1
fi

# --- Detecta statusLine ja existente -> NAO sobrescreve calado ---
_ja="$(jq -c '.statusLine // empty' "$SETTINGS" 2>/dev/null || true)"
if [ -n "$_ja" ]; then
  _cmd_atual="$(jq -r '.statusLine.command // empty' "$SETTINGS" 2>/dev/null || true)"
  # Ja aponta pro nosso binario? Entao esta feito, nada a fazer.
  case "$_cmd_atual" in
    *norte-statusline*) echo "Ja instalada e apontando pro Norte-box. Nada a fazer."; exit 0 ;;
  esac
  echo "ATENCAO: ja existe uma statusLine configurada:"
  echo "   $_ja"
  echo
  if [ -z "$FORCAR" ]; then
    # Sem terminal (rodando dentro de script/pipe) NAO da pra perguntar -> nunca sobrescreve
    # calado: cancela e ensina o --forcar. So pergunta quando ha um TTY de verdade.
    if [ -e /dev/tty ] && { exec 3</dev/tty; } 2>/dev/null; then
      printf "Trocar pela barrinha do Norte-box? (backup sera feito) [s/N] "
      read -r _resp <&3 2>/dev/null || _resp=""
      exec 3<&- 2>/dev/null || true
      case "$_resp" in
        s|S|sim|SIM) : ;;
        *) echo "Cancelado. Nada foi alterado."; exit 0 ;;
      esac
    else
      echo "Sem terminal pra confirmar. Nada foi alterado."
      echo "  Pra trocar mesmo assim: bash instalar-barrinha.sh \"$SETTINGS\" --forcar"
      exit 0
    fi
  else
    echo "(--forcar: trocando sem perguntar)"
  fi
fi

# --- BACKUP com timestamp ANTES de escrever ---
_epoch="$(date +%s 2>/dev/null || echo now)"
_bak="${SETTINGS}.bak.${_epoch}"
if cp "$SETTINGS" "$_bak" 2>/dev/null; then
  echo "Backup: $_bak"
else
  echo "ERRO: nao consegui fazer backup de $SETTINGS. Abortando (nao escrevo sem backup)."
  exit 1
fi

# --- Escreve o bloco statusLine (merge preservando o resto do settings) ---
_tmp="$(mktemp 2>/dev/null || echo "${SETTINGS}.tmp.$$")"
if jq --arg cmd "$BARRA" \
     '.statusLine = {"type":"command","command":$cmd,"padding":0}' \
     "$SETTINGS" > "$_tmp" 2>/dev/null && jq -e . "$_tmp" >/dev/null 2>&1; then
  mv "$_tmp" "$SETTINGS" 2>/dev/null || { echo "ERRO ao gravar. Restaure de $_bak."; exit 1; }
  echo
  echo "PRONTO. A barrinha esta ligada. Reinicie/atualize o Claude Code pra ver:"
  echo "   ▲N · ctx:P% · Modelo"
  echo "(Pra desfazer: cp \"$_bak\" \"$SETTINGS\")"
else
  rm -f "$_tmp" 2>/dev/null || true
  echo "ERRO ao montar o novo settings.json. Nada foi alterado (seu arquivo esta intacto; backup em $_bak)."
  exit 1
fi
exit 0
