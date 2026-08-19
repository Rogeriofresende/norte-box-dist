#!/usr/bin/env bash
# confirmar-antes.sh - UserPromptSubmit hook do norte-box.
# Freio de METODO (nao de bloqueio): injeta o lembrete "1o movimento = confirmar a
# demanda antes de construir o mecanismo" como additionalContext. NUNCA bloqueia.
# FAIL-OPEN: qualquer erro interno (jq ausente, parse falhou) -> consome stdin e exit 0.
# Consome stdin, trata o prompt como DADO (nunca executa/eval input do usuario).
set -u

# Le o JSON do stdin. Sem jq nao da pra parsear com seguranca -> fail-open silencioso
# (consome stdin pra evitar SIGPIPE e sai; o metodo ainda funciona, so sem o lembrete).
if command -v jq >/dev/null 2>&1; then
  PROMPT="$(cat | jq -r '.prompt // empty' 2>/dev/null || true)"
else
  cat >/dev/null 2>&1 || true
  exit 0
fi

reminder=$(cat <<'EOF'
=== 1o MOVIMENTO — confirmar a demanda ANTES de construir ===
Em pedido NOVO, antes de construir qualquer mecanismo (codigo, analise, artefato,
investigacao), se o pedido descreve construir algo SEM alvo claro, seu 1o movimento
e CONFIRMAR, em 1 pergunta curta, o que a pessoa quer e por qual caminho. So avance
depois do OK dela. Raiz que isso corrige: chegar com a coisa pronta antes de confirmar.
Excecao (execute direto): pedido ja inequivoco OU continuacao explicita ("instala X
que aprovei", "faz o proximo passo"). Na duvida, confirme — custa 1 linha.
=== fim ===
EOF
)

# Emite o additionalContext. Se jq falhar aqui por qualquer motivo -> fail-open (exit 0).
jq -n --arg ctx "$reminder" '{
  "hookSpecificOutput": {
    "hookEventName": "UserPromptSubmit",
    "additionalContext": $ctx
  }
}' 2>/dev/null || true

exit 0
