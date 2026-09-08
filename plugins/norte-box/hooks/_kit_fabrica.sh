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

# ============================================================================
# DOC-MODELO (NRT-_746) — um kit PODE carregar, alem do checklist, um modelo.txt (texto com lacunas
# {{campo}}) que a fabrica preenche com os valores da pessoa pra GERAR um documento. Peca aditiva:
# kit SEM modelo.txt (ou com modelo VAZIO) = comportamento BYTE-IDENTICO ao de hoje (regressao sagrada).
# ============================================================================

# _norte_kit_modelo_relevante <arquivo> — 0 SO se o arquivo existe E e' NAO-VAZIO (tem ao menos 1 byte de
#   conteudo). Este e' o UNICO gatilho que faz o modelo entrar no token/hash e no lint. Ausente ou vazio -> 1
#   (o kit se comporta como o de hoje). Read-only.
_norte_kit_modelo_relevante() {
  local _m="${1:-}"
  [ -n "$_m" ] && [ -f "$_m" ] && [ -s "$_m" ]
}

# _norte_kit_hash_com_modelo <checklist> [modelo] — ecoa o hash ESTAVEL que identifica o kit.
#   REGRESSAO SAGRADA: se NAO ha modelo relevante (ausente/vazio), retorna EXATAMENTE o hash de hoje
#   (_norte_prova_hash_arquivo <checklist>) — mesmos bytes, mesmo valor. So quando ha modelo NAO-VAZIO o hash
#   passa a cobrir os dois arquivos, pela forma travada pelo desenho:
#       hash de { cat checklist.txt; printf '\n--modelo--\n'; cat modelo.txt; }
#   Assim adicionar/editar o modelo MUDA o token (o consentimento cobre o modelo tambem); tirar o modelo
#   volta ao hash de hoje. Vazio se faltar o motor de hash. So LE o disco; nao executa dado.
_norte_kit_hash_com_modelo() {
  local _chk="${1:-}" _mod="${2:-}"
  command -v _norte_prova_hash_arquivo >/dev/null 2>&1 || return 1
  [ -n "$_chk" ] && [ -f "$_chk" ] || return 1
  if ! _norte_kit_modelo_relevante "$_mod"; then
    # SEM modelo: fORMULA DE HOJE, intocada (byte-identica).
    _norte_prova_hash_arquivo "$_chk" 2>/dev/null
    return $?
  fi
  # COM modelo: hasheia o COMBINADO via um temporario privado (o motor hasheia arquivo, nao stream).
  local _tmpdir _combo _h
  _tmpdir="${HOME}/.norte-box/tmp"
  ( umask 077; mkdir -p "$_tmpdir" ) 2>/dev/null || return 1
  _combo="$(umask 077; mktemp "$_tmpdir/modelo-hash-XXXXXX" 2>/dev/null || true)"
  [ -n "$_combo" ] && [ -f "$_combo" ] || return 1
  { cat "$_chk"; printf '\n--modelo--\n'; cat "$_mod"; } > "$_combo" 2>/dev/null || { rm -f "$_combo" 2>/dev/null; return 1; }
  _h="$(_norte_prova_hash_arquivo "$_combo" 2>/dev/null || true)"
  rm -f "$_combo" 2>/dev/null
  [ -n "$_h" ] || return 1
  printf '%s' "$_h"
}

# _norte_kit_campo_valido <nome> — 0 se <nome> e' um nome de campo de lacuna VALIDO: so [a-z0-9_-], 1..32
#   chars. REJEITA vazio, com espaco, com '/', maiuscula, e >32 chars. Usado pra lintar {{campo}} e as chaves
#   do valores.txt. NAO transforma — so classifica. bash 3.2 (case, sem ${var,,}).
_norte_kit_campo_valido() {
  local _c="${1:-}"
  [ -n "$_c" ] || return 1
  [ "${#_c}" -le 32 ] || return 1
  case "$_c" in
    *[!a-z0-9_-]*) return 1 ;;
  esac
  return 0
}

