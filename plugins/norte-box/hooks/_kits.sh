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
