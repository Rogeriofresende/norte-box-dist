#!/usr/bin/env bash
# _situacao.sh — FONTE UNICA da "fichinha de situacao" do Norte-box (ABRIR SITUANDO + SELO HONESTO).
# Sourceado pelos hooks situacao-gravar (Stop) e situacao-abrir (SessionStart).
#
# A ideia (padaria): quando a pessoa abre a caixa, a 1a coisa que ela ve e um cartao curto —
# "Seu objetivo era X. Da ultima vez entreguei Y — [🟢 PROVADO / 🟡 NAO PROVEI AINDA]. Hoje: continuar
# ou mudar de rumo?". Pra isso a caixa GRAVA uma fichinha no fim de cada sessao (objetivo em
# palavras cruas + o que entregou + provado?sim/nao + proximo sugerido) e LE ela na abertura seguinte.
#
# LEIS (nao-negociaveis):
#   - PRIVADO POR PADRAO: a fichinha e um arquivo LOCAL em $HOME/.norte-box/situacao.json. NUNCA sai
#     da maquina, NUNCA passa por telemetria/rede. Esta lib nao envia nada; so le/escreve o disco local.
#   - HONESTO POR PADRAO (fail-honest): o selo default e 🟡 NAO-PROVADO. So vira 🟢 PROVADO se houver
#     um ARTEFATO de prova real referenciado (campo prova.artefato apontando um arquivo que existe).
#     Como o "motor de prova" (Val de bolso) ainda nao existe, nada fica verde hoje — de proposito.
#   - Portabilidade macOS (bash 3.2). Precisa de jq; sem jq, as funcoes degradam sem travar.
set -u

# Caminho unico da fichinha.
_norte_situacao_path() { printf '%s/.norte-box/situacao.json' "${HOME}"; }

# _norte_realpath <caminho> — ecoa o caminho CANONICO (resolve .., ., symlinks). Usa realpath/grealpath
# se existir; senao cai num fallback portavel (cd no dir + pwd -P + basename). Vazio se o caminho nao
# resolve. Usado pra fechar o furo de path-traversal ($HOME/.../provas/../../../etc/hosts).
_norte_realpath() {
  local _p="${1:-}"; [ -n "$_p" ] || return 1
  if command -v realpath >/dev/null 2>&1; then realpath "$_p" 2>/dev/null && return 0; fi
  if command -v grealpath >/dev/null 2>&1; then grealpath "$_p" 2>/dev/null && return 0; fi
  # fallback bash 3.2: canoniza o DIRETORIO (pwd -P segue symlinks do caminho ate ali) + o basename.
  local _d _b
  _d="$(dirname "$_p" 2>/dev/null)"; _b="$(basename "$_p" 2>/dev/null)"
  _d="$(cd "$_d" 2>/dev/null && pwd -P 2>/dev/null)" || return 1
  [ -n "$_d" ] || return 1
  printf '%s/%s' "$_d" "$_b"
}

# _norte_prova_hash_texto <texto> — ecoa um hash curto e ESTAVEL de uma string. Nao e cripto — so
# precisa distinguir "coisa diferente". shasum -> sha256sum -> cksum. Usado pra hashear o CONTEUDO da
# entrega (o vinculo estavel A3, ver abaixo) e, por retro-compat, o objetivo.
_norte_prova_hash_texto() {
  local _t="${1:-}"
  if command -v shasum >/dev/null 2>&1; then printf '%s' "$_t" | shasum -a 256 2>/dev/null | cut -c1-16; return 0; fi
  if command -v sha256sum >/dev/null 2>&1; then printf '%s' "$_t" | sha256sum 2>/dev/null | cut -c1-16; return 0; fi
  printf '%s' "$_t" | cksum 2>/dev/null | tr -d ' ' | cut -c1-16
}
# Alias retro-compat (o nome antigo era _norte_prova_hash_objetivo). Mantido pra nao quebrar chamadores.
_norte_prova_hash_objetivo() { _norte_prova_hash_texto "$@"; }

# _norte_prova_hash_arquivo <caminho> — ecoa o hash ESTAVEL do CONTEUDO de um arquivo (a "entrega"
# provada). Este e o VINCULO A3 (anti-reuso): a prova carrega o hash do arquivo que o motor RODOU, e a
# fichinha registra o MESMO hash em prova.entrega. Trocar a prova por uma de OUTRA entrega faz os hashes
# divergirem -> amarelo. Nao depende do .objetivo (que fica vazio no meio do turno) — so do que foi
# efetivamente entregue, que o motor tem em mao na hora de provar. Vazio se o arquivo nao existe.
_norte_prova_hash_arquivo() {
  local _p="${1:-}"; [ -n "$_p" ] || return 1; [ -f "$_p" ] || return 1
  if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$_p" 2>/dev/null | cut -c1-16; return 0; fi
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$_p" 2>/dev/null | cut -c1-16; return 0; fi
  cksum "$_p" 2>/dev/null | tr -d ' ' | cut -c1-16
}

# _norte_situacao_tem — 0 se a fichinha existe e e JSON valido; 1 caso contrario.
_norte_situacao_tem() {
  local _f; _f="$(_norte_situacao_path)"
  [ -f "$_f" ] || return 1
  command -v jq >/dev/null 2>&1 || return 1
  jq -e . "$_f" >/dev/null 2>&1
}

# _norte_situacao_campo <chave> — ecoa o valor STRING de uma chave do topo (ex: objetivo, entregou,
# proximo, ultima_atualizacao). Vazio se ausente/nulo. Nunca executa o dado.
_norte_situacao_campo() {
  local _f; _f="$(_norte_situacao_path)"
  _norte_situacao_tem || return 1
  jq -r --arg k "$1" '.[$k] // "" | if type=="string" then . else "" end' "$_f" 2>/dev/null
}

