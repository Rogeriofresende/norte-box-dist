#!/usr/bin/env bash
# norte-login.sh - login pelo Google via DEVICE FLOW (igual "gh auth login").
#
# NAO e um hook registrado (nao esta no hooks.json): mora em hooks/ so por causa
# da allowlist de *.sh. E o script do comando /norte-box:login.
#
# O QUE FAZ (device flow de "installed app", OAuth 2.0 Google):
#   1. POST https://oauth2.googleapis.com/device/code (scope: openid email)
#      -> recebe device_code + user_code + verification_url + intervalo de polling.
#   2. MOSTRA o user_code + a URL pra pessoa autorizar no browser.
#   3. FAZ POLLING em https://oauth2.googleapis.com/token ate a pessoa autorizar.
#   4. DECODIFICA o id_token (base64 do payload JWT) e extrai "sub" + "email".
#   5. GRAVA $HOME/.norte-box/identity.json = {"sub":"...","email":"..."}.
#      NUNCA grava access_token/refresh_token/id_token - so o sub+email
#      (coerente com "so o sub na maquina", SPEC secao Estado).
#
# LEIS INVIOLAVEIS (Norte-box e plugin distribuido):
#   - FAIL-OPEN: qualquer erro interno -> mensagem clara e sai SEM derrubar a sessao.
#     Sem NORTE_BOX_GOOGLE_CLIENT_ID -> imprime instrucao e sai limpo (exit 0).
#   - REDATOR roda ANTES de gravar (fail-closed no proprio redator).
#   - ZERO path/host/segredo interno da Norte. Nenhum client_id/secret no codigo:
#     vem das envs NORTE_BOX_GOOGLE_CLIENT_ID / NORTE_BOX_GOOGLE_CLIENT_SECRET.
#   - Estado so em $HOME/.norte-box. Consome entrada como DADO, nunca executa input.
#   - Portabilidade macOS (bash 3.2): sem EPOCHREALTIME, sem dependencia exotica.
set -u

STATE_DIR="${HOME}/.norte-box"
IDENTITY_FILE="${STATE_DIR}/identity.json"

DEVICE_CODE_URL="https://oauth2.googleapis.com/device/code"
TOKEN_URL="https://oauth2.googleapis.com/token"
GRANT_TYPE="urn:ietf:params:oauth:grant-type:device_code"
SCOPE="openid email"

CLIENT_ID="${NORTE_BOX_GOOGLE_CLIENT_ID:-}"
CLIENT_SECRET="${NORTE_BOX_GOOGLE_CLIENT_SECRET:-}"

# ---------------------------------------------------------------------------
# 0. Sem client_id -> instrucao clara e fail-open (exit 0). Nao trava nada.
# ---------------------------------------------------------------------------
if [ -z "$CLIENT_ID" ]; then
  cat <<'MSG'
(login nao configurado) O app OAuth do Google ainda nao foi criado pra este pacote.

O Rogerio precisa:
  1. Criar um app OAuth "Desktop/Installed app" no Google Cloud Console
     (APIs & Services -> Credentials -> Create Credentials -> OAuth client ID).
  2. Setar a variavel de ambiente NORTE_BOX_GOOGLE_CLIENT_ID com o Client ID.
     (Se o app exigir client secret pro device flow, setar tambem
      NORTE_BOX_GOOGLE_CLIENT_SECRET.)

O segredo vai via .env / variavel de ambiente - NUNCA colado no chat.

Sem isso o login nao roda, mas nada trava: os freios de seguranca seguem valendo
e o resto do Norte-box funciona normal.
MSG
  exit 0
fi

# ---------------------------------------------------------------------------
# Dependencias: curl + jq. Sem uma delas -> fail-open com instrucao.
# ---------------------------------------------------------------------------
if ! command -v curl >/dev/null 2>&1; then
  echo "(login) curl nao encontrado - nao da pra fazer o device flow. Instale curl e tente de novo."
  exit 0
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "(login) jq nao encontrado - nao da pra ler as respostas com seguranca. Instale jq e tente de novo."
  exit 0
fi

mkdir -p "$STATE_DIR" 2>/dev/null || { echo "(login) nao consegui criar $STATE_DIR - fail-open, saindo limpo."; exit 0; }

