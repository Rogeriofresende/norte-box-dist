#!/usr/bin/env bash
# telemetry-emit.sh - UserPromptSubmit/PostToolUse hook do norte-box (o MEDIDOR).
# Enfileira 1 evento de USO em $HOME/.norte-box/telemetry-queue.jsonl (buffer local) e
# tenta um flush ASSINCRONO fire-and-forget (HTTPS) pro endpoint da var NORTE_BOX_TELEMETRY_URL.
#
# ===================================================================================
# MODELO A (decisao do CEO, ADOTADO): NUMEROS POR PADRAO. O fluxo AUTOMATICO manda SO o
# MEDIDOR (pedidos, tokens aprox, tempo, espaco, contagem de comandos) — ZERO CONTEUDO.
# NUNCA vai automatico: o que voce digita, a resposta da IA, nome/caminho de arquivo, diffs.
# A Norte NAO VE o seu trabalho por padrao. O conteudo so sai por opt-in EXPLICITO, sessao a
# sessao, com previa (comando /norte-box:compartilhar) — um caminho SEPARADO deste hook.
#
# Este hook LE o prompt/tool_input/tool_response so pra CONTAR o tamanho (chars/4 ~= tokens),
# e IMEDIATAMENTE DESCARTA o texto. O conteudo NUNCA entra na linha da fila nem no POST. A
# unica coisa que sobe e {uso:{comandos,tokens,ms,bytes}} + metadados nao-sensiveis (event,
# tool_name, ts, invite_id opaco). Desacoplar a captura de conteudo do fluxo automatico e o
# ponto INTEIRO deste modelo (project_norte_box_telemetria_parece_malware).
# ===================================================================================
#
# STUB desta rodada: se NORTE_BOX_TELEMETRY_URL vazia -> so enfileira e sai (o COLETOR no
# servidor e um passo de deploy A PARTE, ver docs/TELEMETRIA.md).
#
# LEIS (SPEC secao 0):
#   - FAIL-OPEN: exit 0 SEMPRE. Qualquer erro interno/rede/parse -> deixa passar, nunca trava o trabalho.
#   - NUMEROS POR PADRAO (nao-negociavel): o evento automatico NAO carrega NENHUM campo de
#     conteudo. O texto e lido so pra medir o tamanho e descartado no mesmo passo.
#   - Consome stdin como DADO, NUNCA executa input. NAO escreve fora de $HOME/.norte-box.
#   - Respeita o desligamento: telemetry off (ausencia de telemetry.enabled) -> nao emite.
#   - Portabilidade macOS: bash 3.2. NAO usa EPOCHREALTIME. Tempo por metodo portatil.
set -u

STATE_DIR="${HOME}/.norte-box"
QUEUE="${STATE_DIR}/telemetry-queue.jsonl"
ENABLED_FLAG="${STATE_DIR}/telemetry.enabled"

# Config do cliente (endereco/senha do coletor) por arquivo local, pra nao depender do
# shell profile. Fail-open: se o arquivo faltar/estiver ruim, segue sem ele.
#
# SEGURANCA (furo #2): NAO fazemos `. .env` (sourcing = eval; um `$(comando)` dentro do
# arquivo executaria na maquina do cliente). Lemos como DADO: so linhas CHAVE=valor de uma
# ALLOWLIST de chaves conhecidas, valor literal, ZERO interpretacao de shell.
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

# Marca o inicio o mais cedo possivel (mede o overhead do proprio emit, fire-and-forget).
# Metodo portatil: perl Time::HiRes (ms) se existir, senao date +%s (segundos), senao vazio.
_now_ms() {
  if command -v perl >/dev/null 2>&1; then
    perl -MTime::HiRes=time -e 'printf "%d", time()*1000' 2>/dev/null && return 0
  fi
  date +%s 2>/dev/null && return 0
  return 1
}
_t_start="$(_now_ms 2>/dev/null || true)"

# Consome stdin sempre (evita SIGPIPE). E DADO, jamais comando.
_stdin="$(cat 2>/dev/null || true)"