# _norte_kit_modelo_lint <modelo> — LINT do modelo.txt: verde (0) SO se TODA chave {{...}} no texto e'
#   bem-formada (abre e fecha certo, sem aninhar) E o nome interno e' um campo valido. Malformadas que o
#   desenho travou como INAPROVAVEIS: {{ campo }} (espaco), {{a/b}}, {{}} (vazio), {{..}} (fora do conjunto),
#   {{ abertura sem fechamento, }} fechamento solto. Ecoa "campos=<n> ruins=<n>". Read-only; nao executa dado.
#
#   Como e' feito sem regex-de-verdade (bash 3.2, sem PCRE): varre o texto em uma passada, achando cada '{{'
#   e o '}}' MAIS PROXIMO depois dele; o miolo entre eles e' o campo; valida o miolo. Um '{{' sem '}}' depois,
#   ou um '}}' antes de qualquer '{{' aberto, contam como ruins. Nao ha eval — so fatiamento de string.
_norte_kit_modelo_lint() {
  local _mod="${1:-}"
  [ -n "$_mod" ] && [ -f "$_mod" ] || { printf 'campos=0 ruins=0\n'; return 1; }
  # le o arquivo inteiro numa string (modelo e' pequeno; texto puro).
  local _txt
  _txt="$(cat "$_mod" 2>/dev/null)"
  local _campos=0 _ruins=0
  local _rest="$_txt" _pre _miolo _depois
  # detecta '}}' solto (fechamento antes de qualquer '{{'): se aparece '}}' na parte ANTES do 1o '{{'.
  # trata a varredura por '{{' de forma iterativa.
  while :; do
    case "$_rest" in
      *'{{'*) : ;;               # ainda ha uma abertura
      *)
        # nao ha mais '{{'. Se sobrou '}}' no resto, e' fechamento solto -> ruim.
        case "$_rest" in *'}}'*) _ruins=$((_ruins+1)) ;; esac
        break ;;
    esac
    _pre="${_rest%%'{{'*}"        # tudo antes do 1o '{{'
    # um '}}' no trecho ANTES da abertura = fechamento solto.
    case "$_pre" in *'}}'*) _ruins=$((_ruins+1)) ;; esac
    _depois="${_rest#*'{{'}"      # tudo depois do 1o '{{'
    case "$_depois" in
      *'}}'*)
        _miolo="${_depois%%'}}'*}"          # miolo ate o 1o '}}'
        # o miolo NAO pode conter outro '{{' (aninhamento) -> malformado.
        case "$_miolo" in
          *'{{'*) _ruins=$((_ruins+1)) ;;
          *)
            if _norte_kit_campo_valido "$_miolo"; then
              _campos=$((_campos+1))
            else
              _ruins=$((_ruins+1))            # {{}}, {{ x }}, {{a/b}}, {{..}}, etc.
            fi ;;
        esac
        _rest="${_depois#*'}}'}"             # segue depois do '}}'
        ;;
      *)
        # '{{' sem '}}' correspondente depois -> abertura solta.
        _ruins=$((_ruins+1))
        break ;;
    esac
  done
  printf 'campos=%s ruins=%s\n' "$_campos" "$_ruins"
  # verde SO com >=1 campo bem-formado e ZERO ruim (modelo sem lacuna nenhuma nao e' um "modelo" util).
  [ "$_campos" -ge 1 ] && [ "$_ruins" -eq 0 ]
}

# _norte_kit_modelo_campos <modelo> — ecoa (um por linha, sem repetir) os nomes de campo {{...}} BEM-FORMADOS
#   do modelo. Usado pelo gerar pra saber quais valores exigir. Assume o modelo JA LINTADO (so campos validos);
#   ainda assim so extrai miolos que passam _norte_kit_campo_valido (defesa). bash 3.2, sem array associativo:
#   dedup via lista de vistos numa string com delimitador.
_norte_kit_modelo_campos() {
  local _mod="${1:-}"
  [ -n "$_mod" ] && [ -f "$_mod" ] || return 0
  local _txt _rest _depois _miolo _vistos="|"
  _txt="$(cat "$_mod" 2>/dev/null)"
  _rest="$_txt"
  while :; do
    case "$_rest" in *'{{'*) : ;; *) break ;; esac
    _depois="${_rest#*'{{'}"
    case "$_depois" in
      *'}}'*)
        _miolo="${_depois%%'}}'*}"
        _rest="${_depois#*'}}'}"
        case "$_miolo" in *'{{'*) continue ;; esac
        _norte_kit_campo_valido "$_miolo" || continue
        # dedup: so imprime se o campo (cercado por '|') ainda nao foi visto.
        case "$_vistos" in
          *"|${_miolo}|"*) : ;;
          *) printf '%s\n' "$_miolo"; _vistos="${_vistos}${_miolo}|" ;;
        esac
        ;;
      *) break ;;
    esac
  done
}