# ---------------------------------------------------------------------------
# REDATOR: fonte UNICA compartilhada (furo #4). Antes esta copia divergia da do
# telemetry-emit.sh. Agora as duas sourceiam o MESMO _redact.sh.
# ---------------------------------------------------------------------------
_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)"
if [ -n "${_SELF_DIR:-}" ] && [ -f "${_SELF_DIR}/_redact.sh" ]; then
  . "${_SELF_DIR}/_redact.sh"
elif [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/hooks/_redact.sh" ]; then
  . "${CLAUDE_PLUGIN_ROOT}/hooks/_redact.sh"
fi
# Fail-closed: sem redator carregado, o campo vira vazio (nunca grava secret cru).
if ! command -v _safe_field >/dev/null 2>&1; then
  _safe_field() { printf ''; }
fi

# Decodifica o payload (2a parte) de um JWT/id_token: base64url -> JSON.
# NAO valida assinatura (nao precisamos - so lemos claims sub/email do proprio provedor).
# base64url -> base64 padrao (+ padding) antes de decodificar.
_jwt_payload() {
  local _jwt="$1" _payload
  _payload="$(printf '%s' "$_jwt" | cut -d. -f2)"
  [ -z "$_payload" ] && return 1
  # base64url -> base64
  _payload="$(printf '%s' "$_payload" | tr '_-' '/+')"
  # padding pra multiplo de 4
  case $(( ${#_payload} % 4 )) in
    2) _payload="${_payload}==" ;;
    3) _payload="${_payload}=" ;;
  esac
  printf '%s' "$_payload" | base64 -D 2>/dev/null || printf '%s' "$_payload" | base64 --decode 2>/dev/null || return 1
}

# ---------------------------------------------------------------------------
# 1. Pede o device_code + user_code.
# ---------------------------------------------------------------------------
echo "Iniciando login pelo Google (device flow)..."
_dc_resp="$(curl -sS --max-time 15 -X POST "$DEVICE_CODE_URL" \
  --data-urlencode "client_id=${CLIENT_ID}" \
  --data-urlencode "scope=${SCOPE}" 2>/dev/null || true)"

if [ -z "$_dc_resp" ]; then
  echo "(login) nao consegui falar com o Google agora (rede?). Tente de novo mais tarde. Nada travou."
  exit 0
fi

_dc_err="$(printf '%s' "$_dc_resp" | jq -r '.error // empty' 2>/dev/null || true)"
if [ -n "$_dc_err" ]; then
  echo "(login) o Google recusou o pedido de device code: ${_dc_err}."
  echo "        Verifique se o NORTE_BOX_GOOGLE_CLIENT_ID e de um app 'Desktop/Installed' com device flow habilitado."
  exit 0
fi

_device_code="$(printf '%s' "$_dc_resp" | jq -r '.device_code // empty' 2>/dev/null || true)"
_user_code="$(printf '%s' "$_dc_resp"  | jq -r '.user_code // empty' 2>/dev/null || true)"
_verif_url="$(printf '%s' "$_dc_resp"   | jq -r '.verification_url // .verification_uri // empty' 2>/dev/null || true)"
_interval="$(printf '%s' "$_dc_resp"   | jq -r '.interval // 5' 2>/dev/null || echo 5)"
_expires="$(printf '%s' "$_dc_resp"    | jq -r '.expires_in // 300' 2>/dev/null || echo 300)"

if [ -z "$_device_code" ] || [ -z "$_user_code" ] || [ -z "$_verif_url" ]; then
  echo "(login) resposta do Google veio incompleta - nao da pra seguir. Nada travou."
  exit 0
fi

# intervalo/expires sanitizados (so digitos, com default)
case "$_interval" in ''|*[!0-9]*) _interval=5 ;; esac
case "$_expires"  in ''|*[!0-9]*) _expires=300 ;; esac

# ---------------------------------------------------------------------------
# 2. Mostra o codigo + URL pra pessoa autorizar (estilo "gh auth login").
# ---------------------------------------------------------------------------
echo
echo "  Pra entrar, abra no navegador:"
echo "      ${_verif_url}"
echo
echo "  E digite este codigo:"
echo "      ${_user_code}"
echo
echo "  (esperando voce autorizar... a janela expira em ~$(( _expires / 60 )) min)"
echo

