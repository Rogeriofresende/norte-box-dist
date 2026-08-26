#!/usr/bin/env bash
# situacao-gravar.sh — Stop hook do norte-box: grava a FICHINHA de situacao no fim da sessao.
#
# O QUE FAZ: no fim de cada turno/sessao, guarda um cartaozinho LOCAL com o objetivo em palavras
# cruas (a 1a fala da pessoa nesta sessao), pra que a PROXIMA abertura mostre "de onde viemos" e
# a pessoa nunca fique no branco. A fichinha mora em $HOME/.norte-box/situacao.json.
#
# HONESTO POR PADRAO: grava SEMPRE provado=false (selo 🟡 NAO-PROVADO). O verde so viria de um
# artefato de prova real — que ainda nao existe (o motor de prova/Val de bolso nao foi construido).
# De proposito: "um amarelo honesto vale mais que um verde que mente".
#
# PRIVADO POR PADRAO: a fichinha e LOCAL, NUNCA enviada. Este hook nao toca telemetria/rede — ele
# roda INDEPENDENTE do modo (privado ou compartilhavel): a memoria da pessoa e dela, sempre. So
# guardamos o ROTULO do objetivo (a fala que abre a sessao), nao o trabalho.
#
# LEIS (iguais aos outros hooks do box):
#   - FAIL-OPEN: exit 0 SEMPRE. Nunca trava/atrasa o Claude.
#   - Consome stdin como DADO, nunca executa. Nao escreve fora de $HOME/.norte-box.
#   - Sem jq / sem transcript -> nao grava (fail-open), sai limpo.
set -u

_stdin="$(cat 2>/dev/null || true)"

# Carrega a lib da fichinha (fonte unica de read/write).
_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)"
if [ -n "${_SELF_DIR:-}" ] && [ -f "${_SELF_DIR}/_situacao.sh" ]; then
  . "${_SELF_DIR}/_situacao.sh"
elif [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/hooks/_situacao.sh" ]; then
  . "${CLAUDE_PLUGIN_ROOT}/hooks/_situacao.sh"
else
  exit 0
fi
command -v _norte_situacao_gravar >/dev/null 2>&1 || exit 0
command -v jq >/dev/null 2>&1 || exit 0

# Caminho do transcript (o Stop hook fornece transcript_path).
_transcript="$(printf '%s' "$_stdin" | jq -r '.transcript_path // empty' 2>/dev/null || true)"
[ -n "$_transcript" ] || exit 0
[ -f "$_transcript" ] || exit 0

# Objetivo em PALAVRAS CRUAS = a 1a fala do usuario nesta sessao (o que ele pediu). Deterministico,
# nao inventado. So o TEXTO da 1a mensagem; nada do trabalho subsequente entra na fichinha.
_objetivo="$(jq -rs '
  [ .[] | select(.type=="user") ] | .[0]
  | (.message.content)
  | if type=="array" then (map(select(.type=="text") | .text) | join(" "))
    elif type=="string" then .
    else "" end
' "$_transcript" 2>/dev/null || true)"

# Sem 1a fala legivel (ex: sessao so-comando) -> nao sobrescreve a fichinha existente (fail-open).
[ -n "$_objetivo" ] || exit 0

# Normaliza: 1 linha, aparada, cap de tamanho (o cartao e curto; nao guardamos um dump). So o rotulo.
_objetivo="$(printf '%s' "$_objetivo" | tr '\n\r\t' '   ' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | cut -c1-240)"
[ -n "$_objetivo" ] || exit 0

# entregou/proximo: a gravacao automatica nao sabe RESUMIR o que foi feito (bash nao le a intencao).
# Deixamos vazios aqui — a skill /norte-box:continuar (que pede o resumo ao modelo) e o lugar certo
# pra enriquecer isso depois. O importante do 1.1 (nunca ficar no branco) ja e coberto pelo objetivo.
NB_SIT_OBJETIVO="$_objetivo" NB_SIT_ENTREGOU="" NB_SIT_PROXIMO="" _norte_situacao_gravar || exit 0

# --- 2o PORTAO (NRT-_990429 fatia 2 — FIAR O WRITER NO FLUXO REAL) --------------------------------
# Ate aqui o writer _norte_objetivo_conferir so era chamado pelo teste. Consequencia: no uso REAL, uma
# sessao COM objetivo declarado nunca ganhava o bloco .objetivo_conferido -> o selo ficava preso no
# amarelo (o antigo Caso 6). O ajuste gracioso do gate ja tirou o amarelo cego (ausencia = pulado); aqui
# fechamos o elo GENUINO: se o agente DECLAROU onde a entrega responde ao objetivo — via um marcador de
# saida "OBJETIVO-RESPONDE: <trecho literal da entrega>" na sua ultima resposta — a caixa registra a
# conferencia. O trecho_encontrado NAO vem do modelo: o writer computa por grep -F do trecho DENTRO do
# artefato de prova real (blefe pego). Sem marcador -> nao faz nada (preserva o estado; nunca forja verde).
#
# LEIS: FAIL-OPEN (qualquer tropeco daqui pra frente sai 0, a sessao NUNCA trava). Kill-switch
# NB_OBJETIVO_CHECK=0 restaura o de hoje (nao mexe na conferencia). So roda quando o objetivo foi
# DECLARADO por ato explicito (objetivo_declarado:true) — o rotulo AUTO da 1a fala nao liga o 2o portao.
case "${NB_OBJETIVO_CHECK:-1}" in 0|no|nao|off|false) exit 0 ;; esac
command -v _norte_objetivo_conferir >/dev/null 2>&1 || exit 0
command -v _norte_objetivo_declarado >/dev/null 2>&1 || exit 0
# So confere contra objetivo DECLARADO (soberano); rotulo auto nao vale (mesma regra do gate).
_norte_objetivo_declarado || exit 0

