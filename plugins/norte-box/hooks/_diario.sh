#!/usr/bin/env bash
# _diario.sh — FONTE UNICA do "diario do que construimos" do Norte-box (Camada 1, resto 1).
# Sourceado pelo hook diario-gravar (Stop), pela situacao-abrir (SessionStart, mostra as ultimas 3)
# e pelo comando /norte-box:diario (le a lista inteira).
#
# A ideia (padaria): uma LISTA VIVA que cresce sozinha — a cada fim de sessao a caixa ANEXA uma
# linha "o que voce pediu · o que eu fiz · provado?(🟢/🟡) · decisao · quando". Assim da pra abrir a
# caixa e VER o historico do que ja foi construido, sem depender da memoria de ninguem.
#
# LEIS (nao-negociaveis, iguais a fichinha _situacao.sh):
#   - PRIVADO POR PADRAO: o diario mora num arquivo LOCAL em $HOME/.norte-box/diario.jsonl. NUNCA sai
#     da maquina, NUNCA passa por telemetria/rede. Esta lib so le/escreve o disco local.
#   - HONESTO POR PADRAO (fail-honest): o selo de cada linha REUSA a regra do selo (via _situacao.sh):
#     🟢 PROVADO so com artefato de prova real; senao 🟡 NAO-PROVADO. Nunca inventa verde.
#   - APPEND-ONLY: cada sessao anexa UMA linha jsonl; nunca reescreve/apaga o historico.
#   - IDEMPOTENTE POR SESSAO: o Stop pode disparar N vezes na MESMA sessao; cada sessao grava NO MAXIMO
#     1 linha. A linha carrega uma chave estavel da sessao (session_id do Stop, ou fallback). Se o
#     diario ja tem uma linha com essa chave, o append vira no-op (return 0). Sessoes diferentes
#     (chaves diferentes) sempre geram linhas distintas — o mesmo pedido em dias/sessoes diferentes
#     DEVE gerar 2 linhas; so a repeticao DENTRO da mesma sessao e suprimida.
#   - Portabilidade macOS (bash 3.2). Precisa de jq; sem jq, as funcoes degradam sem travar (fail-open).
set -u

# Caminho unico do diario.
_norte_diario_path() { printf '%s/.norte-box/diario.jsonl' "${HOME}"; }

# _norte_diario_ja_tem_sessao <chave> — 0 se o diario JA tem uma linha com essa chave de sessao; 1 se
# nao (ou sem arquivo/jq/chave). Usado pra tornar o append idempotente por sessao (anti double-fire).
_norte_diario_ja_tem_sessao() {
  local _chave="${1:-}" _f
  [ -n "$_chave" ] || return 1
  command -v jq >/dev/null 2>&1 || return 1
  _f="$(_norte_diario_path)"
  [ -f "$_f" ] || return 1
  # Casa a chave em QUALQUER linha ja gravada (nao so a ultima) — robusto a reordenacao.
  jq -e --arg s "$_chave" 'select(type=="object") | .sessao == $s' "$_f" >/dev/null 2>&1
}

