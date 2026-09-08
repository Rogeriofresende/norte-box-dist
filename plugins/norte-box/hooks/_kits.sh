#!/usr/bin/env bash
# _kits.sh — o KIT "VIRAR ROTINA" + CATALOGO do norte-box (NRT-_990380, passo 11 do plano).
#
# A ideia (padaria): depois de a caixa PROVAR uma tarefa (documento->checklist) de verdade, a pessoa quer
# rodar A MESMA conferencia em documentos NOVOS sem reconstruir o checklist toda vez. Um KIT guarda o
# checklist + um cartao de identidade, e "virar rotina" (nb-kit-rodar) roda a conferencia num doc novo
# pela ESTEIRA REAL (o motor da estreia), com o MESMO selo honesto — 🟢 so quando a conferencia fecha.
#
# ACHADO que decide o desenho: o CONTEUDO do checklist NAO e salvo em lugar nenhum (registro e prova so
# guardam checklist_hash; um run verde nem mostra as ancoras). Por isso o KIT RECEBE o arquivo do checklist
# como argumento na criacao — nao da pra reconstruir de uma tarefa ja feita. O kit e quem PASSA a guardar
# o checklist, pra o kit-rodar ter o que rodar.
#
# ADITIVO. NAO reconstroi a conferencia nem o selo: REUSA _norte_estreia_selar (que ja orquestra o motor
# contrato-doc, grava o registro selado + HMAC e vira a fichinha 🟢 pela mesma lei honesta). O kit-rodar
# so RESOLVE o checklist do kit e chama a esteira; o veredito vem do EXIT REAL do motor, NUNCA "verde
# porque e kit".
#
# LEIS (iguais aos outros passos):
#   - PRIVADO POR PADRAO: os kits moram em $HOME/.norte-box/kits/<nome>/; NUNCA saem da maquina. Sem rede.
#   - KILL-SWITCH: NORTE_KITS=0 desliga (recusa, exit 2, amarelo).
#   - Portabilidade macOS (bash 3.2): sem eval, sem array associativo, sem mapfile. O <nome> e tratado
#     como STRING (nunca como comando) e validado como SLUG antes de virar caminho — guarda path-traversal.
#   - FAIL-HONEST: origem 🟢 SO com prova real (3 gates); na duvida, 🟡. kit-rodar recusa se o checklist do
#     kit foi alterado/sumiu desde a criacao (o kit e imutavel).
#
# IMUTABILIDADE (decisao do juiz, risco 1): criar um kit com nome que JA existe RECUSA (exit 2). Nao ha
# --force nesta fatia — pra uma "versao nova", use outro nome (ex: contrato-v2). O kit e uma foto fixa do
# checklist no momento da criacao; o kit-rodar re-hasheia o checklist e compara com essa foto.
set -u

# --- raiz PRIVADA dos kits (a UNICA arvore onde um kit mora) ---
_norte_kits_raiz() { printf '%s/.norte-box/kits' "${HOME}"; }
# raiz dos registros de entrega (compartilhada com a estreia) — de onde a contagem de USOS e DERIVADA.
_norte_kits_entregas_raiz() { printf '%s/.norte-box/entregas' "${HOME}"; }

# _norte_kit_slug_valido <nome> — 0 se <nome> e um SLUG SEGURO pra virar diretorio; 1 caso contrario.
#   ACEITA so [A-Za-z0-9._-]. REJEITA: vazio, "." e "..", qualquer barra, qualquer char de controle, e
#   qualquer coisa fora do conjunto (espaco, ;, *, ?, |, $, aspas, etc). NAO transforma — RECUSA (diferente
#   do _norte_provar_slug, que substitui). Assim um nome perigoso ('../x', 'a; touch ...') nunca vira caminho
#   nem comando: e barrado antes de tocar o disco. O <nome> nunca e executado — so comparado como string.
_norte_kit_slug_valido() {
  local _n="${1:-}"
  [ -n "$_n" ] || return 1
  # "." e ".." sao nomes de diretorio especiais (subir/mesmo dir) — recusa duro.
  case "$_n" in '.'|'..') return 1 ;; esac
  # so o conjunto branco. Qualquer char fora de [A-Za-z0-9._-] reprova (inclui '/', espaco, glob, ';', etc).
  case "$_n" in
    *[!A-Za-z0-9._-]*) return 1 ;;
  esac
  # limite de tamanho (nome de dir sadio; evita nomes absurdos).
  [ "${#_n}" -le 64 ] || return 1
  return 0
}

