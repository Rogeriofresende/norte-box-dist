#!/usr/bin/env bash
# telemetry-drain.sh - Onda 2. Drena o buffer local (telemetry-queue.jsonl) pro COLETOR
# com RETRY, cursor e TTL de 7 dias. E a rede de seguranca do emit fire-and-forget:
# eventos que nao subiram (offline, servidor caido) sao reenviados na proxima drenagem.
#
# LEIS (mesmas do emit):
#   - FAIL-OPEN: exit 0 SEMPRE. Nunca trava/atrasa o trabalho (roda async nos hooks).
#   - So envia se a coleta esta LIGADA (flag telemetry.enabled) e ha URL de coletor.
#   - So https OU loopback (http://127.0.0.1 / http://localhost) - loopback nao e hop de rede,
#     entao e seguro e permite um coletor 100% local. Qualquer outra coisa -> nao envia.
#   - Cursor monotonico (telemetry-queue.cursor = nº de linhas ja confirmadas, do topo).
#     Sucesso (HTTP 200) avanca o cursor; falha NAO avanca (retenta na proxima).
#   - TTL 7d: linhas mais velhas que 7 dias sao descartadas (contam como processadas), nunca enviadas.
#   - Consome a fila como DADO, jamais executa. Nao escreve fora de $HOME/.norte-box.
#
# NRT-_1509 (fix da fila travada 2 dias): a versao antiga mandava lotes de 200 linhas
# (~1,5MB) sob --max-time 8. O tunel :8445 (Tailscale Serve) fecha idle ~10s -> o POST
# grande estourava, o cursor NAO avancava (so avanca em 200/403), e era SILENCIOSO
# (exit 0, sem log) -> travou pra sempre e ninguem viu por 2 dias. Correcao:
#   (1) lote menor (MAX_BATCH 200 -> 50) + timeout maior (--max-time 8 -> 25) -> cabe no tunel;
#   (2) LOOP interno: drena varios lotes por invocacao ate esvaziar (cap MAX_LOOPS);
#   (3) LOG do resultado em telemetry-drain.log (antes era mudo) -> da pra VER se travou;
#   (4) mais gatilhos (hooks.json: Stop alem de SessionStart) -> drena com frequencia.
# Overrides por env (fail-open): NORTE_BOX_DRAIN_MAX_BATCH, NORTE_BOX_DRAIN_MAX_TIME,
#   NORTE_BOX_DRAIN_MAX_LOOPS. Defaults abaixo.
set -u

STATE_DIR="${HOME}/.norte-box"
QUEUE="${STATE_DIR}/telemetry-queue.jsonl"
CURSOR="${STATE_DIR}/telemetry-queue.cursor"
ENABLED_FLAG="${STATE_DIR}/telemetry.enabled"
DRAIN_LOG="${STATE_DIR}/telemetry-drain.log"
# Config do cliente (endereco/senha do coletor) por arquivo local. Fail-open.
# SEGURANCA (furo #2): NAO `. .env` (= eval). Leitor de DADO: so CHAVE=valor de uma
# allowlist, valor literal, ZERO shell. Um `$(comando)` no .env NUNCA executa.
_load_norte_env() {
  local _f="$1" _line _key _val
  [ -f "$_f" ] || return 0
  while IFS= read -r _line || [ -n "$_line" ]; do
    case "$_line" in ''|'#'*) continue ;; esac
    case "$_line" in *'='*) : ;; *) continue ;; esac
    _key="${_line%%=*}"
    _val="${_line#*=}"
    case "$_val" in
      \"*\") _val="${_val#\"}"; _val="${_val%\"}" ;;
      \'*\') _val="${_val#\'}"; _val="${_val%\'}" ;;
    esac
    case "$_key" in
      NORTE_BOX_TELEMETRY_URL)    NORTE_BOX_TELEMETRY_URL="$_val" ;;
      NORTE_BOX_GOOGLE_CLIENT_ID) NORTE_BOX_GOOGLE_CLIENT_ID="$_val" ;;
      *) : ;;
    esac
  done < "$_f"
  return 0
}
_load_norte_env "$STATE_DIR/.env"
URL="${NORTE_BOX_TELEMETRY_URL:-}"
# Auth (furos #1 e #3): usa SO o token PROPRIO do convite (identity.json). SEM fallback pro token
# compartilhado — o convidado nao carrega token de dono. Sem convite validado -> sem token -> nao drena.
TOKEN=""
if command -v jq >/dev/null 2>&1; then
  TOKEN="$(jq -r '.ingest_token // empty' "$STATE_DIR/identity.json" 2>/dev/null || true)"
