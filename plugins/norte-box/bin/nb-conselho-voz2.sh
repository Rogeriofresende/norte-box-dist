#!/usr/bin/env bash
# nb-conselho-voz2.sh — a VOZ de fora (outra IA/marca do usuário). Uso: nb-conselho-voz2.sh "a decisão"
set -euo pipefail
[ -z "${1:-}" ] && { echo "uso: nb-conselho-voz2.sh \"a decisão\""; exit 2; }
DIR="$(cd "$(dirname "$0")" && pwd)"
node "$DIR/conselho-ia2.js" voz "$*"
