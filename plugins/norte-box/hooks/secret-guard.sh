#!/usr/bin/env bash
# secret-guard.sh - UserPromptSubmit hook do norte-box.
# Bloqueia prompts com secret colado (senha/app-password/API key/token/chave privada).
# NUNCA grava o corpo do prompt. FAIL-OPEN: qualquer erro interno -> deixa passar
# (o freio nunca pode derrubar a sessao do usuario).
# Bypass legitimo (ex: ensinar regex de secret): comece o prompt com [no-secret-check]
set -u

# Le o JSON do stdin e extrai so o campo .prompt. Sem jq nao da pra parsear com seguranca -> fail-open.
if command -v jq >/dev/null 2>&1; then
  PROMPT="$(cat | jq -r '.prompt // empty' 2>/dev/null || true)"
else
  cat >/dev/null 2>&1 || true
  exit 0
fi

case "$PROMPT" in
  '[no-secret-check]'*) exit 0 ;;
esac

# Padroes de alta confianca (baixo falso-positivo). App-password so ancorado ^...$
# (senao 4 palavras curtas em pt-BR falso-positivam).
PATTERNS='(^[[:space:]]*([a-z]{4} ){3}[a-z]{4}[[:space:]]*$)|([A-Z_]*APP_PASSWORD[[:space:]]*=[[:space:]]*[^[:space:]]+)|(ghp_[A-Za-z0-9]{30,})|(github_pat_[A-Za-z0-9_]{30,})|(sk-(ant-)?[A-Za-z0-9_-]{20,})|(AKIA[A-Z0-9]{16})|(aact_[A-Za-z0-9_-]{20,})|(xox[bporas]-[A-Za-z0-9-]{10,})|(-----BEGIN [A-Z ]*PRIVATE KEY)|(AIza[0-9A-Za-z_-]{35})'

if printf '%s' "$PROMPT" | grep -qE "$PATTERNS"; then
  # NUNCA logar o prompt - so o evento, e so se der (fail-open no log tambem)
  echo "[secret-guard] BLOCKED $(date -u +%FT%TZ)" >> "${HOME}/.norte-box/secret-guard.log" 2>/dev/null || true
  # PACOTE DE ATRITO (NRT-_990210): deixa 1 breadcrumb SO-ROTULO ("secret-guard") pra a Norte
  # saber que UM gate barrou — nunca a mensagem, nunca o prompt. Fail-open (nao quebra o gate).
  _AG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)"
  if [ -n "${_AG_DIR:-}" ] && [ -f "${_AG_DIR}/_atrito.sh" ]; then
    . "${_AG_DIR}/_atrito.sh" 2>/dev/null && _atrito_breadcrumb "secret-guard" 2>/dev/null || true
  fi
  cat >&2 <<'MSG'
(bloqueio) secret-guard (norte-box): parece que voce colou um secret (senha/token/chave) no chat.

Secret nunca vai pelo chat - fica no transcript pra sempre. Use um canal seguro
(formulario local / terminal proprio com read -s) e cole so o RESULTADO ("deu certo").

Se for falso-positivo (ex: exemplo de regex), reenvie comecando com:
  [no-secret-check]
MSG
  exit 2
fi

exit 0