fi
TTL_DAYS=7
# Lote/timeout/loops dimensionados pro tunel :8445 (idle-close ~10s). Override por env.
# MAX_BATCH = teto de LINHAS por lote; MAX_BYTES = teto de BYTES do payload (o que de fato
# estoura o tunel — 1 unico PostToolUse com tool_response gigante pode ter ~900KB, entao
# cap por linha nao basta; capamos por byte e mandamos evento gigante SOZINHO).
MAX_BATCH="${NORTE_BOX_DRAIN_MAX_BATCH:-50}"
MAX_BYTES="${NORTE_BOX_DRAIN_MAX_BYTES:-700000}"
MAX_TIME="${NORTE_BOX_DRAIN_MAX_TIME:-40}"
MAX_LOOPS="${NORTE_BOX_DRAIN_MAX_LOOPS:-40}"
RETRIES=3
case "$MAX_BATCH" in (*[!0-9]*|'') MAX_BATCH=50 ;; esac
case "$MAX_BYTES" in (*[!0-9]*|'') MAX_BYTES=700000 ;; esac
case "$MAX_TIME"  in (*[!0-9]*|'') MAX_TIME=40 ;; esac
case "$MAX_LOOPS" in (*[!0-9]*|'') MAX_LOOPS=40 ;; esac

# --- LOG do resultado (fecha o buraco: antes era mudo). Bounded: mantem ultimas ~200 linhas. ---
_drain_log() {
  # $1 = mensagem curta (sem conteudo de evento, sem token). Fail-open.
  printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo '?')" "$1" >> "$DRAIN_LOG" 2>/dev/null || true
  # trunca pra nao crescer sem limite
  if [ -f "$DRAIN_LOG" ]; then
    _ln="$(wc -l < "$DRAIN_LOG" 2>/dev/null | tr -d ' ')"
    case "$_ln" in (''|*[!0-9]*) _ln=0 ;; esac
    if [ "$_ln" -gt 250 ]; then
      tail -n 200 "$DRAIN_LOG" > "$DRAIN_LOG.tmp" 2>/dev/null && mv "$DRAIN_LOG.tmp" "$DRAIN_LOG" 2>/dev/null || true
    fi
  fi
}

# --- MODO (Fase 2, fail-closed): so o compartilhavel drena. Privado NAO sobe NADA (nem uma
#     fila residual): a Norte nao ve este trabalho. 2a trava alem da ausencia de URL/token. ---
_SELF_DIR_M="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)"
if [ -n "${_SELF_DIR_M:-}" ] && [ -f "${_SELF_DIR_M}/_modo.sh" ]; then
  . "${_SELF_DIR_M}/_modo.sh"
elif [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/hooks/_modo.sh" ]; then
  . "${CLAUDE_PLUGIN_ROOT}/hooks/_modo.sh"
fi
if ! command -v _norte_pode_enviar >/dev/null 2>&1; then exit 0; fi
# PRE-CONDICAO DE ENVIO (furo MEDIO, Val): modo=compartilhavel E consent aceito na versao vigente.
# Editar modo/URL/token/flag na mao SEM aceitar o termo NAO drena. O consent e re-verificado aqui.
_norte_pode_enviar || exit 0

[ -f "$ENABLED_FLAG" ] || exit 0
[ -n "$URL" ] || exit 0
[ -n "$TOKEN" ] || exit 0   # sem token de convite -> nada a drenar (furo #3: sem fallback)
[ -f "$QUEUE" ] || exit 0
command -v jq   >/dev/null 2>&1 || exit 0
# TRANSPORTE (NRT-_990141): antes exigia curl e SAIA em silencio sem ele — mas a maquina
# ENDURECIDA do CEO tem deny-list de curl (por isso convite/consent ja usam node via nb-post.js).
# O dreno ficava mudo nessas maquinas: a fila enchia e nada subia, sem log (o furo que o teste
# de 3a-maquina expos: consent chegava por node, mas o /ingest do dreno morria no curl ausente).
# Agora: usa curl SE existir; senao cai no node (mesmo stdlib do nb-post.js). Precisa de UM dos dois.
_NB_TRANSPORT=""
if command -v curl >/dev/null 2>&1; then _NB_TRANSPORT="curl"
elif command -v node >/dev/null 2>&1; then _NB_TRANSPORT="node"
else exit 0; fi

case "$URL" in
  https://*)                      : ;;
  http://127.0.0.1*|http://localhost*) : ;;
  *) exit 0 ;;
