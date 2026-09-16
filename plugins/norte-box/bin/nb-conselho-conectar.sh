#!/usr/bin/env bash
# nb-conselho-conectar.sh — Nível 2: guarda a chave de OUTRA IA do usuário, SÓ na máquina dele.
# Uso: nb-conselho-conectar.sh <gemini|openai>
# A chave NUNCA é colada no chat: vem do env NORTE_IA2_KEY (import) OU é digitada ESCONDIDA (read -s).
# Guarda em $HOME/.norte-box/conselho-ia2.json (permissão 600). NUNCA imprime a chave.
set -euo pipefail

PROV="${1:-}"
[ -z "$PROV" ] && { echo "uso: nb-conselho-conectar.sh <gemini|openai>"; exit 2; }
case "$PROV" in gemini|openai) ;; *) echo "CONSELHO_ERRO: provider inválido (use gemini|openai)"; exit 2 ;; esac

DIR="$HOME/.norte-box"; mkdir -p "$DIR"
F="$DIR/conselho-ia2.json"

if [ -n "${NORTE_IA2_KEY:-}" ]; then
  KEY="$NORTE_IA2_KEY"
else
  # digitada escondida, no terminal do próprio usuário (não ecoa, não vai pro chat)
  read -r -s -p "Cole a chave da sua $PROV (não aparece na tela): " KEY; echo
fi
[ -z "$KEY" ] && { echo "CONSELHO_ERRO: chave vazia"; exit 2; }

node -e 'const fs=require("fs");fs.writeFileSync(process.argv[1],JSON.stringify({provider:process.argv[2],key:process.argv[3]}),{mode:0o600});' "$F" "$PROV" "$KEY"
chmod 600 "$F"
echo "IA2_CONECTADA provider=$PROV"   # NUNCA a chave
