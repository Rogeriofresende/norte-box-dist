#!/usr/bin/env bash
# telemetry-stop.sh - Stop hook do norte-box: mede o TAMANHO da resposta da IA (pro medidor).
#
# MODELO A (numeros por padrao): a resposta da IA e parte do CUSTO (tokens de saida), entao
# medimos o TAMANHO dela pra cobrar justo — mas NUNCA GRAVAMOS nem ENVIAMOS o texto da resposta.
# Este hook le a ultima fala do assistente no transcript SO pra CONTAR chars/tokens e descarta
# o texto no mesmo passo. O evento que sobe carrega SO {uso:{comandos,tokens,ms,bytes}} — zero
# conteudo. Antes este hook enfileirava a resposta INTEIRA em prosa (o "ver tudo"); no Modelo A
# a Norte NAO ve o que a IA respondeu, so o quanto ela respondeu.
#
# LEIS (iguais aos outros hooks):
#   - FAIL-OPEN: exit 0 SEMPRE. Nunca trava/atrasa o Claude.
#   - So mede se a coleta esta LIGADA (telemetry.enabled) e o modo permite enviar.
#   - NUMEROS POR PADRAO: nenhum campo de conteudo (response) no evento.
#   - Consome stdin como DADO, nunca executa. Nao escreve fora de $HOME/.norte-box.
set -u

STATE_DIR="${HOME}/.norte-box"
QUEUE="${STATE_DIR}/telemetry-queue.jsonl"
ENABLED_FLAG="${STATE_DIR}/telemetry.enabled"

_stdin="$(cat 2>/dev/null || true)"

# --- MODO (Fase 2, fail-closed): so quem PODE ENVIAR mede a resposta. Privado NAO enfileira,
#     e compartilhavel-na-mao SEM consent tambem NAO (furo MEDIO, Val). MESMO gate do emit/drain:
#     _norte_pode_enviar = modo=compartilhavel E consent aceito na versao vigente. ---
_SELF_DIR_M="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)"
if [ -n "${_SELF_DIR_M:-}" ] && [ -f "${_SELF_DIR_M}/_modo.sh" ]; then
  . "${_SELF_DIR_M}/_modo.sh"
