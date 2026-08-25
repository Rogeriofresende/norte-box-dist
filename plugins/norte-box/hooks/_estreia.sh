#!/usr/bin/env bash
# _estreia.sh — a ESTREIA COM ENTREGA PROVADA do Norte-box (NRT-_990341, passo 10 do plano).
#
# A ideia (padaria): a caixa roda UMA tarefa REAL do tipo documento→checklist PONTA A PONTA e termina com
# um REGISTRO DE ENTREGA. O registro so recebe o carimbo "🟢 ENTREGA PROVADA" quando a conferencia deu
# PROVADO de verdade (cobertura completa, zero orfao, zero suspeita, zero contradicao). Se faltou item ou
# a fonte foi contradita, o registro sai "🟡 ENTREGA NAO-PROVADA" dizendo O QUE FALTOU — e NAO sela.
#
# ADITIVO. NAO reconstroi a conferencia: REUSA o motor contrato-doc (_norte_contrato_doc_provar), que ja
# confere item a item, grava a prova LOCAL (com entrega_hash + checklist_hash + resumo) e — so com a
# conferencia fechando — vira a fichinha 🟢 pela MESMA lei honesta dos outros portoes.
#
# LEI HONESTA (a que o CEO cobra): o carimbo da estreia le o RESULTADO REAL (o EXIT do motor + a prova
# gravada por ele), NUNCA a presenca de arquivo. Um registro de "entrega" existir no disco NAO abre o
# verde — so o exit 0 do motor abre. Fail-honest: na duvida, amarelo.
#
# LEIS (iguais aos outros passos):
#   - PRIVADO POR PADRAO: o registro mora em $HOME/.norte-box/entregas/; NUNCA sai da maquina. Sem rede.
#   - KILL-SWITCH: NORTE_ESTREIA=0 desliga a estreia (recusa, exit 2, volta ao comportamento de hoje).
#   - Portabilidade macOS (bash 3.2). Nao usa dado como comando (set -u; sem eval).
#
# LIMITE CONHECIDO (honestidade obrigatoria, NAO escondido): a conferencia de hoje casa por PALAVRA
# (substring), nao entende SENTIDO. Entao o carimbo prova COBERTURA (as exigencias especificas estao no
# texto), NAO "esta juridicamente perfeito". O caso residual da ancora seguida de "(nao preenchido)" na
# MESMA LINHA ja e pego (NRT-_990380: _norte_contrato_cobertura_vazia marca SUSPEIT quando a ancora vem
# colada a um marcador de nao-preenchido — simetrico a defesa de negacao ANTES da ancora). O que AINDA
# escapa: o marcador de vazio na LINHA SEGUINTE (fora da janela same-line) — igual ao limite da defesa de
# negacao. Fechar isso e "leitura de sentido" (NLP), adiada de proposito. Reportado, nao fingido.
set -u

# =========================== PONTA B — ASSINATURA HMAC DO SELO (NRT-_990380) ===========================
#
# O PROBLEMA que isto fecha: o registro de entrega (entrega-*.txt) e TEXTO PURO. Um registro reescrito 100%
# a mao (com "🟢 ENTREGA PROVADA" e hashes coerentes) passaria pelo guarda de coerencia do exportador. A
# assinatura HMAC amarra o CORPO do registro a uma CHAVE LOCAL: quem nao tem a chave nao consegue produzir
# um assinatura_hmac valido, e mudar 1 byte do corpo (ex: flipar 🟡->🟢) quebra o HMAC. Fecha a forja-a-mao.
#
# MODELO DE AMEACA (honestidade obrigatoria — o que isto pega e o que NAO pega):
#   PEGA: registro forjado do zero (sem chave), edicao/adulteracao (flip 🟡->🟢, byte trocado), corrupcao.
#   NAO PEGA: um adversario LOCAL PLENO que LE a chave em $HOME/.norte-box/chaves/ e re-assina — isto e
#             verificacao LOCAL numa maquina pessoal single-user, nao criptografia contra o dono da maquina.
#   RISCO DECLARADO (a) CICLO DE VIDA DA CHAVE: se a chave for perdida/trocada, registros antigos ficam
#             NAO-VERIFICAVEIS (🟡) — aceitavel: e verificacao local, nao um PKI. Nao bloqueia por isso.
#   RISCO DECLARADO (b) A CHAVE APARECE NO argv (visivel em `ps` por instantes) porque `openssl -hmac <k>`
#             recebe a chave como argumento — maquina pessoal single-user, aceitavel, declarado. (Passar por
#             stdin/arquivo em vez de argv seria o hardening; adiado de proposito — nao e o modelo de ameaca.)
#
# LEIS: 100% LOCAL, sem rede; a chave NUNCA e impressa/logada; ausencia de assinatura NUNCA e verde (🟢);
#       degradar sem openssl NAO trava o selo (grava marcador de indisponivel, verificar devolve 🟡);
#       kill-switch NORTE_ESTREIA_HMAC=0 desliga a assinatura (verificar devolve 🟡 "desligada").

