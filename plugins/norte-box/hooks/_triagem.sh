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
# O FREIO DE SILENCIO (NRT-_990148, conversa 746, regra literal do CEO): "a triagem so fala quando o
# pedido e RISCO REAL (publicar / apagar / mexer) e fica CALADA em consulta / oi / follow-up". Antes a
# peca abria a boca em TODO pedido — inclusive "oi", "quantos leads temos" e follow-ups — virando atrito
# a toa (o CEO odeia perguntar sem motivo). Agora o palpite do tipo VIRA a chave do freio:
#   - tipo ∈ {publicar, apagar-ou-mexer}  -> RISCO REAL: a peca FALA (o bloco de confirmacao abaixo).
#   - tipo = consultar  OU  "" (nao sei / oi / saudacao / follow-up / ambiguo) -> SILENCIO TOTAL
#     (nada no stdout, exit 0). Consultar so LE (nao muda nada); "nao sei" nao e risco provado -> calar.
#   Errar pro lado do silencio e o barato (o CEO nao sente atrito); so ABRE a boca com sinal de risco.
#
# O DESENHO NOVO (a chave e uma so: NUNCA cravar). Detectar o tipo passa a ser um PALPITE best-effort,
# JAMAIS uma afirmacao. QUANDO FALA (so em risco), a peca reusa o FORMATO da peca "quando trava,
# pergunta" (0.3.9):
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
#     Pedido vazio / so-espacos / "oi" / consulta tambem nao trava: sem sinal de RISCO, a peca CALA
#     (nada no stdout, exit 0) — o freio de silencio. So risco (publicar/apagar-ou-mexer) abre a boca.
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

# _nbt_entre <verbo> <ancora> <palheiro-ja-minusculo> — 0 se o palheiro tem "<verbo> ... <ancora>" com um
# OBJETO no MEIO (ate 40 chars de gap). Fecha o furo do Val (NRT-_990148, conversa 746): risco com objeto
# entre o verbo e a palavra-ancora escapava calado porque _nbt_tem so acha string CONTIGUA — "poe online"
# grudado nao existe em "poe ISSO online". Aqui o verbo e a ancora podem estar separados por um objeto
# curto ("isso", "o site", "esse arquivo"). O teto de 40 chars evita casar verbo+ancora acidentais numa
# frase longa e nao-relacionada. bash 3.2: sem regex, so case-glob + expansao de parametro. Nunca executa.
_nbt_entre() {
  local _v="${1:-}" _a="${2:-}" _p="${3:-}"
  case "$_p" in
    *"$_v"*"$_a"*)
      local _resto="${_p#*"$_v"}"      # tudo depois da 1a ocorrencia do verbo
      local _ate="${_resto%%"$_a"*}"   # o que fica entre o verbo e a 1a ancora seguinte (o "objeto")
      [ "${#_ate}" -le 40 ] && return 0 || return 1 ;;
    *) return 1 ;;
  esac
}

# _nbt_e_pergunta <pedido-ja-minusculo> — 0 (verdadeiro) se o pedido, apos tirar espacos finais, TERMINA
# em "?" — a regra literal do CEO (NRT-_990148, conversa 746): "fica calada quando e pergunta — frase
# termina em interrogacao". Perguntas que so CITAM o assunto de risco ("quanto custou o deploy?", "sera
# que publico hoje?", "o servico esta no ar?") vazavam porque a peca casava o substantivo de risco ANTES
# de olhar se era consulta — atrito a toa que o CEO mandou eliminar. Esta checagem entra ANTES da
# classificacao de risco em _norte_triar: se e pergunta -> CALA.
# NAO ha excecao de "ordem": uma ordem de risco REAL vem imperativa e SEM "?" (ex.: "apaga o arquivo"),
# entao nunca cai aqui — segue direto pra classificacao e FALA. Na duvida entre pergunta e ordem, o CEO
# mandou ERRAR PRO SILENCIO (silencio e o lado barato). TRADE-OFF ASSUMIDO (o CEO pediu pra reportar, nao
# esconder): um risco escrito como pergunta ("apaga o banco?", "publico isso?") vai CALAR. E raro (risco
# de verdade vem imperativo, sem "?") e o preco de zerar o atrito das perguntas legitimas.
_nbt_e_pergunta() {
  local _t="${1:-}"
  # tira espacos/tab finais (sed, portavel macOS bash 3.2). NAO executa o conteudo — so limpa a cauda.
  _t="$(printf '%s' "$_t" | sed 's/[[:space:]]*$//')"
  case "$_t" in
    *'?') return 0 ;;
    *) return 1 ;;
  esac
}

