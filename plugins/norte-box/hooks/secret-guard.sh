#!/usr/bin/env bash
# secret-guard.sh - UserPromptSubmit hook do norte-box.
# Bloqueia prompts com secret colado (senha/app-password/API key/token/chave privada).
# NUNCA grava o corpo do prompt. FAIL-OPEN em erro interno (o freio nunca derruba a sessao) —
# COM UMA EXCECAO: se nao houver como analisar o JSON com seguranca (sem jq, python3 E node),
# o freio BLOQUEIA (fail-closed) pedindo o jq, em vez de deixar passar um secret calado.
# Bypass legitimo (ex: ensinar regex de secret): comece o prompt com [no-secret-check]
set -u

# Le o JSON do stdin UMA vez e extrai so o campo .prompt com um parser seguro.
# Ordem: jq (canonico) -> python3 -> node. Um parser so "vale" se RODAR e SAIR 0 — se ele existe
# mas falha (ex: "python3" = atalho falso da Microsoft Store no Win11, que sai 9009; python3 do Mac
# sem as Command Line Tools), NAO confiamos no resultado: tentamos o proximo. Sem nenhum parser
# confiavel -> modo degradado (grep no JSON cru + fail-closed), tratado mais abaixo. Com jq valido,
# o comportamento e IDENTICO ao de antes.
RAW="$(cat)"
PROMPT=""
PARSER=""
DEGRADED=""

# Cada _try_* retorna 0 so se o parser RODOU e saiu 0; ai grava o .prompt em PROMPT. Qualquer falha
# do parser (binario ausente, atalho falso, JSON invalido, erro de encoding) -> return 1 -> proximo.
_try_jq() {
  command -v jq >/dev/null 2>&1 || return 1
  local out rc
  out="$(printf '%s' "$RAW" | jq -r '.prompt // empty' 2>/dev/null)"; rc=$?
  [ "$rc" -eq 0 ] || return 1
  PROMPT="$out"; return 0
}
# python3: le/escreve em BYTES (sys.stdin.buffer / stdout.buffer) pra nao quebrar com acento/seta/
# emoji no Windows (pipe em cp1252 + -I ignora PYTHONIOENCODING). Qualquer erro -> sys.exit(1).
_try_python3() {
  command -v python3 >/dev/null 2>&1 || return 1
  local out rc
  out="$(printf '%s' "$RAW" | python3 -I -c 'import sys,json
try:
 v=json.load(sys.stdin.buffer).get("prompt")
 sys.stdout.buffer.write(v.encode("utf-8") if isinstance(v,str) else b"")
except Exception:
 sys.exit(1)' 2>/dev/null)"; rc=$?
  [ "$rc" -eq 0 ] || return 1
  PROMPT="$out"; return 0
}
# node: concatena os chunks em bytes e decodifica utf-8 (robusto a chunk no meio de um char).
_try_node() {
  command -v node >/dev/null 2>&1 || return 1
  local out rc
  out="$(printf '%s' "$RAW" | node -e 'const c=[];process.stdin.on("data",d=>c.push(d));process.stdin.on("end",()=>{try{const o=JSON.parse(Buffer.concat(c).toString("utf8"));const p=(o&&typeof o.prompt==="string")?o.prompt:"";process.stdout.write(Buffer.from(p,"utf8"));}catch(e){process.exit(1);}})' 2>/dev/null)"; rc=$?
  [ "$rc" -eq 0 ] || return 1
  PROMPT="$out"; return 0
}

if _try_jq; then PARSER="jq"
elif _try_python3; then PARSER="python3"
elif _try_node; then PARSER="node"
fi

if [ -n "$PARSER" ]; then
  # caminho normal: um parser rodou e saiu 0, isolando o .prompt. Bypass legitimo:
  case "$PROMPT" in
    '[no-secret-check]'*) exit 0 ;;
  esac
else
  # MODO DEGRADADO: nenhum parser confiavel (sem jq/python3/node, ou todos existem mas FALHARAM
  # ao rodar). Nao da pra isolar o .prompt com seguranca:
  #  1) bypass continua valendo se o prompt comeca com [no-secret-check];
  #  2) escaneia o JSON CRU com os padroes de alta confianca (grep conservador, logo abaixo);
  #  3) se nada casar, como nao deu pra analisar com seguranca, BLOQUEIA pedindo o jq (fail-closed).
  DEGRADED=1
  if printf '%s' "$RAW" | grep -qE '"prompt"[[:space:]]*:[[:space:]]*"\[no-secret-check\]'; then
    exit 0
  fi
  PROMPT="$RAW"
fi

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

Secret nunca vai pelo chat - fica no transcript pra sempre. Use o formulario seguro:
  /norte:salvar-seguro <o que e>   (abre no seu navegador e grava direto no .env)
e diga so o RESULTADO ("deu certo"). Se ja colou, troque o valor no servico de origem.

Se for falso-positivo (ex: exemplo de regex), reenvie comecando com:
  [no-secret-check]
MSG
  exit 2
fi

# Modo degradado (sem jq/python3/node) e nenhum padrao de secret casou: como nao deu pra analisar
# o prompt com seguranca, BLOQUEIA (fail-closed) pedindo o jq — nunca deixa um secret passar calado.
if [ -n "$DEGRADED" ]; then
  echo "[secret-guard] BLOCKED-NO-PARSER $(date -u +%FT%TZ)" >> "${HOME}/.norte-box/secret-guard.log" 2>/dev/null || true
  _AG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)"
  if [ -n "${_AG_DIR:-}" ] && [ -f "${_AG_DIR}/_atrito.sh" ]; then
    . "${_AG_DIR}/_atrito.sh" 2>/dev/null && _atrito_breadcrumb "secret-guard" 2>/dev/null || true
  fi
  cat >&2 <<'MSG'
(bloqueio) secret-guard (norte-box): nao consegui checar seu prompt com seguranca.
Falta o 'jq' nesta maquina (e tambem nao achei python3 nem node pra substituir). Pra nao deixar
um secret passar calado, o freio bloqueia ate ter como checar.

Instale o jq (1 comando) e tente de novo:
  Windows:  winget install jqlang.jq
  Mac:      brew install jq
  Linux:    sudo apt-get install -y jq    (ou o gerenciador da sua distro)

Se este prompt NAO tem secret e voce precisa seguir agora, reenvie comecando com:
  [no-secret-check]
MSG
  exit 2
fi

exit 0