# Extrai a ULTIMA mensagem do assistente que tem TEXTO (a resposta final; pula mensagens so-tool_use),
# junta seus blocos de texto e le a ULTIMA linha "OBJETIVO-RESPONDE: <trecho>". Consome o transcript como
# DADO (jq), nunca executa. Sem marcador legivel -> _mark vazio -> nao chama o writer (preserva o estado).
_ultimo_texto="$(jq -rs '
  [ .[] | select(.type=="assistant")
        | .message.content
        | if type=="array" then (map(select(.type=="text") | .text) | join("\n"))
          elif type=="string" then .
          else "" end ]
  | map(select(. != ""))
  | .[-1] // ""
' "$_transcript" 2>/dev/null || true)"

# Pega a ULTIMA ocorrencia do marcador (ancorada no inicio da linha, tolera indentacao). tail -n1 garante
# "a ultima da ultima mensagem". Depois tira o prefixo do marcador + espacos das pontas + colapsa pra 1
# linha + cap de tamanho (o trecho e uma citacao curta, nao um dump). Tudo tratado como STRING literal.
_mark_linha="$(printf '%s\n' "$_ultimo_texto" | grep -E '^[[:space:]]*OBJETIVO-RESPONDE:' 2>/dev/null | tail -n 1 || true)"
[ -n "$_mark_linha" ] || exit 0
_trecho_resp="$(printf '%s' "$_mark_linha" \
  | sed -E 's/^[[:space:]]*OBJETIVO-RESPONDE:[[:space:]]*//' \
  | tr '\n\r\t' '   ' \
  | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' \
  | cut -c1-240)"
[ -n "$_trecho_resp" ] || exit 0

# Chama o WRITER honesto: grava .objetivo_conferido conferindo o trecho por grep -F DENTRO do artefato de
# prova ja registrado (o writer resolve o artefato: usa o prova.artefato da fichinha se nenhum for passado).
# Se o trecho existe na entrega -> trecho_encontrado=true (o gate abre verde no PROVADO). Se nao existe
# (blefe) -> false (o gate segura em amarelo). Fail-open: falha do writer nao trava a sessao.
_norte_objetivo_conferir "$_trecho_resp" >/dev/null 2>&1 || exit 0
exit 0
