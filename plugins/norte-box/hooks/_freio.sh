#!/usr/bin/env bash
# _freio.sh — FONTE UNICA do FREIO (NRT-_990212 passo 9, "trava-mestra das acoes").
# Sourceado pelas libs de acao (_sombra.sh / _aplicar.sh) e pelo helper bin/nb-freio.
#
# A ideia (padaria): um FREIO DE MAO. O leigo puxa e a caixa NAO MEXE EM NADA — nenhuma acao (ensaiar,
# aplicar, desfazer) roda enquanto o freio estiver puxado. Solta e volta ao normal. Simples: existe o
# freio = puxado; nao existe = solto. Tudo-ou-nada. Nao ha freio parcial, por-papel, remoto ou agendado.
#
# ESTADO = ARQUIVO $HOME/.norte-box/freio. SEMANTICA POR PRESENCA: o arquivo existir JA significa puxado.
# O conteudo e' so um carimbo humano ("puxado em <data>") — NUNCA e' parseado pra decidir nada. Assim
# ninguem "solta o freio" editando o conteudo; so soltando quem apaga o arquivo (tem a mao na maquina).
#
# LEIS (nao-negociaveis):
#   - FAIL-CLOSED da ACAO: na DUVIDA, trata como PUXADO (bloqueia). HOME vazio/nao-resolvivel -> puxado;
#     pasta .norte-box existe mas ilegivel -> puxado; arquivo existe -> puxado. So SOLTO se o estado for
#     legivel E o arquivo estiver ausente. Um freio que falha ABERTO nao e' freio.
#   - PRECEDENCIA freio > env: quem chamar o guard chama ANTES dos checks de env (kill-switch das outras
#     pecas). Se o freio esta puxado, a acao nem chega a olhar NORTE_SOMBRA/NORTE_APLICAR.
#   - KILL-SWITCH DA PROPRIA PECA: NORTE_FREIO=0 DESLIGA o MECANISMO do freio (emergencia — se a peca do
#     freio der problema, da pra tirar a peca inteira). Isso NAO e' o "soltar" do leigo (o leigo solta
#     apagando o arquivo). NAO existe env-var de BYPASS por acao: so solta quem tem a mao na maquina.
#   - LOCAL + ZERO-REDE. set -u. Portabilidade macOS (bash 3.2).
set -u

# --- caminho do estado do freio (o arquivo cuja PRESENCA = puxado) ---
_norte_freio_arquivo() { printf '%s/.norte-box/freio' "${HOME:-}"; }
# --- pasta que abriga o estado (usada pra checar legibilidade no fail-closed) ---
_norte_freio_pasta()   { printf '%s/.norte-box' "${HOME:-}"; }

# _norte_freio_ativo — o freio deve BLOQUEAR?
#   0 (sucesso/ativo) = PUXADO, bloqueia.   1 = SOLTO, segue.
#   FAIL-CLOSED: qualquer duvida -> 0 (puxado). So devolve 1 (solto) se o estado for legivel E ausente.
_norte_freio_ativo() {
  # kill-switch de EMERGENCIA da propria peca: NORTE_FREIO=0 desliga o MECANISMO (freio nunca bloqueia).
  case "${NORTE_FREIO:-1}" in
    0|no|nao|off|false) return 1 ;;
  esac

  # HOME vazio/nao-resolvivel -> na duvida, PUXADO (fail-closed).
  [ -n "${HOME:-}" ] || return 0
  [ -d "${HOME}" ]   || return 0

  local _pasta _arq
  _pasta="$(_norte_freio_pasta)"
  _arq="$(_norte_freio_arquivo)"

  # Se a pasta .norte-box EXISTE mas esta ILEGIVEL (nao da pra listar/checar dentro) -> PUXADO (nao da
  # pra afirmar com seguranca que o arquivo esta ausente). So consideramos "solto" quando conseguimos
  # de fato ENXERGAR que o arquivo nao esta la.
  if [ -e "$_pasta" ]; then
    if [ ! -d "$_pasta" ]; then
      # existe mas nao e' diretorio (estado bizarro) -> fail-closed.
      return 0
    fi
    if [ ! -r "$_pasta" ] || [ ! -x "$_pasta" ]; then
      # existe, e' pasta, mas nao da pra ler/atravessar -> nao da pra provar ausencia -> PUXADO.
      return 0
    fi
  fi
  # (se a pasta NAO existe, o arquivo nao pode existir -> segue pro teste de presenca abaixo, que dara solto.)

  # A regra central: arquivo PRESENTE = puxado; ausente (e legivel ate aqui) = solto.
  # symlink DANGLING (quebrado) NAO satisfaz [ -e ] (que segue o link) -> some -[ -L ] pra tratar o
  # atalho, mesmo apontando pra nada, como PRESENCA = puxado (fail-closed: estado bizarro = puxado).
  if [ -e "$_arq" ] || [ -L "$_arq" ]; then
    return 0   # PUXADO
  fi
  return 1     # SOLTO
}

# _norte_freio_checa — o GUARD que as acoes chamam no TOPO (antes de tudo).
#   Se o freio esta puxado: imprime a mensagem padaria e devolve !=0 (a acao deve abortar SEM agir).
#   Se solto: devolve 0 (a acao segue).
_norte_freio_checa() {
  if _norte_freio_ativo; then
    printf '🛑 O freio esta puxado — nao vou mexer em nada. Pra soltar: /norte-box:freio soltar\n'
    return 1
  fi
  return 0
}