# _norte_situacao_provado — 0 (SIM, verde) SO se TODAS valem:
#   (a) o campo .provado for booleano true.
#   (b) existir .prova.artefato apontando um arquivo que EXISTE no disco (a prova real).
#   (c) o CANONICO desse artefato (realpath, resolve ../ e symlinks) estiver DENTRO de
#       $HOME/.norte-box/provas/ (prova GERADA pelo motor). Mata path-traversal (A1).
#   (d) o artefato NAO for um symlink (A2): symlink dentro de provas/ apontando pra /etc/hosts seguiria
#       o [ -f ]; recusamos symlinks de forma dura.
#   (e) a prova pertencer a ENTREGA REGISTRADA na fichinha (A3, anti-reuso): o motor grava, DENTRO do
#       arquivo de prova, a linha "entrega_hash: <h>" com o hash do CONTEUDO da entrega que ele rodou, e
#       grava o MESMO hash em prova.entrega na fichinha (na mesma escrita atomica do provado:true). O
#       selo le o hash DO ARQUIVO (nao so da fichinha) e exige que bata com prova.entrega. Assim trocar a
#       prova por uma de OUTRA entrega/sessao (hash de conteudo diferente) NAO abre verde. NAO depende do
#       .objetivo (que fica vazio no meio do turno) — so do que foi efetivamente entregue.
#       RETRO-COMPAT: provas antigas so tem "objetivo_hash:" — nesse caso o selo cai no vinculo antigo
#       (bate objetivo_hash com o hash do .objetivo atual), sem afrouxar (na duvida -> amarelo).
# Qualquer outra combinacao -> 1 (NAO, amarelo). Fail-honest: na duvida, amarelo. Aditivo: NUNCA afrouxa.
_norte_situacao_provado() {
  local _f _art _raiz _canon; _f="$(_norte_situacao_path)"
  _norte_situacao_tem || return 1
  jq -e '.provado == true' "$_f" >/dev/null 2>&1 || return 1
  _art="$(jq -r '.prova.artefato // "" | if type=="string" then . else "" end' "$_f" 2>/dev/null)"
  [ -n "$_art" ] || return 1
  # (d) recusa symlink DURO (antes de qualquer [ -f ], que seguiria o link).
  [ -L "$_art" ] && return 1
  [ -f "$_art" ] || return 1
  # (c) canoniza e exige o CANONICO dentro da arvore controlada (mata ../ traversal).
  _raiz="$(_norte_realpath "${HOME}/.norte-box/provas")" || return 1
  [ -n "$_raiz" ] || return 1
  _canon="$(_norte_realpath "$_art")" || return 1
  [ -n "$_canon" ] || return 1
  case "$_canon" in
    "$_raiz"/*) : ;;
    *) return 1 ;;
  esac
  # (e) vinculo A3 — prova pertence a ENTREGA registrada. Preferido: entrega_hash (novo, estavel, nao
  #     depende do objetivo). Fallback retro-compat: objetivo_hash (formato antigo). Um dos dois tem que
  #     casar; sem nenhum carimbo -> amarelo (fail-honest).
  local _he_prova _he_ficha _ho_prova _ho_atual _obj
  _he_prova="$(grep -m1 '^entrega_hash: ' "$_canon" 2>/dev/null | sed 's/^entrega_hash: //')"
  if [ -n "$_he_prova" ]; then
    _he_ficha="$(jq -r '.prova.entrega // "" | if type=="string" then . else "" end' "$_f" 2>/dev/null)"
    [ -n "$_he_ficha" ] || return 1
    [ "$_he_prova" = "$_he_ficha" ] || return 1
    return 0
  fi
  # Fallback (provas antigas): objetivo_hash tem que bater com o hash do .objetivo atual.
  _ho_prova="$(grep -m1 '^objetivo_hash: ' "$_canon" 2>/dev/null | sed 's/^objetivo_hash: //')"
  [ -n "$_ho_prova" ] || return 1
  _obj="$(jq -r '.objetivo // "" | if type=="string" then . else "" end' "$_f" 2>/dev/null)"
  _ho_atual="$(_norte_prova_hash_texto "$_obj")"
  [ -n "$_ho_atual" ] || return 1
  [ "$_ho_prova" = "$_ho_atual" ] || return 1
  return 0
}

# _norte_situacao_objetivo_ok — 2o PORTAO (NRT-_990429): "a entrega RESPONDE ao objetivo?".
# O selo do passo 1 (_norte_situacao_provado) so responde "PROVEI a entrega?" (roda / passa no motor).
# Uma entrega pode estar PROVADA e ainda ser a coisa ERRADA (derivou do que a pessoa pediu). Este portao
# confere MECANICAMENTE se a entrega bate com o objetivo DECLARADO — sem confiar no texto do modelo.
#
# COMO: quando ha objetivo, a caixa registra na fichinha um bloco .objetivo_conferido com:
#   - objetivo_hash: hash do .objetivo que ESTAVA valendo na hora da conferencia (amarra a conferencia
#     a UMA versao do objetivo — se o objetivo muda depois, a conferencia velha nao vale mais);
#   - trecho: um pedaco curto que o agente aponta como "onde a entrega responde ao objetivo";
#   - trecho_encontrado: bool computado MECANICAMENTE (grep -F do trecho DENTRO do artefato de prova
#     real) por quem GRAVA (nunca confia no texto do modelo). Aqui o portao so LE esse bool ja apurado.
#
# CONTRATO (pra o selo compor limpo com o provado):
#   exit 0  = NAO BLOQUEIA o verde. Dois casos, distinguidos pelo texto ecoado:
#             * "ok:<trecho>"       -> o trecho CITADO e REAL (grep -F achou na entrega). ATENCAO: isto NAO
#                                      prova que a entrega RESPONDE ao objetivo — so que o agente nao blefou
#                                      o trecho. Quem confere se o trecho responde ao objetivo e a PESSOA.
#             * "pulado:<motivo>"   -> pulado com nota (kill-switch OU sem objetivo declarado). Honesto:
#                                      ausencia de objetivo NAO derruba o verde; quem manda ai e o provado.
#   exit 1  = BLOQUEIA o verde (AMARELO). Ecoa "amarelo:<motivo>" legivel. Fail-honest: na duvida, amarelo.
#
# LEIS (padrao Norte): LOCAL, so le disco. Fail-OPEN pra sessao (se quebra, nao trava). Fail-CLOSED pro
# verde (na duvida -> amarelo, nunca verde otimista). ADITIVO: nao afrouxa nada do provado/hash existente.
# KILL-SWITCH: NB_OBJETIVO_CHECK=0 -> "pulado:kill-switch" (o selo se comporta como HOJE, exit 0).
# AUSENCIA GRACIOSA (NRT-_990429 fatia 2 — o wiring): objetivo declarado mas SEM bloco objetivo_conferido
#   -> "pulado:sem conferencia registrada ainda" (exit 0, NAO bloqueia o verde). Racional: o 2o portao so
#   pega BLEFE (uma conferencia que EXISTE e FALHA). ABSENCIA de conferencia nao e blefe — e so' o agente
#   que nao citou onde a entrega responde (nem todo turno tem objetivo declarado + citacao). Se a ausencia
#   virasse amarelo, TODA sessao com /objetivo ficaria presa no amarelo ate o writer pegar — disruptivo e
#   sem valor de seguranca (o verde continua vindo do PROVADO, que exige prova de motor real). O 🟡 fica
#   reservado pro que importa: HA um bloco de conferencia e ele NAO bate (trecho ausente = blefe / hash do
#   objetivo mudou). Retro-compat: fichinha ANTIGA (sem objetivo_conferido) tambem cai aqui -> pulada, nunca
#   amarelo retroativo cego.
_norte_situacao_objetivo_ok() {
  # kill-switch: default LIGADO; NB_OBJETIVO_CHECK=0 -> inerte (pulado), o selo fica igual ao de hoje.
  case "${NB_OBJETIVO_CHECK:-1}" in 0|no|nao|off|false) printf 'pulado:kill-switch'; return 0 ;; esac
  command -v jq >/dev/null 2>&1 || { printf 'pulado:sem jq'; return 0; }
  local _f; _f="$(_norte_situacao_path)"
  _norte_situacao_tem || { printf 'pulado:sem fichinha'; return 0; }

  # O 2o portao so' vale pro objetivo DECLARADO por ato explicito (/norte-box:objetivo -> objetivo_declarado:true).
  # O rotulo AUTO da 1a fala (objetivo_declarado:false ou ausente) e um lembrete fraco, NAO o pedido soberano
  # da pessoa — nao faz sentido "conferir a entrega contra um rotulo que a maquina inventou". Sem declaracao
  # -> pulado com nota (nao bloqueia o verde; o provado manda). Isso tambem garante retro-compat total:
  # fichinha ANTIGA (sem o campo objetivo_declarado) NUNCA vira amarelo retroativo cego — fica pulada.
  jq -e '.objetivo_declarado == true' "$_f" >/dev/null 2>&1 \
    || { printf 'pulado:sem objetivo declarado (so o /objetivo liga o 2o portao)'; return 0; }

  # Objetivo atual (o .objetivo cru da fichinha — o mesmo que o cartao mostra).
  local _obj
  _obj="$(jq -r '.objetivo // "" | if type=="string" then . else "" end' "$_f" 2>/dev/null)"
  # Declarado mas com texto vazio (nao devia acontecer) -> pulado com nota (honesto, nao bloqueia).
  [ -n "$_obj" ] || { printf 'pulado:objetivo declarado porem vazio'; return 0; }

  # Ha bloco de conferencia? AUSENCIA GRACIOSA: objetivo declarado mas sem o bloco (o agente nao citou
  # onde a entrega responde, OU e uma fichinha antiga) -> PULADO com nota, NAO amarelo. O amarelo fica so'
  # pra conferencia PRESENTE que FALHA (blefe/hash) — checado abaixo. Assim o /objetivo nao prende no
  # amarelo antes do writer pegar; o verde segue vindo do PROVADO.
  jq -e '.objetivo_conferido | type=="object"' "$_f" >/dev/null 2>&1 \
    || { printf 'pulado:sem conferencia registrada ainda (o agente nao citou onde a entrega responde; o provado manda)'; return 0; }

  local _oh_reg _trecho _tenc _oh_atual
  _oh_reg="$(jq -r '.objetivo_conferido.objetivo_hash // "" | if type=="string" then . else "" end' "$_f" 2>/dev/null)"
  _trecho="$(jq -r '.objetivo_conferido.trecho // "" | if type=="string" then . else "" end' "$_f" 2>/dev/null)"
  _tenc="$(jq -r 'if .objetivo_conferido.trecho_encontrado==true then "1" else "0" end' "$_f" 2>/dev/null)"

  # Objetivo mudou desde a prova? (hash registrado != hash do objetivo atual) -> amarelo.
  _oh_atual="$(_norte_prova_hash_texto "$_obj")"
  [ -n "$_oh_reg" ]   || { printf 'amarelo:conferencia sem hash do objetivo'; return 1; }
  [ -n "$_oh_atual" ] || { printf 'amarelo:nao consegui hashear o objetivo atual'; return 1; }
  [ "$_oh_reg" = "$_oh_atual" ] || { printf 'amarelo:o objetivo mudou desde a ultima conferencia (a entrega foi conferida contra outro objetivo)'; return 1; }

  # Trecho vazio -> amarelo (nao ha o que casar mecanicamente).
  [ -n "$_trecho" ] || { printf 'amarelo:sem trecho citado (nao da pra conferir onde a entrega responde)'; return 1; }

  # trecho_encontrado tem que ser true (computado por grep -F por quem gravou — aqui so lemos o veredito).
  # HONESTO: o grep so prova que o trecho CITADO e real (aparece na entrega). Nao prova que a entrega
  # RESPONDE ao objetivo — so pega o blefe (citou um trecho que nao existe). A copy fala so o que garante.
  [ "$_tenc" = "1" ] || { printf 'amarelo:o trecho citado nao aparece na entrega — pode ser blefe (nao consegui confirmar que ele e real)'; return 1; }

  printf 'ok:%s' "$_trecho"
  return 0
}

# _norte_situacao_objetivo_linha — 1 linha curta de status pra o cartao/situacao (REUSA a funcao acima,
# nao recomputa). "Objetivo conferido: 🟢" quando bate; "🟡 <motivo>" quando diverge; "⚪ <motivo>" quando
# pulado (kill-switch/sem objetivo) — pulado NAO e alarme, so uma nota honesta. Sempre exit 0 (extra do
# cartao, fail-open). Kill-switch NB_OBJETIVO_CHECK=0 vem herdado da _norte_situacao_objetivo_ok.
_norte_situacao_objetivo_linha() {
  local _out _rc _motivo
  _out="$(_norte_situacao_objetivo_ok 2>/dev/null)"; _rc=$?
  case "$_out" in
    ok:*)     printf 'Objetivo conferido: 🟢 o agente citou um trecho REAL da entrega (confira se ele responde ao seu objetivo)' ;;
    pulado:*) _motivo="${_out#pulado:}"; printf 'Objetivo conferido: ⚪ pulado (%s)' "$_motivo" ;;
    amarelo:*) _motivo="${_out#amarelo:}"; printf 'Objetivo conferido: 🟡 %s' "$_motivo" ;;
    *)        printf 'Objetivo conferido: ⚪ pulado (sem informacao)' ;;
  esac
  return 0
}

# _norte_situacao_selo — ecoa a frase do selo, honesta pelo estado real.
# 2 PORTOES (NRT-_990429): so 🟢 se PROVADO (o motor rodou e deu certo) E o objetivo confere (ou foi
# pulado por ausencia/kill-switch). Provado mas objetivo DIVERGE -> 🟡 com o motivo (a entrega roda, mas
# nao e a coisa que a pessoa pediu). ADITIVO: com NB_OBJETIVO_CHECK=0 o 2o portao vira inerte (pulado ->
# exit 0) e o selo fica IDENTICO ao de hoje (so o provado manda).
_norte_situacao_selo() {
  if _norte_situacao_provado; then
    # PROVADO. Agora o 2o portao: objetivo confere? (exit 0 = nao bloqueia; exit 1 = bloqueia com motivo).
    local _oout _orc _omot
    _oout="$(_norte_situacao_objetivo_ok 2>/dev/null)"; _orc=$?
    if [ "$_orc" -eq 0 ]; then
      printf '🟢 PROVADO'
    else
      _omot="${_oout#amarelo:}"
      printf '🟡 NAO-PROVADO (provei que roda, mas nao confirmei o trecho citado do objetivo: %s)' "$_omot"
    fi
  else
    printf '🟡 NAO-PROVADO'
  fi
}

# _norte_situacao_ver_rodar — ecoa a SAIDA REAL capturada pela prova (a secao "---- saida ----" do
# prova.artefato), pronta pra o cartao "▶ Ver rodar" mostrar "a coisa rodando" — nao so o selo.
#
# LEIS (nao-negociaveis, iguais aos outros passos):
#   - FAIL-HONEST: so ecoa algo se HOUVER prova VALIDA. Reusa EXATAMENTE a validacao do selo
#     (_norte_situacao_provado): provado=true + artefato dentro de $HOME/.norte-box/provas/ + nao-symlink
#     + hash bate. Sem prova valida -> ecoa NADA e retorna 1 (o cartao NAO mostra bloco; nao fabrica saida).
#   - SEGURO: le o artefato pelo CANONICO ja validado (o mesmo caminho que o selo aprovou). Nunca le
#     caminho fora da arvore controlada. Se a leitura falhar por qualquer motivo -> nada (fail-honest).
#   - REDACTION OBRIGATORIA: a saida e do TRABALHO do cliente (stdout da entrega dele) — pode ter secret.
#     Passa TUDO pelo _redact ANTES de ecoar. Se o _redact nao estiver disponivel OU falhar -> ecoa NADA
#     (fail-CLOSED na redacao: melhor nao mostrar do que vazar cru).
#   - KILL-SWITCH: NORTE_VER_RODAR=0 desliga (ecoa nada, retorna 1) — fail-open pro comportamento de hoje
#     (so o selo, sem o bloco).
#   - CAP: so as ULTIMAS ~15 linhas / ~1500 chars (a prova pode ser longa; o cartao e curto).
# Retorna 0 se ecoou saida; 1 caso contrario (o chamador so mostra o bloco quando recebe algo).
_norte_situacao_ver_rodar() {
  # kill-switch: default LIGADO; NORTE_VER_RODAR=0 desliga.
  case "${NORTE_VER_RODAR:-1}" in 0|no|nao|off|false) return 1 ;; esac
  # so segue se a prova for VALIDA pelas MESMAS leis do selo (nao reimplementa a validacao).
  _norte_situacao_provado || return 1
  local _f _art _canon _raiz
  _f="$(_norte_situacao_path)"
  _art="$(jq -r '.prova.artefato // "" | if type=="string" then . else "" end' "$_f" 2>/dev/null)"
  [ -n "$_art" ] || return 1
  # re-deriva o CANONICO (o selo ja garantiu symlink+traversal; aqui LEMOS o canonico, defesa em prof.).
  [ -L "$_art" ] && return 1
  [ -f "$_art" ] || return 1
  _raiz="$(_norte_realpath "${HOME}/.norte-box/provas")" || return 1
  [ -n "$_raiz" ] || return 1
  _canon="$(_norte_realpath "$_art")" || return 1
  [ -n "$_canon" ] || return 1
  case "$_canon" in "$_raiz"/*) : ;; *) return 1 ;; esac
  # extrai SO a secao de saida do arquivo de prova: tudo DEPOIS do cabecalho do motor. O cabecalho tem
  # linhas conhecidas (PROVA.../quando:/tipo:/exit:/entrega_hash:) e — QUANDO o printf da marca sobrevive
  # ao runtime — uma linha "---- saida ...". ATENCAO (bug real do motor sob bash, HEAD 011ace6): o
  # printf '---- saida ...' comeca com '--' e o bash trata como opcao invalida -> a marca NAO e escrita.
  # Por isso NAO ancoramos na marca (que pode faltar): ancoramos no FIM do cabecalho — a ultima linha de
  # cabecalho e sempre "entrega_hash:" (ou, em provas antigas, "objetivo_hash:"). Pegamos tudo DEPOIS
  # dela, e se por acaso a linha da marca sobreviveu, ela e pulada tambem. Sem cabecalho reconhecivel ->
  # nada (fail-honest).
  local _bruto
  _bruto="$(awk '
    f { if ($0 ~ /^---- saida/) next; print; next }
    /^(entrega_hash|objetivo_hash): / { f=1; next }
    /^---- saida/ { f=1; next }
  ' "$_canon" 2>/dev/null)"
  [ -n "$_bruto" ] || return 1
  # CAP: ultimas 15 linhas, depois cap de 1500 chars (defesa dupla).
  local _cortado
  _cortado="$(printf '%s\n' "$_bruto" | tail -n 15 2>/dev/null | head -c 1500 2>/dev/null)"
  [ -n "$_cortado" ] || return 1
  # REDACTION OBRIGATORIA (fail-CLOSED): sem _redact disponivel/funcionando -> nao mostra nada.
  command -v _redact >/dev/null 2>&1 || return 1
  local _limpo
  _limpo="$(printf '%s' "$_cortado" | _redact)" || return 1
  [ -n "$_limpo" ] || return 1
  printf '%s' "$_limpo"
  return 0
}

# _norte_situacao_assinatura — ecoa o bloco ✍️ ASSINATURA: 3 carimbos, cada um AMARRADO EM FATO
# (NUNCA texto do agente). E a "assinatura" no rodape do cartao de resposta: quem construiu, se provou,
# e que explicou em padaria.
#
#   • Construi  = arquivo(s) que a entrega criou e que EXISTEM no disco. Fonte honesta mais simples: o
#     prova.artefato (o arquivo que o MOTOR escreveu e que fisicamente existe quando ha prova valida).
#     So conta se a prova for VALIDA pelas MESMAS leis do selo (artefato dentro de provas/, existe,
#     nao-symlink, hash bate). Nesse caso ecoa o TIPO do arquivo (path passado pelo _redact -> "[arquivo:.txt]",
#     nunca o nome cru: LGPD). Sem artefato registrado -> "nenhum arquivo registrado" (honesto, nao inventa).
#   • Provei    = lido DIRETO do estado do motor: 🟢 SO quando _norte_situacao_provado (== provado:true +
#     prova.artefato valido — a MESMA validacao do selo). Sem prova -> 🟡 "nao provei ainda". A LEI: e
#     MECANICO — o texto do corpo do cartao (que o LLM escreve) NAO pode virar 🟢. Se o agente ESCREVER
#     "eu provei" mas o motor NAO marcou provado:true, este carimbo mostra 🟡. Impossivel forjar verde
#     por string livre: nao lemos NENHUM campo de texto aqui pro selo — so o veredito do motor.
#   • Expliquei = o cartao em linguagem de padaria existe/foi renderizado. Fato auto-evidente: se esta
#     funcao roda dentro do situacao-abrir (que ESTA montando o cartao), o cartao existe -> 🟢 sempre.
#
# LEIS (nao-negociaveis, iguais aos outros passos):
#   - FAIL-HONEST no "Provei": IMPOSSIVEL 🟢 sem o motor. NUNCA some a linha (fica 🟡, honesto).
#   - KILL-SWITCH: NORTE_ASSINATURA=0 desliga (ecoa nada, retorna 1) — fail-open pro cartao de hoje.
#   - REDACTION: o "Construi" mostra conteudo do disco (o caminho do artefato) -> passa pelo _redact
#     ANTES. Sem _redact disponivel/funcionando -> cai no rotulo honesto sem path (nunca vaza cru).
#   - SO LE o disco local. Nao escreve nada.
# Retorna 0 se ecoou o bloco; 1 se desligado (kill-switch).
_norte_situacao_assinatura() {
  # kill-switch: default LIGADO; NORTE_ASSINATURA=0 desliga.
  case "${NORTE_ASSINATURA:-1}" in 0|no|nao|off|false) return 1 ;; esac

  # --- Provei (MECANICO — veredito do motor, jamais texto do agente) ---
  local _provei_selo
  if _norte_situacao_provado; then
    _provei_selo='🟢 provei (o motor rodou a sua entrega e deu certo — exit 0)'
  else
    _provei_selo='🟡 nao provei ainda — sem prova do motor'
  fi

  # --- Construi (arquivo real no disco; TIPO redigido, nunca nome cru) ---
  local _construi='nenhum arquivo registrado'
  if _norte_situacao_provado; then
    # a prova e valida -> ha um artefato de prova REAL no disco (o selo ja garantiu existe+dentro de
    # provas/+nao-symlink). Ecoa o TIPO do arquivo, redigido (path -> "[arquivo:.ext]"), nunca o nome.
    local _f _art _canon _raiz _art_red
    _f="$(_norte_situacao_path)"
    _art="$(jq -r '.prova.artefato // "" | if type=="string" then . else "" end' "$_f" 2>/dev/null)"
    if [ -n "$_art" ]; then
      _raiz="$(_norte_realpath "${HOME}/.norte-box/provas" 2>/dev/null)"
      _canon="$(_norte_realpath "$_art" 2>/dev/null)"
      # so usa o canonico se ele existir e estiver dentro da arvore controlada (defesa em profundidade).
      if [ -n "$_canon" ] && [ -n "$_raiz" ]; then
        case "$_canon" in
          "$_raiz"/*)
            if command -v _redact >/dev/null 2>&1; then
              _art_red="$(printf '%s' "$_canon" | _redact 2>/dev/null)"
              [ -n "$_art_red" ] && _construi="$_art_red (existe no disco)"
            fi
            ;;
        esac
      fi
    fi
  fi

  # --- Expliquei (fato auto-evidente: o cartao esta sendo montado agora) ---
  local _expliquei='🟢 expliquei em portugues de padaria (este cartao)'

  printf '✍️ ASSINATURA (cada carimbo amarrado em FATO, nunca no que eu digo):\n'
  printf '  • Construí: %s\n'  "$_construi"
  printf '  • Provei: %s\n'    "$_provei_selo"
  printf '  • Expliquei: %s\n' "$_expliquei"
  return 0
}

# _norte_memoria_funda — ecoa o bloco 🧠 MEMORIA FUNDA da reabertura: o PERFIL do negocio + as CORRECOES
# do jeito da pessoa, CITADOS VERBATIM (o texto CRU que ela declarou por ato explicito), com a data.
#
# A LEI (o coracao — a armadilha nº1): CITA, NAO REESCREVE. Mostra o texto CRU gravado, sem resumir/
# parafrasear. Store vazio -> honesto: "nenhuma regra gravada" / sem linha de perfil. NUNCA preenche o
# vazio (nao inventa perfil/regra que a pessoa nao declarou).
#
# LEIS (nao-negociaveis, iguais aos outros passos):
#   - VERBATIM + REDACTION: o perfil/as regras sao texto CRU do cliente -> pode conter secret (uma regra
#     tipo "minha senha do sistema e X"). Passa CADA texto pelo _redact ANTES de exibir. Se o _redact
#     nao estiver disponivel/falhar num item -> aquele item e OMITIDO (fail-CLOSED na redacao: melhor
#     nao mostrar do que vazar cru). O verbatim vale pro texto NAO-secreto (char-por-char); o secret
#     dentro dele e mascarado — as duas leis convivem (mostra o cru, menos o segredo reconhecido).
#   - KILL-SWITCH: NORTE_MEMORIA=0 desliga (ecoa nada, retorna 1) — fail-open pro cartao de hoje.
#   - SO LE o disco local. As correcoes vem de _norte_correcoes_todas (se a lib _correcoes.sh estiver
#     carregada); sem ela, so o perfil aparece (fail-open). Nao imprime caminho de filesystem.
# Retorna 0 se ecoou o bloco; 1 se desligado (kill-switch).
_norte_memoria_funda() {
  # kill-switch: default LIGADO; NORTE_MEMORIA=0 desliga.
  case "${NORTE_MEMORIA:-1}" in 0|no|nao|off|false) return 1 ;; esac
  command -v jq >/dev/null 2>&1 || return 1

  # NADA a citar (sem perfil E sem regra) -> nao mostra bloco nenhum. Fail-honest: o box nao "preenche o
  # vazio" pra um usuario de 1a vez que ainda nao ensinou nada. O bloco (e o honesto "nenhuma regra
  # gravada") so aparece quando HA memoria de que falar (ex: perfil setado, mas ainda 0 regras).
  local _tem_perfil=1 _tem_alguma_regra=1
  [ -n "$(_norte_perfil_atual 2>/dev/null)" ] && _tem_perfil=0
  if command -v _norte_correcoes_tem >/dev/null 2>&1 && _norte_correcoes_tem 2>/dev/null; then
    _tem_alguma_regra=0
  fi
  if [ "$_tem_perfil" -ne 0 ] && [ "$_tem_alguma_regra" -ne 0 ]; then
    return 1
  fi

  # --- PERFIL (verbatim, redigido) ---
  local _perfil_cru _perfil_em _perfil_red _linha_perfil='(ainda nao me contou o que e o seu negocio)'
  _perfil_cru="$(_norte_perfil_atual 2>/dev/null)"
  if [ -n "$_perfil_cru" ]; then
    if command -v _redact >/dev/null 2>&1; then
      _perfil_red="$(printf '%s' "$_perfil_cru" | _redact 2>/dev/null)"
    fi
    # fail-CLOSED: sem _redact / redacao vazia -> nao mostra o perfil cru (some a linha de perfil).
    if [ -n "${_perfil_red:-}" ]; then
      _perfil_em="$(_norte_perfil_em 2>/dev/null)"
      if [ -n "$_perfil_em" ]; then
        _linha_perfil="você me disse que seu negócio é: \"${_perfil_red}\" (gravado em ${_perfil_em%%T*})"
      else
        _linha_perfil="você me disse que seu negócio é: \"${_perfil_red}\""
      fi
    fi
  fi

  # --- REGRAS/CORRECOES (verbatim, redigidas, uma por linha) ---
  local _regras_bloco='' _tem_regra=1
  if command -v _norte_correcoes_todas >/dev/null 2>&1; then
    local _crus
    _crus="$(_norte_correcoes_todas 2>/dev/null)"
    if [ -n "$_crus" ]; then
      # redige CADA linha; item cujo _redact falhe/vaze e OMITIDO (fail-closed por item).
      local _l _lred
      while IFS= read -r _l; do
        [ -n "$_l" ] || continue
        if command -v _redact >/dev/null 2>&1; then
          _lred="$(printf '%s' "$_l" | _redact 2>/dev/null)"
        else
          _lred=""
        fi
        [ -n "$_lred" ] || continue
        _regras_bloco="${_regras_bloco}  ${_lred}"$'\n'
        _tem_regra=0
      done <<EOF
$_crus
EOF
    fi
  fi

  printf '🧠 MEMORIA FUNDA (o que voce ja me ensinou — citado do jeito que voce disse):\n'
  printf '  PERFIL: %s\n' "$_linha_perfil"
  if [ "$_tem_regra" -eq 0 ]; then
    printf '  SUAS REGRAS:\n'
    printf '%s' "$_regras_bloco"
  else
    printf '  SUAS REGRAS: nenhuma regra gravada.\n'
  fi
  return 0
}

# === TIPO DO PEDIDO (campo MANUAL — NRT-_990212 passo 5) ================================
# O HUMANO escolhe/confirma 1 de 5 tipos: criar | corrigir | revisar | automatizar | publicar.
# NUNCA adivinhado por keyword (os 2 grupos: classificador automatico e fraco — 40% acerto / 20% erro
# confiante; o CEO fala por sentido). Aqui e so um campo que o humano seta. Minusculo de proposito.
_NORTE_TIPOS_VALIDOS="criar corrigir revisar automatizar publicar"

# _norte_tipo_valido <tipo> — 0 se e um dos 5; 1 caso contrario. Nao adivinha; so valida a escolha.
_norte_tipo_valido() {
  local _t="${1:-}"; [ -n "$_t" ] || return 1
  case " $_NORTE_TIPOS_VALIDOS " in *" $_t "*) return 0 ;; *) return 1 ;; esac
}

# _norte_tipo_atual — ecoa o tipo gravado na fichinha (vazio se nao setado). Nunca inventa.
_norte_tipo_atual() {
  local _f; _f="$(_norte_situacao_path)"
  _norte_situacao_tem || return 1
  jq -r '.tipo_pedido // "" | if type=="string" then . else "" end' "$_f" 2>/dev/null
}

# _norte_tipo_definir <tipo> — grava .tipo_pedido na fichinha SO se for um dos 5 (senao retorna 1 sem
# tocar nada). PRESERVA todos os outros campos (objetivo/entregou/proximo/provado/prova). Cria a fichinha
# minima se ainda nao houver. Fail-honest: escolha invalida NAO grava (o comando reapresenta o menu).
_norte_tipo_definir() {
  local _t="${1:-}"
  _norte_tipo_valido "$_t" || return 1
  command -v jq >/dev/null 2>&1 || return 1
  local _dir="${HOME}/.norte-box" _f _tmp _ts
  _f="$(_norte_situacao_path)"; mkdir -p "$_dir" 2>/dev/null || return 1
  _ts="$(date -u +%FT%TZ 2>/dev/null || echo unknown)"; _tmp="${_f}.tmp.$$"
  if [ -f "$_f" ] && jq -e . "$_f" >/dev/null 2>&1; then
    jq --arg t "$_t" --arg ts "$_ts" '.tipo_pedido=$t | .ultima_atualizacao=$ts' "$_f" > "$_tmp" 2>/dev/null \
      || { rm -f "$_tmp" 2>/dev/null; return 1; }
  else
    jq -cn --arg t "$_t" --arg ts "$_ts" \
      '{objetivo:"", entregou:"", proximo:"", tipo_pedido:$t, provado:false, prova:{artefato:"",entrega:""}, ultima_atualizacao:$ts}' > "$_tmp" 2>/dev/null \
      || { rm -f "$_tmp" 2>/dev/null; return 1; }
  fi
  mv -f "$_tmp" "$_f" 2>/dev/null || { rm -f "$_tmp" 2>/dev/null; return 1; }
  return 0
}

# === MEMORIA FUNDA — PERFIL do negocio (NRT-_990212 passo 7) ===========================
# O PERFIL e uma string UNICA que a PESSOA declara por ATO EXPLICITO (o comando /norte-box:perfil).
# A caixa guarda o texto CRU dela, char-por-char, + a data. NUNCA infere de conversa solta ("sou
# dentista" numa fala qualquer NAO grava nada). NUNCA parafraseia/resume. O LLM NAO tem caminho de
# escrita aqui — a gravacao e este codigo determinista que copia a string recebida via jq --arg (byte
# a byte). Mora na MESMA fichinha (situacao.json), campos .perfil (string crua) + .perfil_em (data).
#
# LEIS (nao-negociaveis, iguais a fichinha):
#   - SO GRAVA POR ATO EXPLICITO: quem chama e o comando (a pessoa rodou). Sem texto -> return 1, nada.
#   - VERBATIM: o texto entra como veio (jq --arg copia a string crua). Zero resumo/deducao.
#   - PRESERVA os outros campos (objetivo/entregou/proximo/tipo/provado/prova). Cria a fichinha minima
#     se ainda nao houver. So LE/ESCREVE o disco local.

# _norte_perfil_atual — ecoa o perfil CRU gravado (vazio se nao setado). Nunca inventa/parafraseia.
_norte_perfil_atual() {
  local _f; _f="$(_norte_situacao_path)"
  _norte_situacao_tem || return 1
  jq -r '.perfil // "" | if type=="string" then . else "" end' "$_f" 2>/dev/null
}

# _norte_perfil_em — ecoa a data (ISO) em que o perfil foi gravado (vazio se ausente).
_norte_perfil_em() {
  local _f; _f="$(_norte_situacao_path)"
  _norte_situacao_tem || return 1
  jq -r '.perfil_em // "" | if type=="string" then . else "" end' "$_f" 2>/dev/null
}

# _norte_perfil_definir <texto> — grava .perfil = <texto CRU> + .perfil_em = agora. Sem texto (vazio)
# -> return 1 SEM tocar nada (o comando reapresenta o pedido; NUNCA adivinha). O texto e copiado
# char-por-char via jq --arg (o LLM nao tem caminho de escrita: quem passa a string e o comando, e o
# jq so copia). PRESERVA todos os outros campos. Aditivo: nunca apaga historico de outra chave.
_norte_perfil_definir() {
  local _p="${1:-}"
  [ -n "$_p" ] || return 1
  command -v jq >/dev/null 2>&1 || return 1
  local _dir="${HOME}/.norte-box" _f _tmp _ts
  _f="$(_norte_situacao_path)"; mkdir -p "$_dir" 2>/dev/null || return 1
  _ts="$(date -u +%FT%TZ 2>/dev/null || echo unknown)"; _tmp="${_f}.tmp.$$"
  if [ -f "$_f" ] && jq -e . "$_f" >/dev/null 2>&1; then
    jq --arg p "$_p" --arg ts "$_ts" '.perfil=$p | .perfil_em=$ts | .ultima_atualizacao=$ts' "$_f" > "$_tmp" 2>/dev/null \
      || { rm -f "$_tmp" 2>/dev/null; return 1; }
  else
    jq -cn --arg p "$_p" --arg ts "$_ts" \
      '{objetivo:"", entregou:"", proximo:"", tipo_pedido:"", perfil:$p, perfil_em:$ts, provado:false, prova:{artefato:"",entrega:""}, ultima_atualizacao:$ts}' > "$_tmp" 2>/dev/null \
      || { rm -f "$_tmp" 2>/dev/null; return 1; }
  fi
  mv -f "$_tmp" "$_f" 2>/dev/null || { rm -f "$_tmp" 2>/dev/null; return 1; }
  return 0
}

# --- MEMORIA DO OBJETIVO (NRT-_990419 Camada 3): a caixa lembra do objetivo ENTRE conversas. -------
# O objetivo tem DUAS origens: (1) DECLARADO por ato explicito (/norte-box:objetivo "<palavras cruas>")
# -> .objetivo_declarado:true, o Stop NUNCA sobrescreve (soberania: so a pessoa reescreve); (2) rotulo
# AUTO da 1a fala (o que _norte_situacao_gravar ja fazia) -> .objetivo_declarado:false, fraco, so um
# lembrete. O leitor unico abaixo entrega o texto atual (declarado tem prioridade porque .objetivo ja
# carrega o texto certo) e carrega o KILL-SWITCH: NORTE_OBJETIVO=0 -> a memoria do objetivo fica muda.

# _norte_objetivo_definir <texto> — grava o objetivo VERBATIM (ato explicito). Marca declarado:true pra
# o Stop preservar. Preserva os demais campos se a fichinha existe; senao cria uma nova. Clona o padrao
# de _norte_perfil_definir (verbatim jq --arg, tmp+mv atomico). Sem jq / sem texto -> 1 (fail-open).
_norte_objetivo_definir() {
  local _o="${1:-}"
  [ -n "$_o" ] || return 1
  command -v jq >/dev/null 2>&1 || return 1
  local _dir="${HOME}/.norte-box" _f _tmp _ts
  _f="$(_norte_situacao_path)"; mkdir -p "$_dir" 2>/dev/null || return 1
  _ts="$(date -u +%FT%TZ 2>/dev/null || echo unknown)"; _tmp="${_f}.tmp.$$"
  if [ -f "$_f" ] && jq -e . "$_f" >/dev/null 2>&1; then
    jq --arg o "$_o" --arg ts "$_ts" '.objetivo=$o | .objetivo_em=$ts | .objetivo_declarado=true | .ultima_atualizacao=$ts' "$_f" > "$_tmp" 2>/dev/null \
      || { rm -f "$_tmp" 2>/dev/null; return 1; }
  else
    jq -cn --arg o "$_o" --arg ts "$_ts" \
      '{objetivo:$o, objetivo_em:$ts, objetivo_declarado:true, entregou:"", proximo:"", tipo_pedido:"", perfil:"", perfil_em:"", provado:false, prova:{artefato:"",entrega:""}, ultima_atualizacao:$ts}' > "$_tmp" 2>/dev/null \
      || { rm -f "$_tmp" 2>/dev/null; return 1; }
  fi
  mv -f "$_tmp" "$_f" 2>/dev/null || { rm -f "$_tmp" 2>/dev/null; return 1; }
  return 0
}

# _norte_objetivo_atual — ecoa o objetivo atual (declarado OU rotulo auto — o .objetivo ja tem o certo).
# KILL-SWITCH DENTRO: NORTE_OBJETIVO=0 -> ecoa nada (return 1). Sem fichinha -> nada. Usado pelo abrir
# e pela deriva (os dois herdam o kill-switch de graca).
_norte_objetivo_atual() {
  [ "${NORTE_OBJETIVO:-1}" = "0" ] && return 1
  local _f; _f="$(_norte_situacao_path)"
  _norte_situacao_tem || return 1
  jq -r '.objetivo // "" | if type=="string" then . else "" end' "$_f" 2>/dev/null
}

# _norte_objetivo_declarado — 0 (SIM) se o objetivo foi DECLARADO por ato explicito; 1 caso contrario.
_norte_objetivo_declarado() {
  local _f; _f="$(_norte_situacao_path)"
  _norte_situacao_tem || return 1
  jq -e '.objetivo_declarado == true' "$_f" >/dev/null 2>&1
}

# _norte_objetivo_em — ecoa a data (ISO) em que o objetivo foi DECLARADO (vazio se ausente/nao-declarado).
_norte_objetivo_em() {
  local _f; _f="$(_norte_situacao_path)"
  _norte_situacao_tem || return 1
  jq -r '.objetivo_em // "" | if type=="string" then . else "" end' "$_f" 2>/dev/null
}

# _norte_objetivo_conferir <trecho> [artefato-de-entrega] — GRAVA o bloco .objetivo_conferido (NRT-_990429).
# Este e o WRITER honesto do 2o portao: o trecho_encontrado NAO vem do modelo — e computado AQUI, por
# grep -F do <trecho> DENTRO do artefato de entrega/prova REAL. Assim o agente pode "citar" onde a entrega
# responde ao objetivo, mas se o trecho NAO existe no arquivo de verdade, o bool sai false (blefe pego).
#
# QUAL artefato: se [artefato-de-entrega] vier e existir, usa ele (o arquivo que o agente aponta como a
# entrega); senao cai no prova.artefato registrado na fichinha (o arquivo que o MOTOR provou). Sem nenhum
# arquivo legivel -> trecho_encontrado=false (nao inventa verde). O objetivo_hash gravado e o hash do
# .objetivo ATUAL — amarra a conferencia a esta versao do objetivo (se ele mudar depois, o portao acusa).
#
# LEIS: SO GRAVA POR ATO EXPLICITO (quem chama passa o trecho). VERBATIM no trecho (jq --arg copia cru).
# PRESERVA os outros campos. So le/escreve o disco local. Sem jq / sem trecho / sem objetivo -> 1 (nada).
# Trecho SO-ESPACOS ("   ") conta como SEM trecho (ausencia): retorna 1 sem gravar — bate com "sem trecho -> nada".
_norte_objetivo_conferir() {
  local _trecho="${1:-}" _art_in="${2:-}"
  [ -n "$_trecho" ] || return 1
  # trecho que colapsa pra VAZIO (so espacos/tabs/newlines) NAO e trecho — trata como ausencia (docstring:
  # "sem trecho -> nada"). Sem isso, "   " passaria o [ -n ] e gravaria uma conferencia inutil (grep -F de
  # espacos casa quase sempre) que poderia abrir verde a toa. Bash 3.2: tr apara todo whitespace.
  local _trecho_util
  _trecho_util="$(printf '%s' "$_trecho" | tr -d '[:space:]')"
  [ -n "$_trecho_util" ] || return 1
  command -v jq >/dev/null 2>&1 || return 1
  _norte_situacao_tem || return 1
  local _dir="${HOME}/.norte-box" _f _tmp _ts _obj _oh _art _enc
  _f="$(_norte_situacao_path)"; mkdir -p "$_dir" 2>/dev/null || return 1
  _obj="$(jq -r '.objetivo // "" | if type=="string" then . else "" end' "$_f" 2>/dev/null)"
  [ -n "$_obj" ] || return 1
  _oh="$(_norte_prova_hash_texto "$_obj")"; [ -n "$_oh" ] || return 1

  # escolhe o artefato de entrega: explicito (se existe) OU o prova.artefato registrado (se existe).
  if [ -n "$_art_in" ] && [ -f "$_art_in" ]; then
    _art="$_art_in"
  else
    _art="$(jq -r '.prova.artefato // "" | if type=="string" then . else "" end' "$_f" 2>/dev/null)"
  fi

  # computa MECANICAMENTE trecho_encontrado (grep -F, string literal). Sem arquivo legivel -> false.
  _enc="false"
  if [ -n "$_art" ] && [ ! -L "$_art" ] && [ -f "$_art" ]; then
    if grep -Fq -- "$_trecho" "$_art" 2>/dev/null; then _enc="true"; fi
  fi

  _ts="$(date -u +%FT%TZ 2>/dev/null || echo unknown)"; _tmp="${_f}.tmp.$$"
  jq --arg tr "$_trecho" --arg oh "$_oh" --argjson enc "$_enc" --arg ts "$_ts" \
    '.objetivo_conferido={objetivo_hash:$oh, trecho:$tr, trecho_encontrado:$enc, conferido_em:$ts} | .ultima_atualizacao=$ts' \
    "$_f" > "$_tmp" 2>/dev/null || { rm -f "$_tmp" 2>/dev/null; return 1; }
  mv -f "$_tmp" "$_f" 2>/dev/null || { rm -f "$_tmp" 2>/dev/null; return 1; }
  return 0
}

# _norte_situacao_gravar — escreve/atualiza a fichinha (fim de sessao). Recebe por variaveis de
# ambiente pra nao brigar com aspas: NB_SIT_OBJETIVO, NB_SIT_ENTREGOU, NB_SIT_PROXIMO.
#
# SELO (fix A — "o verde do motor SOBREVIVE ao Stop"): a gravacao NAO zera cegamente o provado. Se, no
# momento do Stop, JA existe uma prova de motor VALIDA (as MESMAS leis (b)-(e) do selo: artefato dentro
# de provas/, existe, nao-symlink, e o vinculo A3 bate) -> PRESERVA provado:true + prova.artefato +
# prova.entrega. Caso contrario -> default HONESTO: provado:false + prova vazia. Assim o motor marca
# verde no meio do turno e a marca sobrevive ao Stop; quem NAO provou continua amarelo. Aditivo: o Stop
# nunca INVENTA verde — so preserva o que o motor ja provou de verdade.
# Retorna 0 se gravou; 1 se nao deu (sem jq, disco nao gravavel) — o chamador ignora (fail-open).
_norte_situacao_gravar() {
  command -v jq >/dev/null 2>&1 || return 1
  local _dir="${HOME}/.norte-box" _f _tmp _ts
  _f="$(_norte_situacao_path)"
  mkdir -p "$_dir" 2>/dev/null || return 1
  _ts="$(date -u +%FT%TZ 2>/dev/null || echo unknown)"
  _tmp="${_f}.tmp.$$"

  # Ha uma prova de motor VALIDA na fichinha atual? (usa exatamente a regra do selo — nao reimplementa).
  # Se sim, capturamos artefato + entrega pra PRESERVAR; senao, gravamos o default honesto (amarelo).
  local _keep_art="" _keep_ent=""
  if _norte_situacao_provado 2>/dev/null; then
    _keep_art="$(jq -r '.prova.artefato // "" | if type=="string" then . else "" end' "$_f" 2>/dev/null)"
    _keep_ent="$(jq -r '.prova.entrega  // "" | if type=="string" then . else "" end' "$_f" 2>/dev/null)"
  fi

  # PRESERVA o tipo do pedido (campo MANUAL) se ja setado — o Stop nunca apaga a escolha do humano.
  # E o PERFIL (memoria funda, NRT-_990212 passo 7): campo declarado por ato explicito; o Stop tambem
  # NUNCA apaga o texto cru nem a data do perfil — so preserva o que a pessoa gravou.
  local _keep_tipo="" _keep_perfil="" _keep_perfil_em=""
  if [ -f "$_f" ] && jq -e . "$_f" >/dev/null 2>&1; then
    _keep_tipo="$(jq -r '.tipo_pedido // "" | if type=="string" then . else "" end' "$_f" 2>/dev/null)"
    _keep_perfil="$(jq -r '.perfil // "" | if type=="string" then . else "" end' "$_f" 2>/dev/null)"
    _keep_perfil_em="$(jq -r '.perfil_em // "" | if type=="string" then . else "" end' "$_f" 2>/dev/null)"
  fi

  # MEMORIA DO OBJETIVO (NRT-_990419): se foi DECLARADO por ato explicito (/objetivo), o Stop PRESERVA
  # o texto+data e mantem declarado:true — a 1a fala NUNCA sobrescreve (soberania). Sem declaracao, o
  # objetivo = rotulo AUTO da 1a fala (NB_SIT_OBJETIVO), declarado:false (fraco). Mesma keep-list nas
  # DUAS branches abaixo (o risco que o juiz apontou: divergir aqui rebaixa o objetivo declarado calado).
  local _use_obj="${NB_SIT_OBJETIVO:-}" _use_obj_em="" _use_obj_decl="false"
  if [ -f "$_f" ] && jq -e '.objetivo_declarado == true' "$_f" >/dev/null 2>&1; then
    _use_obj="$(jq -r '.objetivo // "" | if type=="string" then . else "" end' "$_f" 2>/dev/null)"
    _use_obj_em="$(jq -r '.objetivo_em // "" | if type=="string" then . else "" end' "$_f" 2>/dev/null)"
    _use_obj_decl="true"
  fi

  # CONFERENCIA DO OBJETIVO (NRT-_990429): PRESERVA o bloco .objetivo_conferido SO se ele ainda vale pro
  # objetivo que vai ser escrito — isto e, o objetivo_hash registrado bate com o hash do objetivo NOVO
  # (_use_obj). Se o objetivo mudou, o bloco fica STALE de proposito e e DESCARTADO (a conferencia velha
  # nao vale pra outro objetivo — deixar cair e o comportamento honesto; o selo cai em amarelo ate reconferir).
  # _keep_confer_json = o objeto JSON cru (ou "null"), injetado com --argjson nas duas branches.
  local _keep_confer_json="null" _cf_oh _cur_oh
  if [ -f "$_f" ] && jq -e '.objetivo_conferido | type=="object"' "$_f" >/dev/null 2>&1; then
    _cf_oh="$(jq -r '.objetivo_conferido.objetivo_hash // "" | if type=="string" then . else "" end' "$_f" 2>/dev/null)"
    _cur_oh="$(_norte_prova_hash_texto "$_use_obj" 2>/dev/null)"
    if [ -n "$_cf_oh" ] && [ -n "$_cur_oh" ] && [ "$_cf_oh" = "$_cur_oh" ]; then
      _keep_confer_json="$(jq -c '.objetivo_conferido' "$_f" 2>/dev/null)"
      [ -n "$_keep_confer_json" ] || _keep_confer_json="null"
    fi
  fi

  if [ -n "$_keep_art" ]; then
    # PRESERVA o verde legitimo do motor. Objetivo/entregou/proximo sao atualizados (o Stop conhece a
    # 1a fala); provado/prova ficam como o motor deixou; tipo_pedido + perfil (manuais) preservados.
    jq -cn \
      --arg objetivo  "$_use_obj" \
      --arg objem     "$_use_obj_em" \
      --arg objdecl   "$_use_obj_decl" \
      --arg entregou  "${NB_SIT_ENTREGOU:-}" \
      --arg proximo   "${NB_SIT_PROXIMO:-}" \
      --arg tipo      "$_keep_tipo" \
      --arg perfil    "$_keep_perfil" \
      --arg perfilem  "$_keep_perfil_em" \
      --arg art       "$_keep_art" \
      --arg ent       "$_keep_ent" \
      --argjson confer "$_keep_confer_json" \
      --arg ts        "$_ts" \
      '{objetivo:$objetivo, objetivo_em:$objem, objetivo_declarado:($objdecl=="true"),
        entregou:$entregou, proximo:$proximo, tipo_pedido:$tipo,
        perfil:$perfil, perfil_em:$perfilem,
        provado:true, prova:{artefato:$art, entrega:$ent}, objetivo_conferido:$confer,
        ultima_atualizacao:$ts}' > "$_tmp" 2>/dev/null || { rm -f "$_tmp" 2>/dev/null; return 1; }
  else
    # Default HONESTO: sem prova valida do motor -> provado:false, prova vazia. Conteudo do trabalho NAO
    # entra: so o rotulo do objetivo; tipo_pedido + perfil (manuais) preservados.
    jq -cn \
      --arg objetivo  "$_use_obj" \
      --arg objem     "$_use_obj_em" \
      --arg objdecl   "$_use_obj_decl" \
      --arg entregou  "${NB_SIT_ENTREGOU:-}" \
      --arg proximo   "${NB_SIT_PROXIMO:-}" \
      --arg tipo      "$_keep_tipo" \
      --arg perfil    "$_keep_perfil" \
      --arg perfilem  "$_keep_perfil_em" \
      --argjson confer "$_keep_confer_json" \
      --arg ts        "$_ts" \
      '{objetivo:$objetivo, objetivo_em:$objem, objetivo_declarado:($objdecl=="true"),
        entregou:$entregou, proximo:$proximo, tipo_pedido:$tipo,
        perfil:$perfil, perfil_em:$perfilem,
        provado:false, prova:{artefato:"", entrega:""}, objetivo_conferido:$confer,
        ultima_atualizacao:$ts}' > "$_tmp" 2>/dev/null || { rm -f "$_tmp" 2>/dev/null; return 1; }
  fi
  mv -f "$_tmp" "$_f" 2>/dev/null || { rm -f "$_tmp" 2>/dev/null; return 1; }
  return 0
}
