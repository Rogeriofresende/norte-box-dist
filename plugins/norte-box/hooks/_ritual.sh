#!/usr/bin/env bash
# _ritual.sh — biblioteca do OBSERVADOR EM SOMBRA (NRT-_746, fatia 1).
# NAO e um hook (nome com _ inicial, fora do hooks.json). E sourceada por ritual-emit.sh e
# pelos testes/replay. Objetivo UNICO desta fatia: PROVAR que a caixa consegue ENXERGAR o
# FORMATO de um ritual repetido (mandato -> teste/review -> PR) — 100% LOCAL, log-only.
#
# ============================================================================================
# O QUE ESTA LIB FAZ (e o que NAO faz):
#   - CLASSIFICA um evento (tool_use ou prompt) num RÓTULO de vocabulario FECHADO, em memoria.
#   - GRAVA so o rotulo (1o-visto de cada marco por run) + timestamps + hash-de-run.
#   - No marco `pr`, CONFERE a assinatura `mandato_pr_v1` (marcos + ORDEM) e anota +1 no placar.
#   - NAO envia NADA (sem curl/wget/http/node-post). Sem conteudo. Sem sugerir. Sem agir.
#     Modo SOMBRA puro: ler o formato do trabalho, contar, e calar.
#
# LIMITACAO HONESTA (do rigor Codex): a assinatura `mandato_pr_v1` NAO inclui `DoD`
# (definition of done). DoD nao e detectavel sem LER o conteudo do mandato — e esta caixa,
# por lei, NUNCA le conteudo (so classifica a forma do evento e descarta o texto). Entao a
# v1 prova o esqueleto do ritual (mandato->teste/review->pr), nao a qualidade do mandato.
#
# INVARIANTE AUDITAVEL (nao-negociavel): os UNICOS strings que estes arquivos guardam sao
#   rotulos do vocabulario FECHADO abaixo + chaves fixas de JSON + timestamps + hash de run.
#   NENHUM path, comando, nome-de-arquivo, argumento ou texto do trabalho. Se um marco nao
#   couber com CERTEZA num rotulo -> NAO classifica (errar pra MENOS > vazar).
#
# LEIS (iguais ao telemetry-emit/atrito-emit):
#   - FAIL-OPEN: toda funcao retorna 0 (nunca trava o trabalho). Erro interno -> silencioso.
#   - Consome dado como DADO, NUNCA executa input. Escreve SO em $HOME/.norte-box.
#   - Portabilidade macOS bash 3.2 (sem EPOCHREALTIME, sem mapfile, sem associative arrays).
#
# CONCORRENCIA: 2 sessoes na mesma maquina nunca podem corromper os JSONs. Escrita ATOMICA
#   (tmp + mv) + LOCK por-arquivo via mkdir (o unico primitivo atomico portatil em bash 3.2).

# ---------------------------------------------------------------------------------------------
# 0) CONSTANTES / VOCABULARIO FECHADO
# ---------------------------------------------------------------------------------------------
# Rotulos de MARCO (o unico vocabulario que pode virar string nos arquivos, alem de chaves/ts/hash).
_NB_RITUAL_MARCOS=" mandato edita teste review commit pr "
# Marcos OBRIGATORIOS da assinatura mandato_pr_v1 (edita/commit sao OPCIONAIS, nao travam).
_NB_RITUAL_OBRIG=" mandato teste review pr "
# Nome da assinatura (versionado).
_NB_RITUAL_ASSINATURA="mandato_pr_v1"
# Janela: um marco com mais de 12h no momento do fecho e considerado velho (descartado).
_NB_RITUAL_JANELA_MS=$(( 12 * 60 * 60 * 1000 ))
# Housekeeping: apaga estados de run com mtime > 48h.
_NB_RITUAL_STATE_TTL_MIN=$(( 48 * 60 ))

_nb_ritual_state_dir() { printf '%s/ritual-state' "${HOME}/.norte-box"; }
_nb_ritual_contagem()  { printf '%s/ritual-contagem.json' "${HOME}/.norte-box"; }

