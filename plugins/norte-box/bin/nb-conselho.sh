#!/usr/bin/env bash
# nb-conselho.sh — teto diário do /norte:conselho.
# Uso: nb-conselho.sh [leve|fundo]   (default: leve)
#   leve  = 1 pergunta ao Claude (3 papéis + juiz numa resposta). Teto CONSELHO_CAP (default 15).
#   fundo = vozes em perguntas separadas + juiz cego (gasta ~5x). Teto CONSELHO_CAP_FUNDO (default 3).
# NÃO chama nenhum modelo — quem responde é o Claude do próprio usuário (o comando conselho.md).
# Este script só CONTA e barra ao passar do teto. Grava SÓ em $HOME/.norte-box. Imprime UMA linha.
set -euo pipefail

MODO="${1:-leve}"
case "$MODO" in
  leve)  CAP="${CONSELHO_CAP:-15}";        USO_FILE="conselho-uso.json" ;;
  fundo) CAP="${CONSELHO_CAP_FUNDO:-3}";    USO_FILE="conselho-uso-fundo.json" ;;
  *) echo "CONSELHO_ERRO: modo inválido '$MODO' (use leve|fundo)"; exit 2 ;;
esac

DIR="$HOME/.norte-box"
USO="$DIR/$USO_FILE"
mkdir -p "$DIR"
HOJE="$(date +%F)"

node -e '
const fs=require("fs");
const uso=process.argv[1], hoje=process.argv[2], cap=parseInt(process.argv[3],10), modo=process.argv[4];
let st={date:hoje,count:0};
try{ st=JSON.parse(fs.readFileSync(uso,"utf8")); }catch(_){}
if(st.date!==hoje) st={date:hoje,count:0};
if(st.count>=cap){ console.log(`CONSELHO_CHEIO modo=${modo} count=${st.count} cap=${cap}`); process.exit(0); }
st.count+=1;
fs.writeFileSync(uso, JSON.stringify(st));
console.log(`CONSELHO_OK modo=${modo} count=${st.count} cap=${cap} restam=${cap-st.count}`);
' "$USO" "$HOJE" "$CAP" "$MODO"