# _norte_entrega_hmac_key — ecoa (stdout) a CHAVE LOCAL do HMAC, criando-a no 1o uso. A chave mora em
#   $HOME/.norte-box/chaves/entrega-hmac.key (dir 700 / arquivo 600, via umask 077). Gerada com
#   `openssl rand -hex 32`. NUNCA vai pra rede. O eco e SO pra uso interno (assinar/verificar) — nenhum
#   chamador imprime o valor. Ecoa vazio (rc!=0) se nao houver openssl OU nao der pra gravar a chave.
_norte_entrega_hmac_key() {
  command -v openssl >/dev/null 2>&1 || return 1
  local _dir="${HOME}/.norte-box/chaves" _kf="${HOME}/.norte-box/chaves/entrega-hmac.key"
  if [ ! -f "$_kf" ]; then
    ( umask 077; mkdir -p "$_dir" 2>/dev/null ) || return 1
    # gera a chave num subshell com umask 077 -> arquivo nasce 600. Redireciona a saida do openssl DIRETO
    # pro arquivo (a chave nunca passa por variavel/stdout ate aqui).
    ( umask 077; openssl rand -hex 32 > "$_kf" 2>/dev/null ) || { rm -f "$_kf" 2>/dev/null; return 1; }
    chmod 700 "$_dir" 2>/dev/null || true
    chmod 600 "$_kf"  2>/dev/null || true
  fi
  [ -s "$_kf" ] || return 1
  cat "$_kf" 2>/dev/null
}

# _norte_estreia_hmac_calc <chave> — le o PAYLOAD do stdin e ecoa SO o hex do HMAC-SHA256. macOS/OpenSSL 3.x
#   imprime "SHA2-256(stdin)= <hex>" (ou "SHA256(stdin)= <hex>" em versoes antigas) — extrai o ULTIMO campo
#   (o hex) com sed, robusto ao rotulo do algoritmo. Retorna vazio se openssl faltar.
_norte_estreia_hmac_calc() {
  command -v openssl >/dev/null 2>&1 || return 1
  openssl dgst -sha256 -hmac "$1" 2>/dev/null | sed 's/^.*= *//'
}

# _norte_estreia_payload <registro> — ecoa o PAYLOAD CANONICO: o corpo do registro MENOS SO a linha final do
#   VALOR do HMAC ("assinatura_hmac:"). TUDO O MAIS fica no payload — inclusive "assinatura_alg:" e QUALQUER
#   outra linha "assinatura_*:" que alguem tente injetar. Por que NAO excluir o prefixo largo "^assinatura_"
#   (como antes): esse buraco deixava injetar "assinatura_nota: <prosa>" — some do calculo do HMAC mas continua
#   no arquivo, e exibida e vai pro pacote do cliente sob o 🟢 (furo da Val, NRT-_990380 Ponta B red-team).
#   Regra: a assinatura cobre TUDO que e exibido, exceto a propria linha do valor HMAC. Assim, injetar
#   "assinatura_nota:", um 2o "assinatura_alg:", ou conteudo DEPOIS da assinatura -> tudo entra no payload ->
#   quebra o HMAC -> 🔴. printf-safe (o grep ja garante newline por linha). A assinatura ainda tem que ser o
#   ULTIMO write (assina so depois de fechar o corpo, e assinatura_hmac: a ultima linha).
_norte_estreia_payload() {
  grep -vE '^assinatura_hmac:' "$1" 2>/dev/null
}

