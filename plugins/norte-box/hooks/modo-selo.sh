#!/usr/bin/env bash
# modo-selo.sh - SessionStart hook do norte-box (Fase 2 — DOIS MODOS).
# Mostra, no inicio de cada sessao, em QUAL MODO o Norte-box esta:
#   - privado        -> "Modo privado — a Norte nao ve este trabalho"
#   - compartilhavel -> "Modo compartilhavel — MEDIDOR ligado (SO numeros); a Norte NAO ve o trabalho"
# O selo bate com o ESTADO REAL do disco (le a MESMA fonte que os hooks de telemetria usam
# pra decidir se enviam — _modo.sh). Nunca "diz privado e envia": o gate e a leitura sao o
# mesmo arquivo. FAIL-CLOSED: sem leitor de modo -> mostra privado (o estado seguro).
#
# LEIS: FAIL-OPEN pro trabalho (exit 0 sempre), sync (imprime ANTES da sessao comecar).
#   So LE $HOME/.norte-box/modo. Nao escreve nada. Nao imprime segredo/caminho.
set -u

_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)"
if [ -n "${_SELF_DIR:-}" ] && [ -f "${_SELF_DIR}/_modo.sh" ]; then
  . "${_SELF_DIR}/_modo.sh"
elif [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/hooks/_modo.sh" ]; then
  . "${CLAUDE_PLUGIN_ROOT}/hooks/_modo.sh"
fi

# Consome stdin (SessionStart manda um JSON) como DADO, so pra evitar SIGPIPE.
cat >/dev/null 2>&1 || true

if command -v _norte_modo >/dev/null 2>&1; then
  _m="$(_norte_modo)"
else
  _m="privado"   # fail-closed: sem leitor -> o estado seguro e privado
fi

if [ "$_m" = "compartilhavel" ]; then
  printf '%s\n' "🔗 Norte-box · Modo compartilhavel — MEDIDOR ligado (SO os numeros de uso). A Norte NAO ve o seu trabalho; pra mostrar uma sessao: /norte-box:compartilhar. Trocar: /norte-box:modo privado"
else
  printf '%s\n' "🔒 Norte-box · Modo privado — a Norte NAO ve este trabalho (nada e enviado). Trocar: /norte-box:modo compartilhavel"
fi
exit 0
