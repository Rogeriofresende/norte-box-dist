#!/usr/bin/env bash
# _quando_trava.sh — O FREIO "QUANDO TRAVA, PERGUNTA EM VEZ DE CHUTAR" do norte-box (NRT-_990484).
# Sourceado pelo helper bin/nb-perguntar (e por qualquer hook/skill que precise, no MEIO de uma
# execucao, avisar que bateu numa parede em vez de seguir no palpite).
#
# O BURACO QUE ESTA PECA FECHA: a IA esta no meio de uma tarefa, bate numa parede — falta um DADO que
# a acao ia usar, OU um comando ja falhou 2 vezes seguidas — e, em vez de PARAR, ela CHUTA (inventa o
# dado que falta, ou tenta um caminho novo por conta propria, as vezes irreversivel). Chute no meio da
# execucao e como o erro mais caro que existe. Esta peca poe um freio ali: quando ha parede, monta UMA
# pergunta no FORMATO PADRAO e PARA — a ultima palavra volta pra pessoa.
#
# A RECEITA (por que o FORMATO e fixo e nao um texto livre do LLM): um estudo de campo (STaR-GATE)
# mostrou que os modelos, por padrao, perguntam MAL — vago, sem opcoes, empurrando a propria aposta.
# Entao a gente NAO deixa o LLM improvisar a pergunta: PADRONIZA o formato. A pergunta e SEMPRE:
#   1) UMA linha de padaria (linguagem simples, sem jargao) dizendo o que travou.
#   2) 2 a 3 opcoes concretas de caminho.
#   3) Um DEFAULT SEGURO que PARA — nunca chuta, nunca escolhe sozinho um caminho irreversivel. O
#      default e sempre "parar e esperar a pessoa", jamais "seguir no palpite".
#
# MOLDURA HONESTA (nao overclaim):
#   - A peca so DETECTA a parede pelo sinal que voce passa (falta-dado / comando-falhou-Nx) e MONTA a
#     pergunta. Ela NAO adivinha o dado, NAO tenta o comando de novo, NAO decide o caminho.
#   - O comando so vira parede a partir de 2 falhas SEGUIDAS. 1 falha = ainda nao pergunta (pode ter
#     sido tropeco; barulho de mais atrapalha mais que ajuda).
#   - E um FREIO pra PERGUNTAR, nunca uma licenca pra executar sozinho. O default sempre PARA.
#
# LEIS (nao-negociaveis, iguais aos outros passos):
#   - LOCAL, ZERO REDE: so monta texto e ecoa no stdout. NUNCA sai da maquina, nada de telemetria/rede.
#   - FAIL-OPEN: com o kill-switch NORTE_PERGUNTA=0 a peca fica INERTE (nada no stdout, exit 0) e o
#     fluxo segue exatamente como antes desta peca existir. Sinal desconhecido / faltando argumento
#     tambem nao trava: ecoa nada e exit 0 (quem chamou segue sem a pergunta).
#   - DADO E DADO, NUNCA COMANDO: o nome do dado, o comando que falhou e o texto de erro sao TEXTO que
#     entra na pergunta — NUNCA sao executados/eval. `set -u`, sem eval, sem expandir valor como shell.
#     Um payload de shell dentro de qualquer argumento NAO executa; vira texto (e ate saneado por linha).
#   - Portabilidade macOS (bash 3.2, SEM arrays associativos/mapfile/${v^^}). Sem jq obrigatorio.
#
# KILL-SWITCH do mecanismo: NORTE_PERGUNTA=0 -> a peca fica INERTE (nao emite pergunta), fail-open
# (exit 0, nada no stdout). Vazio/1/qualquer-outra-coisa = ligado.
set -u

# --- kill-switch: NORTE_PERGUNTA=0 -> inerte (nao emite pergunta). ---
_nbp_desligado() {
  case "${NORTE_PERGUNTA:-1}" in
    0|no|nao|off|false) return 0 ;;
    *) return 1 ;;
  esac
}

# _nbp_int <valor> <default> — ecoa o inteiro valido (so digitos) ou o default. Imita _nbv_int do
# bilhete-validade: env com lixo cai no default, nunca quebra.
_nbp_int() {
  local _v="${1:-}" _d="${2:-}"
  case "$_v" in
    ''|*[!0-9]*) printf '%s' "$_d" ;;
    *) printf '%s' "$_v" ;;
  esac
}

# _nbp_1linha <texto> — reduz um texto a UMA linha segura: tira \r, troca quebras de linha por espaco
# e corta em ~200 chars. DADO E DADO: isto neutraliza multi-linha/CRLF vindos de um argumento nao-
# confiavel antes de ele entrar na pergunta. Nunca executa nada.
_nbp_1linha() {
  local _t="${1:-}"
  # tr: \r some, \n vira espaco. cut: no maximo 200 bytes (evita despejar um erro gigante na cara).
  printf '%s' "$_t" | tr -d '\r' | tr '\n' ' ' | cut -c1-200
}