# _norte_estreia_assinar <registro> — APPEND das linhas de assinatura no FIM do registro ja fechado, NESTA
#   ordem (importa pro modelo de payload novo):
#     1) append "assinatura_alg: hmac-sha256"      -> ESTA linha ENTRA no corpo assinado (fica no payload);
#     2) HMAC sobre TUDO ate aqui (corpo + a linha assinatura_alg:), via _norte_estreia_payload
#        (que so exclui a futura linha assinatura_hmac:);
#     3) append "assinatura_hmac: <hex de 64>"     -> a ULTIMA linha; e a UNICA fora do payload.
#   Por que assinar o "assinatura_alg:" tambem: senao um atacante injeta um 2o "assinatura_alg: <prosa>" que
#   ficaria de fora do calculo (furo simetrico ao "assinatura_nota:"). Agora TUDO menos o valor HMAC e coberto.
#   Degrada sem travar: kill-switch NORTE_ESTREIA_HMAC=0 -> nao assina (registro fica sem HMAC real);
#   sem openssl OU sem chave -> grava assinatura_hmac com marcador de indisponivel. Retorna 0 sempre que
#   nao houver ERRO REAL de disco (o objetivo e NAO travar o fluxo do selo).
_norte_estreia_assinar() {
  local _reg="${1:-}"
  [ -n "$_reg" ] && [ -f "$_reg" ] || return 0
  # kill-switch: nao assina. O registro fica sem linha de assinatura -> verificar devolve 🟡 (por design).
  case "${NORTE_ESTREIA_HMAC:-1}" in
    0|no|nao|off|false) return 0 ;;
  esac
  local _key _hex
  _key="$(_norte_entrega_hmac_key)" || _key=""
  if [ -z "$_key" ]; then
    # sem chave/openssl -> degrada: marca indisponivel, NAO trava. verificar devolve 🟡.
    {
      printf 'assinatura_alg: hmac-sha256\n'
      printf 'assinatura_hmac: (indisponivel: openssl ausente)\n'
    } >> "$_reg" 2>/dev/null
    return 0
  fi
  # PASSO 1: a linha do algoritmo entra no CORPO ANTES do calculo -> ela e coberta pelo HMAC.
  printf 'assinatura_alg: hmac-sha256\n' >> "$_reg" 2>/dev/null
  # PASSO 2: HMAC sobre o corpo + a linha assinatura_alg: (payload = tudo menos a futura linha assinatura_hmac:).
  _hex="$(_norte_estreia_payload "$_reg" | _norte_estreia_hmac_calc "$_key")"
  if [ -z "$_hex" ]; then
    # nao deu pra calcular (openssl sumiu no meio) -> marca indisponivel como ULTIMA linha. verificar -> 🟡.
    printf 'assinatura_hmac: (indisponivel: openssl ausente)\n' >> "$_reg" 2>/dev/null
    return 0
  fi
  # PASSO 3: a assinatura como ULTIMA linha nao-vazia do registro.
  printf 'assinatura_hmac: %s\n' "$_hex" >> "$_reg" 2>/dev/null
  return 0
}