# _norte_kit_origem_carimbo <checklist> <registro> — ecoa "🟢" ou "🟡 origem nao confirmada".
#   Carimba 🟢 SO se as 3 coisas baterem (decisao do juiz):
#     (a) o checklist_hash do <registro> == hash do <checklist> passado (mesma funcao, mesmo conteudo);
#     (b) o carimbo: do <registro> e 🟢 (ENTREGA PROVADA);
#     (c) _norte_estreia_verificar <registro> confere (rc 0) — a assinatura HMAC do registro bate.
#   Qualquer falha (ou registro ausente, ou funcoes faltando) -> 🟡 (honesto, nao inventa). So LE o disco.
_norte_kit_origem_carimbo() {
  local _chk="${1:-}" _reg="${2:-}"
  local _amarelo='🟡 origem nao confirmada'
  [ -n "$_reg" ] && [ -f "$_reg" ] || { printf '%s\n' "$_amarelo"; return 0; }
  command -v _norte_prova_hash_arquivo >/dev/null 2>&1 || { printf '%s\n' "$_amarelo"; return 0; }
  command -v _norte_estreia_verificar >/dev/null 2>&1 || { printf '%s\n' "$_amarelo"; return 0; }

  # (a) hash do checklist passado == checklist_hash gravado no registro.
  local _h_chk _h_reg
  _h_chk="$(_norte_prova_hash_arquivo "$_chk" 2>/dev/null || true)"
  _h_reg="$(grep -m1 '^checklist_hash: ' "$_reg" 2>/dev/null | sed 's/^checklist_hash: //')"
  [ -n "$_h_chk" ] && [ -n "$_h_reg" ] && [ "$_h_chk" = "$_h_reg" ] || { printf '%s\n' "$_amarelo"; return 0; }

  # (b) o carimbo do registro e 🟢 (ENTREGA PROVADA).
  grep -q '^carimbo: 🟢' "$_reg" 2>/dev/null || { printf '%s\n' "$_amarelo"; return 0; }

  # (c) a assinatura HMAC do registro confere (rc 0).
  _norte_estreia_verificar "$_reg" >/dev/null 2>&1 || { printf '%s\n' "$_amarelo"; return 0; }

  printf '🟢\n'
}

