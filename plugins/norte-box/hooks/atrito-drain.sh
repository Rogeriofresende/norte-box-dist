#!/usr/bin/env bash
# atrito-drain.sh — FASE 2 do PACOTE DE ATRITO (NRT-_990210): drena a fila LOCAL de atrito
# (atrito-queue.jsonl) pro COLETOR, SO-ROTULOS. Espelha o telemetry-drain.sh (mesma rede de
# seguranca: gate modo+consent fail-closed, token proprio do convite, https/loopback, TTL 7d,
# cursor monotonico, retry) — mas com fila/cursor/log/kill-switch PROPRIOS e uma trava a mais:
#
#   PROJECAO SO-ROTULO ANTES DE SAIR (defesa em profundidade / Val): cada linha e RECONSTRUIDA
#   pelo jq mantendo APENAS { atrito:{cmd?,travas?,erro?}, ts, kind:"atrito", invite_id } — o
#   whitelist de rotulos. Qualquer campo estranho (prompt/tool_input/command/query/stderr/…),
#   se por acidente aparecesse na fila, e DESCARTADO antes do POST. O grep=0 vale no que SAI da
#   maquina, nao so no que foi gravado. Linha sem forma de atrito valida -> descartada (nao sobe).
#   ALEM DA FORMA, valida o CONTEUDO (furo fase 2 / Val): cmd/travas casam a allowlist FECHADA de
#   _atrito.sh (fonte unica) e ts casa ISO-8601 — assim nao da pra esconder CPF/nome/secret DENTRO
#   de um campo whitelistado adulterando a fila local. Valor fora da allowlist -> descartado.
#
# LEIS (iguais ao medidor):
#   - FAIL-OPEN pro trabalho: exit 0 SEMPRE (roda async nos hooks; nunca trava/atrasa a pessoa).
#   - FAIL-CLOSED pro envio: modo=compartilhavel E consent aceito na versao vigente (_norte_pode_enviar).
#     Modo privado NAO sobe NADA. Editar disco na mao sem aceitar o termo NAO drena.
#   - KILL-SWITCH proprio do ENVIO: NORTE_ATRITO_SEND_OFF=1 -> nao drena (a fila local segue,
#     a captura fase 1 segue; so o envio para). Independente do NORTE_ATRITO_OFF (captura).
#   - So https OU loopback (127.0.0.1/localhost). Qualquer outra coisa -> nao envia.
#   - Cursor monotonico proprio (atrito-queue.cursor). 200 avanca; falha transitoria NAO avanca.
#   - TTL 7d: linhas > 7 dias contam como processadas, nunca sobem.
#   - Le a fila como DADO, jamais executa. Nao escreve fora de $HOME/.norte-box.
#   - ADITIVO: NAO toca a fila/cursor do medidor. Fila/cursor/log proprios.
# Portabilidade macOS bash 3.2.
set -u

# --- KILL-SWITCH proprio do ENVIO (fail-open pro trabalho) ---
[ "${NORTE_ATRITO_SEND_OFF:-0}" = "1" ] && exit 0

STATE_DIR="${HOME}/.norte-box"
QUEUE="${STATE_DIR}/atrito-queue.jsonl"
CURSOR="${STATE_DIR}/atrito-queue.cursor"
ENABLED_FLAG="${STATE_DIR}/telemetry.enabled"
DRAIN_LOG="${STATE_DIR}/atrito-drain.log"

# --- Config do cliente (endereco do coletor) por arquivo local, MESMA fonte do medidor.
#     SEGURANCA: NAO `. .env` (=eval). Leitor de DADO: so CHAVE=valor de uma allowlist, ZERO shell. ---
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
      NORTE_BOX_TELEMETRY_URL) NORTE_BOX_TELEMETRY_URL="$_val" ;;
      *) : ;;
    esac
  done < "$_f"
  return 0
}
_load_norte_env "$STATE_DIR/.env"
URL="${NORTE_BOX_TELEMETRY_URL:-}"

# Auth: SO o token PROPRIO do convite (identity.json). Sem fallback pro token do dono.
TOKEN=""
if command -v jq >/dev/null 2>&1; then
  TOKEN="$(jq -r '.ingest_token // empty' "${STATE_DIR}/identity.json" 2>/dev/null || true)"