# _nbt_palpite_tipo <pedido-minusculo> — devolve o PALPITE do tipo (best-effort, NUNCA certeza). Ecoa
# uma das etiquetas: "publicar" (vai pro mundo) / "apagar-ou-mexer" (mexe arquivo) / "consultar" (so
# leitura) / "" (nao sei). E so um chute por pista de texto — quem confirma e o CEO.
_nbt_palpite_tipo() {
  local _p="${1:-}"
  # vai-pro-mundo (publicar/postar/enviar/subir/deploy/commit-push/newsletter/producao).
  # LISTA ENGORDADA (NRT-_990148, conversa 746, red-team do Val): a lista curta deixava passar CALADO
  # pedido de risco escrito com outra palavra ("sobe pro ar", "faz o deploy", "dispara a newsletter").
  # Radicais mirados no VERBO DE ACAO — ex.: "manda pra"/"manda o " (nao o bare "manda", que aparece em
  # "manda ver os numeros" = consulta) e "sobe pro"/"sobe pra" (nao o bare "sobe", que aparece em
  # "que horas sobe o relatorio?" = consulta). Assim engorda o alcance SEM disparar em consulta/oi.
  if _nbt_tem "public" "$_p" || _nbt_tem "post" "$_p" || _nbt_tem "envi" "$_p" \
     || _nbt_tem "pro mundo" "$_p" || _nbt_tem "no ar" "$_p" || _nbt_tem "instagram" "$_p" \
     || _nbt_tem "deploy" "$_p" || _nbt_tem "producao" "$_p" || _nbt_tem "produção" "$_p" \
     || _nbt_tem "commit e push" "$_p" || _nbt_tem "faz o commit" "$_p" || _nbt_tem "commita" "$_p" \
     || _nbt_tem "git push" "$_p" || _nbt_tem " push " "$_p" || _nbt_tem "push pra" "$_p" \
     || _nbt_tem "newsletter" "$_p" \
     || _nbt_tem "coloca online" "$_p" || _nbt_tem "poe online" "$_p" || _nbt_tem "deixa online" "$_p" \
     || _nbt_tem "sobe pro" "$_p" || _nbt_tem "sobe pra" "$_p" || _nbt_tem "sobe o site" "$_p" \
     || _nbt_tem "sobe isso" "$_p" || _nbt_tem "sobe a " "$_p" \
     || _nbt_tem "subir pro" "$_p" || _nbt_tem "subir pra" "$_p" \
     || _nbt_tem "dispara" "$_p" || _nbt_tem "dispare" "$_p" || _nbt_tem "disparar" "$_p" \
     || _nbt_tem "manda pra" "$_p" || _nbt_tem "manda pro" "$_p" || _nbt_tem "mandar pra" "$_p" \
     || _nbt_tem "manda o " "$_p" || _nbt_tem "manda a " "$_p" || _nbt_tem "manda isso" "$_p" \
     || _nbt_tem "manda esse" "$_p" || _nbt_tem "manda essa" "$_p" \
     || _nbt_tem "joga no site" "$_p" || _nbt_tem "joga no ar" "$_p" || _nbt_tem "joga pro ar" "$_p" \
     || _nbt_entre "poe " "online" "$_p" || _nbt_entre "põe " "online" "$_p" \
     || _nbt_entre "coloca " "online" "$_p" || _nbt_entre "deixa " "online" "$_p" \
     || _nbt_entre "poe " "no ar" "$_p" || _nbt_entre "põe " "no ar" "$_p" \
     || _nbt_entre "coloca " "no ar" "$_p" || _nbt_entre "deixa " "no ar" "$_p" \
     || _nbt_entre "poe " "pro ar" "$_p" || _nbt_entre "põe " "pro ar" "$_p" \
     || _nbt_entre "coloca " "pro ar" "$_p" || _nbt_entre "deixa " "pro ar" "$_p"; then
    printf 'publicar'
    return 0
  fi
  # mexe-arquivo (apagar/deletar/remover/mover/renomear/gravar + limpar/zerar/sobrescrever/revogar/
  # dropar/truncar/formatar/derrubar/matar-processo/resetar/rm). LISTA ENGORDADA (mesma origem).
  # Radicais que poderiam pegar consulta ficam colados ao objeto de acao ("tira esse"/"limpa a",
  # nao o bare "tira"/"limpa" que aparecem em "tirar duvida"/"limpo de bugs?"). "reset"/"trunc" ficam
  # bare de proposito (pegam reseta/resetar/trunca/truncar) — nao aparecem em consulta plausivel.
  if _nbt_tem "apag" "$_p" || _nbt_tem "delet" "$_p" || _nbt_tem "remov" "$_p" \
     || _nbt_tem "mover" "$_p" || _nbt_tem "renome" "$_p" || _nbt_tem "grav" "$_p" \
     || _nbt_tem "tira esse" "$_p" || _nbt_tem "tira essa" "$_p" || _nbt_tem "tira o " "$_p" \
     || _nbt_tem "tira a " "$_p" || _nbt_tem "tira aquele" "$_p" \
     || _nbt_tem "tirar esse" "$_p" || _nbt_tem "tirar essa" "$_p" || _nbt_tem "tirar o " "$_p" \
     || _nbt_tem "tirar a " "$_p" \
     || _nbt_tem "limpa a" "$_p" || _nbt_tem "limpa o" "$_p" || _nbt_tem "limpa essa" "$_p" \
     || _nbt_tem "limpa esse" "$_p" || _nbt_tem "limpar a" "$_p" || _nbt_tem "limpar o" "$_p" \
     || _nbt_tem "zera" "$_p" || _nbt_tem "zerar" "$_p" \
     || _nbt_tem "sobrescrev" "$_p" \
     || _nbt_tem "troca o conteud" "$_p" || _nbt_tem "troca esse conteud" "$_p" \
     || _nbt_tem "troca essa conteud" "$_p" \
     || _nbt_tem "revoga" "$_p" || _nbt_tem "revogar" "$_p" \
     || _nbt_tem "dropa" "$_p" || _nbt_tem " drop " "$_p" || _nbt_tem " drop-" "$_p" \
     || _nbt_tem "faz drop" "$_p" || _nbt_tem "trunc" "$_p" \
     || _nbt_tem "formata o" "$_p" || _nbt_tem "formata a" "$_p" || _nbt_tem "formatar" "$_p" \
     || _nbt_tem "derruba" "$_p" || _nbt_tem "derrubar" "$_p" \
     || _nbt_tem "mata o process" "$_p" || _nbt_tem "matar o process" "$_p" \
     || _nbt_tem "mata o servico" "$_p" || _nbt_tem "mata a instancia" "$_p" \
     || _nbt_tem "reset" "$_p" \
     || _nbt_tem "rm " "$_p" || _nbt_tem "rm-" "$_p" || _nbt_tem "rm." "$_p" \
     || _nbt_tem "rm dessa" "$_p" || _nbt_tem "rm nessa" "$_p" \
     || _nbt_entre "move " "arquivo" "$_p" || _nbt_entre "mova " "arquivo" "$_p" || _nbt_entre "mover " "arquivo" "$_p" \
     || _nbt_entre "tira " "arquivo" "$_p" || _nbt_entre "tire " "arquivo" "$_p" || _nbt_entre "tirar " "arquivo" "$_p" \
     || _nbt_entre "remove " "arquivo" "$_p" || _nbt_entre "remova " "arquivo" "$_p" || _nbt_entre "remover " "arquivo" "$_p" \
     || _nbt_entre "move " "pasta" "$_p" || _nbt_entre "mova " "pasta" "$_p" \
     || _nbt_entre "tira " "pasta" "$_p" || _nbt_entre "tire " "pasta" "$_p" || _nbt_entre "tirar " "pasta" "$_p" \
     || _nbt_entre "remove " "pasta" "$_p" || _nbt_entre "remova " "pasta" "$_p" || _nbt_entre "remover " "pasta" "$_p" \
     || _nbt_entre "move " "isso" "$_p" || _nbt_entre "mova " "isso" "$_p" \
     || _nbt_entre "tira " "isso" "$_p" || _nbt_entre "remove " "isso" "$_p"; then
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

# _nbt_e_risco <etiqueta> — a CHAVE do freio de silencio (NRT-_990148). 0 (verdadeiro) se o tipo
# palpitado e RISCO REAL — aquilo que o CEO mandou a peca FALAR: publicar (vai pro mundo) ou
# apagar-ou-mexer (muda o disco). 1 (falso) pra consultar (so leitura) e pra "" (nao sei / oi /
# saudacao / follow-up / ambiguo) — nesses a peca CALA. So um palpite vira gatilho, nunca certeza.
_nbt_e_risco() {
  case "${1:-}" in
    publicar|apagar-ou-mexer) return 0 ;;   # RISCO REAL -> FALA
    *)                        return 1 ;;   # consultar / nao-sei -> SILENCIO
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