# --- MODO (Fase 2, fail-closed): so o modo compartilhavel coleta O MEDIDOR. Privado NAO
#     enfileira nem envia nada (a Norte nao ve este trabalho — nem os numeros). Cinto+suspensorio:
#     alem da AUSENCIA de URL/token no disco (no privado o instalador nao grava), este gate recusa
#     mesmo se um residuo escapar. Compartilhavel = so os NUMEROS sobem (Modelo A). ---
_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)"
if [ -n "${_SELF_DIR:-}" ] && [ -f "${_SELF_DIR}/_modo.sh" ]; then
  . "${_SELF_DIR}/_modo.sh"
elif [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/hooks/_modo.sh" ]; then
  . "${CLAUDE_PLUGIN_ROOT}/hooks/_modo.sh"
fi
# Sem o leitor de modo carregado -> fail-CLOSED (trata como privado, nao emite).
if ! command -v _norte_pode_enviar >/dev/null 2>&1; then
  exit 0
fi
# PRE-CONDICAO DE ENVIO (furo MEDIO, Val): modo=compartilhavel E consent aceito na versao vigente.
# Editar modo/URL/token/flag na mao SEM aceitar o termo NAO abre o envio (o consent e re-verificado
# aqui, nao so no comando /norte-box:modo). Fail-closed: qualquer duvida -> nao emite.
_norte_pode_enviar || exit 0

# --- Desligamento: telemetry off = sem flag = nao emite (o trabalho segue normal) ---
if [ ! -f "$ENABLED_FLAG" ]; then
  exit 0
fi

# Sem jq nao da pra montar JSON com seguranca -> fail-open (nao emite).
command -v jq >/dev/null 2>&1 || exit 0

mkdir -p "$STATE_DIR" 2>/dev/null || exit 0

# --- Detecta o evento pelo campo PRESENTE (nao confia so em hook_event_name) ---
# UserPromptSubmit tem .prompt; PostToolUse tem .tool_name/.tool_input/.tool_response.
# ATENCAO (Modelo A): estes _*_raw sao usados SO pra MEDIR o tamanho. O texto e descartado
# logo abaixo — nunca vai pra fila nem pro POST. Nao redigimos porque nao guardamos: o
# conteudo nao sai daqui, entao nao ha campo de conteudo pra vazar.
_prompt_raw="$(printf '%s' "$_stdin"        | jq -r '.prompt // empty' 2>/dev/null || true)"
_tool="$(printf '%s' "$_stdin"              | jq -r '.tool_name // empty' 2>/dev/null || true)"
_tool_input_raw="$(printf '%s' "$_stdin"    | jq -c '.tool_input // empty' 2>/dev/null || true)"
_tool_response_raw="$(printf '%s' "$_stdin" | jq -c '.tool_response // empty' 2>/dev/null || true)"
_event_name="$(printf '%s' "$_stdin"        | jq -r '.hook_event_name // empty' 2>/dev/null || true)"

if [ -n "$_prompt_raw" ]; then
  _event="UserPromptSubmit"
elif [ -n "$_tool" ] || [ -n "$_tool_input_raw" ] || [ -n "$_tool_response_raw" ]; then
  _event="PostToolUse"
elif [ -n "$_event_name" ]; then
  _event="$_event_name"
else
  # Nada reconhecivel -> fail-open (nao ha trabalho pra medir).
  exit 0
fi

# --- COLAPSO DO NOME DA FERRAMENTA (furo LGPD, Val) ------------------------------------------
# O `tool_name` cru pode carregar STRING NOMEADA POR CLIENTE. Um tool MCP e nomeado
# `mcp__<servidor>__<funcao>` — ex `mcp__clinica-dr-joao__buscar_prontuario` vaza o nome do
# cliente + a natureza do trabalho (prontuario). Modelo A = SO NUMEROS: o payload NUNCA pode
# carregar nome escolhido por terceiro. Entao colapsamos:
#   - qualquer coisa que comece com `mcp__`            -> "mcp"
#   - um nome CORE conhecido (allowlist abaixo)        -> passa VERBATIM (Read/Edit/Bash/...)
#   - QUALQUER outra coisa (tool novo, custom, vazio)  -> "outro"
# Assim so sobem rotulos GENERICOS de tipo-de-acao — nunca uma string por cliente. Fail-safe:
# na duvida, colapsa (default "outro"). Allowlist casada por igualdade EXATA (nao substring).
#
# RITUAL DE ENTRADA (NRT-_990500 · ideacao Fable+Gemini, Codex juiz): um nome so entra aqui com
# PROVA de que e LITERAL da harness (fixo pelo Claude Code, nunca escolhido por cliente) E tem uso
# real observado. Nome por SUPOSICAO nao entra — fica "outro" de proposito (errar pra MENOS >
# vazar). Os tipos de acao Skill/Agent/ToolSearch/AskUserQuestion e a familia Task* (TaskCreate/
# Update/List/Stop) sao rotulos GENERICOS fixos: o QUAL (skill, subagent_type, titulo) vive no
# tool_input, que e MEDIDO e DESCARTADO, nunca vira rotulo. "Task" (harness antigo) e "Agent"
# (harness novo) coexistem de proposito. ListMcpResourcesTool/ReadMcpResourceTool = correcao de
# DRIFT (a harness renomeou *Resources -> *ResourcesTool; mantemos os dois pares).
_NB_TOOL_ALLOW=" Read Edit MultiEdit Write NotebookEdit Bash BashOutput KillShell Glob Grep Task Agent Skill ToolSearch AskUserQuestion TaskCreate TaskUpdate TaskList TaskStop WebFetch WebSearch TodoWrite ExitPlanMode ListMcpResources ReadMcpResource ListMcpResourcesTool ReadMcpResourceTool "
_nb_collapse_tool() {
  # $1 = nome cru da ferramenta. Ecoa o rotulo generico seguro.
  case "$1" in
    mcp__*)  printf 'mcp' ;;                       # qualquer MCP -> "mcp" (nunca o nome do servidor)
    '')      printf 'outro' ;;                     # sem nome (ex UserPromptSubmit) -> generico
    *)
      case "$_NB_TOOL_ALLOW" in
        *" $1 "*) printf '%s' "$1" ;;              # core conhecido -> verbatim
        *)        printf 'outro' ;;                # desconhecido/custom -> "outro"
      esac
      ;;
  esac
}
_tool_safe="$(_nb_collapse_tool "${_tool:-}")"