fi
# invite_id opaco pra carimbar (o servidor tambem carimba pelo token; mandamos o mesmo opaco do medidor).
INVITE_ID=""
if command -v jq >/dev/null 2>&1; then
  INVITE_ID="$(jq -r '.invite_id // .sub // empty' "${STATE_DIR}/identity.json" 2>/dev/null || true)"
  [ -z "$INVITE_ID" ] && INVITE_ID="$(jq -r '.hash // empty' "${STATE_DIR}/consent.json" 2>/dev/null || true)"
  [ -z "$INVITE_ID" ] && INVITE_ID="anon"
fi

TTL_DAYS=7
MAX_BATCH="${NORTE_ATRITO_DRAIN_MAX_BATCH:-100}"
MAX_TIME="${NORTE_ATRITO_DRAIN_MAX_TIME:-25}"
MAX_LOOPS="${NORTE_ATRITO_DRAIN_MAX_LOOPS:-20}"
RETRIES=3
case "$MAX_BATCH" in (*[!0-9]*|'') MAX_BATCH=100 ;; esac
case "$MAX_TIME"  in (*[!0-9]*|'') MAX_TIME=25 ;; esac
case "$MAX_LOOPS" in (*[!0-9]*|'') MAX_LOOPS=20 ;; esac

_drain_log() {
  printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo '?')" "$1" >> "$DRAIN_LOG" 2>/dev/null || true
  if [ -f "$DRAIN_LOG" ]; then
    _ln="$(wc -l < "$DRAIN_LOG" 2>/dev/null | tr -d ' ')"
    case "$_ln" in (''|*[!0-9]*) _ln=0 ;; esac
    if [ "$_ln" -gt 250 ]; then
      tail -n 200 "$DRAIN_LOG" > "$DRAIN_LOG.tmp" 2>/dev/null && mv "$DRAIN_LOG.tmp" "$DRAIN_LOG" 2>/dev/null || true
    fi
  fi
}

# --- MODO (fail-closed): so compartilhavel + consent aceito na versao vigente drena. ---
_SELF_DIR_M="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)"
if [ -n "${_SELF_DIR_M:-}" ] && [ -f "${_SELF_DIR_M}/_modo.sh" ]; then
  . "${_SELF_DIR_M}/_modo.sh"
