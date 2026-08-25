#!/usr/bin/env bash
# _correcoes.sh — FONTE UNICA das "correcoes do jeito da pessoa" do Norte-box (memoria funda, NRT-_990212
# passo 7). Sourceado pelo comando /norte-box:regra (append) e pela situacao-abrir (SessionStart, cita as
# regras gravadas na reabertura).
#
# A ideia (padaria): alem do OBJETIVO (situacao.json) e do DIARIO (diario.jsonl), a caixa passa a guardar
# as CORRECOES do jeito da pessoa — "eu assino Dra. Viviane, nunca so Viviane", "eu faco assim, nao
# assado". Cada correcao e uma regra CRUA que a pessoa DECLARA por ATO EXPLICITO (o comando), e a caixa
# CITA de volta (verbatim) na proxima reabertura. Perfil e correcao usam a MESMA lei — uma mecanica,
# duas portas.
#
# A LEI (o coracao — a armadilha nº1): FAIL-HONEST / ANTI-INVENCAO.
#   - SO GRAVA POR ATO EXPLICITO: quem chama e o comando /norte-box:regra (a pessoa rodou). Conversa
#     comum ("nao gosto assim", "acho que...") NAO grava NADA. Sem texto passado -> nada e escrito.
#   - VERBATIM: grava o texto CRU da pessoa, char-por-char (jq --arg copia a string byte a byte), + a
#     data + qual conversa. ZERO resumo, ZERO deducao, ZERO campo inferido. O LLM NAO tem caminho de
#     escrita aqui — a gravacao e este codigo determinista que copia a string recebida.
#   - origem = "ato_explicito" SEMPRE (constante no codigo, nao vem do dado). Rastreia que a regra
#     nasceu de um comando, nunca de uma inferencia.
#
# LEIS (nao-negociaveis, iguais ao _diario.sh):
#   - PRIVADO POR PADRAO: mora num arquivo LOCAL em $HOME/.norte-box/correcoes.jsonl. NUNCA sai da
#     maquina, NUNCA passa por telemetria/rede. Esta lib so le/escreve o disco local.
#   - APPEND-ONLY: cada regra anexa UMA linha jsonl; nunca reescreve/apaga o historico.
#   - Portabilidade macOS (bash 3.2). Precisa de jq; sem jq, as funcoes degradam sem travar (fail-open).
set -u

# Caminho unico do store de correcoes.
_norte_correcoes_path() { printf '%s/.norte-box/correcoes.jsonl' "${HOME}"; }

# _norte_correcao_anexar — anexa UMA correcao ao correcoes.jsonl. Recebe por variaveis de ambiente (pra
# nao brigar com aspas):
#   NB_COR_TEXTO    (obrigatorio) = o texto CRU da regra, do jeito que a pessoa escreveu (verbatim).
#   NB_COR_CONVERSA (opcional)    = qual conversa/sessao originou (rastro; vazio se nao souber).
# origem e SEMPRE "ato_explicito" (constante — nao vem do dado). criado_em = agora (ISO).
# Retorna 0 se anexou; 1 se nao deu (sem jq / sem texto / disco nao gravavel) — o chamador ignora.
# NUNCA parafraseia: o campo texto_cru recebe NB_COR_TEXTO byte a byte via jq --arg.
_norte_correcao_anexar() {
  command -v jq >/dev/null 2>&1 || return 1
  local _texto="${NB_COR_TEXTO:-}"
  [ -n "$_texto" ] || return 1   # sem texto explicito -> nao grava (fail-honest / anti-invencao)
  local _dir="${HOME}/.norte-box" _f _ts _conversa
  _f="$(_norte_correcoes_path)"
  mkdir -p "$_dir" 2>/dev/null || return 1
  _ts="$(date -u +%FT%TZ 2>/dev/null || echo unknown)"
  _conversa="${NB_COR_CONVERSA:-}"
  local _line
  _line="$(jq -cn \
    --arg texto    "$_texto" \
    --arg criado   "$_ts" \
    --arg conversa "$_conversa" \
    '{texto_cru:$texto, criado_em:$criado, conversa:$conversa, origem:"ato_explicito"}' 2>/dev/null)" || return 1
  [ -n "$_line" ] || return 1
  printf '%s\n' "$_line" >> "$_f" 2>/dev/null || return 1
  return 0
}

# _norte_correcoes_todas — ecoa TODAS as correcoes gravadas, uma por linha, ja formatadas pra leitura
# humana e VERBATIM: "• <texto_cru> (gravada em DATA)". So LE; nunca escreve. Vazio se nao ha store.
# O <texto_cru> sai como veio (nao resume/reescreve). A DATA e cortada em YYYY-MM-DD (so o dia).
# Nao imprime caminho de filesystem. Nao redige aqui — a redacao (secret) e responsabilidade de QUEM
# EXIBE (a situacao-abrir passa cada texto pelo _redact antes de mostrar); esta lib entrega o cru.
_norte_correcoes_todas() {
  command -v jq >/dev/null 2>&1 || return 1
  local _f
  _f="$(_norte_correcoes_path)"
  [ -f "$_f" ] || return 1
  jq -r '
    select(type=="object")
    | "• " + (.texto_cru // "?")
      + (if (.criado_em // "") != "" then " (gravada em " + (.criado_em | .[0:10]) + ")" else "" end)
  ' "$_f" 2>/dev/null
}

# _norte_correcoes_tem — 0 se ha ao menos 1 correcao gravada; 1 caso contrario. Usado pra decidir entre
# citar as regras ou dizer honesto "nenhuma regra gravada".
_norte_correcoes_tem() {
  command -v jq >/dev/null 2>&1 || return 1
  local _f
  _f="$(_norte_correcoes_path)"
  [ -f "$_f" ] || return 1
  jq -e 'select(type=="object") | .texto_cru' "$_f" >/dev/null 2>&1
}
