#!/usr/bin/env bash
# atrito-dono.sh — REGRA item->dono do pacote de atrito (NRT-_990210).
# Le os sinais de atrito (so-rotulos) da fila local e produz uma lista simples:
#   "onde travou/errou  ->  dono (Ada tecnico / Leo copy-metodo)".
# E o INSUMO do conserto ANTES da estreia da advocacia. Versao minima honesta (nao um
# meta-framework): so agrega contagem por rotulo e aponta o dono por um mapa fixo.
#
# NUNCA carrega conteudo — le so os campos de rotulo (cmd/travas/erro). Se a fila trouxer
# qualquer campo de conteudo (nao deveria), este script IGNORA (projeta so os rotulos).
# Fail-open: sem fila / sem jq -> imprime "nada" e sai 0.
set -u

STATE_DIR="${HOME}/.norte-box"
QUEUE="${NORTE_ATRITO_QUEUE:-$STATE_DIR/atrito-queue.jsonl}"

command -v jq >/dev/null 2>&1 || { echo "nada a analisar (sem jq)"; exit 0; }
[ -f "$QUEUE" ] || { echo "nada a analisar (fila de atrito vazia)"; exit 0; }

# --- MAPA fixo rotulo-de-trava -> dono. So rotulos conhecidos; desconhecido -> Ada (revisar). ---
# secret-guard   = trava tecnica de seguranca        -> Ada
# consent-gate   = fluxo de aceite/onboarding tecnico -> Ada
# confirmar-antes= metodo/copy do lembrete            -> Leo
# outro-gate     = gate novo nao mapeado              -> Ada (revisar)
_dono_da_trava() {
  case "$1" in
    secret-guard)    printf 'Ada (tecnico)' ;;
    consent-gate)    printf 'Ada (tecnico)' ;;
    confirmar-antes) printf 'Leo (copy/metodo)' ;;
    *)               printf 'Ada (revisar)' ;;
  esac
}

echo "== Pacote de atrito -> itens pra consertar ANTES da advocacia =="
echo

# --- Comandos usados/tentados (so verbo, contagem) ---
echo "-- comandos usados (verbo, so da allowlist) --"
CMDS="$(jq -r 'select(.atrito.cmd != null) | .atrito.cmd' "$QUEUE" 2>/dev/null | sort | uniq -c | sort -rn)"
if [ -n "$CMDS" ]; then printf '%s\n' "$CMDS" | sed 's/^/   /'; else echo "   (nenhum)"; fi
echo

# --- Travas por rotulo -> dono ---
echo "-- travas que barraram -> dono --"
TRAVAS="$(jq -r 'select(.atrito.travas != null) | .atrito.travas[]' "$QUEUE" 2>/dev/null | sort | uniq -c | sort -rn)"
if [ -n "$TRAVAS" ]; then
  # cada linha: "  N  rotulo"
  printf '%s\n' "$TRAVAS" | while IFS= read -r _l; do
    _n="$(printf '%s' "$_l" | awk '{print $1}')"
    _rot="$(printf '%s' "$_l" | awk '{print $2}')"
    [ -z "$_rot" ] && continue
    printf '   [%sx] %-16s -> %s\n' "$_n" "$_rot" "$(_dono_da_trava "$_rot")"
  done
else
  echo "   (nenhuma trava)"
fi
echo

# --- Erros (bit) -> Ada tecnico ---
ERROS="$(jq -r 'select(.atrito.erro==true) | "erro"' "$QUEUE" 2>/dev/null | wc -l | tr -d ' ')"
case "$ERROS" in ''|*[!0-9]*) ERROS=0 ;; esac
echo "-- erros (deu-erro sim) --"
if [ "$ERROS" -gt 0 ]; then
  printf '   [%sx] %-16s -> %s\n' "$ERROS" "erro-tecnico" "Ada (tecnico)"
else
  echo "   (nenhum erro)"
fi
echo
echo "== fim (so rotulos + donos; zero conteudo do trabalho dela) =="
exit 0