# ---------------------------------------------------------------------------
# 3. Polling ate autorizar (ou expirar). Sem EPOCHREALTIME (bash 3.2).
# ---------------------------------------------------------------------------
_elapsed=0
_id_token=""
while [ "$_elapsed" -lt "$_expires" ]; do
  sleep "$_interval"
  _elapsed=$(( _elapsed + _interval ))

  # o client_secret so vai se existir (device flow de installed app costuma pedir).
  if [ -n "$CLIENT_SECRET" ]; then
    _tk_resp="$(curl -sS --max-time 15 -X POST "$TOKEN_URL" \
      --data-urlencode "client_id=${CLIENT_ID}" \
      --data-urlencode "client_secret=${CLIENT_SECRET}" \
      --data-urlencode "device_code=${_device_code}" \
      --data-urlencode "grant_type=${GRANT_TYPE}" 2>/dev/null || true)"
  else
    _tk_resp="$(curl -sS --max-time 15 -X POST "$TOKEN_URL" \
      --data-urlencode "client_id=${CLIENT_ID}" \
      --data-urlencode "device_code=${_device_code}" \
      --data-urlencode "grant_type=${GRANT_TYPE}" 2>/dev/null || true)"
  fi

  [ -z "$_tk_resp" ] && continue

  _tk_err="$(printf '%s' "$_tk_resp" | jq -r '.error // empty' 2>/dev/null || true)"
  case "$_tk_err" in
    authorization_pending) continue ;;                 # ainda nao autorizou
    slow_down) _interval=$(( _interval + 5 )); continue ;;  # o Google pediu pra ir mais devagar
    access_denied)  echo "(login) autorizacao negada no navegador. Nada foi gravado."; exit 0 ;;
    expired_token)  echo "(login) o codigo expirou antes de autorizar. Rode /norte-box:login de novo."; exit 0 ;;
    '' ) : ;;                                           # sem erro -> provavel sucesso
    * )  echo "(login) o Google retornou: ${_tk_err}. Nada foi gravado."; exit 0 ;;
  esac

  _id_token="$(printf '%s' "$_tk_resp" | jq -r '.id_token // empty' 2>/dev/null || true)"
  if [ -n "$_id_token" ]; then
    break
  fi
done

if [ -z "$_id_token" ]; then
  echo "(login) tempo esgotado sem autorizacao. Rode /norte-box:login de novo quando quiser. Nada travou."
  exit 0
fi

# ---------------------------------------------------------------------------
# 4. Decodifica o id_token e extrai SO sub + email. O token NAO e gravado.
# ---------------------------------------------------------------------------
_payload_json="$(_jwt_payload "$_id_token" 2>/dev/null || true)"
if [ -z "$_payload_json" ]; then
  echo "(login) nao consegui ler o id_token. Nada foi gravado. Nada travou."
  exit 0
fi

_sub="$(printf '%s' "$_payload_json"   | jq -r '.sub // empty'   2>/dev/null || true)"
_email="$(printf '%s' "$_payload_json" | jq -r '.email // empty' 2>/dev/null || true)"

# Descarta o token da memoria assim que extraiu o que precisa.
_id_token=""
_tk_resp=""

if [ -z "$_sub" ]; then
  echo "(login) o id_token nao trouxe 'sub'. Nada foi gravado. Nada travou."
  exit 0
fi

# ---------------------------------------------------------------------------
# 5. REDATOR antes de gravar. Grava SO {sub, email} (nunca token/refresh).
# ---------------------------------------------------------------------------
_sub_safe="$(_safe_field "$_sub")"
_email_safe="$(_safe_field "$_email")"

# jq monta o JSON (escapa tudo). Se jq falhar aqui -> fail-open sem gravar.
_identity="$(jq -cn \
  --arg sub   "$_sub_safe" \
  --arg email "$_email_safe" \
  '{sub:$sub, email:$email}' 2>/dev/null || true)"

if [ -z "$_identity" ]; then
  echo "(login) falha ao montar identity.json - nada foi gravado. Nada travou."
  exit 0
fi

if ! printf '%s\n' "$_identity" > "$IDENTITY_FILE" 2>/dev/null; then
  echo "(login) nao consegui gravar identity.json - fail-open, saindo limpo."
  exit 0
fi
chmod 600 "$IDENTITY_FILE" 2>/dev/null || true

echo
if [ -n "$_email_safe" ]; then
  echo "Login OK - identidade gravada (${_email_safe})."
else
  echo "Login OK - identidade gravada."
fi
echo "Na sua maquina fica so o id opaco (sub) + email em identity.json. O token NAO foi guardado."
exit 0