# _norte_kit_criar <nome> <checklist> [registro]
#   Guarda o <checklist> num kit privado kits/<nome>/ e grava o cartao kit.txt. RECUSA se o nome nao for
#   slug seguro (exit 2), se o kit ja existir (imutavel, exit 2), ou se o checklist nao existir/for vazio.
#   RETORNO: 0 criou / 2 nao criou (nome invalido / ja existe / pre-condicao / kill-switch). Nunca sobrescreve.
_norte_kit_criar() {
  local _nome="${1:-}" _chk="${2:-}" _reg="${3:-}"

  # kill-switch.
  case "${NORTE_KITS:-1}" in
    0|no|nao|off|false)
      printf '🟡 os kits nao estao ligados nesta maquina (NORTE_KITS=0).\n'
      return 2 ;;
  esac

  # nome = SLUG seguro (guarda path-traversal e injecao). O nome nunca e executado.
  if ! _norte_kit_slug_valido "$_nome"; then
    printf '🟡 nome de kit invalido: use so letras, numeros, ponto, hifen e underscore (sem barra, espaco, "..") — o nome vira uma pasta.\n'
    return 2
  fi

  # o checklist tem que existir e ter conteudo.
  [ -n "$_chk" ] && [ -f "$_chk" ] || {
    printf '🟡 nao consegui criar o kit: diga qual e o arquivo do checklist (nao achei "%s").\n' "$_chk"
    return 2
  }
  [ -s "$_chk" ] || {
    printf '🟡 nao consegui criar o kit: o checklist esta vazio.\n'
    return 2
  }

  local _raiz _dir
  _raiz="$(_norte_kits_raiz)"
  _dir="${_raiz}/${_nome}"

  # IMUTAVEL: se o kit ja existe, recusa (nao sobrescreve). Sem --force nesta fatia.
  if [ -e "$_dir" ]; then
    printf '🟡 esse kit ja existe — kit e imutavel; use outro nome pra uma versao nova (ex: %s-v2).\n' "$_nome"
    return 2
  fi

  mkdir -p "$_dir" 2>/dev/null || {
    printf '🟡 nao consegui criar o kit (disco nao gravavel).\n'
    return 2
  }

  # copia o checklist pro kit (a foto fixa que o kit-rodar vai re-hashear e comparar).
  cp "$_chk" "$_dir/checklist.txt" 2>/dev/null || {
    rm -rf "$_dir" 2>/dev/null
    printf '🟡 nao consegui guardar o checklist no kit (disco nao gravavel).\n'
    return 2
  }

  # hash do checklist (mesma funcao que o motor usa -> bate com o checklist_hash dos registros).
  local _chkhash=""
  if command -v _norte_prova_hash_arquivo >/dev/null 2>&1; then
    _chkhash="$(_norte_prova_hash_arquivo "$_dir/checklist.txt" 2>/dev/null || true)"
  fi

  # carimbo de ORIGEM: 🟢 so com prova real (3 gates); senao 🟡 honesto. Nao inventa.
  local _origem
  _origem="$(_norte_kit_origem_carimbo "$_dir/checklist.txt" "$_reg")"

  # o cartao do kit — texto puro chave: valor. O <nome> entra como STRING via printf %s (nunca interpretado).
  {
    printf 'nome: %s\n' "$_nome"
    printf 'tipo: doc+checklist\n'
    printf 'quando: %s\n' "$(date -u +%FT%TZ 2>/dev/null || echo t)"
    printf 'checklist_hash: %s\n' "$_chkhash"
    printf 'origem: %s\n' "$_reg"
    printf 'origem_carimbo: %s\n' "$_origem"
  } > "$_dir/kit.txt" 2>/dev/null || {
    rm -rf "$_dir" 2>/dev/null
    printf '🟡 nao consegui gravar o cartao do kit (disco nao gravavel).\n'
    return 2
  }

  printf '🟢 kit "%s" criado — rode em documentos novos com: nb-kit-rodar %s <novo-doc>\n' "$_nome" "$_nome"
  printf '   origem: %s\n' "$_origem"
  return 0
}

# _norte_kit_usos <nome> — ecoa quantos registros de entrega tem rotulo "kit-<nome>". DERIVADO do dado real
#   (conta os registros da esteira), NUNCA um contador proprio. grep -l -x -F casa a linha "rotulo: kit-<nome>"
#   INTEIRA e literal (o nome e string; sem glob/regex). 0 se nenhum. (Risco 2, declarado: varre os registros
#   — aceitavel no volume atual de uma maquina pessoal.)
_norte_kit_usos() {
  local _nome="${1:-}"; [ -n "$_nome" ] || { printf '0\n'; return 0; }
  local _raiz; _raiz="$(_norte_kits_entregas_raiz)"
  [ -d "$_raiz" ] || { printf '0\n'; return 0; }
  local _n
  _n="$(grep -lxF "rotulo: kit-${_nome}" "$_raiz"/entrega-*.txt 2>/dev/null | grep -c .)"
  [ -n "$_n" ] || _n=0
  printf '%s\n' "$_n"
}

# _norte_kit_divergencias <nome> — DEFESA EM PROFUNDIDADE (Val, item 3): conta registros de entrega do
#   kit <nome> que estao 🟢 MAS carregam checklist_hash != o do kit.txt. Com o TOCTOU fechado no kit-rodar
#   isso deve ser SEMPRE 0; se algum dia aparecer >0, e um sinal de que um registro verde rodou um checklist
#   que nao e o do kit (furo novo, adulteracao manual do registro, ou registro de uma versao anterior do
#   codigo). Read-only, derivado do dado real, trata o nome como STRING. 0 se nao ha divergencia/registros.
_norte_kit_divergencias() {
  local _nome="${1:-}"; [ -n "$_nome" ] || { printf '0\n'; return 0; }
  local _kittxt _raiz _hkit
  _kittxt="$(_norte_kits_raiz)/${_nome}/kit.txt"
  [ -f "$_kittxt" ] || { printf '0\n'; return 0; }
  _hkit="$(grep -m1 '^checklist_hash: ' "$_kittxt" 2>/dev/null | sed 's/^checklist_hash: //')"
  [ -n "$_hkit" ] || { printf '0\n'; return 0; }
  _raiz="$(_norte_kits_entregas_raiz)"
  [ -d "$_raiz" ] || { printf '0\n'; return 0; }
  local _reg _div=0 _hr
  # so os registros deste kit (rotulo literal) que estao verdes.
  for _reg in $(grep -lxF "rotulo: kit-${_nome}" "$_raiz"/entrega-*.txt 2>/dev/null); do
    [ -f "$_reg" ] || continue
    grep -q '^carimbo: 🟢' "$_reg" 2>/dev/null || continue
    _hr="$(grep -m1 '^checklist_hash: ' "$_reg" 2>/dev/null | sed 's/^checklist_hash: //')"
    [ -n "$_hr" ] && [ "$_hr" != "$_hkit" ] && _div=$((_div+1))
  done
  printf '%s\n' "$_div"
}

