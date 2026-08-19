#!/usr/bin/env bash
# time-nomes.sh — CLI do time: VER os agentes e RENOMEAR quem a pessoa quiser.
# O nome novo PERSISTE ($HOME/.norte-box/agentes-nomes.json) e vale nas proximas sessoes.
#
# Uso (via /norte-box:time):
#   time-nomes.sh ver                         # lista id -> nome atual + papel
#   time-nomes.sh renomear <id> <novo nome>   # troca o nome de exibicao de <id>
#   time-nomes.sh resetar <id>                # volta <id> pro nome padrao
#   time-nomes.sh resetar-tudo                # apaga todos os overrides
#
# <id> canonico: ada max val leo iris (o nome INTERNO nunca muda; so o de exibicao).
#
# LEIS: estado so em $HOME/.norte-box; grava com jq (json valido) de forma atomica;
#   trata argumentos como DADO (nunca eval); fail-open com mensagem clara.
set -u

DIR="$(cd "$(dirname "$0")" && pwd)"
STATE_DIR="${HOME}/.norte-box"
NOMES_FILE="${STATE_DIR}/agentes-nomes.json"

. "$DIR/_agentes-nomes.sh" 2>/dev/null || { echo "erro: helper de nomes ausente"; exit 0; }

_is_id() { case " $AGENTE_IDS " in *" $1 "*) return 0 ;; *) return 1 ;; esac; }

cmd="${1:-ver}"

_ver() {
  echo "O time (id interno -> nome atual -> papel):"
  for id in $AGENTE_IDS; do
    printf '  %-5s -> %-14s %s\n' "$id" "$(nome_agente "$id")" "$(_papel_de "$id")"
  done
  echo
  echo "Renomear:  /norte-box:time renomear <id> <novo nome>   (ex: renomear leo Leozinho)"
  echo "Resetar:   /norte-box:time resetar <id>   |   resetar-tudo"
}

_gravar() {
  # $1 = id, $2 = novo nome (vazio => remover override)
  command -v jq >/dev/null 2>&1 || { echo "erro: preciso do jq pra gravar o nome com seguranca."; return 0; }
  mkdir -p "$STATE_DIR" 2>/dev/null || true
  [ -f "$NOMES_FILE" ] || printf '{}\n' > "$NOMES_FILE" 2>/dev/null
  # valida json existente (fail-open: se corrompido, comeca do zero)
  jq empty "$NOMES_FILE" >/dev/null 2>&1 || printf '{}\n' > "$NOMES_FILE"
  local tmp="${NOMES_FILE}.tmp.$$"
  if [ -z "$2" ]; then
    jq --arg k "$1" 'del(.[$k])' "$NOMES_FILE" > "$tmp" 2>/dev/null
  else
    jq --arg k "$1" --arg v "$2" '.[$k]=$v' "$NOMES_FILE" > "$tmp" 2>/dev/null
  fi
  if [ -s "$tmp" ] && jq empty "$tmp" >/dev/null 2>&1; then
    mv "$tmp" "$NOMES_FILE" 2>/dev/null && return 0
  fi
  rm -f "$tmp" 2>/dev/null
  echo "erro: nao consegui gravar o nome (fail-open, nada mudou)."
  return 0
}

case "$cmd" in
  ver|"")
    _ver
    ;;
  renomear)
    id="${2:-}"; shift 2 2>/dev/null || shift $#
    novo="$*"
    if [ -z "$id" ] || [ -z "$novo" ]; then
      echo "uso: /norte-box:time renomear <id> <novo nome>"; echo; _ver; exit 0
    fi
    if ! _is_id "$id"; then
      echo "id desconhecido: '$id'. ids validos: $AGENTE_IDS"; exit 0
    fi
    antigo="$(nome_agente "$id")"
    _gravar "$id" "$novo"
    echo "ok: '$antigo' agora se chama '$novo' (id interno segue '$id'). Persiste nas proximas conversas."
    ;;
  resetar)
    id="${2:-}"
    if [ -z "$id" ] || ! _is_id "$id"; then
      echo "uso: /norte-box:time resetar <id>  (ids: $AGENTE_IDS)"; exit 0
    fi
    _gravar "$id" ""
    echo "ok: '$id' voltou pro nome padrao ($(_nome_padrao "$id"))."
    ;;
  resetar-tudo)
    rm -f "$NOMES_FILE" 2>/dev/null
    echo "ok: todos os nomes voltaram ao padrao (Ada/Max/Val/Leo/Iris)."
    ;;
  *)
    echo "comando desconhecido: '$cmd'"; echo; _ver
    ;;
esac
exit 0