# _norte_triar <pedido> — o CORACAO da peca. Recebe o pedido do CEO (texto) e, SO EM RISCO REAL, monta
# UMA sugestao-a-confirmar. NUNCA crava. SEMPRE exit 0 (fail-open).
#   kill-switch NORTE_TRIAGEM=0 -> inerte: nada no stdout, exit 0.
#   FREIO DE SILENCIO (NRT-_990148): tipo consultar / "" (oi/saudacao/follow-up/ambiguo) -> CALA
#     (nada no stdout, exit 0). So tipo publicar/apagar-ou-mexer -> FALA (palpite + opcoes + default PARA).
_norte_triar() {
  local _raw _p _low _tipo _fr _tom

  if _nbt_desligado; then
    return 0   # inerte: nada no stdout (o fluxo segue como antes, sem a triagem).
  fi

  _raw="$(_nbt_1linha "${1:-}")"
  _low="$(_nbt_lower "$_raw")"

  # DETECTOR DE PERGUNTA (NRT-_990148, conversa 746, regra literal do CEO) — ANTES da classificacao de
  # risco. Se o pedido termina em "?" -> e PERGUNTA -> CALA, mesmo que cite um assunto de risco. Isso mata
  # o atrito das consultas que so NOMEIAM o risco ("quanto custou o deploy?", "sera que publico hoje?",
  # "o servico esta no ar?") e que antes disparavam porque a peca casava o substantivo antes de ver o "?".
  # Ordem de risco REAL vem imperativa SEM "?" -> nao cai aqui -> segue e FALA. Na duvida, silencio (barato).
  if _nbt_e_pergunta "$_low"; then
    return 0   # pergunta -> calada: nada no stdout, exit 0 (o freio de silencio, no lado barato).
  fi

  _tipo="$(_nbt_palpite_tipo "$_low")"

  # FREIO DE SILENCIO: so abre a boca em RISCO REAL (publicar / apagar-ou-mexer). Consulta, "oi",
  # follow-up e qualquer coisa que a peca nao conseguiu ler como risco -> CALA (stdout vazio, exit 0).
  # Errar pro lado do silencio e o barato; so o sinal de risco justifica interromper o CEO.
  if ! _nbt_e_risco "$_tipo"; then
    return 0   # calada: nao e risco -> nada no stdout, fluxo segue sem atrito.
  fi

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
