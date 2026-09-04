#!/usr/bin/env bash
# _kit_fabrica.sh — a FABRICA DE KITS (creator mode): a PORTA DA FRENTE do kit (NRT-_990148, fatia 1).
#
# O buraco que esta peca fecha: hoje nb-kit-criar exige um checklist JA PRONTO (um arquivo com as exigencias
# escritas). Quem chega descrevendo uma tarefa na boca ("quero conferir se um contrato tem partes, valor,
# prazo e foro") nao tem por onde comecar — nao existe onde REDIGIR o checklist com preview antes de salvar.
# A fabrica e esse comeco: DESCREVE -> o AGENTE redige um rascunho -> PREVIEW -> APROVA (por token) -> salva
# REUSANDO nb-kit-criar (o motor de guardar; a fabrica NAO reimplementa o salvar). O kit nasce igual ao de
# hoje: imutavel, privado, e com ORIGEM 🟡 honesta (o kit de fabrica ainda nao PROVOU nada — o 🟢 so vem
# depois do 1o nb-kit-rodar, que roda a esteira REAL contra um doc de verdade).
#
# O PORTAO (Proposta A — token amarrado ao CONTEUDO): aprovar exige um TOKEN = os 8 primeiros chars do hash
# do checklist do rascunho. O preview EMITE esse token; aprovar re-hasheia e SO segue se bater. Se a pessoa
# (ou o agente) editar o rascunho entre o preview e o aprovar, o hash muda, o token velho nao bate mais e a
# aprovacao RECUSA — "nao vou aprovar bytes diferentes dos que voce viu". O token e a prova de que o que esta
# sendo salvo e' EXATAMENTE o que foi mostrado. (Amarra o consentimento ao conteudo, nao ao nome.)
#
# LEIS (iguais aos outros passos do norte-box):
#   - PRIVADO POR PADRAO: os rascunhos moram em $HOME/.norte-box/rascunhos/<nome>/; NUNCA saem da maquina. Sem rede.
#   - KILL-SWITCH: NORTE_KIT_FABRICA=0 desliga (recusa, exit 2, amarelo).
#   - Portabilidade macOS (bash 3.2): sem eval, sem array associativo, sem mapfile, sem ${var,,}. O <nome> e'
#     tratado como STRING (nunca como comando) e validado como SLUG antes de virar caminho — guarda traversal.
#   - FAIL-HONEST: rascunho vazio/malformado = estruturalmente INAPROVAVEL (o preview NAO emite token). Nada
#     auto: aprovar so acontece por chamada explicita com o token do ULTIMO preview.
#   - IMUTABILIDADE herdada: se um KIT com esse nome ja existe, a fabrica RECUSA CEDO (antes de a pessoa
#     investir no rascunho) — o kit e uma foto fixa; pra versao nova, outro nome.
#
# RISCO RESIDUAL declarado (honestidade): o token e' ANTI-CONFUSAO (garante que o byte aprovado == o byte
# visto), NAO um segredo criptografico — sao 8 chars publicos, visiveis no preview. Ele impede aprovar por
# engano um conteudo trocado; NAO e' um mecanismo de autenticacao contra um atacante local que ja pode ler
# e reescrever o rascunho a vontade (nesse modelo, quem controla o HOME controla tudo — igual ao resto da
# caixa). A defesa REAL contra corrida (troca do arquivo ENTRE re-hash e save) e' o ANTI-TOCTOU do aprovar:
# hash + lint + save rodam todos sobre a MESMA COPIA (os mesmos bytes) — copiada do padrao do _norte_kit_rodar.
set -u

# --- raiz PRIVADA dos rascunhos (a arvore onde um rascunho mora ATE ser aprovado e virar kit) ---
_norte_fabrica_raiz() { printf '%s/.norte-box/rascunhos' "${HOME}"; }

