#!/usr/bin/env bash
# _agentes-nomes.sh — helper COMPARTILHADO: resolve o nome de exibicao de cada agente do time.
# Reusado pela auto-apresentacao (SessionStart) e pelo comando de rename (/norte-box:time).
#
# Fonte da verdade dos NOMES novos: $HOME/.norte-box/agentes-nomes.json = { "<id>": "<nome novo>" }.
# Se o arquivo nao existe / jq ausente / id nao tem override -> cai no nome padrao (curado).
# LEIS: so LE (nunca escreve aqui), fail-open, trata o json como DADO (jq, nunca eval).
#
# Uso:
#   . "$DIR/_agentes-nomes.sh"
#   nome_agente ada   -> imprime "Ada" (ou o nome que a pessoa deu)
#   for id in $AGENTE_IDS; do ...; done   # ids canonicos, ordem fixa
set -u

STATE_DIR="${HOME}/.norte-box"
NOMES_FILE="${STATE_DIR}/agentes-nomes.json"

# ids canonicos + papel de 1 linha (o "papel colado"). Ordem = ordem de apresentacao.
AGENTE_IDS="ada max val leo"

_papel_de() {
  case "$1" in
    ada)  printf 'engenharia e operações — constrói, entrega e mantém de pé' ;;
    max)  printf 'chefe de gabinete — coordena o time e te dá a foto clara' ;;
    val)  printf 'revisão — tenta quebrar o que deram por pronto (bugs, segurança, retorno)' ;;
    leo)  printf 'marketing — a mensagem que chega no cliente (copy, conteúdo, alcance)' ;;
    *)    printf 'agente' ;;
  esac
}

_nome_padrao() {
  case "$1" in
    ada) printf 'Ada' ;; max) printf 'Max' ;; val) printf 'Val' ;;
    leo) printf 'Leo' ;; *) printf '%s' "$1" ;;
  esac
}

# nome_agente <id> -> nome de exibicao (override do json, senao padrao). Fail-open.
nome_agente() {
  local id="$1" novo=""
  if [ -f "$NOMES_FILE" ] && command -v jq >/dev/null 2>&1; then
    novo="$(jq -r --arg k "$id" '.[$k] // empty' "$NOMES_FILE" 2>/dev/null || true)"
  fi
  if [ -n "$novo" ]; then printf '%s' "$novo"; else _nome_padrao "$id"; fi
}