elif [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/hooks/_modo.sh" ]; then
  . "${CLAUDE_PLUGIN_ROOT}/hooks/_modo.sh"
fi

# --- ALLOWLIST (fail-closed do CONTEUDO): carrega _atrito.sh (FONTE UNICA das allowlists
#     _NB_ATRITO_CMD_ALLOW + _NB_ATRITO_GATE_ALLOW). A projecao valida o VALOR de cada rotulo
#     contra a MESMA allowlist da captura — nao duplica a lista aqui. Se o _atrito.sh sumir,
#     as allowlists ficam vazias -> a projecao descarta TODO cmd/trava (fail-CLOSED do conteudo). ---
if [ -n "${_SELF_DIR_M:-}" ] && [ -f "${_SELF_DIR_M}/_atrito.sh" ]; then
  . "${_SELF_DIR_M}/_atrito.sh"
elif [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/hooks/_atrito.sh" ]; then
  . "${CLAUDE_PLUGIN_ROOT}/hooks/_atrito.sh"
fi
# Espaco-cercadas (" a b c "). A da trava inclui o sentinela "outro-gate" (colapso legitimo do
# _atrito_gate_rotulo). Vazias se _atrito.sh nao carregou -> nada de cmd/trava sobrevive.
_CMD_ALLOW="${_NB_ATRITO_CMD_ALLOW:-  }"
_GATE_ALLOW="${_NB_ATRITO_GATE_ALLOW:-  } outro-gate "
command -v _norte_pode_enviar >/dev/null 2>&1 || exit 0   # sem leitor de modo -> fail-CLOSED
_norte_pode_enviar || exit 0

[ -f "$ENABLED_FLAG" ] || exit 0
[ -n "$URL" ]   || exit 0
[ -n "$TOKEN" ] || exit 0
[ -f "$QUEUE" ] || exit 0
command -v jq   >/dev/null 2>&1 || exit 0
command -v curl >/dev/null 2>&1 || exit 0

case "$URL" in
  https://*)                           : ;;
  http://127.0.0.1*|http://localhost*) : ;;
  *) exit 0 ;;
esac

NOW="$(date -u +%s 2>/dev/null || echo 0)"
CUTOFF=$(( NOW - TTL_DAYS * 86400 ))

# --- PROJETOR SO-ROTULO (a trava nova): reconstroi cada linha mantendo APENAS o whitelist.
#     Descarta qualquer campo estranho. Linha sem forma de atrito valida -> vira "" (some).
#     invite_id carimbado aqui; kind forcado "atrito". Nada de conteudo sobrevive. ---
_projetar_rotulos() {
  # stdin: linhas jsonl cruas da fila. stdout: array jq [{atrito:{...}, ts, kind, invite_id}, ...]
  # so com os campos do whitelist, ja filtrado por TTL. Falha -> "" (o chamador trata).
  #
  # DEFESA DE CONTEUDO (Val, furo da fase 2): filtrar por FORMA nao basta — um cmd/trava/ts
  # string qualquer passava verbatim, dando pra esconder CPF/nome/secret DENTRO do proprio campo
  # whitelistado. Aqui cada VALOR e casado contra a allowlist FECHADA de _atrito.sh (fonte unica):
  #   - cmd:    so sobrevive se o verbo ∈ _CMD_ALLOW (~17 verbos [a-z-]); fora -> ausente.
  #   - travas: cada entrada so sobrevive se ∈ _GATE_ALLOW ({secret-guard,consent-gate,
  #             confirmar-antes,outro-gate}); fora -> descartada.
  #   - ts:     so sobrevive se casar ISO-8601 (^\d{4}-\d{2}-\d{2}T...Z$); senao -> "".
  # A pertinencia no jq espelha o `*" $x "*` do bash: contains(" \(x) ") na allowlist espaco-cercada
  # (contains, NAO index — index em string retorna 0 na posicao-0 e confunde o "!= null").
  jq -c --arg iid "$INVITE_ID" --argjson cutoff "$CUTOFF" --argjson now "$NOW" \
        --arg cmd_allow "$_CMD_ALLOW" --arg gate_allow "$_GATE_ALLOW" '
    select(type=="object")
    # TTL: linha mais velha que o cutoff -> descarta (nao sobe). Sem ts -> mantem (fail-open).
    | select( ((.ts // "") | if .=="" then $now else (try fromdateiso8601 catch $now) end) >= $cutoff )
    # PROJECAO: reconstroi so o whitelist E valida o CONTEUDO contra a allowlist fechada.
    | ( .atrito // {} ) as $a
    | { atrito: (
          # cmd: string E na allowlist de verbos (igualdade exata via cerca de espaco). Fora -> ausente.
          # contains (nao index): substring seguro, sem o pega-position-0. $a.cmd e VARIAVEL (nao .).
          ( if ($a.cmd | type)=="string" and ($cmd_allow | contains(" " + $a.cmd + " "))
              then {cmd: $a.cmd} else {} end )
          # travas: array; cada entrada string E na allowlist de gates. As de fora somem (map+select).
          # CADA entrada bindada em $e ANTES do pipe: senao o "." dentro de contains reaponta pro
          # $gate_allow (o input do pipe), nao pro elemento -> tudo cairia (bug de precedencia jq).
        + ( if ($a.travas | type)=="array"
              then ( ($a.travas
                       | map(select(type=="string"))
                       | map(. as $e | select($gate_allow | contains(" " + $e + " ")))) as $tv
                     | if ($tv | length) > 0 then {travas: $tv} else {} end )
              else {} end )
          # erro: bit puro, sem conteudo -> passa como esta.
        + ( if ($a.erro == true) then {erro: true} else {} end )
      ),
      # ts: so ISO-8601 estrito (data T hora Z). Qualquer outra coisa -> "" (nada de texto livre).
      ts:        (.ts // "" | if (type=="string" and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]+)?Z$")) then . else "" end),
      kind:      "atrito",
      invite_id: $iid }
    # so sobe se sobrou ALGUM rotulo (senao e ruido vazio)
    | select( (.atrito | length) > 0 )
  ' 2>/dev/null | jq -s -c '.' 2>/dev/null
}

# --- Envia UM lote a partir do cursor. Ecoa: "SENT n" | "FAIL code" | "IDLE" | "SKIP n". ---
_send_one_batch() {
  local TOTAL CUR PENDING_RAW COUNT_PENDING ARR NSEND ok drop i CODE
  TOTAL="$(wc -l < "$QUEUE" 2>/dev/null | tr -d ' ')"; [ -z "$TOTAL" ] && TOTAL=0
  CUR=0; [ -f "$CURSOR" ] && CUR="$(cat "$CURSOR" 2>/dev/null | tr -d ' ')"
  case "$CUR" in (*[!0-9]*|'') CUR=0 ;; esac
  [ "$CUR" -gt "$TOTAL" ] && CUR=0
  [ "$CUR" -ge "$TOTAL" ] && { echo "IDLE"; return 0; }

  PENDING_RAW="$(tail -n +"$((CUR + 1))" "$QUEUE" 2>/dev/null | head -n "$MAX_BATCH")"
  COUNT_PENDING="$(printf '%s\n' "$PENDING_RAW" | grep -c '[^[:space:]]')"
  [ "${COUNT_PENDING:-0}" -eq 0 ] && { echo "IDLE"; return 0; }

  # PROJETA so-rotulo (a trava): o que vai na rede e RECONSTRUIDO do whitelist, nunca a linha crua.
  ARR="$(printf '%s\n' "$PENDING_RAW" | _projetar_rotulos)"
  case "$ARR" in '['*']') : ;; *) echo "FAIL badjson"; return 1 ;; esac

  NSEND="$(printf '%s' "$ARR" | jq 'length' 2>/dev/null)"; case "$NSEND" in (*[!0-9]*|'') NSEND=0 ;; esac

  if [ "$NSEND" -gt 0 ]; then
    ok=0; drop=0; i=0; CODE=000
    while [ "$i" -lt "$RETRIES" ]; do
      CODE="$(curl -sS --max-time "$MAX_TIME" -o /dev/null -w '%{http_code}' \
        -X POST -H 'Content-Type: application/json' \
        -H "Authorization: Bearer ${TOKEN}" \
        --data-binary "$ARR" "$URL" 2>/dev/null || echo 000)"
      [ "$CODE" = "200" ] && { ok=1; break; }
      [ "$CODE" = "403" ] && { drop=1; break; }   # convite revogado: nao adianta retentar
      i=$((i + 1)); sleep "$i"
    done
    if [ "$ok" != "1" ] && [ "$drop" != "1" ]; then
      echo "FAIL $CODE"; return 1
    fi
    printf '%s' "$(( CUR + COUNT_PENDING ))" > "$CURSOR" 2>/dev/null || true
    if [ "$ok" = "1" ]; then echo "SENT $COUNT_PENDING"; else echo "DROP403 $COUNT_PENDING"; fi
    return 0
  fi

  # nada valido a enviar neste lote (so TTL/ruido) -> avanca o cursor por todas as pendentes.
  printf '%s' "$(( CUR + COUNT_PENDING ))" > "$CURSOR" 2>/dev/null || true
  echo "SKIP $COUNT_PENDING"
  return 0
}

# --- LOOP: drena varios lotes ate esvaziar (ou MAX_LOOPS / falha transitoria) ---
_start_cur="$(cat "$CURSOR" 2>/dev/null | tr -d ' ')"; case "$_start_cur" in (*[!0-9]*|'') _start_cur=0 ;; esac
_sent_total=0; _loops=0; _last=""; _fail=""
while [ "$_loops" -lt "$MAX_LOOPS" ]; do
  _last="$(_send_one_batch)"
  _loops=$(( _loops + 1 ))
  case "$_last" in
    IDLE) break ;;
    "SENT "*|"DROP403 "*|"SKIP "*)
      _n="${_last##* }"; case "$_n" in (*[!0-9]*|'') _n=0 ;; esac
      _sent_total=$(( _sent_total + _n ))
      ;;
    "FAIL "*) _fail="$_last"; break ;;
    *) _fail="$_last"; break ;;
  esac
done
_end_cur="$(cat "$CURSOR" 2>/dev/null | tr -d ' ')"; case "$_end_cur" in (*[!0-9]*|'') _end_cur=0 ;; esac
_total="$(wc -l < "$QUEUE" 2>/dev/null | tr -d ' ')"; case "$_total" in (*[!0-9]*|'') _total=0 ;; esac
_remain=$(( _total - _end_cur )); [ "$_remain" -lt 0 ] && _remain=0

if [ -n "$_fail" ]; then
  _drain_log "atrito-drain: processado=${_sent_total} cursor=${_start_cur}->${_end_cur} restam=${_remain} loops=${_loops} STATUS=${_fail}"
elif [ "$_sent_total" -gt 0 ] || [ "$_end_cur" != "$_start_cur" ]; then
  _drain_log "atrito-drain: processado=${_sent_total} cursor=${_start_cur}->${_end_cur} restam=${_remain} loops=${_loops} STATUS=OK"
fi
exit 0