# _norte_kit_rascunho_lint <arquivo> — LINT do formato do checklist da fabrica.
#   REGRA: cada linha de CONTEUDO precisa casar "descricao :: ancora" com <ancora> NAO-vazia. Linha vazia (so
#   espacos) e linha de COMENTARIO ('#'...) sao IGNORADAS — igual ao motor contrato-doc (que pula ''|'#'*).
#   Assim um rascunho que PASSA o lint da fabrica tambem e aceito pelo motor (o lint e mais restritivo de
#   proposito: ensina o formato canonico "desc :: ancora", sem os atalhos "NAO:" / "sem ::" do motor).
#   RETORNO: 0 SO se ha >=1 linha de conteudo E todas casam (ancora nao-vazia); 1 caso contrario.
#   ECOA "ok=<n> ruins=<n>" (pra o preview mostrar o que esta certo/errado). Read-only; nao executa o dado.
_norte_kit_rascunho_lint() {
  local _arq="${1:-}"
  [ -n "$_arq" ] && [ -f "$_arq" ] || { printf 'ok=0 ruins=0\n'; return 1; }
  local _linha _ok=0 _ruins=0 _limpa _desc _anc
  while IFS= read -r _linha || [ -n "$_linha" ]; do
    # ignora linha vazia (so espacos) e comentario '#' — mesmo criterio do motor.
    case "$_linha" in ''|'#'*) continue ;; esac
    case "$(printf '%s' "$_linha" | tr -d '[:space:]')" in '') continue ;; esac
    # precisa ter o separador "::".
    if ! printf '%s' "$_linha" | grep -q '::'; then
      _ruins=$((_ruins+1)); continue
    fi
    # separa "descricao :: ancora" e apara as pontas (mesmo corte do motor).
    _desc="$(printf '%s' "$_linha" | sed 's/ *::.*$//')"
    _anc="$(printf '%s' "$_linha" | sed 's/^[^:]*:: *//')"
    _anc="$(printf '%s' "$_anc" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    _desc="$(printf '%s' "$_desc" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    # ancora vazia -> linha ruim (uma exigencia sem o que conferir nao prova nada).
    if [ -z "$_anc" ]; then
      _ruins=$((_ruins+1)); continue
    fi
    _ok=$((_ok+1))
  done < "$_arq"
  printf 'ok=%s ruins=%s\n' "$_ok" "$_ruins"
  # verde SO com >=1 linha boa e ZERO ruim.
  [ "$_ok" -ge 1 ] && [ "$_ruins" -eq 0 ]
}