# _norte_kit_valor_perigoso <valor> — 0 (SIM, perigoso -> RECUSA) se o valor contem caractere de controle
#   (inclui quebra de linha embutida — improvavel via read line-a-line, mas defende) OU a sequencia '{{' ou
#   '}}' (injecao de lacuna: um valor com '{{outro}}' abriria uma lacuna nova na substituicao/pos-scan).
#   1 se o valor e' limpo. GUARDA DO PONTO CEGO (juiz). bash 3.2 (case + tr).
_norte_kit_valor_perigoso() {
  local _v="${1:-}"
  # controle: se remover os chars de controle muda o tamanho, havia controle.
  local _limpo
  _limpo="$(printf '%s' "$_v" | tr -d '[:cntrl:]')"
  [ "${#_limpo}" -ne "${#_v}" ] && return 0
  case "$_v" in
    *'{{'*|*'}}'*) return 0 ;;
  esac
  return 1
}

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

  local _chk _mod
  _chk="$(_norte_fabrica_raiz)/${_nome}/checklist.txt"
  _mod="$(_norte_fabrica_raiz)/${_nome}/modelo.txt"
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

  # --- DOC-MODELO (NRT-_746): se ha um modelo.txt NAO-VAZIO no rascunho, ele TAMBEM tem que passar no lint
  #     do modelo (chaves {{...}} bem-formadas, campos validos). Modelo malformado = INAPROVAVEL: preview NAO
  #     emite token (mesma lei do checklist vazio). SEM modelo (ausente/vazio) -> nada muda (regressao sagrada).
  local _tem_modelo=1 _mlint _mlint_rc=0
  if _norte_kit_modelo_relevante "$_mod"; then
    _tem_modelo=0
    _mlint="$(_norte_kit_modelo_lint "$_mod")"; _mlint_rc=$?
    printf '📎 este rascunho tem um MODELO (gera documento por preenchimento): '
    if [ "$_mlint_rc" -eq 0 ]; then
      printf 'formato do modelo confere (%s).\n\n' "$_mlint"
    else
      printf 'FORMATO DO MODELO NAO confere (%s) — chaves {{...}} malformadas.\n\n' "$_mlint"
    fi
  fi

  # SO emite token se o checklist E (se houver modelo) o modelo passarem. Modelo malformado bloqueia o token.
  if [ "$_lint_rc" -eq 0 ] && [ "$_mlint_rc" -eq 0 ]; then
    printf '✅ o formato confere (%s). Este rascunho pode virar kit.\n' "$_lint"
    # SO com tudo verde: calcula o token (8 primeiros chars do hash). COM modelo, o hash cobre checklist+modelo
    # (a aprovacao passa a cobrir o modelo); SEM modelo, e' BYTE-IDENTICO ao de hoje (_norte_kit_hash_com_modelo).
    local _token=""
    _token="$(_norte_kit_hash_com_modelo "$_chk" "$_mod" 2>/dev/null | cut -c1-8)"
    if [ -n "$_token" ]; then
      printf '\n   pra aprovar: nb-kit-aprovar %s --confirmo %s\n' "$_nome" "$_token"
      printf '   (o token e destes bytes exatos; se voce editar o rascunho, ele muda e o antigo nao vale mais)\n'
    else
      printf '\n🟡 nao consegui calcular o token de aprovacao (motor de hash ausente).\n'
    fi
  else
    if [ "$_lint_rc" -ne 0 ]; then
      printf '🟡 o formato NAO confere (%s). Cada linha precisa ser "descricao :: ancora" (a ancora, o texto que\n' "$_lint"
      printf '   o documento bom deve conter, nao pode ficar vazia). Rascunho vazio/malformado NAO pode ser aprovado.\n'
      printf '   Corrija as linhas e rode o preview de novo.\n'
    fi
    if [ "$_tem_modelo" -eq 0 ] && [ "$_mlint_rc" -ne 0 ]; then
      printf '🟡 o MODELO tem chaves malformadas — use lacunas "{{campo}}" (campo so [a-z0-9_-], 1..32 chars, sem\n'
      printf '   espaco/barra). Enquanto o modelo nao conferir, o rascunho NAO pode ser aprovado. Corrija e refaca o preview.\n'
    fi
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
# _norte_kit_editar <nome-existente> <nome-novo> — EDITAR um kit existente, versao MINIMA (NRT-_991092, fatia 3).
#
#   O buraco que esta peca fecha: herdamos kits IMUTAVEIS (a foto e fixa). Pra ajustar a descricao/texto de
#   um kit existente a pessoa precisa comecar do zero. A "edicao" na verdade e: carregar o checklist ATUAL do
#   kit num novo rascunho (pre-preenchido), deixar ajustar o texto, e seguir o MESMO fluxo
#   preview->token->aprovar que a fabrica JA tem. O resultado e uma NOVA VERSAO do kit (nome novo) que
#   PRESERVA o anterior (nao sobrescreve nada). Reusa 100% do motor existente.
#
#   FLUXO:
#     nb-kit-editar <nome-existente> <nome-novo>   -> cria rascunho pre-preenchido + ecoa o caminho
#     (edita o texto no checklist.txt se quiser)
#     nb-kit-rascunho <nome-novo>                  -> preview + token (IDENTICO ao fluxo criar)
#     nb-kit-aprovar <nome-novo> --confirmo <tok>  -> nova versao salva; a antiga continua intacta
#
#   PORTAO DE INTEGRIDADE (anti-circular): o kit-existente tem que ser um kit REAL (diretorio + kit.txt +
#   checklist.txt). Nao pode usar como "kit existente" um caminho do rascunho ou da caixa que nao seja
#   um kit valido — o checklist e lido DO KIT, nao inventado.
#
#   LEIS herdadas (iguais ao resto da fabrica):
#     - IMUTABILIDADE: <nome-novo> nao pode colidir com um kit que ja existe.
#     - Portabilidade macOS (bash 3.2): sem eval, sem array associativo.
#     - O <nome> e tratado como STRING (validado como SLUG antes de virar caminho).
#     - Kill-switch: NORTE_KIT_FABRICA=0 recusa (exit 2, amarelo).
#     - Fail-honest: nao inventa verde; o kit novo nasce com origem 🟡.
#     - A copia e feita por cp (atomica pra o fs local); o rascunho nasce privado (umask 077).
#   RETORNO: 0 rascunho pre-preenchido aberto / 2 recusa (kill/slug/kit-nao-existe/nome-novo-ja-kit/disco).
_norte_kit_editar() {
  local _nome_orig="${1:-}" _nome_novo="${2:-}"

  # kill-switch.
  case "${NORTE_KIT_FABRICA:-1}" in
    0|no|nao|off|false)
      printf '🟡 a fabrica de kits nao esta ligada nesta maquina (NORTE_KIT_FABRICA=0).\n'
      return 2 ;;
  esac

  # ambos os nomes precisam ser SLUGs seguros.
  if ! command -v _norte_kit_slug_valido >/dev/null 2>&1; then
    printf '🟡 motor de validacao de slug nao disponivel.\n'
    return 2
  fi
  if ! _norte_kit_slug_valido "$_nome_orig"; then
    printf '🟡 nome do kit existente invalido: use so letras, numeros, ponto, hifen e underscore.\n'
    return 2
  fi
  if ! _norte_kit_slug_valido "$_nome_novo"; then
    printf '🟡 nome do kit novo invalido: use so letras, numeros, ponto, hifen e underscore (sem barra, espaco, "..").\n'
    return 2
  fi
  if [ "$_nome_orig" = "$_nome_novo" ]; then
    printf '🟡 o nome do kit novo precisa ser diferente do existente — o kit e imutavel; use outro nome (ex: %s-v2).\n' "$_nome_orig"
    return 2
  fi

  # KIT EXISTENTE tem que ser um kit REAL (diretorio + kit.txt + checklist.txt validos).
  local _kits_raiz _orig_dir _orig_chk _orig_kittxt
  if command -v _norte_kits_raiz >/dev/null 2>&1; then
    _kits_raiz="$(_norte_kits_raiz)"
  else
    _kits_raiz="${HOME}/.norte-box/kits"
  fi
  _orig_dir="${_kits_raiz}/${_nome_orig}"
  _orig_chk="${_orig_dir}/checklist.txt"
  _orig_kittxt="${_orig_dir}/kit.txt"

  [ -d "$_orig_dir" ] && [ -f "$_orig_kittxt" ] || {
    printf '🟡 nao achei o kit "%s". Veja os que existem com: nb-kits\n' "$_nome_orig"
    return 2
  }
  [ -f "$_orig_chk" ] && [ -s "$_orig_chk" ] || {
    printf '🟡 o checklist do kit "%s" sumiu ou esta vazio — nao e possivel editar a partir dele.\n' "$_nome_orig"
    return 2
  }

  # NOME NOVO nao pode colidir com kit que ja existe (imutabilidade herdada).
  local _novo_dir
  _novo_dir="${_kits_raiz}/${_nome_novo}"
  if [ -e "$_novo_dir" ]; then
    printf '🟡 ja existe um kit com o nome "%s" — use outro nome pra uma nova versao (ex: %s-v2).\n' "$_nome_novo" "$_nome_novo"
    return 2
  fi

  # NOME NOVO nao pode colidir com rascunho em andamento. Avisa mas NAO bloqueia (a pessoa pode querer
  # continuar de onde parou — idempotente). So bloqueia se o rascunho JA TEM conteudo diferente do kit
  # original (significaria que ja foi editado: sobrescrever apagaria trabalho anterior).
  local _raiz_rasc _novo_rascdir _novo_rascchk
  _raiz_rasc="$(_norte_fabrica_raiz)"
  _novo_rascdir="${_raiz_rasc}/${_nome_novo}"
  _novo_rascchk="${_novo_rascdir}/checklist.txt"
  if [ -f "$_novo_rascchk" ] && [ -s "$_novo_rascchk" ]; then
    # rascunho ja tem conteudo. Compara com o kit original.
    if ! command -v _norte_prova_hash_arquivo >/dev/null 2>&1; then
      # sem hash, nao consegue comparar — avisa e bloqueia (seguro: nao sobrescreve cego).
      printf '🟡 ja existe um rascunho com o nome "%s" e nao consegui verificar se e igual ao kit (motor de hash ausente) — nao vou sobrescrever. Reveja o rascunho com: nb-kit-rascunho %s\n' "$_nome_novo" "$_nome_novo"
      return 2
    fi
    local _h_rasc _h_orig
    _h_rasc="$(_norte_prova_hash_arquivo "$_novo_rascchk" 2>/dev/null || true)"
    _h_orig="$(_norte_prova_hash_arquivo "$_orig_chk" 2>/dev/null || true)"
    if [ -n "$_h_rasc" ] && [ "$_h_rasc" != "$_h_orig" ]; then
      printf '🟡 ja existe um rascunho "%s" com conteudo diferente do kit "%s" — nao vou sobrescrever (voce pode ter feito edicoes). Retome com: nb-kit-rascunho %s\n' "$_nome_novo" "$_nome_orig" "$_nome_novo"
      return 2
    fi
    # hashes iguais = e o proprio kit copiado (idempotente) ou o rascunho ainda nao foi editado. Prossegue.
  fi

  # ABRE A AREA DO RASCUNHO (privada, 0700) e PRE-PREENCHE com o checklist do kit original.
  ( umask 077; mkdir -p "$_novo_rascdir" ) 2>/dev/null || {
    printf '🟡 nao consegui abrir a area do rascunho (disco nao gravavel).\n'
    return 2
  }
  ( umask 077; cp "$_orig_chk" "$_novo_rascchk" ) 2>/dev/null || {
    printf '🟡 nao consegui copiar o checklist do kit "%s" pro rascunho (disco nao gravavel).\n' "$_nome_orig"
    return 2
  }

  # DOC-MODELO (NRT-_746): se o kit original TEM um modelo.txt nao-vazio, copia-o tambem pro rascunho — assim
  # editar um kit com modelo PRESERVA o modelo (a pessoa ajusta o modelo do mesmo jeito que ajusta o checklist).
  # Se o kit nao tem modelo, nao cria nada (o rascunho segue "so checklist"; a pessoa pode ADICIONAR um modelo.txt
  # ali antes do preview — o caminho canonico de dar modelo a um kit ja aprovado). Falha de copia derruba honesto.
  local _orig_mod _novo_rascmod
  _orig_mod="${_orig_dir}/modelo.txt"
  _novo_rascmod="${_novo_rascdir}/modelo.txt"
  if _norte_kit_modelo_relevante "$_orig_mod"; then
    ( umask 077; cp "$_orig_mod" "$_novo_rascmod" ) 2>/dev/null || {
      printf '🟡 nao consegui copiar o modelo do kit "%s" pro rascunho (disco nao gravavel).\n' "$_nome_orig"
      return 2
    }
  fi

  # o cartao do rascunho — registra de onde vem (editado de qual kit).
  ( umask 077
    {
      printf 'nome: %s\n' "$_nome_novo"
      printf 'editado_de: %s\n' "$_nome_orig"
      printf 'quando: %s\n' "$(date -u +%FT%TZ 2>/dev/null || echo t)"
      printf 'estado: rascunho\n'
    } > "${_novo_rascdir}/rascunho.txt"
  ) 2>/dev/null || {
    printf '🟡 nao consegui gravar o cartao do rascunho (disco nao gravavel).\n'
    return 2
  }

  # ecoa o caminho do checklist pre-preenchido (a pessoa/agente edita ali).
  printf '📝 rascunho "%s" aberto com o checklist do kit "%s" (pre-preenchido). Ajuste as exigencias em:\n' "$_nome_novo" "$_nome_orig"
  printf '   %s\n' "$_novo_rascchk"
  if _norte_kit_modelo_relevante "$_novo_rascmod"; then
    printf '   (o modelo do kit tambem foi copiado — ajuste-o em: %s)\n' "$_novo_rascmod"
  fi
  printf '   (quando terminar de editar, rode: nb-kit-rascunho %s)\n' "$_nome_novo"
  return 0
}

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

  local _dir _chk _mod
  _dir="$(_norte_fabrica_raiz)/${_nome}"
  _chk="${_dir}/checklist.txt"
  _mod="${_dir}/modelo.txt"
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

  # --- FECHA A JANELA TOCTOU: 1 SO COPIA de CADA arquivo; token + lint + save usam as MESMAS copias. ---
  # DOC-MODELO (NRT-_746): se o rascunho tem modelo.txt nao-vazio, ele entra no anti-TOCTOU tambem — copia,
  # re-hasheia (junto com o checklist, pela mesma formula do preview) e INSTALA a copia no kit. SEM modelo, o
  # fluxo e' BYTE-IDENTICO ao de hoje (a copia do modelo nem e' criada, e o hash cai na formula de hoje).
  local _tmpdir _copia _copia_mod=""
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
  local _tem_modelo=1
  if _norte_kit_modelo_relevante "$_mod"; then
    _tem_modelo=0
    _copia_mod="$(umask 077; mktemp "$_tmpdir/fabrica-mod-XXXXXX" 2>/dev/null || true)"
    [ -n "$_copia_mod" ] && [ -f "$_copia_mod" ] || {
      rm -f "$_copia" 2>/dev/null
      printf '🟡 nao consegui preparar area temporaria pra aprovar o modelo (disco nao gravavel).\n'
      return 2
    }
  fi
  # limpa as copias SEMPRE (sucesso ou erro), sem rm -rf — so os arquivos especificos.
  # shellcheck disable=SC2064
  trap "rm -f \"$_copia\" \"$_copia_mod\" 2>/dev/null" RETURN

  cp "$_chk" "$_copia" 2>/dev/null || {
    printf '🟡 nao consegui preparar o rascunho pra aprovar (disco nao gravavel).\n'
    return 2
  }
  if [ "$_tem_modelo" -eq 0 ]; then
    cp "$_mod" "$_copia_mod" 2>/dev/null || {
      printf '🟡 nao consegui preparar o modelo do rascunho pra aprovar (disco nao gravavel).\n'
      return 2
    }
  fi

  # RE-HASHEIA AS COPIAS e compara os 8 primeiros chars com o token. Adulterado (ou trocado antes da copia)
  # -> RECUSA (nao aprova bytes diferentes dos que a pessoa viu no preview). COM modelo, o hash cobre os dois
  # arquivos (mesma formula do preview); SEM modelo, e' o hash do checklist de hoje (byte-identico).
  local _hcopia
  _hcopia="$(_norte_kit_hash_com_modelo "$_copia" "$_copia_mod" 2>/dev/null | cut -c1-8)"
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
  # RE-LINTA O MODELO (se houver): um modelo malformado NAO vira kit, mesmo com token certo (defesa em profundidade).
  if [ "$_tem_modelo" -eq 0 ] && ! _norte_kit_modelo_lint "$_copia_mod" >/dev/null 2>&1; then
    printf '🟡 o modelo tem chaves {{...}} malformadas — nao vou aprovar. Corrija o modelo e refaca o preview.\n'
    return 2
  fi

  # SALVA reusando o motor de guardar. SEM registro (3o arg) -> origem sai 🟡 honesta (fabrica nao provou nada).
  # Passa a COPIA (os mesmos bytes conferidos): o kit guarda EXATAMENTE o que teve o token/lint validados.
  local _saida _rc
  _saida="$(_norte_kit_criar "$_nome" "$_copia")"; _rc=$?
  printf '%s\n' "$_saida"

  if [ "$_rc" -eq 0 ]; then
    # DOC-MODELO: instala a COPIA do modelo no dir do kit (junto do checklist que o _norte_kit_criar acabou de
    # instalar). Usa as MESMAS copias conferidas (anti-TOCTOU cobrindo 2 arquivos). Se a instalacao do modelo
    # falhar, o kit ficou salvo SEM modelo — avisa honesto (o checklist vale; a geracao por modelo e' que nao).
    if [ "$_tem_modelo" -eq 0 ]; then
      local _kit_destdir
      if command -v _norte_kits_raiz >/dev/null 2>&1; then
        _kit_destdir="$(_norte_kits_raiz)/${_nome}"
      else
        _kit_destdir="${HOME}/.norte-box/kits/${_nome}"
      fi
      ( umask 077; cp "$_copia_mod" "${_kit_destdir}/modelo.txt" ) 2>/dev/null || {
        printf '🟡 o kit foi salvo, mas nao consegui instalar o modelo.txt (disco nao gravavel) — o kit vale so como checklist; a geracao por modelo nao vai funcionar. Refaca via nb-kit-editar.\n'
      }
    fi

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

