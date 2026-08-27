#!/usr/bin/env bash
# _socorro.sh — O "BILHETE DE SOCORRO" do norte-box (NRT-_990484, peca-irma do freio quando-trava).
# Sourceado pelo helper bin/nb-socorro (e por qualquer hook/skill que precise, quando a caixa TRAVA DE
# VEZ no meio de uma execucao, empacotar num arquivo LOCAL o que a Norte precisa pra socorrer rapido).
#
# O BURACO QUE ESTA PECA FECHA: a peca-irma _quando_trava.sh cobre "faltou um DADO" (pergunta e espera).
# ESTA aqui e o caso DIFERENTE: a caixa TENTOU e NAO CONSEGUIU — bateu num erro que a trava DE VEZ (ex:
# o comando falhou N vezes, uma dependencia sumiu, um passo explodiu). Em vez de deixar quem esta usando
# preso sem saber o que fazer, a caixa EMPACOTA SOZINHA, num arquivo LOCAL, tudo o que a Norte precisa
# pra socorrer rapido — e avisa: "nao consegui — salvei aqui o que precisa pra te ajudar". A pessoa decide
# se manda (ou nao). NADA sai da maquina sozinho.
#
# O QUE ENTRA NO BILHETE (montado do que JA existe no disco — nao inventa, nao reconstroi leitores):
#   - o OBJETIVO em palavras cruas         -> reusa _norte_situacao_campo objetivo (do _situacao.sh)
#   - o QUE A CAIXA TENTOU (o diario)       -> reusa _norte_diario_ultimas (do _diario.sh)
#   - o ERRO EXATO que travou               -> vem por argumento (NB_SOC_ERRO), tratado como TEXTO
#   - o SELO atual (🟡/🔴) + a VERSAO + o MODO -> reusa _norte_situacao_selo, plugin.json, _norte_modo
#   - um RESUMO curto ("nao consegui X depois de tentar Y")
#
# MOLDURA HONESTA (nao overclaim):
#   - A peca so JUNTA o que ja esta no disco + o erro que voce passa e escreve UM arquivo local. Ela NAO
#     tenta consertar, NAO decide, NAO envia. E um "pedido de socorro" pronto pra pessoa mandar — nunca
#     um canal que dispara sozinho.
#   - Como todo pacote que pode ser compartilhado, a privacidade e best-effort pelo redator (lista de
#     padroes conhecidos): reduz o vazamento de secret/PII RECONHECIDO, nao promete zero. Por isso, na
#     duvida entre incluir e nao incluir um campo, ELE NAO ENTRA (fail-safe de privacidade).
#
# LEIS (nao-negociaveis, iguais aos outros passos):
#   - LOCAL, ZERO REDE: so le o disco + monta texto + ecoa no stdout (ou grava um arquivo LOCAL, via bin).
#     NUNCA sai da maquina, nada de telemetria/rede. Esta lib nao envia NADA.
#   - PRIVACIDADE FAIL-SAFE (este arquivo pode ser compartilhado): NUNCA entra segredo, senha, token, nem
#     o CONTEUDO bruto de arquivo do cliente — so objetivo + erro + metadados + rotulos. TUDO que vem do
#     disco/argumento passa pelo _redact ANTES de entrar no bilhete. Se o _redact nao estiver disponivel
#     OU falhar num campo, aquele campo e OMITIDO (fail-CLOSED na redacao: melhor faltar do que vazar).
#   - FAIL-OPEN pro fluxo: com o kill-switch NORTE_SOCORRO=0 a peca fica INERTE (nada no stdout, exit 0) e
#     o fluxo segue exatamente como antes desta peca existir. Sem nenhuma fonte no disco, degrada com uma
#     mensagem honesta ("nao achei X") em vez de quebrar.
#   - DADO E DADO, NUNCA COMANDO: o erro, o resumo e tudo o que vem de fora sao TEXTO que entra no bilhete
#     — NUNCA sao executados/eval. `set -u`, sem eval, sem expandir valor como shell.
#   - Portabilidade macOS (bash 3.2, SEM arrays associativos/mapfile/${v^^}). Sem jq obrigatorio (degrada).
#
# KILL-SWITCH do mecanismo: NORTE_SOCORRO=0 -> a peca fica INERTE (nao monta bilhete), fail-open
# (exit 0, nada no stdout). Vazio/1/qualquer-outra-coisa = ligado.
set -u