# _norte_diario_anexar — anexa UMA linha ao diario.jsonl. Recebe por variaveis de ambiente (pra nao
# brigar com aspas): NB_DIA_PEDIU (o que a pessoa pediu), NB_DIA_FIZ (o que a caixa fez, pode vazio),
# NB_DIA_DECISAO (opcional), NB_DIA_SESSAO (chave estavel da sessao = session_id do Stop, ou fallback).
# O SELO nao vem por parametro: e sempre lido do estado real (fail-honest, via _norte_situacao_selo se
# disponivel; senao default 🟡 NAO-PROVADO). Retorna 0 se anexou; 1 se nao deu (sem jq / disco nao
# gravavel / nada a gravar) — o chamador ignora (fail-open).
#
# IDEMPOTENTE POR SESSAO: se NB_DIA_SESSAO ja aparece numa linha do diario, NAO anexa de novo (o Stop
# disparou 2x na mesma sessao) e retorna 0 — no-op. Sem NB_DIA_SESSAO, cai num fallback estavel
# (hash de pediu+dia) pra ainda evitar a duplicata obvia do double-fire; sessoes/dias diferentes com
# pedidos diferentes seguem gerando linhas distintas.
_norte_diario_anexar() {
  command -v jq >/dev/null 2>&1 || return 1
  local _pediu="${NB_DIA_PEDIU:-}"
  [ -n "$_pediu" ] || return 1   # sem "o que pediu" nao ha linha util -> fail-open silencio
  local _dir="${HOME}/.norte-box" _f _ts _selo _sessao
  _f="$(_norte_diario_path)"
  mkdir -p "$_dir" 2>/dev/null || return 1
  _ts="$(date -u +%FT%TZ 2>/dev/null || echo unknown)"
  # Chave de idempotencia da sessao. Preferido: session_id do Stop (NB_DIA_SESSAO). Se ausente,
  # fallback estavel = "fb:" + hash(pediu + dia) pra que 2 disparos iguais no mesmo dia dedupliquem
  # sem colar dias/pedidos diferentes. (pedido igual em dias diferentes -> hash diferente -> 2 linhas.)
  _sessao="${NB_DIA_SESSAO:-}"
  if [ -z "$_sessao" ]; then
    local _dia _hkey _h
    _dia="${_ts%%T*}"
    _hkey="${_pediu}|${_dia}"
    if command -v shasum >/dev/null 2>&1; then
      _h="$(printf '%s' "$_hkey" | shasum 2>/dev/null | cut -c1-16)"
    elif command -v sha1sum >/dev/null 2>&1; then
      _h="$(printf '%s' "$_hkey" | sha1sum 2>/dev/null | cut -c1-16)"
    fi
    [ -n "${_h:-}" ] && _sessao="fb:${_h}"
  fi
  # Ja gravou essa sessao? Entao o Stop disparou de novo -> no-op (idempotente).
  if [ -n "$_sessao" ] && _norte_diario_ja_tem_sessao "$_sessao"; then
    return 0
  fi
  # Selo honesto reusa a regra unica do passo 1. Sem a lib carregada -> default amarelo (fail-honest).
  if command -v _norte_situacao_selo >/dev/null 2>&1; then
    _selo="$(_norte_situacao_selo 2>/dev/null)"
  fi
  [ -n "${_selo:-}" ] || _selo="🟡 NAO-PROVADO"
  local _line
  _line="$(jq -cn \
    --arg pediu   "$_pediu" \
    --arg fiz     "${NB_DIA_FIZ:-}" \
    --arg selo    "$_selo" \
    --arg decisao "${NB_DIA_DECISAO:-}" \
    --arg sessao  "$_sessao" \
    --arg ts      "$_ts" \
    '{pediu:$pediu, fiz:$fiz, selo:$selo, decisao:$decisao, sessao:$sessao, quando:$ts}' 2>/dev/null)" || return 1
  [ -n "$_line" ] || return 1
  printf '%s\n' "$_line" >> "$_f" 2>/dev/null || return 1
  return 0
}

# _norte_diario_ultimas <N> — ecoa as ULTIMAS N linhas do diario, ja formatadas pra leitura humana
# (uma por linha, tom de padaria). Vazio se nao ha diario ou jq ausente (fail-open silencio).
# So LE; nunca escreve. Nao imprime caminho de filesystem.
_norte_diario_ultimas() {
  command -v jq >/dev/null 2>&1 || return 1
  local _n="${1:-3}" _f
  _f="$(_norte_diario_path)"
  [ -f "$_f" ] || return 1
  # tail das ultimas N linhas jsonl validas -> formata "• pediu: X | fiz: Y | selo | quando".
  tail -n "$_n" "$_f" 2>/dev/null | jq -r '
    select(type=="object")
    | "• pediu: " + (.pediu // "?")
      + (if (.fiz // "") != "" then " | fiz: " + .fiz else "" end)
      + " | " + (.selo // "🟡 NAO-PROVADO")
      + (if (.decisao // "") != "" then " | decisao: " + .decisao else "" end)
      + (if (.quando // "") != "" then " | " + (.quando | .[0:10]) else "" end)
  ' 2>/dev/null
}
