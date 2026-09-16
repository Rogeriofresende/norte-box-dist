#!/usr/bin/env bash
# nb-conselho-juiz2.sh — o JUIZ DE FORA (outra IA/marca) fecha o conselho.
# Uso: nb-conselho-juiz2.sh "a decisão" "texto das vozes (Claude + voz de fora)"
set -euo pipefail
[ -z "${1:-}" ] && { echo "uso: nb-conselho-juiz2.sh \"a decisão\" \"as vozes\""; exit 2; }
DIR="$(cd "$(dirname "$0")" && pwd)"
node "$DIR/conselho-ia2.js" juiz "$1" "${2:-}"
