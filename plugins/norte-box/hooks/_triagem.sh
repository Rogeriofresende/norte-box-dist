#!/usr/bin/env bash
# _triagem.sh — A "TRIAGEM DO PEDIDO" do norte-box refeita pra NUNCA CRAVAR o tipo (NRT-_990484,
# conversa 746 passo 3). Sourceada por bin/nb-triagem (e por qualquer hook/skill que, ANTES de agir,
# queira ler o pedido do CEO e dar UMA sugestao-a-confirmar do que ele parece pedir).
#
# O BURACO QUE ESTA PECA FECHA (por que a versao velha morreu 3x): a triagem velha tentava NOMEAR o
# tipo da tarefa (vai-pro-mundo / mexe-arquivo / so-consulta) por lista de palavras e AFIRMAVA com
# certeza ("Entendi como: publicar"). Ela errava a NEGACAO: "nao publica" -> ela via a palavra
# "publicar" e classificava como publicar, invertendo a intencao CALADA. Um palpite errado, afirmado
# como certeza, vira uma inversao silenciosa da vontade do CEO — o erro mais caro. O Val reprovou 3x
# por essa falsa confianca.
#
# O DESENHO NOVO (a chave e uma so: NUNCA cravar). Detectar o tipo passa a ser um PALPITE best-effort,
# JAMAIS uma afirmacao. A peca reusa o FORMATO da peca "quando trava, pergunta" (0.3.9):
#   1) UMA linha de padaria com o palpite marcado como palpite: "isso me parece <tipo> — confirma?"
#      (nunca "Entendi como X", nunca "E do tipo X", nunca "Vou tratar como X").
#   2) 2-3 opcoes concretas: (1) sim  (2) nao, e outro  (3) nao sei — pergunte antes de agir.
#   3) Um DEFAULT SEGURO que PARA/pergunta — sem resposta = perguntar/parar, NUNCA prosseguir no palpite.
#
# POR QUE ISSO CONSERTA A NEGACAO: como a peca nunca crava, ERRAR o palpite e ACEITAVEL (e sugestao). Se
# o palpite de "nao publica" saisse como "publicar", isso vira uma PERGUNTA que o CEO corrige com um
# clique — nao uma inversao calada. O que a peca NAO pode fazer e AFIRMAR o tipo. (Ainda assim ela tenta
# ler a negacao: quando ve "nao/para de/chega de/proibido/evita/nem ...", o palpite ja nasce marcado
# como "parece que voce NAO quer" — mas continua sendo palpite-a-confirmar, nunca certeza.)
#
# MOLDURA HONESTA (nao overclaim):
#   - A peca so PALPITA o tipo por pistas de texto e MONTA a sugestao. Ela NAO decide, NAO age, NAO
#     classifica com certeza. O tipo detectado e um chute a confirmar — errar e ok, cravar nao.
#   - Nao substitui o julgamento do CEO: a ultima palavra e sempre dele (as opcoes + o default garantem).
#
# LEIS (nao-negociaveis, iguais aos outros passos):
#   - LOCAL, ZERO REDE: so monta texto e ecoa no stdout. NUNCA sai da maquina, nada de telemetria/rede.
#   - FAIL-OPEN: kill-switch NORTE_TRIAGEM=0 -> INERTE (nada no stdout, exit 0), o fluxo segue como antes.
#     Pedido vazio / so-espacos tambem nao trava: sem palpite util, ecoa uma sugestao neutra "nao sei o
#     tipo — me confirma?" (nunca inventa um tipo com certeza) e exit 0.
#   - DADO E DADO, NUNCA COMANDO: o pedido do CEO e TEXTO que entra na sugestao — NUNCA e executado/eval.
#     `set -u`, sem eval, sem expandir o pedido como shell. Payload de shell no pedido vira texto (e e
#     saneado por linha). Comparacoes de palavra sao case-insensitive via minusculizacao por `tr`, sem
#     ${v^^} (bash 3.2).
#   - Portabilidade macOS (bash 3.2, SEM arrays associativos/mapfile/${v^^}). Sem jq obrigatorio.
#
# KILL-SWITCH do mecanismo: NORTE_TRIAGEM=0 -> a peca fica INERTE (nao emite sugestao), fail-open (exit
# 0, nada no stdout). Vazio/1/qualquer-outra-coisa = ligado.
set -u