# ---------------------------------------------------------------------------------------------
# 1) TEMPO (portatil, ms). perl Time::HiRes -> ms; senao date +%s * 1000. Nunca fake.
# ---------------------------------------------------------------------------------------------
_nb_ritual_now_ms() {
  if command -v perl >/dev/null 2>&1; then
    perl -MTime::HiRes=time -e 'printf "%d", time()*1000' 2>/dev/null && return 0
  fi
  local _s; _s="$(date +%s 2>/dev/null || true)"
  case "$_s" in ''|*[!0-9]*) printf ''; return 0 ;; *) printf '%s000' "$_s"; return 0 ;; esac
}

# ---------------------------------------------------------------------------------------------
# 2) run_id: HASH (16 hex) do session_id — MESMA receita do telemetry-emit (reuso deliberado).
#    O session_id cru NUNCA e gravado (e o nome do transcript local; hashear impede cruzar).
#    Sem hash disponivel / sem session_id -> vazio (o observador so degrada, nunca trava).
# ---------------------------------------------------------------------------------------------
_nb_ritual_run_id() {
  local _sid="${1:-}"
  [ -z "$_sid" ] && { printf ''; return 0; }
  if command -v shasum >/dev/null 2>&1; then
    printf '%s' "$_sid" | shasum -a 256 2>/dev/null | cut -c1-16
  elif command -v sha256sum >/dev/null 2>&1; then
    printf '%s' "$_sid" | sha256sum 2>/dev/null | cut -c1-16
  else
    printf ''
  fi
  return 0
}

# ---------------------------------------------------------------------------------------------
# 3) CLASSIFICACAO ESTRUTURAL (do rigor Codex): analisa a FORMA do evento, nao faz busca textual.
#    `echo "gh pr create"` NAO e `pr`. Um marco-comando dentro de string/echo/comentario NAO conta.
#    Na duvida -> NAO classifica (ecoa vazio). Nomes MCP NUNCA viram rotulo.
# ---------------------------------------------------------------------------------------------