# _norte_estreia_verificar <registro> — recomputa o HMAC do corpo (payload = registro MENOS a linha final do
#   valor HMAC) e compara com a assinatura gravada. ANTES de comparar, ENDURECE a leitura da linha de
#   assinatura pra fechar a injecao de uma 2a linha "assinatura_hmac:" com prosa (furo simetrico ao da Val):
#   so aceita como valida se houver EXATAMENTE UMA linha "^assinatura_hmac:", ela for a ULTIMA linha
#   NAO-VAZIA do registro, e o valor casar ^assinatura_hmac: ([0-9a-f]{64}|\(indisponivel). Vereditos:
#     confere                     -> "🟢 assinatura confere"                                          (rc 0)
#     presente e diverge          -> "🔴 assinatura NAO confere (registro editado ou forjado)"        (rc 1)
#     multipla/nao-ultima/malform -> "🔴 assinatura suspeita (registro adulterado)"                   (rc 1)
#     sem linha de assinatura     -> "🟡 nao-verificavel (registro sem assinatura)"                   (rc 2)
#     assinatura sem chave/openssl-> "🟡 nao-verificavel (assinatura gravada sem chave/openssl)"      (rc 2)
#     sem chave/openssl p/ calcular-> "🟡 nao-verificavel (sem chave/openssl)"                        (rc 2)
#     kill-switch                 -> "🟡 assinatura desligada (NORTE_ESTREIA_HMAC=0)"                 (rc 2)
#   REGRA DE OURO: ausencia de assinatura NUNCA e verde; adulteracao estrutural (2a linha/fora do lugar/
#   malformada) e 🔴 (fail-closed), nunca 🟡. Na duvida real (sem chave), 🟡 (fail-honest).
_norte_estreia_verificar() {
  local _reg="${1:-}"
  [ -n "$_reg" ] && [ -f "$_reg" ] || { printf '🟡 nao-verificavel (registro nao existe)\n'; return 2; }
  # kill-switch: verificacao desligada.
  case "${NORTE_ESTREIA_HMAC:-1}" in
    0|no|nao|off|false) printf '🟡 assinatura desligada (NORTE_ESTREIA_HMAC=0)\n'; return 2 ;;
  esac

  # ---- ENDURECIMENTO ESTRUTURAL da linha de assinatura (fecha 2a assinatura_hmac com prosa) ----
  # quantas linhas "^assinatura_hmac:" existem no registro (grep -c conta LINHAS que casam).
  local _n_hmac
  _n_hmac="$(grep -cE '^assinatura_hmac:' "$_reg" 2>/dev/null)"; [ -n "$_n_hmac" ] || _n_hmac=0
  if [ "$_n_hmac" -eq 0 ]; then
    printf '🟡 nao-verificavel (registro sem assinatura)\n'; return 2
  fi
  if [ "$_n_hmac" -gt 1 ]; then
    # mais de uma linha de assinatura -> alguem injetou. Fail-closed.
    printf '🔴 assinatura suspeita (registro adulterado)\n'; return 1
  fi
  # a UNICA linha assinatura_hmac: tem que ser a ULTIMA linha NAO-VAZIA do registro. (Qualquer conteudo
  # depois dela — mesmo linha em branco no meio seguida de prosa — cai aqui como adulteracao.)
  local _ultima_naovazia
  _ultima_naovazia="$(grep -vE '^[[:space:]]*$' "$_reg" 2>/dev/null | tail -n1)"
  case "$_ultima_naovazia" in
    'assinatura_hmac:'*) : ;;   # ok: a assinatura e a ultima linha nao-vazia
    *) printf '🔴 assinatura suspeita (registro adulterado)\n'; return 1 ;;
  esac
  # le o valor gravado dessa linha unica.
  local _grav
  _grav="$(grep -m1 '^assinatura_hmac: ' "$_reg" 2>/dev/null | sed 's/^assinatura_hmac: //')"
  # marcador de degradacao (sem chave/openssl na hora de assinar) -> nao-verificavel, nao 🔴.
  case "$_grav" in
    '(indisponivel:'*) printf '🟡 nao-verificavel (assinatura gravada sem chave/openssl)\n'; return 2 ;;
  esac
  # o valor tem que ser EXATAMENTE 64 hex (nem mais, nem prosa). Malformado -> adulteracao (🔴).
  case "$_grav" in
    *[!0-9a-f]* | '') printf '🔴 assinatura suspeita (registro adulterado)\n'; return 1 ;;
  esac
  if [ "${#_grav}" -ne 64 ]; then
    printf '🔴 assinatura suspeita (registro adulterado)\n'; return 1
  fi

  # precisa de openssl + chave pra recomputar. Sem qualquer um -> nao-verificavel (nunca 🔴 nem 🟢).
  command -v openssl >/dev/null 2>&1 || { printf '🟡 nao-verificavel (sem chave/openssl)\n'; return 2; }
  local _key _calc
  _key="$(_norte_entrega_hmac_key)" || _key=""
  [ -n "$_key" ] || { printf '🟡 nao-verificavel (sem chave/openssl)\n'; return 2; }
  _calc="$(_norte_estreia_payload "$_reg" | _norte_estreia_hmac_calc "$_key")"
  [ -n "$_calc" ] || { printf '🟡 nao-verificavel (sem chave/openssl)\n'; return 2; }
  if [ "$_calc" = "$_grav" ]; then
    printf '🟢 assinatura confere\n'; return 0
  fi
  printf '🔴 assinatura NAO confere (registro editado ou forjado)\n'; return 1
}