# --- kill-switch: NORTE_TRIAGEM=0 -> inerte (nao emite sugestao). ---
_nbt_desligado() {
  case "${NORTE_TRIAGEM:-1}" in
    0|no|nao|off|false) return 0 ;;
    *) return 1 ;;
  esac
}

# _nbt_1linha <texto> — reduz um texto a UMA linha segura: tira \r, troca quebras de linha por espaco e
# corta em ~200 chars. DADO E DADO: neutraliza multi-linha/CRLF vindos do pedido antes de ele entrar na
# sugestao. Nunca executa nada.
_nbt_1linha() {
  local _t="${1:-}"
  printf '%s' "$_t" | tr -d '\r' | tr '\n' ' ' | cut -c1-200
}

# _nbt_lower <texto> — minuscula, sem ${v^^} (bash 3.2). So pra COMPARAR pistas (o texto mostrado ao CEO
# continua o original). tr cobre ascii; acentos ficam como estao (as pistas sao ascii de proposito).
_nbt_lower() {
  printf '%s' "${1:-}" | tr 'A-Z' 'a-z'
}

# _nbt_tem <agulha> <palheiro-ja-minusculo> — 0 se a agulha (ja minuscula) aparece no palheiro. Usa case
# glob (sem regex, sem grep), seguro com `set -u`. NUNCA executa o conteudo.
_nbt_tem() {
  local _needle="${1:-}" _hay="${2:-}"
  case "$_hay" in
    *"$_needle"*) return 0 ;;
    *) return 1 ;;
  esac
}

# _nbt_palpite_tipo <pedido-minusculo> — devolve o PALPITE do tipo (best-effort, NUNCA certeza). Ecoa
# uma das etiquetas: "publicar" (vai pro mundo) / "apagar-ou-mexer" (mexe arquivo) / "consultar" (so
# leitura) / "" (nao sei). E so um chute por pista de texto — quem confirma e o CEO.
_nbt_palpite_tipo() {
  local _p="${1:-}"
  # vai-pro-mundo (publicar/postar/enviar/subir pro mundo)
  if _nbt_tem "public" "$_p" || _nbt_tem "post" "$_p" || _nbt_tem "envi" "$_p" \
     || _nbt_tem "pro mundo" "$_p" || _nbt_tem "no ar" "$_p" || _nbt_tem "instagram" "$_p"; then
    printf 'publicar'
    return 0
  fi
  # mexe-arquivo (apagar/deletar/remover/mover/renomear/gravar)
  if _nbt_tem "apag" "$_p" || _nbt_tem "delet" "$_p" || _nbt_tem "remov" "$_p" \
     || _nbt_tem "mover" "$_p" || _nbt_tem "renome" "$_p" || _nbt_tem "grav" "$_p"; then
    printf 'apagar-ou-mexer'
    return 0
  fi
  # so-consulta (quanto/quantos/mostra/lista/ver/consulta/qual)
  if _nbt_tem "quant" "$_p" || _nbt_tem "mostr" "$_p" || _nbt_tem "list" "$_p" \
     || _nbt_tem "consult" "$_p" || _nbt_tem "qual" "$_p" || _nbt_tem "ver " "$_p"; then
    printf 'consultar'
    return 0
  fi
  printf ''   # nao sei
}

