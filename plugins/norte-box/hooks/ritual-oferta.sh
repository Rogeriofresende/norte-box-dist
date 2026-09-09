#!/usr/bin/env bash
# ritual-oferta.sh — SessionStart hook do norte-box (fatia "OFERECER DORMENTE", NRT oferta).
# Quando o OBSERVADOR (fatia anterior) ja contou >=3 rituais mandato_pr_v1 COMPLETOS, a caixa
# OFERECE UMA VEZ, de forma SUTIL, na abertura da sessao: "quer virar atalho?".
# ATOMICO (fix furos 1+2, Val red-team): a DECISAO de ofertar e a GRAVACAO de oferta_ts/ofertas
# acontecem SOB O MESMO LOCK e ANTES de imprimir (via _nb_atalho_reivindica_oferta) — so imprime
# quem reivindicou. Sob N aberturas paralelas -> ofertas==1, impressa 1x. Lock com espera CURTA:
# se preso, silencia e NAO trava a abertura da sessao (falha pro lado do silencio).
#
# ============================================================================================
# LEIS (iguais ao observador):
#   - FAIL-OPEN: exit 0 SEMPRE (nunca trava a sessao). Erro interno -> silencioso.
#   - Kill-switch NORTE_RITUAL_OFF=1 respeitado na 1a linha.
#   - Opt-in FAIL-CLOSED: sem a flag .enabled -> nao oferta.
#   - ZERO rede. Escreve SO em $HOME/.norte-box. Sem conteudo (so 1 linha de texto FIXO + rotulo).
#   - Sync (imprime ANTES da sessao comecar), mas leve: 1 leitura + 1 escrita condicional.
set -u

# --- KILL-SWITCH (1a linha, antes de qualquer trabalho) ---
[ "${NORTE_RITUAL_OFF:-0}" = "1" ] && exit 0

# Consome stdin (SessionStart manda um JSON) como DADO, so pra evitar SIGPIPE.
cat >/dev/null 2>&1 || true

STATE_DIR="${HOME}/.norte-box"
ENABLED_FLAG="${STATE_DIR}/ritual-observador.enabled"

# --- OPT-IN FAIL-CLOSED: sem a flag-arquivo -> nao oferta (a caixa segue igual) ---
[ -f "$ENABLED_FLAG" ] || exit 0

# Sem jq nao da pra ler/gravar com seguranca -> fail-open (silencia).
command -v jq >/dev/null 2>&1 || exit 0

# Carrega as libs (observador p/ lock/atomic/now; atalho p/ gatilho+gravacao).
_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)"
_load() { # $1 = nome do arquivo de lib
  if [ -n "${_SELF_DIR:-}" ] && [ -f "${_SELF_DIR}/$1" ]; then . "${_SELF_DIR}/$1"; return 0; fi
  if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/hooks/$1" ]; then . "${CLAUDE_PLUGIN_ROOT}/hooks/$1"; return 0; fi
  return 1
}
_load "_ritual.sh" || true          # best-effort (o _atalho degrada sem ele)
_load "_atalho.sh"  || exit 0        # sem a lib da fatia -> nada a fazer
command -v _nb_atalho_reivindica_oferta >/dev/null 2>&1 || exit 0

# --- REIVINDICA A OFERTA (atomico: decide+grava SOB O MESMO LOCK, ANTES de imprimir) ---
# Fix furos 1+2 (Val): sob N SessionStart paralelos so UM reivindica (grava oferta_ts/ofertas
# sob lock) e ecoa "1"; os demais veem oferta_ts ja gravado e ecoam "0". So o vencedor imprime
# -> ofertas==1, impressa 1x. Espera CURTA do lock (~20 tentativas): se preso, ecoa "0" -> NAO
# imprime e NAO trava a abertura da sessao (falha pro SILENCIO; oferta na proxima abertura).
if [ "$(_nb_atalho_reivindica_oferta 20 2>/dev/null || printf '0')" = "1" ]; then
  # 1 linha discreta. Texto FIXO — nenhum path/comando/conteudo do trabalho.
  printf '%s\n' "💡 Norte-box · Voce ja fechou o ritual mandato→PR 3× — quer transformar num atalho? Rode: /norte-box:ritual atalho mandato_pr_v1  (ou dispense: /norte-box:ritual atalho-nao mandato_pr_v1)"
fi

exit 0