esac

# _nb_post_code <url> <bearer> <json-body> -> ecoa SO o http_code (000 se rede falhou).
# Mesmo contrato do `curl -w '%{http_code}'`, pra a logica de cursor/200/403 nao mudar.
_nb_post_code() {
  local _u="$1" _tok="$2" _body="$3"
  if [ "$_NB_TRANSPORT" = "curl" ]; then
    curl -sS --max-time "$MAX_TIME" -o /dev/null -w '%{http_code}' \
      -X POST -H 'Content-Type: application/json' \
      -H "Authorization: Bearer ${_tok}" \
      --data-binary "$_body" "$_u" 2>/dev/null || echo 000
  else
    # node stdlib (http/https), sem dependencia: imprime SO o status. Corpo por STDIN (nao expoe
    # o token/URL na linha de comando; o token vai por env pro processo filho, some ao sair).
    printf '%s' "$_body" | NB_URL="$_u" NB_TOK="$_tok" NB_TMO="$MAX_TIME" node -e '
      const lib=require((process.env.NB_URL||"").startsWith("http://")?"http":"https");
      let b="";process.stdin.on("data",d=>b+=d);process.stdin.on("end",()=>{
        const data=Buffer.from(b||"{}");
        const req=lib.request(process.env.NB_URL,{method:"POST",headers:{
          "Content-Type":"application/json","Content-Length":data.length,
          "Authorization":"Bearer "+process.env.NB_TOK},
          timeout:(parseInt(process.env.NB_TMO,10)||40)*1000},res=>{
          process.stdout.write(String(res.statusCode||"000"));res.resume();res.on("end",()=>process.exit(0));});
        req.on("error",()=>{process.stdout.write("000");process.exit(0);});
        req.on("timeout",()=>{req.destroy();process.stdout.write("000");process.exit(0);});
        req.write(data);req.end();
      });' 2>/dev/null || echo 000
  fi
}

NOW="$(date -u +%s 2>/dev/null || echo 0)"
CUTOFF=$(( NOW - TTL_DAYS * 86400 ))