# _norte_kits_catalogo — o CATALOGO: 1 bloco por kit (nome, tipo, quando, origem 🟢/🟡, usos DERIVADO do
#   dado real). Read-only. Fail-honest: sem kits -> diz que nao ha. Trata o nome como STRING.
_norte_kits_catalogo() {
  # kill-switch (o catalogo tambem respeita o desligar dos kits).
  case "${NORTE_KITS:-1}" in
    0|no|nao|off|false)
      printf '🟡 os kits nao estao ligados nesta maquina (NORTE_KITS=0).\n'
      return 2 ;;
  esac

  local _raiz; _raiz="$(_norte_kits_raiz)"
  if [ ! -d "$_raiz" ] || [ -z "$(ls -1 "$_raiz" 2>/dev/null)" ]; then
    printf '📦 nenhum kit ainda. Crie um a partir de uma tarefa provada com: nb-kit-criar <nome> <checklist> [registro]\n'
    return 0
  fi

  printf '📦 CATALOGO DE KITS (o que a caixa ja sabe repetir):\n\n'
  # loop por diretorio de kit (bash 3.2: sem array associativo).
  local _d _kittxt _nome _tipo _quando _origem _usos _div
  for _d in "$_raiz"/*/; do
    [ -d "$_d" ] || continue
    _kittxt="${_d}kit.txt"
    [ -f "$_kittxt" ] || continue
    _nome="$(grep -m1 '^nome: '           "$_kittxt" 2>/dev/null | sed 's/^nome: //')"
    _tipo="$(grep -m1 '^tipo: '           "$_kittxt" 2>/dev/null | sed 's/^tipo: //')"
    _quando="$(grep -m1 '^quando: '       "$_kittxt" 2>/dev/null | sed 's/^quando: //')"
    _origem="$(grep -m1 '^origem_carimbo: ' "$_kittxt" 2>/dev/null | sed 's/^origem_carimbo: //')"
    [ -n "$_nome" ] || _nome="$(basename "$_d")"
    _usos="$(_norte_kit_usos "$_nome")"
    # printf %s pro nome/campos -> STRING, nunca interpretado.
    printf '  • %s\n' "$_nome"
    printf '      tipo: %s · origem: %s · usos: %s\n' "$_tipo" "$_origem" "$_usos"
    printf '      criado: %s\n' "$_quando"
    printf '      rodar: nb-kit-rodar %s <novo-doc>\n' "$_nome"
    # DEFESA EM PROFUNDIDADE (Val): so imprime a linha de alerta se houver divergencia (>0). No caminho
    # sadio (0), o formato do bloco fica IGUAL ao de antes — nao mexe nas assercoes do catalogo.
    _div="$(_norte_kit_divergencias "$_nome")"
    [ "${_div:-0}" -gt 0 ] && printf '      🟡 ALERTA: %s registro(s) verde(s) deste kit tem checklist_hash != o do kit (rodaram um checklist diferente do kit — investigue).\n' "$_div"
    printf '\n'
  done
  return 0
}

# _norte_kit_rodar <nome> <novo-doc>
#   Roda a conferencia do kit <nome> no documento novo, pela ESTEIRA REAL (_norte_estreia_selar). Antes,
#   RESOLVE o checklist do kit e RE-HASHEIA: se o checklist do kit foi ALTERADO desde a criacao (hash !=
#   kit.txt) ou SUMIU -> RECUSA 🟡 (exit 2) — nao roda com um checklist que ja nao e o do kit.
#   Batendo, chama _norte_estreia_selar "<novo-doc>" "<copia do checklist>" "kit-<nome>". O selo, o
#   registro e o HMAC saem do motor REAL; o exit espelha o motor (0/1/2). Nunca "verde porque e kit".
#
#   FURO TOCTOU (achado da Val, ~15% sob corrida): antes, o hash de integridade era tirado do
#   kits/<nome>/checklist.txt e ESSE MESMO caminho era passado pro motor, que o LE DE NOVO. Um processo
#   concorrente que trocasse o checklist.txt ENTRE as duas leituras fazia o kit selar 🟢 rodando um
#   checklist DIFERENTE do que teve o hash conferido. Conserto (sem lock): COPIA o checklist do kit pra
#   um arquivo temporario DENTRO da arvore controlada, HASHEIA A COPIA e roda O MOTOR SOBRE A COPIA — o
#   hash conferido e a rodada usam os MESMOS BYTES (o mesmo arquivo). Trocar o original depois da copia
#   nao afeta; trocar antes da copia faz o hash da copia divergir do kit.txt -> RECUSA (correto).
_norte_kit_rodar() {
  local _nome="${1:-}" _doc="${2:-}"

  # kill-switch.
  case "${NORTE_KITS:-1}" in
    0|no|nao|off|false)
      printf '🟡 os kits nao estao ligados nesta maquina (NORTE_KITS=0).\n'
      return 2 ;;
  esac

  # nome = slug seguro (mesma guarda da criacao — o nome vira caminho).
  if ! _norte_kit_slug_valido "$_nome"; then
    printf '🟡 nome de kit invalido.\n'
    return 2
  fi

  [ -n "$_doc" ] && [ -f "$_doc" ] || {
    printf '🟡 nao consegui rodar o kit: diga qual e o documento novo (nao achei "%s").\n' "$_doc"
    return 2
  }

  local _raiz _dir _chk _kittxt
  _raiz="$(_norte_kits_raiz)"
  _dir="${_raiz}/${_nome}"
  _chk="${_dir}/checklist.txt"
  _kittxt="${_dir}/kit.txt"

  [ -d "$_dir" ] && [ -f "$_kittxt" ] || {
    printf '🟡 nao achei o kit "%s". Veja os que existem com: nb-kits\n' "$_nome"
    return 2
  }

  # o checklist do kit tem que existir (nao pode ter sumido).
  [ -f "$_chk" ] || {
    printf '🟡 nao consegui rodar o kit "%s": o checklist dele sumiu.\n' "$_nome"
    return 2
  }

  command -v _norte_prova_hash_arquivo >/dev/null 2>&1 || {
    printf '🟡 nao consegui verificar a integridade do kit (motor de hash ausente).\n'
    return 2
  }

  # --- FECHA A JANELA TOCTOU: 1 SO COPIA, e o hash + a rodada usam a MESMA copia. ---
  # arvore controlada pro temporario (privada, 0700). Se nao der pra criar/copiar -> degrada honesto.
  local _tmpdir _copia
  _tmpdir="${HOME}/.norte-box/tmp"
  ( umask 077; mkdir -p "$_tmpdir" ) 2>/dev/null || {
    printf '🟡 nao consegui preparar area temporaria pra rodar o kit (disco nao gravavel).\n'
    return 2
  }
  _copia="$(umask 077; mktemp "$_tmpdir/kit-run-XXXXXX" 2>/dev/null || true)"
  [ -n "$_copia" ] && [ -f "$_copia" ] || {
    printf '🟡 nao consegui preparar area temporaria pra rodar o kit (disco nao gravavel).\n'
    return 2
  }
  # limpa a copia SEMPRE (sucesso ou erro), sem rm -rf — so o arquivo especifico.
  # shellcheck disable=SC2064
  trap "rm -f \"$_copia\" 2>/dev/null" RETURN

  cp "$_chk" "$_copia" 2>/dev/null || {
    printf '🟡 nao consegui preparar o checklist do kit pra rodar (disco nao gravavel).\n'
    return 2
  }

  # RE-HASHEIA A COPIA e compara com o hash gravado na criacao. Adulterado (ou trocado antes da copia) ->
  # RECUSA (nao roda um checklist trocado). A partir daqui, TUDO usa a copia — a corrida nao tem janela.
  local _h_copia _h_kit
  _h_copia="$(_norte_prova_hash_arquivo "$_copia" 2>/dev/null || true)"
  _h_kit="$(grep -m1 '^checklist_hash: ' "$_kittxt" 2>/dev/null | sed 's/^checklist_hash: //')"
  if [ -z "$_h_copia" ] || [ -z "$_h_kit" ] || [ "$_h_copia" != "$_h_kit" ]; then
    printf '🟡 o checklist deste kit foi alterado desde a criacao — nao vou rodar com um checklist trocado (o kit e imutavel).\n'
    return 2
  fi

  # esteira REAL: o selo/registro/HMAC vem do motor. rotulo = kit-<nome> (aparece no nb-tarefas).
  # PASSA A COPIA (nao o original): o hash conferido e a rodada leem os MESMOS bytes -> sem TOCTOU.
  command -v _norte_estreia_selar >/dev/null 2>&1 || {
    printf '🟡 nao consegui rodar o kit: o motor da estreia nao esta disponivel nesta instalacao.\n'
    return 2
  }
  _norte_estreia_selar "$_doc" "$_copia" "kit-${_nome}"
  return $?
}

# _norte_kit_strip_controle — filtro de EXIBICAO: apaga chars de controle EXCETO TAB. Preserva UTF-8/acentos
#   (nao toca em bytes >= 0x80) e o TAB (0x09). Remove 0x00-0x08, 0x0B-0x1F e 0x7F (DEL). NAO remove a quebra
#   de linha porque o CALLER ja quebrou o texto em linhas (le linha-a-linha) — o \n nunca chega aqui dentro de
#   uma linha; um \n embutido numa "linha" (via read) so viria de \r\n e o \r (0x0D) e' apagado. bash-3.2-safe.
#   Le stdin, escreve stdout. Guarda o 1o comando que despeja conteudo de kit na tela: nada de escape de terminal.
_norte_kit_strip_controle() { tr -d '\000-\010\013-\037\177'; }

# _norte_kit_ver <nome> — CARTAO READ-ONLY do que um kit faz (NRT-_746, fatia VER).
#   O buraco: nb-kit-gerar exige saber as lacunas {{campo}} do modelo, mas NENHUM comando as mostra; nem da pra
#   ver o que um kit CONFERE sem abrir arquivo. Este comando fecha isso — SO LE (read-only): kit.txt + checklist.txt
#   + as lacunas do modelo.txt. NAO escreve em kits/, NAO emite selo, NAO toca registro (anti-circular por
#   construcao — nao chama a esteira).
#
#   SELO HONESTO (a lei mais importante deste comando): mostra "origem (gravada)" (REPRINT LITERAL do campo do
#   kit.txt, NUNCA promovido a 🟢) SEPARADO de "integridade agora" (hash do checklist+modelo recomputado AGORA x
#   o checklist_hash gravado no kit.txt). O viewer NUNCA fabrica verde: no maximo REBAIXA a confianca (se o hash
#   diverge -> 🟡 explicito, avisando que o nb-kit-rodar vai recusar). Verde aqui e' so "os bytes de hoje batem
#   com o cartao", nao "o kit provou algo".
#
#   SEGURANCA (1o comando que despeja conteudo do kit na tela): STRIP de chars de controle exceto TAB em TODA
#   linha exibida (ancora/descricao) — bloqueia escapes de terminal. CAP de exibicao: 50 linhas de CONFERE +
#   "…e mais N" (N REAL, nao esconde a contagem). O <nome> e' validado como SLUG antes de virar caminho; o dado
#   nunca vira comando (printf '%s').
#   KILL-SWITCH: NORTE_KITS=0 (a familia toda) e NORTE_KIT_VER=0 (so este) -> recusa 🟡, exit 2.
#   RETORNO: 0 mostrou / 2 recusa (kill / slug / kit inexistente).
_norte_kit_ver() {
  local _nome="${1:-}"

  # kill-switch da familia + o proprio.
  case "${NORTE_KITS:-1}" in
    0|no|nao|off|false)
      printf '🟡 os kits nao estao ligados nesta maquina (NORTE_KITS=0).\n'
      return 2 ;;
  esac
  case "${NORTE_KIT_VER:-1}" in
    0|no|nao|off|false)
      printf '🟡 o "ver kit" nao esta ligado nesta maquina (NORTE_KIT_VER=0).\n'
      return 2 ;;
  esac

  # nome = SLUG seguro (o nome vira caminho; guarda path-traversal e injecao). O nome nunca e' executado.
  if ! _norte_kit_slug_valido "$_nome"; then
    printf '🟡 nome de kit invalido: use so letras, numeros, ponto, hifen e underscore (sem barra, espaco, "..").\n'
    return 2
  fi

  local _raiz _dir _kittxt _chk _mod
  _raiz="$(_norte_kits_raiz)"
  _dir="${_raiz}/${_nome}"
  _kittxt="${_dir}/kit.txt"
  _chk="${_dir}/checklist.txt"
  _mod="${_dir}/modelo.txt"

  # kit inexistente -> recusa 🟡, exit 2.
  [ -d "$_dir" ] && [ -f "$_kittxt" ] || {
    printf '🟡 nao achei o kit "%s". Veja os que existem com: nb-kits\n' "$_nome"
    return 2
  }

  # --- campos do cartao (LE do disco, reprint literal onde manda a lei) ---
  local _nome_reg _quando _origem_reg _hkit
  _nome_reg="$(grep -m1 '^nome: '           "$_kittxt" 2>/dev/null | sed 's/^nome: //')"
  _quando="$(grep -m1  '^quando: '          "$_kittxt" 2>/dev/null | sed 's/^quando: //')"
  # ORIGEM (gravada): REPRINT LITERAL do campo origem_carimbo do kit.txt. NUNCA promovida a 🟢 pelo viewer.
  _origem_reg="$(grep -m1 '^origem_carimbo: ' "$_kittxt" 2>/dev/null | sed 's/^origem_carimbo: //')"
  _hkit="$(grep -m1 '^checklist_hash: '     "$_kittxt" 2>/dev/null | sed 's/^checklist_hash: //')"
  [ -n "$_nome_reg" ] || _nome_reg="$_nome"
  [ -n "$_origem_reg" ] || _origem_reg='(nao registrada)'

  # TIPO derivado do DISCO (nao do campo tipo: do kit.txt, que sempre grava doc+checklist): tem modelo.txt
  # nao-vazio -> "doc+checklist" (gera); senao -> "so checklist".
  local _tem_modelo=1 _tipo='so checklist'
  if command -v _norte_kit_modelo_relevante >/dev/null 2>&1 && _norte_kit_modelo_relevante "$_mod"; then
    _tem_modelo=0; _tipo='doc+checklist'
  fi

  local _usos
  _usos="$(_norte_kit_usos "$_nome_reg" 2>/dev/null)"; [ -n "$_usos" ] || _usos=0

  # --- INTEGRIDADE AGORA: recomputa o hash do CHECKLIST e compara com o gravado no kit.txt. ---
  # ESPELHA EXATAMENTE o que o nb-kit-rodar faz (_norte_kit_rodar re-hasheia SO o checklist.txt via
  # _norte_prova_hash_arquivo e compara com checklist_hash do kit.txt) — a mensagem promete "o nb-kit-rodar
  # vai recusar", entao a integridade tem que usar O MESMO criterio do rodar, senao mente. IMPORTANTE: o
  # sistema atual grava/confere o hash do checklist SOZINHO mesmo em kit COM modelo (o modelo.txt NAO entra
  # no checklist_hash nem no gate do rodar) — o viewer NAO pode fingir cobrir mais do que o rodar cobre.
  # RISCO RESIDUAL declarado: trocar SO o modelo.txt de um kit ja criado nao muda esta integridade nem e'
  # barrado pelo rodar — e' um furo do sistema (o checklist_hash nao cobre o modelo), nao deste viewer.
  # Se bate -> 🟢 "bate com o cartao"; diverge/sem hash/motor ausente -> 🟡 (rebaixa, nunca fabrica verde).
  local _integridade _hnow=""
  if [ ! -f "$_chk" ]; then
    _integridade='🟡 o checklist deste kit sumiu — o nb-kit-rodar vai recusar'
  elif ! command -v _norte_prova_hash_arquivo >/dev/null 2>&1 || [ -z "$_hkit" ]; then
    _integridade='🟡 nao consegui recomputar a integridade (motor de hash ausente ou cartao sem hash)'
  else
    _hnow="$(_norte_prova_hash_arquivo "$_chk" 2>/dev/null || true)"
    if [ -n "$_hnow" ] && [ "$_hnow" = "$_hkit" ]; then
      _integridade="🟢 bate com o cartao (hash ${_hkit})"
    else
      _integridade='🟡 ALTERADO desde a criacao — o nb-kit-rodar vai recusar'
    fi
  fi

  # ============================ IMPRESSAO ============================
  printf '📦 %s\n' "$_nome_reg"
  printf '   tipo: %s · origem (gravada): %s · usos: %s · criado: %s\n' "$_tipo" "$_origem_reg" "$_usos" "$_quando"
  printf '   integridade agora: %s\n' "$_integridade"

  # --- CONFERE (as exigencias do checklist) — linhas de conteudo (ignora vazias/comentarios, igual ao motor). ---
  # Cada linha "descricao :: ancora": mostra "descricao" + a "ancora" entre aspas. Sem "::", mostra a linha crua.
  # STRIP de controle em TUDO que e' exibido. CAP de 50 linhas + "…e mais N" (N real).
  local _cap=50
  if [ -f "$_chk" ]; then
    # 1a passada: conta as linhas de conteudo (pra o N real do cap).
    local _total=0 _linha
    while IFS= read -r _linha || [ -n "$_linha" ]; do
      case "$_linha" in ''|'#'*) continue ;; esac
      case "$(printf '%s' "$_linha" | tr -d '[:space:]')" in '') continue ;; esac
      _total=$((_total+1))
    done < "$_chk"

    printf '   CONFERE (%s exigencia%s):\n' "$_total" "$([ "$_total" -eq 1 ] && printf '' || printf 's')"
    # 2a passada: imprime ate o cap.
    local _num=0 _desc _anc
    while IFS= read -r _linha || [ -n "$_linha" ]; do
      case "$_linha" in ''|'#'*) continue ;; esac
      case "$(printf '%s' "$_linha" | tr -d '[:space:]')" in '') continue ;; esac
      _num=$((_num+1))
      [ "$_num" -gt "$_cap" ] && continue
      # STRIP de controle na linha ANTES de fatiar/exibir (defesa do 1o despejo de conteudo na tela).
      _linha="$(printf '%s' "$_linha" | _norte_kit_strip_controle)"
      if printf '%s' "$_linha" | grep -q '::'; then
        _desc="$(printf '%s' "$_linha" | sed -e 's/ *::.*$//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
        _anc="$(printf '%s' "$_linha" | sed -e 's/^[^:]*:: *//')"
        printf '     %s. %s :: "%s"\n' "$_num" "$_desc" "$_anc"
      else
        printf '     %s. %s\n' "$_num" "$_linha"
      fi
    done < "$_chk"
    if [ "$_total" -gt "$_cap" ]; then
      printf '     …e mais %s\n' "$((_total - _cap))"
    fi
  else
    printf '   CONFERE: 🟡 o checklist deste kit sumiu.\n'
  fi

  # --- GERA (as lacunas do modelo, se houver) — mostra SO os nomes das lacunas (nunca o modelo.txt inteiro). ---
  if [ "$_tem_modelo" -eq 0 ] && command -v _norte_kit_modelo_campos >/dev/null 2>&1; then
    local _campos_lista _k=0 _linha_campos=""
    _campos_lista="$(_norte_kit_modelo_campos "$_mod" 2>/dev/null)"
    local _campo
    # monta "{{c1}} {{c2}} ..." e conta K. Aplica strip de controle (defesa; campos ja sao [a-z0-9_-]).
    while IFS= read -r _campo || [ -n "$_campo" ]; do
      [ -n "$_campo" ] || continue
      _campo="$(printf '%s' "$_campo" | _norte_kit_strip_controle)"
      _k=$((_k+1))
      _linha_campos="${_linha_campos} {{${_campo}}}"
    done <<EOF
$_campos_lista
EOF
    printf '   GERA: sim — modelo com %s lacuna%s:%s\n' "$_k" "$([ "$_k" -eq 1 ] && printf '' || printf 's')" "$_linha_campos"
    printf '         nb-kit-gerar %s <valores.txt> [saida]\n' "$_nome_reg"
  else
    printf '   GERA: nao (kit sem modelo.txt)\n'
  fi

  # --- como rodar a conferencia num doc novo ---
  printf '   rodar: nb-kit-rodar %s <novo-doc>\n' "$_nome_reg"
  return 0
}