# _norte_kit_rascunho_criar <nome> — abre (idempotente) a area de rascunho de um kit novo.
#   Recusa CEDO se o kit JA existe (imutavel) — antes de a pessoa investir escrevendo o rascunho.
#   Cria rascunhos/<nome>/ (umask 077) + checklist.txt VAZIO (se ainda nao existe) + rascunho.txt (cartao).
#   IDEMPOTENTE: re-rodar NAO apaga conteudo ja escrito no checklist.txt (nao sobrescreve).
#   ECOA o CAMINHO ABSOLUTO do checklist.txt (pra o agente saber ONDE escrever as linhas).
#   RETORNO: 0 pronto / 2 recusa (kill-switch / nome invalido / kit ja existe / disco).
_norte_kit_rascunho_criar() {
  local _nome="${1:-}"

  # kill-switch.
  case "${NORTE_KIT_FABRICA:-1}" in
    0|no|nao|off|false)
      printf '🟡 a fabrica de kits nao esta ligada nesta maquina (NORTE_KIT_FABRICA=0).\n'
      return 2 ;;
  esac

  # nome = SLUG seguro (o nome vira caminho; guarda traversal e injecao). Reusa a guarda dos kits.
  if ! command -v _norte_kit_slug_valido >/dev/null 2>&1 || ! _norte_kit_slug_valido "$_nome"; then
    printf '🟡 nome de kit invalido: use so letras, numeros, ponto, hifen e underscore (sem barra, espaco, "..") — o nome vira uma pasta.\n'
    return 2
  fi

  # IMUTABILIDADE herdada: se o KIT ja existe, recusa CEDO (nao adianta rascunhar — nb-kit-criar recusaria).
  local _kitdir
  if command -v _norte_kits_raiz >/dev/null 2>&1; then
    _kitdir="$(_norte_kits_raiz)/${_nome}"
  else
    _kitdir="${HOME}/.norte-box/kits/${_nome}"
  fi
  if [ -e "$_kitdir" ]; then
    printf '🟡 esse kit ja existe (imutavel) — use outro nome pra uma versao nova (ex: %s-v2).\n' "$_nome"
    return 2
  fi

  local _raiz _dir _chk
  _raiz="$(_norte_fabrica_raiz)"
  _dir="${_raiz}/${_nome}"
  _chk="${_dir}/checklist.txt"

  # cria a area do rascunho (privada, 0700). Idempotente: mkdir -p nao reclama se ja existe.
  ( umask 077; mkdir -p "$_dir" ) 2>/dev/null || {
    printf '🟡 nao consegui abrir a area do rascunho (disco nao gravavel).\n'
    return 2
  }

  # checklist.txt VAZIO — SO se ainda nao existe (idempotente: nao apaga o que ja foi escrito).
  if [ ! -e "$_chk" ]; then
    ( umask 077; : > "$_chk" ) 2>/dev/null || {
      printf '🟡 nao consegui preparar o arquivo do checklist do rascunho (disco nao gravavel).\n'
      return 2
    }
  fi

  # o cartao do rascunho — texto puro chave: valor. O <nome> entra como STRING via printf %s (nunca interpretado).
  ( umask 077
    {
      printf 'nome: %s\n' "$_nome"
      printf 'quando: %s\n' "$(date -u +%FT%TZ 2>/dev/null || echo t)"
      printf 'estado: rascunho\n'
    } > "${_dir}/rascunho.txt"
  ) 2>/dev/null || {
    printf '🟡 nao consegui gravar o cartao do rascunho (disco nao gravavel).\n'
    return 2
  }

  # ecoa o CAMINHO absoluto do checklist.txt (o agente escreve as linhas "desc :: ancora" nele).
  printf '📝 rascunho "%s" aberto. Escreva as exigencias (uma por linha, "descricao :: ancora") em:\n' "$_nome"
  printf '   %s\n' "$_chk"
  return 0
}