# --- Envia UM lote a partir do cursor atual. Ecoa: "SENT n" | "TTL n" | "FAIL code" | "IDLE" ---
_send_one_batch() {
  local TOTAL CUR PENDING_RAW COUNT_PENDING ARR NSEND ok drop i CODE
  TOTAL="$(wc -l < "$QUEUE" 2>/dev/null | tr -d ' ')"; [ -z "$TOTAL" ] && TOTAL=0
  CUR=0; [ -f "$CURSOR" ] && CUR="$(cat "$CURSOR" 2>/dev/null | tr -d ' ')"
  case "$CUR" in (*[!0-9]*|'') CUR=0 ;; esac
  # fila rotacionou/encolheu (cursor > total) -> reseta
  [ "$CUR" -gt "$TOTAL" ] && CUR=0
  [ "$CUR" -ge "$TOTAL" ] && { echo "IDLE"; return 0; }

  # janela de pendentes (apos o cursor): ate MAX_BATCH linhas E ate MAX_BYTES bytes.
  # awk acumula bytes e para ao estourar o teto de bytes OU de linhas — mas SEMPRE emite
  # ao menos 1 linha (evento gigante vai sozinho). Assim nenhum POST passa de ~MAX_BYTES.
  PENDING_RAW="$(tail -n +"$((CUR + 1))" "$QUEUE" 2>/dev/null \
    | awk -v maxb="$MAX_BYTES" -v maxl="$MAX_BATCH" '
        { n=length($0)+1;
          if (nl>0 && (bytes+n>maxb || nl>=maxl)) exit;
          print; bytes+=n; nl++ }')"
  COUNT_PENDING="$(printf '%s\n' "$PENDING_RAW" | grep -c '[^[:space:]]')"
  [ "${COUNT_PENDING:-0}" -eq 0 ] && { echo "IDLE"; return 0; }

  # monta o array das linhas validas (objeto) e nao-expiradas (ts >= cutoff).
  # linha sem ts -> mantem (fail-open). Se o jq com TTL falhar, cai no fallback sem TTL.
  ARR="$(printf '%s\n' "$PENDING_RAW" \
    | jq -c "select(type==\"object\") | select(((.ts // \"\") | if .==\"\" then $NOW else (try fromdateiso8601 catch $NOW) end) >= $CUTOFF)" 2>/dev/null \
    | jq -s -c '.' 2>/dev/null)"
  case "$ARR" in
    '['*']') : ;;
    *) ARR="$(printf '%s\n' "$PENDING_RAW" | jq -c 'select(type=="object")' 2>/dev/null | jq -s -c '.' 2>/dev/null)" ;;
  esac
  case "$ARR" in '['*']') : ;; *) echo "FAIL badjson"; return 1 ;; esac   # invalido -> desiste (nao perde dado)

  NSEND="$(printf '%s' "$ARR" | jq 'length' 2>/dev/null)"; case "$NSEND" in (*[!0-9]*|'') NSEND=0 ;; esac

  if [ "$NSEND" -gt 0 ]; then
    ok=0; drop=0; i=0; CODE=000
    while [ "$i" -lt "$RETRIES" ]; do
      CODE="$(_nb_post_code "$URL" "$TOKEN" "$ARR")"
      [ "$CODE" = "200" ] && { ok=1; break; }
      # 403 = convite revogado: o servidor recusa pra sempre -> nao adianta retentar (avanca o cursor).
      [ "$CODE" = "403" ] && { drop=1; break; }
      i=$((i + 1)); sleep "$i"
    done
    # falha transitoria (rede/servidor) -> cursor NAO avanca, tenta na proxima.
    if [ "$ok" != "1" ] && [ "$drop" != "1" ]; then
      echo "FAIL $CODE"
      return 1
    fi
    # sucesso (200) avanca; 403 avanca (descarta o que o servidor recusa pra sempre)
    printf '%s' "$(( CUR + COUNT_PENDING ))" > "$CURSOR" 2>/dev/null || true
    if [ "$ok" = "1" ]; then echo "SENT $COUNT_PENDING"; else echo "DROP403 $COUNT_PENDING"; fi
    return 0
  fi

  # nada valido a enviar por TTL: avanca o cursor por TODAS as pendentes deste lote
  printf '%s' "$(( CUR + COUNT_PENDING ))" > "$CURSOR" 2>/dev/null || true
  echo "TTL $COUNT_PENDING"
  return 0
}

# --- LOOP: drena varios lotes ate esvaziar (ou ate MAX_LOOPS / falha transitoria) ---
_start_cur="$(cat "$CURSOR" 2>/dev/null | tr -d ' ')"; case "$_start_cur" in (*[!0-9]*|'') _start_cur=0 ;; esac
_sent_total=0; _loops=0; _last=""; _fail=""
while [ "$_loops" -lt "$MAX_LOOPS" ]; do
  _last="$(_send_one_batch)"
  _loops=$(( _loops + 1 ))
  case "$_last" in
    IDLE) break ;;                                  # fila vazia -> pronto
    "SENT "*|"DROP403 "*|"TTL "*)
      _n="${_last##* }"; case "$_n" in (*[!0-9]*|'') _n=0 ;; esac
      _sent_total=$(( _sent_total + _n ))
      ;;
    "FAIL "*) _fail="$_last"; break ;;              # falha transitoria -> para, tenta na proxima invocacao
    *) _fail="$_last"; break ;;
  esac
done
_end_cur="$(cat "$CURSOR" 2>/dev/null | tr -d ' ')"; case "$_end_cur" in (*[!0-9]*|'') _end_cur=0 ;; esac
_total="$(wc -l < "$QUEUE" 2>/dev/null | tr -d ' ')"; case "$_total" in (*[!0-9]*|'') _total=0 ;; esac
_remain=$(( _total - _end_cur )); [ "$_remain" -lt 0 ] && _remain=0

if [ -n "$_fail" ]; then
  _drain_log "drain: processado=${_sent_total} cursor=${_start_cur}->${_end_cur} restam=${_remain} loops=${_loops} STATUS=${_fail}"
elif [ "$_sent_total" -gt 0 ] || [ "$_end_cur" != "$_start_cur" ]; then
  _drain_log "drain: processado=${_sent_total} cursor=${_start_cur}->${_end_cur} restam=${_remain} loops=${_loops} STATUS=OK"
fi
# silencio no log quando nada mudou (fila vazia) — evita ruido.
exit 0