# --- Carrega os leitores irmaos (fonte unica; NAO reimplementa). bin/ e hooks/ sao irmaos. Se algum
# nao carregar, a peca degrada sem travar (fail-open): o bloco correspondente sai como "nao achei". ---
_nbs_lib_dir() {
  local _d
  _d="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)"
  [ -n "${_d:-}" ] && { printf '%s' "$_d"; return 0; }
  [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && { printf '%s/hooks' "$CLAUDE_PLUGIN_ROOT"; return 0; }
  return 1
}
_nbs_carrega_irmaos() {
  local _dir; _dir="$(_nbs_lib_dir)" || return 0
  # shellcheck source=/dev/null
  [ -f "$_dir/_redact.sh" ]   && . "$_dir/_redact.sh"   2>/dev/null || true
  # shellcheck source=/dev/null
  [ -f "$_dir/_situacao.sh" ] && . "$_dir/_situacao.sh" 2>/dev/null || true
  # shellcheck source=/dev/null
  [ -f "$_dir/_diario.sh" ]   && . "$_dir/_diario.sh"   2>/dev/null || true
  # shellcheck source=/dev/null
  [ -f "$_dir/_modo.sh" ]     && . "$_dir/_modo.sh"     2>/dev/null || true
  return 0
}
_nbs_carrega_irmaos

# --- kill-switch: NORTE_SOCORRO=0 -> inerte (nao monta bilhete). ---
_nbs_desligado() {
  case "${NORTE_SOCORRO:-1}" in
    0|no|nao|off|false) return 0 ;;
    *) return 1 ;;
  esac
}

# _nbs_1linha <texto> — reduz um texto a UMA linha segura: tira \r, troca quebras de linha por espaco e
# corta em ~280 chars. Neutraliza multi-linha/CRLF de um argumento nao-confiavel antes de ele entrar no
# bilhete. Nunca executa nada. (Imita _nbp_1linha da peca-irma.)
_nbs_1linha() {
  local _t="${1:-}"
  printf '%s' "$_t" | tr -d '\r' | tr '\n' ' ' | cut -c1-280
}

# _nbs_redige <texto> — devolve o texto REDIGIDO (secret/PII/caminho mascarados) OU VAZIO se a redacao
# nao estiver disponivel/falhar. FAIL-SAFE DE PRIVACIDADE: sem redator confiavel, o campo VOLTA VAZIO ->
# o chamador OMITE o campo (na duvida, nao inclui). Reusa _safe_field do _redact.sh (fonte unica).
_nbs_redige() {
  local _t="${1:-}"
  [ -n "$_t" ] || { printf ''; return 0; }
  command -v _safe_field >/dev/null 2>&1 || { printf ''; return 1; }  # sem redator -> omite (fail-safe)
  _safe_field "$_t"
}

# _nbs_selo — ecoa o selo atual (🟡/🟢). REUSA _norte_situacao_selo (do _situacao.sh). Sem a lib -> vazio.
_nbs_selo() {
  command -v _norte_situacao_selo >/dev/null 2>&1 || { printf ''; return 1; }
  _norte_situacao_selo 2>/dev/null
}

# _nbs_modo — ecoa o modo atual (privado/compartilhavel). REUSA _norte_modo (do _modo.sh). Fail-closed em
# privado ja vem de la. Sem a lib -> vazio.
_nbs_modo() {
  command -v _norte_modo >/dev/null 2>&1 || { printf ''; return 1; }
  _norte_modo 2>/dev/null
}

# _nbs_versao — ecoa a versao do plugin, lida do plugin.json (NAO inventa). So o numero (metadado, nao e
# segredo, nao passa pelo redator). Sem jq / sem arquivo -> vazio.
_nbs_versao() {
  local _dir _pj
  _dir="$(_nbs_lib_dir)" || { printf ''; return 1; }
  _pj="$_dir/../.claude-plugin/plugin.json"
  [ -f "$_pj" ] || { printf ''; return 1; }
  command -v jq >/dev/null 2>&1 || { printf ''; return 1; }
  jq -r '.version // "" | if type=="string" then . else "" end' "$_pj" 2>/dev/null
}

# _nbs_objetivo — ecoa o OBJETIVO em palavras cruas, JA REDIGIDO. REUSA _norte_situacao_campo objetivo (do
# _situacao.sh). O objetivo e texto do cliente -> passa pelo redator (fail-safe). Vazio se nao ha fichinha
# / sem objetivo / redacao falhou.
_nbs_objetivo() {
  command -v _norte_situacao_campo >/dev/null 2>&1 || { printf ''; return 1; }
  local _o; _o="$(_norte_situacao_campo objetivo 2>/dev/null)"
  [ -n "$_o" ] || { printf ''; return 1; }
  _nbs_redige "$_o"
}

# _nbs_tentou <n> — ecoa AS ULTIMAS n linhas do diario (o "o que a caixa tentou"), JA REDIGIDAS linha a
# linha. REUSA _norte_diario_ultimas (do _diario.sh) — NAO reimplementa a leitura do diario. Cada linha
# passa pelo redator; linha cuja redacao falhar e OMITIDA (fail-safe). Vazio se nao ha diario.
_nbs_tentou() {
  command -v _norte_diario_ultimas >/dev/null 2>&1 || { printf ''; return 1; }
  local _n; _n="$1"; case "$_n" in ''|*[!0-9]*) _n=5 ;; esac
  local _raw; _raw="$(_norte_diario_ultimas "$_n" 2>/dev/null)"
  [ -n "$_raw" ] || { printf ''; return 1; }
  local _line _red _any=1
  # Le linha a linha SEM subshell perder o estado (here-string, bash 3.2 ok).
  while IFS= read -r _line; do
    [ -n "$_line" ] || continue
    _red="$(_nbs_redige "$_line")"
    [ -n "$_red" ] || continue   # redacao falhou nessa linha -> OMITE (fail-safe)
    printf '%s\n' "$_red"
    _any=0
  done <<EOF