# _norte_kit_rascunho_preview <nome> — mostra o rascunho NUMERADO + veredito do lint; SO emite o token de
#   aprovacao SE o lint passar. Rascunho vazio/malformado = estruturalmente INAPROVAVEL -> diz o que esta
#   errado e NAO emite token (nao da pra aprovar o que nao confere).
#   O TOKEN = os 8 primeiros chars do hash do checklist.txt (amarra a aprovacao ao CONTEUDO exato mostrado).
#   RETORNO: 0 preview ok (com ou sem token) / 2 recusa (kill / slug / checklist ausente).
_norte_kit_rascunho_preview() {
  local _nome="${1:-}"

  # kill-switch.
  case "${NORTE_KIT_FABRICA:-1}" in
    0|no|nao|off|false)
      printf '🟡 a fabrica de kits nao esta ligada nesta maquina (NORTE_KIT_FABRICA=0).\n'
      return 2 ;;
  esac

  if ! command -v _norte_kit_slug_valido >/dev/null 2>&1 || ! _norte_kit_slug_valido "$_nome"; then
    printf '🟡 nome de kit invalido.\n'
    return 2
  fi

  local _chk
  _chk="$(_norte_fabrica_raiz)/${_nome}/checklist.txt"
  [ -f "$_chk" ] || {
    printf '🟡 nao achei o rascunho "%s". Abra um com: nb-kit-rascunho %s\n' "$_nome" "$_nome"
    return 2
  }

  printf '📄 PREVIEW do rascunho "%s" — o que vai virar checklist:\n\n' "$_nome"
  # imprime NUMERADO so as linhas de CONTEUDO (ignora vazias/comentarios, igual ao lint/motor).
  local _linha _num=0
  while IFS= read -r _linha || [ -n "$_linha" ]; do
    case "$_linha" in ''|'#'*) continue ;; esac
    case "$(printf '%s' "$_linha" | tr -d '[:space:]')" in '') continue ;; esac
    _num=$((_num+1))
    printf '   %s. %s\n' "$_num" "$_linha"
  done < "$_chk"
  [ "$_num" -eq 0 ] && printf '   (rascunho vazio — nenhuma exigencia escrita ainda)\n'
  printf '\n'

  # veredito do lint. Captura a contagem ok/ruins pra a mensagem, e o rc pra decidir o token.
  local _lint _lint_rc
  _lint="$(_norte_kit_rascunho_lint "$_chk")"; _lint_rc=$?

  if [ "$_lint_rc" -eq 0 ]; then
    printf '✅ o formato confere (%s). Este rascunho pode virar kit.\n' "$_lint"
    # SO com o lint verde: calcula o token (8 primeiros chars do hash do checklist).
    local _token=""
    if command -v _norte_prova_hash_arquivo >/dev/null 2>&1; then
      _token="$(_norte_prova_hash_arquivo "$_chk" 2>/dev/null | cut -c1-8)"
    fi
    if [ -n "$_token" ]; then
      printf '\n   pra aprovar: nb-kit-aprovar %s --confirmo %s\n' "$_nome" "$_token"
      printf '   (o token e destes bytes exatos; se voce editar o rascunho, ele muda e o antigo nao vale mais)\n'
    else
      printf '\n🟡 nao consegui calcular o token de aprovacao (motor de hash ausente).\n'
    fi
  else
    printf '🟡 o formato NAO confere (%s). Cada linha precisa ser "descricao :: ancora" (a ancora, o texto que\n' "$_lint"
    printf '   o documento bom deve conter, nao pode ficar vazia). Rascunho vazio/malformado NAO pode ser aprovado.\n'
    printf '   Corrija as linhas e rode o preview de novo.\n'
  fi
  return 0
}

