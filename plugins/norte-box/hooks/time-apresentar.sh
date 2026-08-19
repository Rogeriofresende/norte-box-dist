#!/usr/bin/env bash
# time-apresentar.sh — AUTO-APRESENTACAO do time (hook SessionStart).
# No inicio da PRIMEIRA conversa, o time se apresenta 1x (cada agente: nome + pra que serve).
# Depois disso NAO repete (flag $HOME/.norte-box/time-apresentado). Respeita o rename:
# usa o nome que a pessoa deu (agentes-nomes.json), nao so o padrao.
#
# LEIS (mesmas dos outros hooks do box):
#   - FAIL-OPEN: exit 0 SEMPRE. Nunca trava a sessao.
#   - Emite `hookSpecificOutput.additionalContext` (o Claude injeta no contexto e apresenta).
#   - Estado so em $HOME/.norte-box. So LE o json de nomes (nunca executa/eval).
#   - Idempotente: 2a sessao no mesmo HOME nao reapresenta.
set -u

DIR="$(cd "$(dirname "$0")" && pwd)"
STATE_DIR="${HOME}/.norte-box"
FLAG="${STATE_DIR}/time-apresentado"

# ja apresentou neste HOME -> nao repete (consome stdin pra evitar SIGPIPE e sai limpo)
if [ -f "$FLAG" ]; then
  cat >/dev/null 2>&1 || true
  exit 0
fi

cat >/dev/null 2>&1 || true   # SessionStart manda um json no stdin; consome como DADO

# jq ausente -> fail-open: nao apresenta (nao vale a pena montar json a mao e arriscar quebrar)
command -v jq >/dev/null 2>&1 || exit 0

# resolve os nomes (respeitando rename)
. "$DIR/_agentes-nomes.sh" 2>/dev/null || exit 0

linhas=""
for id in $AGENTE_IDS; do
  n="$(nome_agente "$id")"
  p="$(_papel_de "$id")"
  linhas="${linhas}- **${n}** — ${p}"$'\n'
done

intro="$(cat <<EOF
=== O TIME SE APRESENTA (1a vez) ===
Apresente o time ao usuario, uma linha por agente, exatamente com estes nomes e papeis
(sao os nomes atuais — o usuario pode ter renomeado algum). Diga, no seu tom, que ele pode
chamar cada um pelo nome e que pode renomear quem quiser com /norte-box:time renomear <id> <novo nome>.

${linhas}
=== fim (nao repita esta apresentacao nas proximas conversas) ===
EOF
)"

jq -n --arg ctx "$intro" '{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": $ctx
  }
}' 2>/dev/null || exit 0

# marca que ja apresentou (fail-open: se nao der pra gravar, na pior das hipoteses reapresenta)
mkdir -p "$STATE_DIR" 2>/dev/null || true
printf '%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo apresentado)" > "$FLAG" 2>/dev/null || true

exit 0