# _norte_kit_gerar <nome> <valores.txt> [saida] — GERA um documento a partir do modelo.txt do kit + valores.
#   (NRT-_746, DOC-MODELO.) Substituicao LITERAL em bash puro (sem LLM, sem eval, sem sed -v). Depois de gerar,
#   entrega o doc ao MOTOR REAL (_norte_kit_rodar) — o selo/registro/HMAC saem DELE (🟢 so do motor, nunca da
#   geracao). O doc gerado nasce 🟡 (ainda nao conferido); o exit final espelha o motor (0/1/2).
#
#   FLUXO (nada e' gravado antes de TODOS os checks passarem):
#     1) kill-switch NORTE_KIT_MODELO; slug do <nome>; kit tem que existir E ter modelo.txt NAO-VAZIO.
#     2) le o <valores.txt> ("campo :: valor", valor literal; ignora vazias e '#'). Guarda do ponto cego:
#        valor com controle/quebra-de-linha ou '{{'/'}}' -> RECUSA (juiz).
#     3) casa campos do modelo x campos do valores: falta valor -> RECUSA; valor extra -> RECUSA (juiz).
#     4) monta o doc em MEMORIA por substituicao literal "${doc//"{{campo}}"/$valor}"; pos-scan: sobrou
#        {{...}} -> RECUSA (defesa).
#     5) resolve a SAIDA pelo realpath do sistema; RECUSA dentro de ~/.norte-box (anti-circular) e no-clobber.
#     6) grava; imprime 🟡; chama _norte_kit_rodar <nome> <doc>. exit = do motor.
#   RETORNO: 1 nas recusas de conteudo (falta/extra/valor perigoso/sobra); 2 nas recusas de pre-condicao
#   (kill/slug/kit-sem-modelo/valores-ausente/saida-invalida/no-clobber/disco); com sucesso, espelha o motor.
_norte_kit_gerar() {
  local _nome="${1:-}" _valores="${2:-}" _saida="${3:-}"

  # kill-switch dedicado do DOC-MODELO.
  case "${NORTE_KIT_MODELO:-1}" in
    0|no|nao|off|false)
      printf '🟡 a geracao de documento por modelo nao esta ligada nesta maquina (NORTE_KIT_MODELO=0).\n'
      return 2 ;;
  esac

  # nome = SLUG seguro (o nome vira caminho; guarda traversal e injecao). O nome nunca e' executado.
  if ! command -v _norte_kit_slug_valido >/dev/null 2>&1 || ! _norte_kit_slug_valido "$_nome"; then
    printf '🟡 nome de kit invalido: use so letras, numeros, ponto, hifen e underscore (sem barra, espaco, "..").\n'
    return 2
  fi

  # o KIT tem que existir E ter modelo.txt NAO-VAZIO.
  local _kits_raiz _kitdir _modelo _chk
  if command -v _norte_kits_raiz >/dev/null 2>&1; then
    _kits_raiz="$(_norte_kits_raiz)"
  else
    _kits_raiz="${HOME}/.norte-box/kits"
  fi
  _kitdir="${_kits_raiz}/${_nome}"
  _modelo="${_kitdir}/modelo.txt"
  _chk="${_kitdir}/checklist.txt"

  [ -d "$_kitdir" ] || {
    printf '🟡 nao achei o kit "%s". Veja os que existem com: nb-kits\n' "$_nome"
    return 2
  }
  if ! _norte_kit_modelo_relevante "$_modelo"; then
    printf '🟡 esse kit nao tem modelo — crie uma versao com modelo via nb-kit-editar (adicione um modelo.txt nao-vazio).\n'
    return 2
  fi

  # <valores.txt> tem que existir e ser legivel.
  [ -n "$_valores" ] && [ -f "$_valores" ] && [ -r "$_valores" ] || {
    printf '🟡 nao consegui gerar: diga qual e o arquivo de valores (nao achei/nao consigo ler "%s").\n' "$_valores"
    return 2
  }

  # motor de rodar tem que existir (delegamos a ele no fim) — cobra CEDO, antes de gravar.
  command -v _norte_kit_rodar >/dev/null 2>&1 || {
    printf '🟡 nao consegui gerar: o motor de rodar (nb-kit-rodar) nao esta disponivel nesta instalacao.\n'
    return 2
  }

  # --- LE OS VALORES ("campo :: valor"). bash 3.2, sem array associativo: 2 listas paralelas string-por-linha
  #     (nomes e valores em variaveis com \n; o valor pode ter espacos/'::', so nao pode ter controle). ---
  local _linha _campo _valor _nomes_vals="" _valores_vals=""
  local _seen_campos="|"
  while IFS= read -r _linha || [ -n "$_linha" ]; do
    case "$_linha" in ''|'#'*) continue ;; esac
    case "$(printf '%s' "$_linha" | tr -d '[:space:]')" in '') continue ;; esac
    # precisa do separador "::".
    printf '%s' "$_linha" | grep -q '::' || {
      printf '🟡 linha de valores sem separador "::": %s\n' "$_linha"
      return 1
    }
    _campo="$(printf '%s' "$_linha" | sed 's/ *::.*$//')"
    _campo="$(printf '%s' "$_campo" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    # o VALOR e' o RESTO da linha, LITERAL (so apara 1 espaco apos "::", igual ao motor; nao apara o fim).
    _valor="$(printf '%s' "$_linha" | sed 's/^[^:]*:: *//')"
    # campo tem que ser um nome valido.
    if ! _norte_kit_campo_valido "$_campo"; then
      printf '🟡 nome de campo invalido no valores.txt: "%s" (use so [a-z0-9_-], 1..32 chars).\n' "$_campo"
      return 1
    fi
    # campo repetido no valores.txt -> ambiguo, RECUSA.
    case "$_seen_campos" in
      *"|${_campo}|"*)
        printf '🟡 campo repetido no valores.txt: "%s" (defina uma vez so).\n' "$_campo"
        return 1 ;;
    esac
    _seen_campos="${_seen_campos}${_campo}|"
    # GUARDA DO PONTO CEGO: valor com controle/quebra ou '{{'/'}}' -> RECUSA (injecao de lacuna/estrutura).
    if _norte_kit_valor_perigoso "$_valor"; then
      printf '🟡 valor do campo "%s" contem caractere de controle ou a sequencia {{ }} — recusado (evita injetar lacuna).\n' "$_campo"
      return 1
    fi
    # empilha (delimitado por \n; nunca executado).
    _nomes_vals="${_nomes_vals}${_campo}
