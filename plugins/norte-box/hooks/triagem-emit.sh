#!/usr/bin/env bash
# triagem-emit.sh - UserPromptSubmit hook do norte-box: a "TRIAGEM DO PEDIDO" LIGADA no automatico,
# com o FREIO DE SILENCIO (NRT-_990148, conversa 746, GO do CEO).
#
# O QUE FAZ: le o pedido novo do CEO, roda a triagem (_norte_triar da lib _triagem.sh) e, SO QUANDO
# a triagem FALA (risco real: publicar / apagar-ou-mexer), injeta a sugestao-a-confirmar como
# additionalContext. Em consulta / "oi" / follow-up / ambiguo, a triagem CALA -> o hook nao injeta
# NADA (fica quieto). Isso realiza a regra literal do CEO: "so fala quando e risco, calada no resto".
#
# ADITIVO, NUNCA BLOQUEIA (igual confirmar-antes.sh): so emite additionalContext (nunca exit 2, nunca
# `decision:block`). O Claude LE a sugestao e decide; a peca nao trava o fluxo.
#
# LEIS (iguais aos outros hooks do box):
#   - FAIL-OPEN: qualquer erro (jq ausente, lib nao carregou, parse falhou) -> consome stdin e exit 0.
#   - DADO E DADO: o prompt e TEXTO que entra na sugestao — NUNCA e executado/eval. `set -u`, sem eval.
#   - LOCAL, ZERO REDE: so monta texto e injeta. Nada sai da maquina.
#   - Kill-switch NORTE_TRIAGEM=0 (herdado da lib): a triagem fica inerte -> nada a injetar.
set -u

# Le o JSON do stdin. Sem jq nao da pra parsear com seguranca -> fail-open silencioso (consome stdin
# pra evitar SIGPIPE e sai; o fluxo segue como antes, so sem a triagem injetada).
if command -v jq >/dev/null 2>&1; then
  PROMPT="$(cat | jq -r '.prompt // empty' 2>/dev/null || true)"
else
  cat >/dev/null 2>&1 || true
  exit 0
fi

# Carrega a lib da peca (fonte unica). bin/ e hooks/ ja sao irmaos; a lib e vizinha deste hook.
# shellcheck source=/dev/null
. "$(dirname "$0")/_triagem.sh" 2>/dev/null || exit 0   # sem a lib -> fail-open (nada injetado).
command -v _norte_triar >/dev/null 2>&1 || exit 0        # lib carregou mas sem a funcao -> fail-open.

# Roda a triagem. Com o FREIO, a saida vem VAZIA quando nao ha risco -> nada a injetar (fica quieto).
SUG="$(_norte_triar "$PROMPT" 2>/dev/null || true)"
[ -z "$SUG" ] && exit 0   # o freio calou (consulta/oi/follow-up) -> hook silencioso.

# So chega aqui em RISCO REAL: injeta a sugestao-a-confirmar como additionalContext (aditivo, nao bloqueia).
jq -n --arg ctx "$SUG" '{
  "hookSpecificOutput": {
    "hookEventName": "UserPromptSubmit",
    "additionalContext": $ctx
  }
}' 2>/dev/null || true

exit 0