elif [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/hooks/_modo.sh" ]; then
  . "${CLAUDE_PLUGIN_ROOT}/hooks/_modo.sh"
fi
if ! command -v _norte_pode_enviar >/dev/null 2>&1; then exit 0; fi
_norte_pode_enviar || exit 0

# Desligado / sem jq -> nao emite (fail-open).
[ -f "$ENABLED_FLAG" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0
mkdir -p "$STATE_DIR" 2>/dev/null || exit 0

# Caminho do transcript (o Stop hook fornece transcript_path).
_transcript="$(printf '%s' "$_stdin" | jq -r '.transcript_path // empty' 2>/dev/null || true)"
[ -n "$_transcript" ] || exit 0
[ -f "$_transcript" ] || exit 0

# Extrai a ULTIMA fala do assistente: todos os blocos de texto do ultimo item type=="assistant".
# Usado SO pra MEDIR o tamanho — o texto e descartado logo abaixo, nunca vai pra fila.
# CONSERTO (teste NRT-_998963): a ultima fala pode ainda nao estar gravada quando o fim roda.
# Rele ate NB_FIM_TENTATIVAS vezes (pausa NB_FIM_PAUSA s); se seguir sem texto, anota mesmo assim
# com fim="sem_texto" (nao some calado). Roda em segundo plano: a espera nao atrasa a pessoa.
_ler_fim() { jq -rs '
  [ .[] | select(.type=="assistant") ] | last
  | (.message.content // [])
  | map(select(.type=="text") | .text) | join("\n")
' "$_transcript" 2>/dev/null || true; }
# invite_id (mesma logica do emit): id opaco da pessoa, nunca token.
_invite_id="$(jq -r '.invite_id // .sub // empty' "${STATE_DIR}/identity.json" 2>/dev/null || true)"
[ -z "$_invite_id" ] && _invite_id="$(jq -r '.hash // empty' "${STATE_DIR}/consent.json" 2>/dev/null || true)"
[ -z "$_invite_id" ] && _invite_id="anon"

# --- TRAJETORIA (passo 1 "filme"): costura este FECHO de turno no MESMO run dos passos, dando-lhe
#     o proximo seq -> o report sabe que o turno FECHOU (run sem este marcador = travou). run_id e o
#     HASH (16 hex) do session_id; o cru NUNCA sobe. ZERO conteudo (so id opaco + contador). ---
_session_raw="$(printf '%s' "$_stdin" | jq -r '.session_id // empty' 2>/dev/null || true)"
_run_id=""
if [ -n "$_session_raw" ]; then
  if command -v shasum >/dev/null 2>&1; then
    _run_id="$(printf '%s' "$_session_raw" | shasum -a 256 2>/dev/null | cut -c1-16)"
  elif command -v sha256sum >/dev/null 2>&1; then
    _run_id="$(printf '%s' "$_session_raw" | sha256sum 2>/dev/null | cut -c1-16)"
  fi
fi
_session_raw=""
_seq="null"
if [ -n "$_run_id" ]; then
  _seq_file="${STATE_DIR}/seq-${_run_id}"
  _prev="$(cat "$_seq_file" 2>/dev/null || echo 0)"
  case "$_prev" in ''|*[!0-9]*) _prev=0 ;; esac
  _seq=$(( _prev + 1 ))
  printf '%s' "$_seq" > "$_seq_file" 2>/dev/null || _seq="null"
fi

# CONSERTO 2 (teste NRT-_998963): se a conversa fechar no meio da espera, o fim nao se perde.
# (a) provisorios de vezes anteriores que foram interrompidas entram na fila (fim="fechou_no_meio");
# (b) esta vez deixa um provisorio; ao terminar normal, ele sai e entra o definitivo.
_entrega_pend() { if cat "$1" >> "$QUEUE" 2>/dev/null; then rm -f "$1"; fi; }
# so recolhe provisorio com mais de 1 min (a espera dura no maximo ~5 s): nunca o de uma conversa
# vizinha que ainda esta esperando -> sem contar o mesmo fim duas vezes.
find "${STATE_DIR}" -maxdepth 1 -name 'fim-pendente-*.json' -mmin +1 2>/dev/null | while IFS= read -r _pf; do
  _entrega_pend "$_pf"
done
_pend="${STATE_DIR}/fim-pendente-$$-${RANDOM}.json"
jq -cn --arg invite_id "$_invite_id" --arg run_id "${_run_id:-}" --argjson seq "${_seq:-null}" \
  --arg ts "$(date -u +%FT%TZ 2>/dev/null || echo unknown)" \
  '{invite_id:$invite_id, kind:"medidor", event:"AssistantResponse", tool:"", ts:$ts,
    run_id:(if $run_id=="" then null else $run_id end), seq:$seq, ts_ms:null, err:false,
    fim:"fechou_no_meio", tentativas:0, uso:{comandos:0, tokens:0, ms:null, bytes:0}}' > "$_pend" 2>/dev/null || true
# aviso de desligar / ordem de parar: entrega o provisorio na hora (o corte seco fica pra proxima vez)
_trap_fim() { [ -s "$_pend" ] || exit 0; _entrega_pend "$_pend"; exit 0; }
trap _trap_fim HUP TERM INT
_tent_max="${NB_FIM_TENTATIVAS:-6}"; _pausa="${NB_FIM_PAUSA:-0.5}"; _tent=0; _fim="com_texto"
while :; do
  _tent=$(( _tent + 1 ))
  _resp_raw="$(_ler_fim)"
  [ -n "$_resp_raw" ] && break
  [ "$_tent" -ge "$_tent_max" ] && { _fim="sem_texto"; break; }
  sleep "$_pausa"
done

# Mede o tamanho e DESCARTA o texto (defesa em profundidade: nenhuma linha abaixo pode reusa-lo).
_chars="$(printf '%s' "$_resp_raw" | wc -c | tr -d ' ')"; [ -z "$_chars" ] && _chars=0
_resp_raw=""
_tokens_aprox=$(( _chars / 4 ))
_ts="$(date -u +%FT%TZ 2>/dev/null || echo unknown)"

# Evento SO-NUMEROS (kind:"medidor"). Sem campo `response` nem qualquer conteudo — Modelo A.
# Mesmo schema do emit (run_id/seq/ts_ms/err) pro report tratar todo evento igual; aqui err=false
# (o fecho nao e resultado de ferramenta) e ts_ms=null (o stop nao mede overhead proprio).
_line="$(jq -cn \
  --arg invite_id "$_invite_id" \
  --arg event     "AssistantResponse" \
  --arg ts        "$_ts" \
  --arg run_id    "${_run_id:-}" \
  --argjson seq   "${_seq:-null}" \
  --argjson tokens "${_tokens_aprox:-0}" \
  --argjson bytes  "${_chars:-0}" \
  --arg fim       "$_fim" \
  --argjson tent  "${_tent:-1}" \
  '{invite_id:$invite_id, kind:"medidor", event:$event, tool:"", ts:$ts,
    run_id:(if $run_id=="" then null else $run_id end), seq:$seq, ts_ms:null, err:false,
    fim:$fim, tentativas:$tent,
    uso:{comandos:0, tokens:$tokens, ms:null, bytes:$bytes}}' 2>/dev/null || true)"

[ -z "$_line" ] && exit 0
trap - HUP TERM INT
if printf '%s\n' "$_line" >> "$QUEUE" 2>/dev/null; then rm -f "$_pend"; fi
exit 0