"
    _valores_vals="${_valores_vals}${_valor}
"
  done < "$_valores"

  # --- CAMPOS DO MODELO x CAMPOS DO VALORES ---
  # 1) todo campo do MODELO precisa ter valor. Lista os que faltam.
  local _campo_m _faltam="" _n_faltam=0
  while IFS= read -r _campo_m || [ -n "$_campo_m" ]; do
    [ -n "$_campo_m" ] || continue
    case "
${_nomes_vals}" in
      *"
${_campo_m}
"*) : ;;   # tem valor
      *) _faltam="${_faltam} ${_campo_m}"; _n_faltam=$((_n_faltam+1)) ;;
    esac
  done <<EOF
$(_norte_kit_modelo_campos "$_modelo")
EOF
  if [ "$_n_faltam" -gt 0 ]; then
    printf '🟡 faltam valores pra %s campo(s) do modelo:%s\n' "$_n_faltam" "$_faltam"
    printf '   preencha no valores.txt (uma linha "campo :: valor" pra cada) e rode de novo. Nada foi gravado.\n'
    return 1
  fi

  # 2) todo campo do VALORES precisa existir no MODELO (pega erro de digitacao). Lista os extras. (juiz: recusa.)
  # constroi a lista de campos do modelo cercada por \n pra casar exato.
  local _campos_modelo _extras="" _n_extras=0
  _campos_modelo="