# _nbt_frase_tipo <etiqueta> — a frase de padaria pro palpite. Sempre em tom de PALPITE, com o "por que"
# entre parenteses. NUNCA afirma.
_nbt_frase_tipo() {
  case "${1:-}" in
    publicar)        printf 'publicar (mandar pro mundo — sai da maquina, quem ve e outra gente)' ;;
    apagar-ou-mexer) printf 'apagar ou mexer num arquivo (muda algo no disco — pode ser dificil de desfazer)' ;;
    consultar)       printf 'so consultar (ler/mostrar um numero, sem mudar nada)' ;;
    *)               printf 'algo que eu ainda nao consegui adivinhar o tipo' ;;
  esac
}

# _nbt_nega <pedido-minusculo> — 0 se o pedido tem cara de NEGACAO/proibicao (o caso que matou a versao
# velha). So influencia o TOM do palpite ("parece que voce NAO quer ...") — NUNCA vira certeza.
_nbt_nega() {
  local _p="${1:-}"
  _nbt_tem "nao " "$_p" || _nbt_tem "não " "$_p" || _nbt_tem "para de " "$_p" \
    || _nbt_tem "pare de " "$_p" || _nbt_tem "chega de " "$_p" || _nbt_tem "proibid" "$_p" \
    || _nbt_tem "evit" "$_p" || _nbt_tem "nem " "$_p" || _nbt_tem "nunca " "$_p"
}

# _nbt_condicional <pedido-minusculo> — 0 se tem cara de DUVIDA/condicional ("talvez", "se der", "acho
# que"). So influencia o TOM — reforca que e palpite.
_nbt_condicional() {
  local _p="${1:-}"
  _nbt_tem "talvez" "$_p" || _nbt_tem "quem sabe" "$_p" || _nbt_tem "se der" "$_p" \
    || _nbt_tem "acho que" "$_p" || _nbt_tem "sera que" "$_p" || _nbt_tem "será que" "$_p"
}

# _norte_triar <pedido> — o CORACAO da peca. Recebe o pedido do CEO (texto) e monta UMA sugestao-a-
# confirmar. NUNCA crava. SEMPRE exit 0 (fail-open).
#   kill-switch NORTE_TRIAGEM=0 -> inerte: nada no stdout, exit 0.
#   qualquer pedido (ate vazio) -> uma sugestao com palpite marcado como palpite + opcoes + default PARA.
_norte_triar() {
  local _raw _p _low _tipo _fr _tom

  if _nbt_desligado; then
    return 0   # inerte: nada no stdout (o fluxo segue como antes, sem a triagem).
  fi

  _raw="$(_nbt_1linha "${1:-}")"
  _low="$(_nbt_lower "$_raw")"
  _tipo="$(_nbt_palpite_tipo "$_low")"
  _fr="$(_nbt_frase_tipo "$_tipo")"

  # TOM do palpite (nunca certeza). Negacao/condicional so mudam a frase pra deixar CLARO que e chute.
  _tom=''
  if _nbt_nega "$_low"; then
    _tom=' (mas parece que voce talvez NAO queira isso — eu posso estar lendo errado)'
  elif _nbt_condicional "$_low"; then
    _tom=' (voce parece em duvida — por isso nao vou assumir nada)'
  fi

  # parte 1 — o palpite SEMPRE como "me parece ... — confirma?" (jamais "Entendi como X").
  printf '🟡 Antes de agir, deixa eu confirmar o que voce quer.\n'
  printf 'Isso me parece %s%s — confirma?\n' "$_fr" "$_tom"
  # parte 2 — 2-3 opcoes concretas.
  printf '  1) Sim, e isso mesmo — pode seguir.\n'
  printf '  2) Nao, e outro tipo de coisa — eu te digo qual.\n'
  printf '  3) Nao sei / na duvida — pergunte antes de agir.\n'
  # parte 3 — DEFAULT seguro que PARA/pergunta (nunca prossegue no palpite).
  printf 'DEFAULT (se voce nao responder): [perguntar e esperar voce] — NAO sigo no meu palpite, NAO assumo o tipo sozinho.\n'
  return 0
}