# --- COLAPSO DO NOME DO EVENTO (defesa em profundidade) --------------------------------------
# `event` vem do tipo do hook (fixo pela harness: UserPromptSubmit/PostToolUse/...), nao e
# escolhido por cliente. Ainda assim colapsamos por allowlist EXATA: um valor fora da lista
# vira "outro" — o payload nunca carrega uma string arbitraria vinda do stdin.
_NB_EVENT_ALLOW=" UserPromptSubmit PostToolUse PreToolUse Stop SubagentStop SessionStart SessionEnd Notification PreCompact AssistantResponse "
case "$_NB_EVENT_ALLOW" in
  *" $_event "*) : ;;          # evento conhecido -> mantem
  *) _event="outro" ;;         # qualquer coisa fora da lista -> generico
esac

# invite_id: id opaco da pessoa (nunca token). Le do consent/identity local se houver.
_invite_id="$(jq -r '.invite_id // .sub // empty' "${STATE_DIR}/identity.json" 2>/dev/null || true)"
[ -z "$_invite_id" ] && _invite_id="$(jq -r '.hash // empty' "${STATE_DIR}/consent.json" 2>/dev/null || true)"
[ -z "$_invite_id" ] && _invite_id="anon"

# --- CUSTO REAL: tokens ~= chars/4 do TAMANHO do trabalho. So MEDIMOS o conteudo; nao o gravamos. ---
# UserPromptSubmit -> tamanho do prompt; PostToolUse -> tamanho do tool_input + tool_response.
# O texto sai de escopo (variaveis locais descartadas) sem nunca entrar na linha da fila.
if [ "$_event" = "UserPromptSubmit" ]; then
  _content="$_prompt_raw"
else
  _content="${_tool_input_raw}${_tool_response_raw}"
fi
_chars="$(printf '%s' "$_content" | wc -c | tr -d ' ')"
[ -z "$_chars" ] && _chars=0
_tokens_aprox=$(( _chars / 4 ))
# Descarta o texto EXPLICITAMENTE assim que o tamanho foi medido (defesa em profundidade:
# garante que nenhuma linha abaixo possa reaproveitar o conteudo por engano).
_content=""; _prompt_raw=""; _tool_input_raw=""; _tool_response_raw=""
# O nome CRU da ferramenta ja foi colapsado em _tool_safe; descarta o cru (pode ser um MCP
# nomeado por cliente) pra nenhuma linha abaixo poder reaproveita-lo por engano.
_tool=""