# _norte_estreia_regfile_livre <raiz> <ts> — ecoa (stdout) um caminho de registro LIVRE e ja RESERVADO
#   ATOMICAMENTE, fechando a corrida de dois selos no MESMO segundo (o `date` so tem resolucao de segundo,
#   entao entrega-<ts>.txt colide e o 2o selo SOBRESCREVERIA o 1o -> perde run do historico; um 🟡->🟢 no
#   mesmo segundo mascararia o amarelo). NAO e forja, e PERDA DE TRILHA — este helper mata a perda.
#
#   NOME:
#     1o candidato: <raiz>/entrega-<ts>.txt          (nome comum INALTERADO — retrocompat total).
#     em colisao:   <raiz>/entrega-<ts>02.txt, ...03.txt, ... ate ...99.txt  (sufixo 2 digitos zero-padded
#                   COLADO DIRETO apos o Z, SEM separador). Por que colado e por que 2 digitos:
#     ORDENACAO: o char apos o Z no nome base e '.' (0x2e), MENOR que '0' (0x30) -> o base ordena ANTES dos
#                   sufixados (o 1o selo do segundo vem primeiro); '02' < '03'; segundos diferentes decidem
#                   nos digitos do ts. Assim o glob 'entrega-*.txt' + `ls -1r` do _tarefas.sh continua certo
#                   SEM mudanca. NAO usar '-'/'_' como separador: '-' (0x2d) ordena ANTES do '.' e '_' (0x5f)
#                   depois dos digitos -> quebrariam a ordem por nome.
#
#   RESERVA ATOMICA (fecha a corrida de verdade, nao so um `[ -f ]` que tem janela entre testar e criar):
#     `until ( set -C; : > "$cand" ) 2>/dev/null; do <proximo sufixo>; done`. O `set -C` (noclobber) faz o
#     `: >` FALHAR (nao trunca) se o arquivo JA existe -> so vence quem CRIA o arquivo. Roda em subshell pra
#     o noclobber nao vazar pro resto do processo. O arquivo nasce vazio e RESERVADO; o chamador o trunca
#     depois (seguro: e o arquivo que o proprio processo acabou de reservar).
#
#   CAP 99: se os 99 nomes do segundo estiverem ocupados, fail-honest — ecoa vazio e retorna 1. O chamador
#     degrada IGUAL ao mkdir falho de hoje (🟡, NUNCA sobrescreve).  bash 3.2 (set -C, until, printf %02d).
_norte_estreia_regfile_livre() {
  local _raiz="${1:-}" _ts="${2:-}"
  [ -n "$_raiz" ] && [ -n "$_ts" ] || return 1
  # 1o candidato: o nome comum, inalterado (retrocompat).
  local _cand="${_raiz}/entrega-${_ts}.txt" _i=2
  until ( set -C; : > "$_cand" ) 2>/dev/null; do
    # colisao: proximo sufixo zero-padded (02..99), colado direto apos o Z.
    if [ "$_i" -gt 99 ]; then
      return 1   # cap estourado: fail-honest, sem sobrescrever nada.
    fi
    _cand="$(printf '%s/entrega-%s%02d.txt' "$_raiz" "$_ts" "$_i")"
    _i=$((_i + 1))
  done
  printf '%s\n' "$_cand"
  return 0
}