$(_norte_kit_modelo_campos "$_modelo")
"
  local _campo_v
  while IFS= read -r _campo_v || [ -n "$_campo_v" ]; do
    [ -n "$_campo_v" ] || continue
    case "$_campos_modelo" in
      *"
${_campo_v}
"*) : ;;   # existe no modelo
      *) _extras="${_extras} ${_campo_v}"; _n_extras=$((_n_extras+1)) ;;
    esac
  done <<EOF
${_nomes_vals}
EOF
  if [ "$_n_extras" -gt 0 ]; then
    printf '🟡 o valores.txt tem %s campo(s) que NAO existem no modelo (erro de digitacao?):%s\n' "$_n_extras" "$_extras"
    printf '   corrija o nome ou remova a linha e rode de novo. Nada foi gravado.\n'
    return 1
  fi

  # --- MONTA O DOC INTEIRO EM MEMORIA (so grava se TODOS os checks passarem). Substituicao LITERAL, sem eval. ---
  local _doc
  _doc="$(cat "$_modelo" 2>/dev/null)" || {
    printf '🟡 nao consegui ler o modelo do kit.\n'
    return 2
  }
  # para cada par (campo,valor), troca TODAS as ocorrencias de "{{campo}}" pelo valor literal.
  # As duas listas estao alinhadas linha-a-linha; percorre pelo indice.
  local _n_pares _i=1
  _n_pares="$(printf '%s' "$_nomes_vals" | grep -c '' )"
  # (grep -c '' conta linhas; _nomes_vals termina em \n por construcao, entao conta certo os pares.)
  while [ "$_i" -le "$_n_pares" ]; do
    _campo="$(printf '%s' "$_nomes_vals"   | sed -n "${_i}p")"
    _valor="$(printf '%s' "$_valores_vals" | sed -n "${_i}p")"
    _i=$((_i+1))
    [ -n "$_campo" ] || continue
    # substituicao LITERAL: a lacuna "{{campo}}" com aspas -> match literal; $_valor entra cru (ja peneirado).
    _doc="${_doc//"{{${_campo}}}"/$_valor}"
  done

  # POS-SCAN: se sobrou QUALQUER "{{" ou "}}" (par completo OU chave orfa), RECUSA (defesa — nao re-expande;
  # algo escapou aos checks). v1 nao suporta chave literal no doc; qualquer {{ ou }} residual = incompleto.
  case "$_doc" in
    *'{{'*|*'}}'*)
      printf '🟡 sobrou uma lacuna {{...}} no documento apos preencher — nao vou gravar um doc incompleto. Nada foi gravado.\n'
      return 1 ;;
  esac

  # --- RESOLVE A SAIDA (realpath do sistema) + anti-circular + no-clobber ---
  local _saida_alvo
  if [ -n "$_saida" ]; then
    _saida_alvo="$_saida"
  else
    _saida_alvo="./${_nome}-$(date +%F 2>/dev/null || echo doc).txt"
  fi

  # no-clobber: nunca sobrescreve um arquivo existente.
  if [ -e "$_saida_alvo" ]; then
    printf '🟡 ja existe um arquivo em "%s" — nao vou sobrescrever. Escolha outro nome de saida. Nada foi gravado.\n' "$_saida_alvo"
    return 2
  fi

  # ANTI-CIRCULAR: o caminho FISICO da saida nao pode cair dentro de ~/.norte-box (a caixa). Resolve pelo
  # realpath do sistema (nunca canonicalizar a mao — memory reference_gate_de_caminho_use_realpath_do_sistema).
  # Como o arquivo ainda NAO existe, canoniza o DIRETORIO-PAI (que existe ou sera criado) + o basename.
  local _saida_dir _saida_base _dir_abs _caixa_abs _alvo_abs
  # tira barra(s) final(is) — nome de arquivo nao termina em '/'.
  local _saida_in="$_saida_alvo"
  while [ "${_saida_in%/}" != "$_saida_in" ]; do _saida_in="${_saida_in%/}"; done
  [ -n "$_saida_in" ] || _saida_in="$_saida_alvo"
  _saida_dir="$(dirname "$_saida_in" 2>/dev/null)"
  _saida_base="$(basename "$_saida_in" 2>/dev/null)"
  # o dir-pai precisa existir pra o realpath do sistema resolver (nao criamos dir novo — mantem simples/seguro).
  [ -d "$_saida_dir" ] || {
    printf '🟡 a pasta de saida "%s" nao existe — crie-a ou aponte um caminho existente. Nada foi gravado.\n' "$_saida_dir"
    return 2
  }
  _dir_abs="$(_norte_realpath "$_saida_dir" 2>/dev/null || printf '%s' "$_saida_dir")"
  _alvo_abs="${_dir_abs}/${_saida_base}"
  _caixa_abs="$(_norte_realpath "${HOME}/.norte-box" 2>/dev/null || printf '%s/.norte-box' "${HOME}")"
  case "$_alvo_abs" in
    "$_caixa_abs"/*|"$_caixa_abs")
      printf '🟡 a saida nao pode cair dentro da propria caixa (%s) — gere o documento numa pasta sua. Nada foi gravado.\n' "$_caixa_abs"
      return 2 ;;
  esac

  # --- GRAVA (privado por padrao) ---
  ( umask 077; printf '%s\n' "$_doc" > "$_saida_alvo" ) 2>/dev/null || {
    printf '🟡 nao consegui gravar o documento em "%s" (disco nao gravavel). Nada foi gravado.\n' "$_saida_alvo"
    return 2
  }
  printf '🟡 doc gerado — ainda nao conferido: %s\n' "$_saida_alvo"

  # --- ENTREGA AO MOTOR REAL: o selo/registro/HMAC saem DELE. O 🟢, se vier, e' do motor. ---
  printf '\n──── doc gerado. agora a conferencia REAL contra o checklist do kit (o 🟢, se vier, e do motor) ────\n'
  _norte_kit_rodar "$_nome" "$_saida_alvo"
  return $?
}