_ts="$(date -u +%FT%TZ 2>/dev/null || echo unknown)"

# --- Tempo (overhead do emit) por metodo PORTATIL. NUNCA um valor fake. ---
# Se nao conseguimos medir (sem perl/date), OMITIMOS o campo (ms=null).
_t_end="$(_now_ms 2>/dev/null || true)"
if [ -n "$_t_start" ] && [ -n "$_t_end" ]; then
  _ms=$(( _t_end - _t_start ))
  [ "$_ms" -lt 0 ] && _ms=0
  _ms_json="$_ms"
else
  _ms_json="null"
fi

# --- Monta o evento SO-NUMEROS com jq (jq escapa tudo -> JSON sempre valido). Se jq falhar -> fail-open. ---
# Campos: invite_id (opaco), kind:"medidor" (marca o evento como so-numeros), event (tipo do hook,
# colapsado por allowlist), tool (rotulo GENERICO da acao — Read/Edit/"mcp"/"outro", NUNCA o nome
# cru; um MCP nomeado por cliente ja virou "mcp"), ts, uso:{...}.
# NENHUM campo de conteudo (prompt/tool_input/tool_response) — Modelo A: numeros por padrao.
_line="$(jq -cn \
  --arg invite_id "$_invite_id" \
  --arg event     "$_event" \
  --arg tool      "${_tool_safe:-outro}" \
  --arg ts        "$_ts" \
  --argjson comandos 1 \
  --argjson tokens "${_tokens_aprox:-0}" \
  --argjson ms     "${_ms_json:-null}" \
  --argjson bytes  "${_chars:-0}" \
  '{invite_id:$invite_id, kind:"medidor", event:$event, tool:$tool, ts:$ts,
    uso:{comandos:$comandos, tokens:$tokens, ms:$ms, bytes:$bytes}}' 2>/dev/null || true)"

[ -z "$_line" ] && exit 0

# Enfileira no buffer local (append). Falha ao gravar -> fail-open.
printf '%s\n' "$_line" >> "$QUEUE" 2>/dev/null || exit 0

# --- Flush ASSINCRONO fire-and-forget (STUB se sem endpoint) ---
# Auth de ingestao (furos #1 e #3): usa SO o token PROPRIO do convite (identity.json). NAO ha
# fallback pro token compartilhado — o kit do convidado nem carrega token de dono. Sem convite
# validado -> sem token -> nao envia agora (fica na fila; o dreno tenta depois de validar).
#
# TRANSPORTE HONESTO (Modelo A): usa o mesmo `nb-post.js` A MOSTRA que o convite/consent usam —
# um POST normal (http/https do stdlib do node), legivel, que DIZ o que manda se perguntado.
# NAO driblamos deny-list de curl aqui (o curl era um patch pra a maquina endurecida do proprio
# CEO; pra distribuicao a usuarios normais, transporte legivel). O payload e SO-NUMEROS.
_url="${NORTE_BOX_TELEMETRY_URL:-}"
_tok="$(jq -r '.ingest_token // empty' "${STATE_DIR}/identity.json" 2>/dev/null || true)"
_nbpost=""
if [ -n "${_SELF_DIR:-}" ] && [ -f "${_SELF_DIR}/../lib/nb-post.js" ]; then
  _nbpost="${_SELF_DIR}/../lib/nb-post.js"
elif [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/lib/nb-post.js" ]; then
  _nbpost="${CLAUDE_PLUGIN_ROOT}/lib/nb-post.js"
fi
if [ -n "$_url" ] && [ -n "$_tok" ] && [ -n "$_nbpost" ] && command -v node >/dev/null 2>&1; then
  case "$_url" in
    https://*|http://127.0.0.1*|http://localhost*)
      ( printf '%s' "$_line" | node "$_nbpost" "$_url" - "$_tok" >/dev/null 2>&1 || true ) &
      disown 2>/dev/null || true
      ;;
  esac
fi

exit 0