# _nb_ritual_glob_mandato <file_path> -> 0 se casa */docs/mandatos/*.md (via case, sem regex).
_nb_ritual_glob_mandato() {
  case "$1" in
    */docs/mandatos/*.md) return 0 ;;
    *) return 1 ;;
  esac
}

# _nb_ritual_primeiro_comando <command-cru>
#   Ecoa o PRIMEIRO comando REAL de uma linha bash — o comando efetivamente EXECUTADO, ignorando
#   espacos/comentarios iniciais. NAO desce por pipes/&&/;: pega so o head da linha. Se o head for
#   `echo`/`printf`/`:`/`#` (comentario) ou vazio -> ecoa vazio (o resto e argumento/string, nao
#   comando). Isso e o que separa "gh pr create" (executado) de `echo "gh pr create"` (string).
_nb_ritual_primeiro_comando() {
  local _c="$1"
  # trim das pontas
  _c="${_c#"${_c%%[![:space:]]*}"}"
  # comentario -> nao ha comando executado
  case "$_c" in '#'*) printf ''; return 0 ;; esac
  # 1o token (ate o 1o espaco/tab/nl)
  local _tok="${_c%%[[:space:]]*}"
  # atribuicao de variavel (VAR=...) prefixando o comando: nao classificamos (ambiguo) -> vazio
  case "$_tok" in *=*) printf ''; return 0 ;; esac
  # o head NAO pode ser um construtor que joga o resto pra dentro de string/arg:
  case "$_tok" in
    echo|printf|:|true|false|test|'['|'[[') printf ''; return 0 ;;
  esac
  printf '%s' "$_tok"
  return 0
}

# _nb_ritual_bash_marco <command-cru> -> ecoa "teste" | "pr" | "commit" | "" (vazio)
#   ESTRUTURAL: so classifica se o marco-comando for o comando REAL no head da linha.
#   teste : primeiro comando ∈ {pytest, python -m pytest, npm/bun/npx (test/jest), go, make (test)}
#   pr    : primeiro comando == gh  E  os 2 tokens seguintes REAIS forem `pr` `create`
#   commit: primeiro comando == git E  o token seguinte REAL for `commit`
_nb_ritual_bash_marco() {
  local _c="$1" _head _rest _t2 _t3
  _head="$(_nb_ritual_primeiro_comando "$_c")"
  [ -z "$_head" ] && { printf ''; return 0; }

  case "$_head" in
    pytest) printf 'teste'; return 0 ;;
    python|python3)
      # python -m pytest  -> teste (analisa os proximos tokens REAIS)
      _rest="${_c#*"$_head"}"
      _rest="${_rest#"${_rest%%[![:space:]]*}"}"
      _t2="${_rest%%[[:space:]]*}"
      _rest="${_rest#"$_t2"}"; _rest="${_rest#"${_rest%%[![:space:]]*}"}"
      _t3="${_rest%%[[:space:]]*}"
      if [ "$_t2" = "-m" ] && [ "$_t3" = "pytest" ]; then printf 'teste'; return 0; fi
      printf ''; return 0 ;;
    npm|bun)
      _rest="${_c#*"$_head"}"; _rest="${_rest#"${_rest%%[![:space:]]*}"}"
      _t2="${_rest%%[[:space:]]*}"
      case "$_t2" in test|jest) printf 'teste'; return 0 ;; esac
      printf ''; return 0 ;;
    npx)
      _rest="${_c#*"$_head"}"; _rest="${_rest#"${_rest%%[![:space:]]*}"}"
      _t2="${_rest%%[[:space:]]*}"
      case "$_t2" in jest|test) printf 'teste'; return 0 ;; esac
      printf ''; return 0 ;;
    go)
      _rest="${_c#*"$_head"}"; _rest="${_rest#"${_rest%%[![:space:]]*}"}"
      _t2="${_rest%%[[:space:]]*}"
      case "$_t2" in test) printf 'teste'; return 0 ;; esac
      printf ''; return 0 ;;
    make)
      _rest="${_c#*"$_head"}"; _rest="${_rest#"${_rest%%[![:space:]]*}"}"
      _t2="${_rest%%[[:space:]]*}"
      case "$_t2" in test) printf 'teste'; return 0 ;; esac
      printf ''; return 0 ;;
    gh)
      _rest="${_c#*"$_head"}"; _rest="${_rest#"${_rest%%[![:space:]]*}"}"
      _t2="${_rest%%[[:space:]]*}"
      _rest="${_rest#"$_t2"}"; _rest="${_rest#"${_rest%%[![:space:]]*}"}"
      _t3="${_rest%%[[:space:]]*}"
      if [ "$_t2" = "pr" ] && [ "$_t3" = "create" ]; then printf 'pr'; return 0; fi
      printf ''; return 0 ;;
    git)
      _rest="${_c#*"$_head"}"; _rest="${_rest#"${_rest%%[![:space:]]*}"}"
      _t2="${_rest%%[[:space:]]*}"
      case "$_t2" in commit) printf 'commit'; return 0 ;; esac
      printf ''; return 0 ;;
  esac
  printf ''
  return 0
}

# _nb_ritual_classifica <tool_name> <field1> <field2>
#   Retorna UM rotulo do vocabulario fechado, ou vazio (nao-classificavel). ESTRUTURAL.
#   Contrato dos campos por tool (o CHAMADOR extrai por jq e passa; a lib nunca ve o stdin cru):
#     Write/Edit/MultiEdit/NotebookEdit : $2 = file_path            (mandato ou edita)
#     Bash                              : $2 = command               (teste/pr/commit)
#     Skill                             : $2 = skill (nome exato)    (review se == cto-review)
#     UserPromptSubmit(prompt)          : tool_name vazio, $2 = 1o-token-do-prompt (review se /cto-review)
_nb_ritual_classifica() {
  local _tool="$1" _f1="${2:-}"
  case "$_tool" in
    Write|Edit|MultiEdit|NotebookEdit)
      if _nb_ritual_glob_mandato "$_f1"; then printf 'mandato'; else printf 'edita'; fi
      return 0 ;;
    Bash)
      printf '%s' "$(_nb_ritual_bash_marco "$_f1")"; return 0 ;;
    Skill)
      # igualdade EXATA — nome de skill/MCP nunca vira rotulo por substring
      [ "$_f1" = "cto-review" ] && { printf 'review'; return 0; }
      printf ''; return 0 ;;
    '')
      # UserPromptSubmit: $_f1 ja e o 1o TOKEN do prompt (args descartados pelo chamador).
      [ "$_f1" = "/cto-review" ] && { printf 'review'; return 0; }
      printf ''; return 0 ;;
    *)
      # tool desconhecido / MCP / custom -> nunca classifica
      printf ''; return 0 ;;
  esac
}

# _nb_ritual_marco_valido <rotulo> -> 0 se pertence ao vocabulario fechado (defesa em profundidade).
_nb_ritual_marco_valido() {
  case "$_NB_RITUAL_MARCOS" in *" $1 "*) return 0 ;; *) return 1 ;; esac
}

# ---------------------------------------------------------------------------------------------
# 4) LOCK + ESCRITA ATOMICA (concorrencia). mkdir e o unico lock atomico portatil (bash 3.2).
#    _nb_ritual_lock <lockdir>  : espera ate ~2s pegando o lock; retorna 0 (pegou) ou 1 (desistiu).
#    _nb_ritual_unlock <lockdir>: solta.
#    _nb_ritual_write_atomic <destino> <conteudo> : grava em tmp + mv (rename atomico no MESMO fs).
# ---------------------------------------------------------------------------------------------
_nb_ritual_lock() {
  local _ld="$1" _i=0
  # remove lock ORFAO (dono morreu sem soltar): mkdir com mtime > 60s e considerado abandonado.
  # IMPORTANTE (fix Val red-team): testar a SAIDA do find, nao o rc — `find ... >/dev/null`
  # retorna rc=0 mesmo SEM match, o que fazia o if ser sempre-verdadeiro e remover ate lock
  # FRESCO de processo vivo (exclusao mutua evaporava → perda de contagem sob concorrencia).
  if [ -d "$_ld" ]; then
    if [ -n "$(find "$_ld" -maxdepth 0 -mmin +1 2>/dev/null)" ]; then
      rmdir "$_ld" 2>/dev/null || true
    fi
  fi
  while [ "$_i" -lt 200 ]; do
    if mkdir "$_ld" 2>/dev/null; then return 0; fi
    _i=$(( _i + 1 ))
    sleep 0.05 2>/dev/null || sleep 1
  done
  return 1
}
_nb_ritual_unlock() { rmdir "$1" 2>/dev/null || true; }

_nb_ritual_write_atomic() {
  local _dest="$1" _content="$2" _tmp
  _tmp="${_dest}.$$.$(_nb_ritual_now_ms).tmp"
  printf '%s' "$_content" > "$_tmp" 2>/dev/null || { rm -f "$_tmp" 2>/dev/null; return 1; }
  mv -f "$_tmp" "$_dest" 2>/dev/null || { rm -f "$_tmp" 2>/dev/null; return 1; }
  return 0
}

# ---------------------------------------------------------------------------------------------
# 5) MAQUINA DE ESTADOS por run. Estado = {"marcos":{"mandato":ts_ms,...}} (so 1o-visto de cada).
#    _nb_ritual_registra_marco <run_id> <rotulo> <ts_ms>
#      Grava o 1o-visto do marco no estado do run (sob lock). Se ja visto, mantem o 1o ts.
#    _nb_ritual_fecha_pr <run_id> <ts_ms_do_pr>
#      No marco `pr`: confere obrigatorios presentes DENTRO DA JANELA e ORDEM; anota no placar
#      (+1 completo se tudo ok, zera o estado; +1 parcial se subconjunto, gravando faltantes).
# ---------------------------------------------------------------------------------------------

# le o ts (ms) de um marco do JSON do estado. jq -r; vazio se ausente/erro.
_nb_ritual_estado_ts() {
  local _statef="$1" _marco="$2"
  jq -r --arg m "$_marco" '.marcos[$m] // empty' "$_statef" 2>/dev/null || printf ''
}

_nb_ritual_registra_marco() {
  local _run="$1" _marco="$2" _ts="$3"
  [ -z "$_run" ] && return 0
  _nb_ritual_marco_valido "$_marco" || return 0
  case "$_ts" in ''|*[!0-9]*) return 0 ;; esac
  command -v jq >/dev/null 2>&1 || return 0

  local _dir _statef _lock _cur _new
  _dir="$(_nb_ritual_state_dir)"
  mkdir -p "$_dir" 2>/dev/null || return 0
  _statef="${_dir}/${_run}.json"
  _lock="${_statef}.lock"

  _nb_ritual_lock "$_lock" || return 0

  if [ -f "$_statef" ]; then
    _cur="$(cat "$_statef" 2>/dev/null || echo '{}')"
  else
    _cur='{"marcos":{}}'
  fi
  # so grava se o marco AINDA nao existe (preserva o 1o-visto). jq faz o merge condicional.
  _new="$(printf '%s' "$_cur" | jq -c --arg m "$_marco" --argjson ts "$_ts" '
      (.marcos // {}) as $mk
      | if ($mk | has($m)) then .
        else .marcos = ($mk + {($m): $ts}) end
    ' 2>/dev/null || true)"
  if [ -n "$_new" ]; then
    _nb_ritual_write_atomic "$_statef" "$_new" || true
  fi
  _nb_ritual_unlock "$_lock"
  return 0
}

# _nb_ritual_bump_contagem <resultado> <faltaram-csv>
#   resultado = "completo" | "parcial". Incrementa o placar sob lock, escrita atomica.
#   faltaram-csv (so no parcial) = rotulos separados por espaco (ex: "teste review").
_nb_ritual_bump_contagem() {
  local _res="$1" _faltaram="${2:-}"
  command -v jq >/dev/null 2>&1 || return 0
  local _f _lock _cur _ts _new _sig="$_NB_RITUAL_ASSINATURA"
  _f="$(_nb_ritual_contagem)"
  _lock="${_f}.lock"
  mkdir -p "$(dirname "$_f")" 2>/dev/null || return 0
  _ts="$(date -u +%FT%TZ 2>/dev/null || echo unknown)"

  _nb_ritual_lock "$_lock" || return 0

  if [ -f "$_f" ]; then
    _cur="$(cat "$_f" 2>/dev/null || echo '{}')"
  else
    _cur='{}'
  fi
  # normaliza a estrutura minima; incrementa completos OU parciais; agrega faltaram (contagem por rotulo).
  # `faltaram` vira objeto {rotulo: n} pra o placar dizer QUAL marco mais falta (so rotulos do vocab).
  _new="$(printf '%s' "$_cur" | jq -c \
      --arg sig "$_sig" --arg res "$_res" --arg ts "$_ts" --arg falt "$_faltaram" '
      def base: {"versao":1,"rituais":{},"atualizado":$ts};
      ( if (.versao? // null)==1 then . else base end ) as $b
      | ($b.rituais[$sig] // {"completos":0,"parciais":0,"parciais_faltou":{},"ultimo_completo_ts":null}) as $r
      | ($falt | split(" ") | map(select(length>0))) as $fs
      | ($r.parciais_faltou // {}) as $pf
      | ( reduce $fs[] as $x ($pf; .[$x] = ((.[$x] // 0) + 1)) ) as $pf2
      | ( if $res=="completo" then
            ($r + {"completos": (($r.completos//0)+1), "ultimo_completo_ts": $ts})
          else
            ($r + {"parciais": (($r.parciais//0)+1), "parciais_faltou": $pf2})
          end ) as $r2
      | $b + {"rituais": ($b.rituais + {($sig): $r2}), "atualizado": $ts}
    ' 2>/dev/null || true)"
  if [ -n "$_new" ]; then
    _nb_ritual_write_atomic "$_f" "$_new" || true
  fi
  _nb_ritual_unlock "$_lock"
  return 0
}

_nb_ritual_fecha_pr() {
  local _run="$1" _ts_pr="$2"
  [ -z "$_run" ] && return 0
  case "$_ts_pr" in ''|*[!0-9]*) return 0 ;; esac
  command -v jq >/dev/null 2>&1 || return 0

  local _dir _statef _lock
  _dir="$(_nb_ritual_state_dir)"
  _statef="${_dir}/${_run}.json"
  _lock="${_statef}.lock"
  [ -f "$_statef" ] || return 0

  _nb_ritual_lock "$_lock" || return 0
  local _cur; _cur="$(cat "$_statef" 2>/dev/null || echo '{}')"
  _nb_ritual_unlock "$_lock"

  # extrai ts (ms) de cada obrigatorio (menos pr, que e o ts do fecho).
  local _ts_mandato _ts_teste _ts_review _falta="" _lo="" _hi=""
  _ts_mandato="$(printf '%s' "$_cur" | jq -r '.marcos.mandato // empty' 2>/dev/null)"
  _ts_teste="$(printf '%s'   "$_cur" | jq -r '.marcos.teste // empty'   2>/dev/null)"
  _ts_review="$(printf '%s'  "$_cur" | jq -r '.marcos.review // empty'  2>/dev/null)"

  # JANELA: um marco com > 12h em relacao ao fecho e considerado VELHO -> tratado como ausente.
  _nb_ritual_dentro_janela() {
    local _t="$1"
    case "$_t" in ''|*[!0-9]*) return 1 ;; esac
    local _delta=$(( _ts_pr - _t ))
    [ "$_delta" -lt 0 ] && _delta=$(( -_delta ))
    [ "$_delta" -le "$_NB_RITUAL_JANELA_MS" ]
  }
  _nb_ritual_dentro_janela "$_ts_mandato" || { _falta="$_falta mandato"; _ts_mandato=""; }
  _nb_ritual_dentro_janela "$_ts_teste"   || { _falta="$_falta teste";   _ts_teste="";   }
  _nb_ritual_dentro_janela "$_ts_review"  || { _falta="$_falta review";  _ts_review="";  }

  # trim do _falta
  _falta="${_falta#"${_falta%%[![:space:]]*}"}"

  if [ -n "$_ts_mandato" ] && [ -n "$_ts_teste" ] && [ -n "$_ts_review" ]; then
    # ORDEM: ts(mandato) < min(teste,review)  E  max(teste,review) < ts(pr)
    _lo="$_ts_teste"; [ "$_ts_review" -lt "$_lo" ] && _lo="$_ts_review"
    _hi="$_ts_teste"; [ "$_ts_review" -gt "$_hi" ] && _hi="$_ts_review"
    if [ "$_ts_mandato" -lt "$_lo" ] && [ "$_hi" -lt "$_ts_pr" ]; then
      _nb_ritual_bump_contagem "completo" ""
      # zera o estado do run (nova passada conta de novo). Escrita atomica sob lock.
      _nb_ritual_lock "$_lock" || return 0
      _nb_ritual_write_atomic "$_statef" '{"marcos":{}}' || true
      _nb_ritual_unlock "$_lock"
      return 0
    else
      # obrigatorios presentes mas ORDEM violada -> parcial (nao completa). Nao lista faltantes
      # (nenhum FALTOU; a ORDEM que quebrou). Marca parcial com faltou vazio.
      _nb_ritual_bump_contagem "parcial" ""
      return 0
    fi
  fi

  # subconjunto: +1 parcial gravando QUAIS obrigatorios faltaram (so rotulos do vocab).
  _nb_ritual_bump_contagem "parcial" "$_falta"
  return 0
}

# ---------------------------------------------------------------------------------------------
# 6) HOUSEKEEPING: apaga estados de run com mtime > 48h (e locks orfaos junto). Best-effort.
# ---------------------------------------------------------------------------------------------
_nb_ritual_housekeeping() {
  local _dir; _dir="$(_nb_ritual_state_dir)"
  [ -d "$_dir" ] || return 0
  find "$_dir" -name '*.json' -mmin "+${_NB_RITUAL_STATE_TTL_MIN}" -delete 2>/dev/null || true
  find "$_dir" -name '*.lock' -type d -mmin +1 -exec rmdir {} + 2>/dev/null || true
  return 0
}