# _norte_kit_aprovar <nome> <token> [doc] — APROVA o rascunho: valida o token contra o CONTEUDO atual, e SO
#   entao salva o kit REUSANDO _norte_kit_criar (o motor de guardar; a fabrica NAO reimplementa o salvar).
#
#   ANTI-TOCTOU (COPIA do padrao do _norte_kit_rodar): faz UMA copia do checklist.txt do rascunho numa arvore
#   controlada; o re-hash (validacao do token), o re-lint e o SAVE rodam todos sobre a MESMA copia (os mesmos
#   bytes). Trocar o original DEPOIS da copia nao afeta; trocar ANTES da copia faz o hash da copia divergir do
#   token -> RECUSA (correto). Fecha a janela "aprovei X, salvei Y".
#
#   Chamado SEM registro (3o arg de _norte_kit_criar) -> a ORIGEM sai 🟡 honesta (o kit de fabrica ainda nao
#   provou nada). O 🟢 so vem depois do 1o nb-kit-rodar (motor real).
#   Sucesso (kit criado, rc 0): remove SO rascunhos/<nome>/ (nao toca em kits/) e aponta o nb-kit-rodar.
#   Falha do save: PRESERVA o rascunho (a pessoa nao perde o trabalho).
#
#   FATIA 2 — 3o arg OPCIONAL [doc]: "aprovou -> roda logo num doc de teste" (fecha o ciclo na hora). SEM
#   [doc], o comportamento e BYTE-IDENTICO a fatia 1 (mesma saida, mesmo exit) — a regressao e SAGRADA. COM
#   [doc], DEPOIS de salvar o kit, roda o 1o teste REAL nesse documento via _norte_kit_rodar (motor real) — o
#   selo/registro/HMAC saem DELE (reuso total). Pre-checagens do [doc] rodam ANTES de aprovar/salvar (nao
#   meio-faz; se qualquer uma reprovar, NADA e salvo):
#     - kill-switch NORTE_KIT_FABRICA_RODAR (0/no/nao/off/false -> recusa 🟡 exit 2, nada salvo);
#     - o doc precisa existir ([ -f ]);
#     - PORTAO ANTI-PROVA-CIRCULAR: o doc NAO pode morar dentro de $HOME/.norte-box/ (e a pasta onde a fabrica
#       escreve os rascunhos — deixar o doc vir dali seria a maquina fabricando o proprio doc que passa de
#       graca). O teste tem que vir de um documento de VERDADE da pessoa, de fora da caixa.
#   HONESTIDADE: o 🟢 NUNCA vem da aprovacao — so do motor real. Se o run der 🟡 (doc nao cobre as ancoras), o
#   kit CONTINUA salvo e o veredito e 🟡 honesto (o teste e informacao, nao desfaz o salvar). O exit final
#   COM [doc] espelha o exit do _norte_kit_rodar (0/1/2).
#   RETORNO: SEM [doc] -> espelha _norte_kit_criar no sucesso (0); 2 nas recusas da fabrica (kill/slug/ausente/
#   token/lint). COM [doc] -> 2 nas pre-checagens/recusas; senao espelha o motor real (0/1/2) apos salvar.
_norte_kit_aprovar() {
  local _nome="${1:-}" _token="${2:-}" _doc="${3:-}"

  # kill-switch.
  case "${NORTE_KIT_FABRICA:-1}" in
    0|no|nao|off|false)
      printf '🟡 a fabrica de kits nao esta ligada nesta maquina (NORTE_KIT_FABRICA=0).\n'
      return 2 ;;
  esac

  if ! command -v _norte_kit_slug_valido >/dev/null 2>&1 || ! _norte_kit_slug_valido "$_nome"; then
    printf '🟡 nome de kit invalido.\n'
    return 2
  fi

  [ -n "$_token" ] || {
    printf '🟡 diga o token do ultimo preview: nb-kit-aprovar %s --confirmo <token>\n' "$_nome"
    return 2
  }

  # --- FATIA 2: PRE-CHECAGENS do [doc] ANTES de aprovar/salvar (nao meio-faz). So valem quando [doc] passado. ---
  # A ordem importa: sao portoes que, reprovando, deixam TUDO intacto (nada salvo, rascunho preservado).
  if [ -n "$_doc" ]; then
    # kill-switch NOVO, so do "rodar na hora" (separado do NORTE_KIT_FABRICA que liga a fabrica inteira).
    case "${NORTE_KIT_FABRICA_RODAR:-1}" in
      0|no|nao|off|false)
        printf '🟡 o "rodar na hora" nao esta ligado nesta maquina (NORTE_KIT_FABRICA_RODAR=0) — nada foi salvo. Aprove sem o teste (nb-kit-aprovar %s --confirmo %s) e rode depois com nb-kit-rodar.\n' "$_nome" "$_token"
        return 2 ;;
    esac
    # o documento de teste precisa existir.
    [ -f "$_doc" ] || {
      printf '🟡 nao achei o documento de teste "%s" — nada foi salvo. Passe um arquivo que exista.\n' "$_doc"
      return 2
    }
    # PORTAO ANTI-PROVA-CIRCULAR: resolve o doc pro caminho FISICO REAL e recusa se mora dentro de
    # $HOME/.norte-box/ (a caixa). Senao o agente poderia fabricar um doc que passa de graca (prova circular).
    # O teste vem da PESSOA. LICAO DO VAL (3 rodadas): NAO reimplementar canonicalizacao a mao — a versao
    # artesanal (cd -P + readlink) vazou 3× por cantos do test/cd (symlink no ultimo componente, ".." apos
    # symlink-de-dir, e trailing slash que curto-circuita o [ -L ]). A cura DURAVEL e delegar ao _norte_realpath
    # (que usa o realpath do sistema; ja resolve symlink + ".." + barra final de uma vez, provado == /bin/realpath).
    # RESIDUAL declarado (modelo da caixa — anti-CONFUSAO, nao anti-atacante-local): HARDLINK dentro->fora
    # (compartilha inode, nao caminho) e TOCTOU do link — "quem controla o HOME controla tudo".
    local _doc_abs _caixa_abs _doc_in
    _doc_in="$_doc"
    while [ "${_doc_in%/}" != "$_doc_in" ]; do _doc_in="${_doc_in%/}"; done   # tira barra(s) final(is) (belt do fallback sem realpath)
    [ -n "$_doc_in" ] || _doc_in="$_doc"
    _doc_abs="$(_norte_realpath "$_doc_in" 2>/dev/null || printf '%s' "$_doc_in")"
    _caixa_abs="$(_norte_realpath "${HOME}/.norte-box" 2>/dev/null || printf '%s/.norte-box' "${HOME}")"
    case "$_doc_abs" in
      "$_caixa_abs"/*|"$_caixa_abs")
        printf '🟡 o documento de teste nao pode vir de dentro da propria caixa (nem por atalho/symlink) — use um documento de verdade seu (fora de %s) — nada foi salvo.\n' "$_caixa_abs"
        return 2 ;;
    esac
  fi

  local _dir _chk
  _dir="$(_norte_fabrica_raiz)/${_nome}"
  _chk="${_dir}/checklist.txt"
  [ -f "$_chk" ] || {
    printf '🟡 nao achei o rascunho "%s". Abra um com: nb-kit-rascunho %s\n' "$_nome" "$_nome"
    return 2
  }

  command -v _norte_prova_hash_arquivo >/dev/null 2>&1 || {
    printf '🟡 nao consegui verificar o token (motor de hash ausente).\n'
    return 2
  }
  command -v _norte_kit_criar >/dev/null 2>&1 || {
    printf '🟡 nao consegui salvar o kit: o motor de guardar (nb-kit-criar) nao esta disponivel nesta instalacao.\n'
    return 2
  }
  # COM [doc]: o teste na hora depende do motor real de rodar. Cobra CEDO (antes de salvar) pra nao salvar o
  # kit e so entao descobrir que nao da pra rodar — nesse caso, nada salvo (pre-checagem "nao meio-faz").
  if [ -n "$_doc" ]; then
    command -v _norte_kit_rodar >/dev/null 2>&1 || {
      printf '🟡 nao consegui preparar o teste na hora: o motor de rodar (nb-kit-rodar) nao esta disponivel nesta instalacao — nada foi salvo.\n'
      return 2
    }
  fi

  # --- FECHA A JANELA TOCTOU: 1 SO COPIA; token + lint + save usam a MESMA copia. ---
  local _tmpdir _copia
  _tmpdir="${HOME}/.norte-box/tmp"
  ( umask 077; mkdir -p "$_tmpdir" ) 2>/dev/null || {
    printf '🟡 nao consegui preparar area temporaria pra aprovar (disco nao gravavel).\n'
    return 2
  }
  _copia="$(umask 077; mktemp "$_tmpdir/fabrica-XXXXXX" 2>/dev/null || true)"
  [ -n "$_copia" ] && [ -f "$_copia" ] || {
    printf '🟡 nao consegui preparar area temporaria pra aprovar (disco nao gravavel).\n'
    return 2
  }
  # limpa a copia SEMPRE (sucesso ou erro), sem rm -rf — so o arquivo especifico.
  # shellcheck disable=SC2064
  trap "rm -f \"$_copia\" 2>/dev/null" RETURN

  cp "$_chk" "$_copia" 2>/dev/null || {
    printf '🟡 nao consegui preparar o rascunho pra aprovar (disco nao gravavel).\n'
    return 2
  }

  # RE-HASHEIA A COPIA e compara os 8 primeiros chars com o token. Adulterado (ou trocado antes da copia)
  # -> RECUSA (nao aprova bytes diferentes dos que a pessoa viu no preview).
  local _hcopia
  _hcopia="$(_norte_prova_hash_arquivo "$_copia" 2>/dev/null | cut -c1-8)"
  # compara o token do usuario NA INTEGRA (sem truncar): um token com lixo depois (ex: <T>ZZZ) ou
  # curto NAO passa (furo de higiene do Val). O que aprova tem que ser EXATAMENTE o que o preview mostrou.
  if [ -z "$_hcopia" ] || [ "$_token" != "$_hcopia" ]; then
    printf '🟡 o rascunho mudou desde o preview — nao vou aprovar bytes diferentes dos que voce viu. Rode o preview de novo (nb-kit-rascunho %s) e use o token novo.\n' "$_nome"
    return 2
  fi

  # RE-LINTA A COPIA (defesa em profundidade: um rascunho que nao confere nao vira kit, mesmo com token certo).
  if ! _norte_kit_rascunho_lint "$_copia" >/dev/null 2>&1; then
    printf '🟡 o rascunho nao passa no formato (linhas fora de "descricao :: ancora") — nao vou aprovar. Corrija e refaca o preview.\n'
    return 2
  fi

  # SALVA reusando o motor de guardar. SEM registro (3o arg) -> origem sai 🟡 honesta (fabrica nao provou nada).
  # Passa a COPIA (os mesmos bytes conferidos): o kit guarda EXATAMENTE o que teve o token/lint validados.
  local _saida _rc
  _saida="$(_norte_kit_criar "$_nome" "$_copia")"; _rc=$?
  printf '%s\n' "$_saida"

  if [ "$_rc" -eq 0 ]; then
    # kit criado: remove SO a area do rascunho (nao toca em kits/). Se a limpeza falhar, nao derruba o sucesso.
    rm -rf "$_dir" 2>/dev/null

    # --- FATIA 2: "aprovou -> roda logo num doc de teste" (fecha o ciclo na hora). ---
    if [ -n "$_doc" ]; then
      # linha de TRANSICAO: separa "✅ kit salvo" (acima) de "agora o 1o teste real" (abaixo). O selo 🟢 que
      # eventualmente aparece vem do MOTOR REAL rodando o doc — NUNCA da aprovacao.
      printf '\n──── kit salvo. agora o 1o teste REAL nesse documento (o 🟢, se vier, e do motor — nao da fabrica) ────\n'
      local _run_saida _run_rc
      _run_saida="$(_norte_kit_rodar "$_nome" "$_doc")"; _run_rc=$?
      printf '%s\n' "$_run_saida"
      # o kit FICOU salvo — o teste e informacao, nao desfaz o salvar. Deixa isso EXPLICITO nos dois desfechos.
      if [ "$_run_rc" -eq 0 ]; then
        printf '   (o kit "%s" FICOU salvo e o 1o teste fechou 🟢 no motor real.)\n' "$_nome"
      else
        printf '   ⚠ o kit "%s" FICOU salvo — o teste e informacao, NAO desfaz o salvar. Rode em outro documento com: nb-kit-rodar %s <novo-doc>\n' "$_nome" "$_nome"
      fi
      # o exit final espelha o motor real (0 provado / 1 nao-provado / 2 pre-condicao) — nunca "verde porque salvou".
      return "$_run_rc"
    fi

    # SEM [doc]: comportamento BYTE-IDENTICO a fatia 1 (regressao sagrada).
    printf '   agora rode a conferencia em documentos novos com: nb-kit-rodar %s <novo-doc>\n' "$_nome"
    printf '   (a origem do kit e 🟡 ate o 1o run verde — o 🟢 vem do motor real, nao da fabrica)\n'
  else
    # save falhou (ex: colisao de kit que nasceu no meio do caminho) -> PRESERVA o rascunho (nao perde trabalho).
    printf '🟡 o kit nao foi salvo — deixei o seu rascunho intacto em: %s\n' "$_chk"
  fi
  return "$_rc"
}