# _nbp_falta_dado <nome-do-dado> [<contexto>] — monta a pergunta padrao pro caso "falta um DADO que a
# acao ia usar". SEMPRE as 3 partes: 1 linha de padaria + 2-3 opcoes + default que PARA. exit 0.
#   parte 1: "Travei: pra seguir eu preciso de <dado>, e ele nao veio."
#   parte 2: opcoes concretas (voce me passa agora / usamos um valor combinado / paro aqui).
#   parte 3: DEFAULT = [parar e esperar voce] — nunca inventa o dado, nunca chuta.
_nbp_falta_dado() {
  local _dado _ctx _dado_l _ctx_l
  _dado="$(_nbp_1linha "${1:-}")"
  _ctx="$(_nbp_1linha "${2:-}")"
  [ -n "$_dado" ] || _dado="um dado que a acao ia usar"

  printf '🟡 Travei: pra seguir eu preciso de "%s", e ele nao veio.' "$_dado"
  if [ -n "$_ctx" ]; then
    printf ' (%s)' "$_ctx"
  fi
  printf '\n'
  printf 'O que voce quer fazer?\n'
  printf '  1) Voce me passa "%s" agora, e eu sigo com o valor certo.\n' "$_dado"
  printf '  2) A gente combina um valor pra usar no lugar (voce me diz qual) e eu sigo com esse.\n'
  printf '  3) Paro por aqui e deixo pra depois.\n'
  printf 'DEFAULT (o que faco se voce nao responder): [parar e esperar voce] — NAO invento "%s" nem sigo no chute.\n' "$_dado"
  return 0
}

# _nbp_comando_falhou <comando> <n-falhas> [<ultimo-erro>] — monta a pergunta padrao pro caso "um
# comando falhou N vezes SEGUIDAS". So DISPARA com n >= 2 (limiar por env NB_PERGUNTA_FALHAS, default
# 2). Com n < 2 -> SILENCIO (ecoa nada, exit 0): ainda nao e parede, pode ter sido tropeco.
# Quando dispara, SEMPRE as 3 partes: 1 linha + 2-3 opcoes + default que PARA. exit 0.
_nbp_comando_falhou() {
  local _cmd _n _err _cmd_l _err_l _lim
  _cmd="$(_nbp_1linha "${1:-}")"
  _n="$(_nbp_int "${2:-}" 0)"
  _err="$(_nbp_1linha "${3:-}")"
  _lim="$(_nbp_int "${NB_PERGUNTA_FALHAS:-}" 2)"
  [ -n "$_cmd" ] || _cmd="o comando"

  # abaixo do limiar (default 2) -> ainda nao e parede: silencio total (fail-open, quem chamou segue).
  if [ "$_n" -lt "$_lim" ]; then
    return 0
  fi

  printf '🟡 Travei: "%s" ja falhou %s vezes seguidas.' "$_cmd" "$_n"
  if [ -n "$_err" ]; then
    printf ' Ultimo erro: %s.' "$_err"
  fi
  printf '\n'
  printf 'Nao vou ficar tentando no chute. O que voce quer fazer?\n'
  printf '  1) Voce olha o erro comigo e me diz o que corrigir, ai eu tento de novo.\n'
  printf '  2) A gente tenta um caminho diferente (voce me diz qual) em vez de insistir nesse.\n'
  printf '  3) Paro por aqui e deixo pra depois.\n'
  printf 'DEFAULT (o que faco se voce nao responder): [parar e esperar voce] — NAO insisto sozinho nem tento um atalho por conta propria.\n'
  return 0
}

# _norte_quando_trava <sinal> [args...] — o CORACAO da peca. Recebe o SINAL da parede e despacha pra o
# montador certo. SEMPRE exit 0 (fail-open: informa/pergunta, nunca trava).
#   kill-switch NORTE_PERGUNTA=0 -> inerte: nada no stdout, exit 0.
#   sinal "falta-dado"     -> _nbp_falta_dado <nome-do-dado> [<contexto>].
#   sinal "comando-falhou" -> _nbp_comando_falhou <comando> <n-falhas> [<ultimo-erro>] (so dispara n>=2).
#   sinal desconhecido / sem sinal -> silencio (ecoa nada, exit 0). Nao inventa parede onde nao ha.
_norte_quando_trava() {
  local _sinal="${1:-}"

  if _nbp_desligado; then
    return 0   # inerte: nada no stdout (o fluxo segue como antes, sem a pergunta).
  fi

  case "$_sinal" in
    falta-dado|falta_dado|dado)
      shift 2>/dev/null || true
      _nbp_falta_dado "${1:-}" "${2:-}"
      ;;
    comando-falhou|comando_falhou|comando|falhou)
      shift 2>/dev/null || true
      _nbp_comando_falhou "${1:-}" "${2:-}" "${3:-}"
      ;;
    *)
      # sinal desconhecido / ausente -> nao ha parede que a peca saiba montar: silencio.
      return 0
      ;;
  esac
  return 0
}