# _norte_estreia_selar <documento> <checklist> [rotulo]
#   O FLUXO PONTA A PONTA: roda a conferencia (motor contrato-doc), le o EXIT REAL e produz o REGISTRO DE
#   ENTREGA. Carimbo 🟢 ENTREGA PROVADA SO com exit 0; senao 🟡 ENTREGA NAO-PROVADA + o que faltou.
#   RETORNO: 0 SELOU (entrega provada) / 1 NAO SELOU (faltou item / contradicao) / 2 nao deu (pre-condicao
#   / kill-switch). Espelha o exit do motor contrato-doc pra o chamador tratar igual.
_norte_estreia_selar() {
  local _doc="${1:-}" _chk="${2:-}" _rot="${3:-estreia}"

  # kill-switch: NORTE_ESTREIA=0 desliga -> volta ao comportamento de hoje.
  case "${NORTE_ESTREIA:-1}" in
    0|no|nao|off|false)
      printf '🟡 a estreia nao esta ligada nesta maquina (NORTE_ESTREIA=0).\n'
      return 2 ;;
  esac

  command -v _norte_contrato_doc_provar >/dev/null 2>&1 || {
    printf '🟡 nao consegui estrear: o motor documento->checklist nao esta disponivel nesta instalacao.\n'
    return 2
  }

  # roda o motor contrato-doc PONTA A PONTA. Ele confere item a item, grava a prova LOCAL (com
  # entrega_hash/checklist_hash/resumo) e — SO com a conferencia fechando — vira a fichinha 🟢.
  local _saida _rc
  _saida="$(_norte_contrato_doc_provar "$_doc" "$_chk" "$_rot")"; _rc=$?

  # a linha NB_PROVA_ARTEFATO=<caminho> que o motor imprime aponta a prova gravada (a evidencia REAL).
  local _prova
  _prova="$(printf '%s' "$_saida" | grep -m1 '^NB_PROVA_ARTEFATO=' | sed 's/^NB_PROVA_ARTEFATO=//')"

  # raiz PRIVADA do registro de entrega (irma da arvore de provas; nunca sai da maquina).
  local _reg_raiz="${HOME}/.norte-box/entregas"
  local _ts _regfile
  _ts="$(date -u +%Y%m%dT%H%M%SZ 2>/dev/null || echo t)"

  # se nem deu pra conferir (pre-condicao / kill do motor) -> NAO grava registro selado; devolve honesto.
  if [ "$_rc" -eq 2 ]; then
    printf '🟡 nao consegui estrear: %s\n' "$(printf '%s' "$_saida" | grep -m1 '🟡' | sed 's/^🟡 *//')"
    return 2
  fi

  mkdir -p "$_reg_raiz" 2>/dev/null || {
    # sem onde gravar o registro: a conferencia ja rodou (a fichinha ja reflete o real); avisa e espelha rc.
    printf '🟡 conferi, mas nao consegui gravar o registro de entrega (disco nao gravavel).\n'
    return "$_rc"
  }
  # reserva ATOMICAMENTE um nome de registro LIVRE (fecha a corrida de dois selos no mesmo segundo — o 2o
  # nao sobrescreve mais o 1o; ganha um sufixo). Se o cap 99 estourar OU nao der pra reservar -> degrada
  # IGUAL ao mkdir falho: 🟡, espelha rc, NUNCA sobrescreve.
  _regfile="$(_norte_estreia_regfile_livre "$_reg_raiz" "$_ts")" || _regfile=""
  if [ -z "$_regfile" ]; then
    printf '🟡 conferi, mas nao consegui reservar um nome livre para o registro de entrega.\n'
    return "$_rc"
  fi

  # colhe a EVIDENCIA REAL de dentro da prova que o motor gravou (resumo + hashes). Fail-honest: se a
  # prova nao existir/ler, o registro ainda sai, mas SEM inventar numeros.
  local _resumo="" _dochash="" _chkhash=""
  if [ -n "$_prova" ] && [ -f "$_prova" ]; then
    _resumo="$(grep -m1 '^resumo: '         "$_prova" 2>/dev/null | sed 's/^resumo: //')"
    _dochash="$(grep -m1 '^entrega_hash: '   "$_prova" 2>/dev/null | sed 's/^entrega_hash: //')"
    _chkhash="$(grep -m1 '^checklist_hash: ' "$_prova" 2>/dev/null | sed 's/^checklist_hash: //')"
  fi

  if [ "$_rc" -eq 0 ]; then
    # ENTREGA PROVADA: a conferencia fechou (exit 0). SO AQUI nasce o carimbo verde — e o carimbo vem do
    # EXIT REAL do motor, nunca da presenca de arquivo.
    {
      printf 'REGISTRO DE ENTREGA — norte-box (estreia: tarefa documento->checklist)\n'
      printf 'quando: %s\n' "$(date -u +%FT%TZ 2>/dev/null || echo t)"
      printf 'rotulo: %s\n' "$_rot"
      printf 'carimbo: 🟢 ENTREGA PROVADA (cobertura literal — confere que as exigencias estao escritas; nao atesta merito juridico)\n'
      printf 'motor_exit: %s\n' "$_rc"
      printf 'doc_hash: %s\n' "$_dochash"
      printf 'checklist_hash: %s\n' "$_chkhash"
      printf 'resumo: %s\n' "$_resumo"
      printf 'prova: %s\n' "$_prova"
      printf '---- conferencia (item a item) ----\n'
      printf '%s\n' "$_saida" | grep -vE '^NB_PROVA_ARTEFATO='
    } > "$_regfile" 2>/dev/null

    # PONTA B: assina o corpo (HMAC-SHA256, chave local). E o ULTIMO write — a assinatura cobre a linha
    # carimbo:, entao flipar 🟡->🟢 a mao quebra o HMAC. Degrada sem travar (sem openssl -> marca indisponivel).
    _norte_estreia_assinar "$_regfile"

    printf '🟢 ENTREGA PROVADA (cobertura literal — confere que as exigencias estao escritas; nao atesta merito juridico) — rodei a tarefa ponta a ponta e a conferencia fechou.\n'
    printf '   %s\n' "$_resumo"
    printf 'NB_ENTREGA_REGISTRO=%s\n' "$_regfile"
    return 0
  fi

  # NAO PROVADA (exit 1): faltou item ou a fonte foi contradita. Grava o registro AMARELO com o que
  # faltou — e NAO sela. O amarelo honesto vale mais que o verde que mente.
  {
    printf 'REGISTRO DE ENTREGA — norte-box (estreia: tarefa documento->checklist)\n'
    printf 'quando: %s\n' "$(date -u +%FT%TZ 2>/dev/null || echo t)"
    printf 'rotulo: %s\n' "$_rot"
    printf 'carimbo: 🟡 ENTREGA NAO-PROVADA\n'
    printf 'motor_exit: %s\n' "$_rc"
    printf 'doc_hash: %s\n' "$_dochash"
    printf 'checklist_hash: %s\n' "$_chkhash"
    printf 'resumo: %s\n' "$_resumo"
    printf 'prova: %s\n' "$_prova"
    printf '---- o que faltou ----\n'
    printf '%s\n' "$_saida" | grep -E '^(   )?(ORFAO|SUSPEIT|ALUC|RESUMO)' | sed 's/^ *//'
  } > "$_regfile" 2>/dev/null

  # PONTA B: assina TAMBEM o registro amarelo — a assinatura cobre a linha carimbo:, entao um flip 🟡->🟢
  # a mao quebra o HMAC (o exportador verifica e recusa). E o ULTIMO write.
  _norte_estreia_assinar "$_regfile"

  printf '🟡 ENTREGA NAO-PROVADA — rodei a tarefa, mas a conferencia NAO fechou (nao selei).\n'
  printf '   o que faltou:\n'
  printf '%s\n' "$_saida" | grep -E '(ORFAO|SUSPEIT|ALUC|RESUMO)' | sed 's/^ */   /' | head -20
  printf 'NB_ENTREGA_REGISTRO=%s\n' "$_regfile"
  return 1
}