$_raw
EOF
  return "$_any"
}

# _norte_socorro <erro> [resumo] — o CORACAO da peca. Monta o BILHETE DE SOCORRO no stdout, juntando o
# que JA existe no disco (objetivo/diario/selo/versao/modo) + o ERRO que voce passa + um RESUMO curto.
# SEMPRE exit 0 (fail-open: informa, nunca trava). Kill-switch NORTE_SOCORRO=0 -> inerte (nada, exit 0).
#   <erro>   : o erro exato que travou (TEXTO; sera redigido e tratado como dado, nunca executado).
#   [resumo] : um resumo curto opcional ("nao consegui X depois de tentar Y"). Se vazio, a peca monta um
#              resumo honesto minimo a partir do erro.
# NADA e enviado — so texto. Quem grava o arquivo local e o bin/nb-socorro.
_norte_socorro() {
  if _nbs_desligado; then
    return 0   # inerte: nada no stdout (o fluxo segue como antes, sem o bilhete).
  fi

  local _erro_r _resumo_r
  # REDIGE ANTES DE CORTAR (furo achado pelo Val): se cortasse a ~280 chars primeiro, um secret bem na
  # emenda do corte partia o token e escapava da regra de comprimento minimo do redator -> prefixo cru
  # vazava no bilhete (que e feito pra ser compartilhado). Agora redige o texto CRU inteiro e SO DEPOIS
  # reduz a 1 linha + corta. Fail-safe preservado: sem redator -> vazio -> o campo e omitido.
  _erro_r="$(_nbs_1linha "$(_nbs_redige "${1:-}")")"
  _resumo_r="$(_nbs_1linha "$(_nbs_redige "${2:-}")")"

  # coleta o que ja existe no disco (cada um ja redigido/omitido pela sua funcao)
  local _obj _selo _ver _modo _tentou
  _obj="$(_nbs_objetivo)"
  _selo="$(_nbs_selo)"
  _ver="$(_nbs_versao)"
  _modo="$(_nbs_modo)"
  _tentou="$(_nbs_tentou 5)"

  # ---- CABECALHO ----
  printf '# 🆘 BILHETE DE SOCORRO — norte-box\n'
  printf 'Nao consegui terminar sozinho. Salvei aqui, LOCAL, o que a Norte precisa pra te ajudar rapido.\n'
  printf 'Isto e um arquivo NA SUA MAQUINA. NADA foi enviado — voce decide se manda.\n'
  printf 'Privacidade: tiramos os segredos/dados pessoais que reconhecemos; na duvida, o campo fica de fora.\n'
  printf '\n'

  # ---- RESUMO CURTO ----
  printf '## O que aconteceu (resumo)\n'
  if [ -n "$_resumo_r" ]; then
    printf '%s\n' "$_resumo_r"
  elif [ -n "$_erro_r" ]; then
    printf 'Nao consegui terminar: bati num erro que me travou de vez (veja abaixo).\n'
  else
    printf 'Nao consegui terminar: travei de vez, mas nao tenho o texto do erro (nao veio ou foi omitido por privacidade).\n'
  fi
  printf '\n'

  # ---- OBJETIVO ----
  printf '## O que eu estava tentando fazer (objetivo)\n'
  if [ -n "$_obj" ]; then
    printf '%s\n' "$_obj"
  else
    printf '(nao achei um objetivo registrado — abra a caixa com /objetivo pra deixar isso gravado.)\n'
  fi
  printf '\n'

  # ---- O QUE TENTEI (diario) ----
  printf '## O que eu ja tinha tentado (ultimos passos)\n'
  if [ -n "$_tentou" ]; then
    printf '%s\n' "$_tentou"
  else
    printf '(nao achei um diario de passos — a caixa ainda nao registrou nada aqui.)\n'
  fi
  printf '\n'

  # ---- ERRO EXATO ----
  printf '## O erro exato que me travou\n'
  if [ -n "$_erro_r" ]; then
    printf '%s\n' "$_erro_r"
  else
    printf '(sem texto de erro — nao veio, ou foi omitido por privacidade.)\n'
  fi
  printf '\n'

  # ---- ESTADO DA CAIXA (metadados) ----
  printf '## Estado da caixa\n'
  printf -- '- selo: %s\n'   "${_selo:-(nao sei)}"
  printf -- '- versao: %s\n' "${_ver:-(nao sei)}"
  printf -- '- modo: %s\n'   "${_modo:-privado}"
  printf '\n'
  printf 'Como pedir socorro: mande este arquivo pra Norte (voce escolhe o canal). Ele nao sai daqui sozinho.\n'
  return 0
}
