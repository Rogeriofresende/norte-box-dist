#!/usr/bin/env bash
# consent-gate.sh - UserPromptSubmit hook do norte-box.
# No 1o uso, se a pessoa ainda nao aceitou o termo (ou a versao aceita e velha), AVISA que a
# telemetria (o MEDIDOR) so opera apos o aceite e instrui a rodar /norte-box:consent.
#
# MODELO A (numeros por padrao) + FAIL-OPEN (SPEC 6.1): este gate NAO trava o trabalho.
# Ele NUNCA usa exit 2. A "trava" e COMPORTAMENTAL — sem aceite, o telemetry-emit nao emite
# (o _norte_pode_enviar exige consent aceito); mas o Claude do usuario segue funcionando.
# Motivo: (1) o termo Modelo A promete "NUNCA trava o seu trabalho"; (2) o exit 2 causava o
# DEADLOCK do "sim" (bug 3) — o `sim` do aceite e um prompt comum, era interceptado pelo exit 2
# ANTES de chegar ao /norte-box:consent que gravaria o aceite. Sem hard-block, nao ha deadlock.
#
# Os freios de SEGURANCA (secret-guard) sao um hook SEPARADO e valem SEMPRE, com ou sem aceite —
# este gate so trata a telemetria/medidor.
# NUNCA executa o input do usuario (consome stdin como DADO). NAO escreve fora de $HOME/.norte-box.
set -u

# Versao vigente do termo. Bump = re-aceite obrigatorio.
# DEVE bater com a versao em commands/consent.md e com NORTE_CONSENT_VERSION em hooks/_modo.sh.
TERM_VERSION="5"

STATE_DIR="${HOME}/.norte-box"
CONSENT_FILE="${STATE_DIR}/consent.json"

# Consome stdin sempre (evita SIGPIPE). NUNCA interpreta como comando.
_stdin="$(cat 2>/dev/null || true)"

# Sem jq nao da pra ler a versao aceita com seguranca -> fail-open (nao avisa, deixa passar).
if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

# Le o prompt e NORMALIZA (tira espaco/tab das pontas) antes de casar - senao " /norte-box:consent"
# (um espaco na frente, coisa que o usuario digita) cairia no aviso pra sempre.
_prompt="$(printf '%s' "$_stdin" | jq -r '.prompt // empty' 2>/dev/null || true)"
_prompt="${_prompt#"${_prompt%%[![:space:]]*}"}"   # trim inicio
_prompt="${_prompt%"${_prompt##*[![:space:]]}"}"   # trim fim

# Comandos de onboarding: nao avisa (a pessoa ja esta no caminho do aceite).
case "$_prompt" in
  '/norte-box:convite'*|'/norte-box:consent'*|'/norte-box:doctor'*|'/norte-box:login'*|'/norte-box:telemetry'*|'/norte-box:compartilhar'*|'/norte-box:modo'*|'[norte-box-consent]'*) exit 0 ;;
esac

# MODO PRIVADO -> a Norte NAO ve nada (nem os numeros). Sem coleta, nao ha o que consentir ->
# este aviso NAO se aplica. So avisa em modo "compartilhavel" (onde o medidor realmente flui).
# Espelha a LEI fail-closed do _modo.sh: so o valor EXATO "compartilhavel" mantem o aviso ativo;
# arquivo ausente/corrompido/qualquer-outro-valor = privado = nao avisa.
_modo_file="${HOME}/.norte-box/modo"
_modo="privado"
if [ -r "$_modo_file" ]; then
  _raw="$(cat "$_modo_file" 2>/dev/null || true)"
  _raw="${_raw#"${_raw%%[![:space:]]*}"}"   # trim inicio
  _raw="${_raw%"${_raw##*[![:space:]]}"}"   # trim fim
  [ "$_raw" = "compartilhavel" ] && _modo="compartilhavel"
fi
[ "$_modo" != "compartilhavel" ] && exit 0

# Ja aceitou com a versao vigente? -> nao avisa (passa em silencio).
if [ -f "$CONSENT_FILE" ]; then
  _accepted_ver="$(jq -r '.versao // empty' "$CONSENT_FILE" 2>/dev/null || true)"
  if [ "$_accepted_ver" = "$TERM_VERSION" ]; then
    exit 0
  fi
fi

# Ainda nao aceitou (ou versao velha), em modo compartilhavel -> AVISA (sem travar).
# additionalContext via stdout JSON (o Claude Code injeta isso no contexto do turno); a mensagem
# humana vai pro stderr. exit 0 SEMPRE (fail-open — nunca segura o trabalho).
cat >&2 <<'MSG'
(aviso) norte-box — o medidor ainda nao esta ligado.

Voce esta no modo COMPARTILHAVEL, mas ainda nao aceitou o termo. Ate aceitar, a Norte
NAO recebe nada (nem os numeros). Pra ligar o MEDIDOR (SO os numeros de uso — pedidos,
tempo, tamanho; pra cobrar de forma justa), rode:

  /norte-box:consent

Por padrao a Norte ve SO os numeros, NUNCA o seu trabalho. Voce compartilha o conteudo de
uma sessao so quando VOCE quiser (/norte-box:compartilhar), com previa antes de enviar.
Os freios de SEGURANCA (secret-guard) ja valem AGORA, com ou sem aceite. Seu trabalho
NUNCA e travado por isto.

Detalhes: docs/TELEMETRIA.md
MSG

# additionalContext pro Claude do turno (best-effort; se jq falhar, so o stderr acima aparece).
printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"[norte-box] O medidor nao esta ligado (modo compartilhavel sem aceite). Sugira ao usuario rodar /norte-box:consent pra ligar SO os numeros de uso. Nada trava o trabalho; o secret-guard ja vale."}}' 2>/dev/null || true

exit 0
