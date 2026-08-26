#!/usr/bin/env bash
# _prova-negativa.sh — PROVA QUE REPROVA (negative control da prova) do Norte-box (NRT-_990429).
# Sourceado pelo helper bin/nb-provar-contra e pelo comando /norte-box:provar-contra.
#
# O BURACO QUE ESTA PECA FECHA: o motor _provar.sh / _norte_provar_planilha CONFIA no exit-code do
# conferidor (checker): checker exit 0 = "provou" (verde). O proprio _provar.sh:214 grifa "A ARMADILHA
# nº1: 'rodou' != 'conferiu'" — mas NADA verifica que o checker TEM DENTES. Um checker frouxo/vazio
# que SEMPRE sai 0 aprova QUALQUER coisa e ninguem percebe. Um "verde" desses e um verde que mente.
#
# O QUE ESTA PECA FAZ: roda o MESMO checker contra um <dados_ruim> (input SABIDAMENTE errado) no MESMO
# sandbox contido do motor (dir descartavel na arvore controlada, timeout duro, CWD=sandbox, rede
# cortada quando da). So chama de "PROVA FORTE" um checker que DEMONSTRA que sabe reprovar um erro
# plantado — E que sabe APROVAR um caso bom (o PAR):
#   passa no <dados_ok> (exit 0) E REPROVA o <dados_ruim> (exit != 0, NAO timeout, NAO crash) -> 🟢 PROVA FORTE.
#   passa o <dados_ruim> (exit 0)                                -> 🟡 RECUSA: "nao pega erro plantado".
#   reprova ATE o <dados_ok>                                     -> 🟡 RECUSA: "dente cego" (reprova tudo).
#   TRAVA/timeout no ruim (ou no bom)                            -> 🟡 FALHA HONESTA: nao sei se reprova.
#   QUEBRA no ruim (traceback/typo/import/127)                   -> 🟡 QUEBROU: nao reprovou de proposito.
#   SO-NEGATIVO (sem <dados_ok>), mesmo reprovando limpo         -> 🟡 INDICIO FRACO: sem caso bom pra
#                                                                  comparar, pode estar so quebrado. Nunca 🟢.
# GEMEO DA ARMADILHA nº1: la o buraco e "sempre exit 0" (checker frouxo). AQUI e "sempre exit != 0 por
# estar QUEBRADO": um checker com typo crasha no ruim -> exit != 0 -> lido cego como "reprovou". O PAR
# (passa no bom E reprova no ruim) mata isso — quebrado crasha no bom tambem -> RECUSA/amarelo.
#
# MOLDURA HONESTA (nao overclaim): "PROVA FORTE" = "o conferidor reprova PELO MENOS UM erro plantado",
# NAO "o conferidor e completo/perfeito". Um unico negative control NAO prova cobertura total. A copy
# so pode dizer isso.
#
# LEIS (nao-negociaveis, iguais aos outros passos do motor):
#   - PRIVADO POR PADRAO: a prova forte mora num arquivo LOCAL em $HOME/.norte-box/provas/<sessao>/.
#     NUNCA sai da maquina, NUNCA passa por telemetria/rede. So le/escreve o disco local.
#   - HONESTO POR PADRAO (fail-honest / fail-CLOSED da confianca): so escreve "prova_forte:true" quando
#     o checker REALMENTE reprovou o erro plantado. Na duvida (timeout/erro de setup) NAO chama de
#     prova forte — devolve amarelo com o motivo real.
#   - FAIL-OPEN da sessao: se ESTA peca quebra (falta jq/runtime, disco), NAO trava a sessao — avisa
#     amarelo (return 2) e segue. A ausencia da peca nunca vira buraco na caixa.
#   - SANDBOX CONTIDO: roda o checker do cliente num dir temporario proprio (dentro da arvore de provas),
#     com timeout duro, e (quando o runtime deixa) SEM rede. Nao herda o CWD do projeto; limpa o temp.
#   - HARDENING: a prova.artefato SEMPRE nasce DENTRO de $HOME/.norte-box/provas/. Grava hash do CHECKER
#     + hash do <dados_ruim>. Reusa o marcador do motor (_norte_provar_marcar_provado) pra amarrar o
#     vinculo A3 na fichinha; artefato fora da arvore NAO vale (defesa em profundidade no _situacao.sh).
#   - DADO E DADO, NUNCA COMANDO: o <dados_ruim> vira ./dados.<ext> no sandbox; o checker o LE. Um
#     payload de shell / path traversal dentro do dado NUNCA e executado fora do checker.
#   - Portabilidade macOS (bash 3.2, SEM arrays associativos/mapfile/${v^^}). Precisa de jq; sem jq,
#     degrada sem travar (fail-open).
#
# KILL-SWITCH: NORTE_PROVA_NEGATIVA=0 desliga a peca (inerte, return 2). A prova NUNCA sai da maquina.
set -u

# --- carrega o motor (fonte unica do sandbox/hash/marcador). bin/ e hooks/ sao irmaos sob norte-box. ---
# So carrega se ainda nao estiver na memoria (o bin ja pode ter sourceado). Idempotente.
if ! command -v _norte_provar_planilha >/dev/null 2>&1; then
  _npn_self="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)"
  if [ -n "${_npn_self:-}" ] && [ -f "${_npn_self}/_provar.sh" ]; then
    # shellcheck source=/dev/null
    . "${_npn_self}/_provar.sh" 2>/dev/null || true
  elif [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/hooks/_provar.sh" ]; then
    # shellcheck source=/dev/null
    . "${CLAUDE_PLUGIN_ROOT}/hooks/_provar.sh" 2>/dev/null || true
  fi
fi
# o _provar.sh reusa a lib da fichinha (_norte_prova_hash_arquivo / _norte_realpath); carrega se estiver ao lado.
if ! command -v _norte_prova_hash_arquivo >/dev/null 2>&1; then
  _npn_self="${_npn_self:-$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)}"
  if [ -n "${_npn_self:-}" ] && [ -f "${_npn_self}/_situacao.sh" ]; then
    # shellcheck source=/dev/null
    . "${_npn_self}/_situacao.sh" 2>/dev/null || true
  fi
fi
# o redator compartilhado (mascara secret/PII antes de imprimir/gravar). carrega se estiver ao lado.
if ! command -v _redact >/dev/null 2>&1; then
  _npn_self="${_npn_self:-$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)}"
  if [ -n "${_npn_self:-}" ] && [ -f "${_npn_self}/_redact.sh" ]; then
    # shellcheck source=/dev/null
    . "${_npn_self}/_redact.sh" 2>/dev/null || true
  fi
fi

# _npn_raiz — a UNICA arvore que o selo aceita como prova. Reusa a do motor se existir; senao a padrao.
_npn_raiz() {
  if command -v _norte_provas_raiz >/dev/null 2>&1; then _norte_provas_raiz; else printf '%s/.norte-box/provas' "${HOME}"; fi
}

# _npn_tipo <arquivo> — runtime pelo sufixo: py | js | sh | "" (nao-suportado). So a extensao (nao le o
# conteudo — nao adivinha shebang). Reusa o do motor se existir (fonte unica).
_npn_tipo() {
  if command -v _norte_provar_tipo >/dev/null 2>&1; then _norte_provar_tipo "$1"; return 0; fi
  case "${1:-}" in
    *.py) printf 'py' ;;
    *.js|*.mjs|*.cjs) printf 'js' ;;
    *.sh|*.bash) printf 'sh' ;;
    *) printf '' ;;
  esac
}

# _npn_dtipo <arquivo> — tipo do DADO pelo sufixo: csv | json | "" (nao-suportado). Reusa o do motor.
_npn_dtipo() {
  if command -v _norte_provar_dados_tipo >/dev/null 2>&1; then _norte_provar_dados_tipo "$1"; return 0; fi
  case "${1:-}" in
    *.csv) printf 'csv' ;;
    *.json) printf 'json' ;;
    *) printf '' ;;
  esac
}

# _npn_runner <tipo> — o binario que roda aquele tipo, se existir no PATH. Reusa o do motor.
_npn_runner() {
  if command -v _norte_provar_runner >/dev/null 2>&1; then _norte_provar_runner "$1"; return 0; fi
  case "${1:-}" in
    py) command -v python3 >/dev/null 2>&1 && { printf 'python3'; return 0; }; command -v python >/dev/null 2>&1 && { printf 'python'; return 0; }; printf '' ;;
    js) command -v node >/dev/null 2>&1 && { printf 'node'; return 0; }; printf '' ;;
    sh) command -v bash >/dev/null 2>&1 && { printf 'bash'; return 0; }; printf '' ;;
    *)  printf '' ;;
  esac
}

# _npn_slug <string> — sanitiza pra virar nome de diretorio seguro. Reusa o do motor.
_npn_slug() {
  if command -v _norte_provar_slug >/dev/null 2>&1; then _norte_provar_slug "$1"; return 0; fi
  printf '%s' "${1:-}" | tr -c 'A-Za-z0-9._-' '_' | cut -c1-64
}

# _npn_tobin — timeout|gtimeout se existir; vazio se nenhum. Reusa o do motor.
_npn_tobin() {
  if command -v _norte_provar_timeout_bin >/dev/null 2>&1; then _norte_provar_timeout_bin; return 0; fi
  command -v timeout >/dev/null 2>&1 && { printf 'timeout'; return 0; }
  command -v gtimeout >/dev/null 2>&1 && { printf 'gtimeout'; return 0; }
  printf ''
}

# _npn_rodar_checker <checker> <tipo> <runner> <dados> <dtipo> <out>
#   Roda o checker no MESMO sandbox contido do motor: dir descartavel dentro da arvore controlada,
#   [unshare -rn]? -> [timeout -k 2 <dur>]? -> <runner> ./check.<ext>, CWD = sandbox, dados em ./dados.<ext>.
#   Escreve stdout+stderr em <out>. Ecoa o rc do checker no stdout (uma linha). Limpa o sandbox.
#   Retorna 0 sempre (o resultado e o rc ecoado); so falha (return 3) se nem deu pra montar o sandbox.
_npn_rodar_checker() {
  local _chk="$1" _tipo="$2" _runner="$3" _dados="$4" _dtipo="$5" _out="$6"
  local _raiz _ts _sbx _copia _cdados _tobin _dur _rc
  _raiz="$(_npn_raiz)"
  _ts="$(date -u +%Y%m%dT%H%M%S%NZ 2>/dev/null || date -u +%Y%m%dT%H%M%SZ 2>/dev/null || echo t)"
  _sbx="${_raiz}/.sbx-neg.$$.${_ts}"
  mkdir -p "$_sbx" 2>/dev/null || return 3
  case "$_tipo" in
    py) _copia="${_sbx}/check.py" ;;
    js) _copia="${_sbx}/check.js" ;;
    sh) _copia="${_sbx}/check.sh" ;;
    *)  rm -rf "$_sbx" 2>/dev/null; return 3 ;;
  esac
  _cdados="${_sbx}/dados.${_dtipo}"
  cp -- "$_chk" "$_copia" 2>/dev/null && cp -- "$_dados" "$_cdados" 2>/dev/null \
    || { rm -rf "$_sbx" 2>/dev/null; return 3; }

  _tobin="$(_npn_tobin)"
  _dur="${NB_PROVAR_TIMEOUT:-20}"
  case "$_dur" in ''|*[!0-9]*) _dur=20 ;; esac

  # monta o comando SEM array associativo (bash 3.2): array indexado simples.
  local _cmd
  _cmd=()
  if command -v unshare >/dev/null 2>&1 && unshare -rn true >/dev/null 2>&1; then
    _cmd+=( unshare -rn )
  fi
  if [ -n "$_tobin" ]; then
    _cmd+=( "$_tobin" -k 2 "$_dur" )
  fi
  _cmd+=( "$_runner" "$_copia" )

  ( cd "$_sbx" 2>/dev/null && "${_cmd[@]}" ) >"$_out" 2>&1
  _rc=$?
  rm -rf "$_sbx" 2>/dev/null
  printf '%s\n' "$_rc"
  return 0
}

# _npn_e_timeout <rc> — 0 (SIM, foi timeout) se o rc bate os codigos do timeout/gtimeout: 124 (estourou),
# 125 (o timeout falhou), 137 (SIGKILL, o -k), 143 (SIGTERM). So conta como timeout SE ha timeout-bin
# instalado (senao esses rc podem ser exit normais do checker). Fail-honest: na duvida, e timeout.
_npn_e_timeout() {
  local _rc="${1:-}"
  [ -n "$(_npn_tobin)" ] || return 1
  case "$_rc" in 124|125|137|143) return 0 ;; *) return 1 ;; esac
}

# _npn_e_crash <rc> <saida> — 0 (SIM, o conferidor QUEBROU por erro PROPRIO) quando o exit != 0 nao veio
# de uma reprovacao deliberada, e sim de o checker estar QUEBRADO (typo, import faltando, sintaxe, binario
# ausente). Isto e o GEMEO SIMETRICO da armadilha nº1: la o buraco e "sempre exit 0"; aqui e "sempre
# exit != 0 por estar quebrado" — que, cego, o motor leria como "reprovou de proposito" e daria 🟢 falso.
#   Duas pistas (basta UMA):
#     (a) EXIT tipico de crash do shell: 126 (nao-executavel) / 127 (command not found).
#     (b) ASSINATURA de crash NAO-capturado na saida: traceback Python, SyntaxError/ImportError/
#         ModuleNotFoundError, "command not found", "No such file or directory", ReferenceError JS.
#   HONESTIDADE: e HEURISTICA (nao pega 100% — um checker pode imprimir "SyntaxError" de proposito no
#   texto de reprovacao). Cobre o comum. A camada 1 (exige o caso BOM) e a defesa PRINCIPAL; esta e
#   defesa em profundidade pra o crash que acontece SO no dado ruim (passa no bom, quebra no ruim).
_npn_e_crash() {
  local _rc="${1:-}" _saida="${2:-}"
  # (a) exit-codes que o shell reserva pra "nao consegui nem rodar o programa".
  case "$_rc" in 126|127) return 0 ;; esac
  # (b) assinaturas de crash na saida. grep -F por literal quando da; -E so pros 2 padroes com alternativa.
  case "$_saida" in
    *"Traceback (most recent call last)"*) return 0 ;;
    *"SyntaxError"*)          return 0 ;;
    *"ImportError"*)          return 0 ;;
    *"ModuleNotFoundError"*)  return 0 ;;
    *"command not found"*)    return 0 ;;
    *"No such file or directory"*) return 0 ;;
    *"ReferenceError"*)       return 0 ;;
    *"is not defined"*)       return 0 ;;
  esac
  return 1
}

# _norte_prova_negativa <checker> <dados_ruim> [dados_ok] [sessao]
#   Roda o negative control. Ecoa um bloco humano (o que aconteceu) e devolve:
#     0 -> PROVA FORTE: EXIGE o PAR — passou no dado BOM (exit 0) E reprovou o erro plantado (exit != 0,
#          nao-timeout, nao-crash). So ha PROVA FORTE 🟢 com <dados_ok>. Gravou o artefato na arvore
#          controlada + marcou provado:true na fichinha (vinculo A3).
#     1 -> RECUSA a prova forte: o checker NAO pega o erro plantado (passou o ruim) OU reprova ate o bom
#          (dente cego). A fichinha NAO vira verde por esta peca.
#     2 -> nao deu pra provar / so ha INDICIO FRACO (amarelo honesto). Cobre:
#          - kill-switch / arquivo ausente / tipo nao-suportado / runtime ausente / sem jq / falha de
#            setup do sandbox;
#          - TIMEOUT no ruim (ou no bom) = falha honesta;
#          - CRASH do conferidor no ruim (typo/import/sintaxe/127) = quebrou, nao reprovou de proposito;
#          - SO-NEGATIVO (sem <dados_ok>) mesmo reprovando limpo o ruim: 🟡 INDICIO FRACO — sem um caso
#            BOM pra comparar nao da pra afirmar que ele tem dentes (pode estar so quebrado). Fail-open.
#   POR QUE O PAR (camada 1): um checker QUEBRADO crasha no BOM tambem -> _rc_ok != 0 -> RECUSA/amarelo;
#   entao exigir "passa no bom E reprova no ruim" ja mata o crash cego. O <dados_ok> deixou de ser
#   opcional-pra-forte: SEM ele, no maximo 🟡 indicio fraco (nunca 🟢).
_norte_prova_negativa() {
  local _chk="${1:-}" _ruim="${2:-}" _ok="${3:-}" _sess="${4:-}"

  # kill-switch: NORTE_PROVA_NEGATIVA=0 -> inerte.
  case "${NORTE_PROVA_NEGATIVA:-1}" in
    0|no|nao|off|false)
      printf '🟡 a peca "prova que reprova" nao esta ligada nesta maquina (NORTE_PROVA_NEGATIVA=0).\n'
      return 2 ;;
  esac

  # --- pre-condicoes (fail-honest / fail-open) ---
  if [ -z "$_chk" ] || [ ! -f "$_chk" ]; then
    printf '🟡 nao consegui provar: o conferidor (checker) indicado nao existe.\n'; return 2
  fi
  if [ -z "$_ruim" ] || [ ! -f "$_ruim" ]; then
    printf '🟡 nao consegui provar: o arquivo de dados ERRADOS (o erro plantado) indicado nao existe.\n'; return 2
  fi
  if [ -n "$_ok" ] && [ ! -f "$_ok" ]; then
    printf '🟡 nao consegui provar: voce apontou um arquivo de dados BONS que nao existe.\n'; return 2
  fi
  command -v jq >/dev/null 2>&1 || { printf '🟡 nao consegui provar: falta o jq nesta maquina.\n'; return 2; }

  local _tipo _runner _druim _dok=""
  _tipo="$(_npn_tipo "$_chk")"
  if [ -z "$_tipo" ]; then
    printf '🟡 nao sei rodar esse tipo de conferidor (por enquanto so .py, .js ou .sh).\n'; return 2
  fi
  _druim="$(_npn_dtipo "$_ruim")"
  if [ -z "$_druim" ]; then
    printf '🟡 nao sei ler esse tipo de dado (por enquanto so planilha .csv ou .json).\n'; return 2
  fi
  if [ -n "$_ok" ]; then
    _dok="$(_npn_dtipo "$_ok")"
    if [ -z "$_dok" ]; then
      printf '🟡 nao sei ler o tipo do arquivo de dados BONS (so .csv ou .json).\n'; return 2
    fi
  fi
  _runner="$(_npn_runner "$_tipo")"
  if [ -z "$_runner" ]; then
    printf '🟡 nao consegui provar: falta o programa pra rodar o conferidor nesta maquina.\n'; return 2
  fi

  # --- diretorio da prova forte (arvore CONTROLADA — a unica que o selo aceita) ---
  local _raiz _sslug _dir _ts _prova
  _raiz="$(_npn_raiz)"
  _sslug="$(_npn_slug "${_sess:-sessao}")"; [ -n "$_sslug" ] || _sslug="sessao"
  _ts="$(date -u +%Y%m%dT%H%M%SZ 2>/dev/null || echo t)"
  _dir="${_raiz}/${_sslug}"
  mkdir -p "$_dir" 2>/dev/null || { printf '🟡 nao consegui gravar a prova (disco nao gravavel).\n'; return 2; }
  _prova="${_dir}/prova-forte-${_ts}.txt"

  # --- (1) roda o checker contra o DADO RUIM (o erro plantado). EXIGE reprovacao (exit != 0). ---
  local _out_ruim _rc_ruim
  _out_ruim="$(mktemp 2>/dev/null || echo "${_dir}/.out-ruim.$$")"
  _rc_ruim="$(_npn_rodar_checker "$_chk" "$_tipo" "$_runner" "$_ruim" "$_druim" "$_out_ruim")"
  if [ -z "$_rc_ruim" ] || [ "$_rc_ruim" = "" ]; then
    rm -f "$_out_ruim" 2>/dev/null
    printf '🟡 nao consegui preparar o sandbox pra rodar o conferidor no dado errado.\n'; return 2
  fi

  # --- (2, opcional) roda o checker contra o DADO BOM. Se passado, EXIGE que passe (exit 0). ---
  local _out_ok="" _rc_ok=""
  if [ -n "$_ok" ]; then
    _out_ok="$(mktemp 2>/dev/null || echo "${_dir}/.out-ok.$$")"
    _rc_ok="$(_npn_rodar_checker "$_chk" "$_tipo" "$_runner" "$_ok" "$_dok" "$_out_ok")"
    if [ -z "$_rc_ok" ] || [ "$_rc_ok" = "" ]; then
      rm -f "$_out_ruim" "$_out_ok" 2>/dev/null
      printf '🟡 nao consegui preparar o sandbox pra rodar o conferidor no dado bom.\n'; return 2
    fi
  fi

  # saidas redigidas (secret/PII fora) e cortadas — a prova forte guarda so o que precisa.
  local _saida_ruim _saida_ok=""
  if command -v _safe_field >/dev/null 2>&1; then
    _saida_ruim="$(_safe_field "$(head -c 4000 "$_out_ruim" 2>/dev/null || true)")"
    [ -n "$_out_ok" ] && _saida_ok="$(_safe_field "$(head -c 4000 "$_out_ok" 2>/dev/null || true)")"
  else
    _saida_ruim="$(head -c 4000 "$_out_ruim" 2>/dev/null || true)"
    [ -n "$_out_ok" ] && _saida_ok="$(head -c 4000 "$_out_ok" 2>/dev/null || true)"
  fi
  rm -f "$_out_ruim" "$_out_ok" 2>/dev/null

  # --- hashes (vinculo): hash do CHECKER (o script que decide) + hash do DADO RUIM (o erro plantado). ---
  local _chash="" _rhash=""
  if command -v _norte_prova_hash_arquivo >/dev/null 2>&1; then
    _chash="$(_norte_prova_hash_arquivo "$_chk" 2>/dev/null || true)"
    _rhash="$(_norte_prova_hash_arquivo "$_ruim" 2>/dev/null || true)"
  fi

  # --- VEREDITO (fail-CLOSED da confianca) ---
  # timeout no ruim = FALHA HONESTA (nao sei se reprova; nao vira prova forte cega).
  if _npn_e_timeout "$_rc_ruim"; then
    printf '🟡 falha honesta: o conferidor TRAVOU/passou do tempo no dado errado — nao da pra dizer se\n'
    printf '   ele reprova o erro plantado (pode estar em loop ou esperando algo). NAO chamei de prova forte.\n'
    printf '   (rc=%s no dado errado)\n' "$_rc_ruim"
    return 2
  fi

  # CAMADA 2 (defesa em profundidade): CRASH no dado ruim = QUEBROU, nao reprovou de proposito.
  # Pega o gemeo da armadilha nº1: um checker com typo/import/sintaxe/127 crasha no ruim -> exit != 0,
  # que lido cego viraria "reprovou = tem dentes" (🟢 falso). Aqui e HEURISTICA (nao pega 100%), mas
  # cobre o comum e captura o crash que so aparece no ruim (passa no bom, quebra no ruim). Amarelo honesto.
  if _npn_e_crash "$_rc_ruim" "$_saida_ruim"; then
    printf '🟡 o conferidor QUEBROU no erro plantado (nao reprovou de proposito): ele saiu com erro por\n'
    printf '   estar QUEBRADO (typo, import faltando, sintaxe, programa ausente), nao por ter pego o erro.\n'
    printf '   um exit != 0 assim NAO prova dente — o motor cego leria isso como "reprovou" e mentiria 🟢.\n'
    printf '   (rc=%s no dado errado)\n' "$_rc_ruim"
    if [ -n "$_saida_ruim" ]; then
      printf '   o que ele cuspiu:\n'
      printf '%s\n' "$_saida_ruim" | sed 's/^/   /' | head -12
    fi
    return 2
  fi

  # dente cego: se o dado_ok foi passado e o checker reprova ATE o bom, ele reprova tudo -> nao serve.
  if [ -n "$_ok" ] && [ "$_rc_ok" != "0" ]; then
    if _npn_e_timeout "$_rc_ok"; then
      printf '🟡 falha honesta: o conferidor TRAVOU no dado BOM — nao da pra confirmar o par. NAO e prova forte.\n'
      return 2
    fi
    if _npn_e_crash "$_rc_ok" "$_saida_ok"; then
      printf '🟡 o conferidor QUEBROU no dado BOM (typo/import/sintaxe/programa ausente) — nao da pra confirmar\n'
      printf '   o par. Ele saiu com erro por estar quebrado, nao por conferir. NAO e prova forte.\n'
      printf '   (rc=%s no dado bom)\n' "$_rc_ok"
      return 2
    fi
    printf '🟡 RECUSA a prova forte: o conferidor reprovou ATE o dado BOM (exit %s) — o "dente" e cego\n' "$_rc_ok"
    printf '   (ele reprova qualquer coisa, entao reprovar o errado nao prova nada).\n'
    printf '   no dado errado deu exit %s; no dado bom deu exit %s.\n' "$_rc_ruim" "$_rc_ok"
    return 1
  fi

  if [ "$_rc_ruim" = "0" ]; then
    # o checker PASSOU o erro plantado -> NAO tem dentes. RECUSA.
    printf '🟡 RECUSA a prova forte: a prova nao pega erro plantado — o conferidor APROVOU (exit 0) um caso\n'
    printf '   sabidamente ERRADO. Ele nao tem dentes: um checker frouxo/vazio aprovaria qualquer coisa.\n'
    if [ -n "$_saida_ruim" ]; then
      printf '   o que ele disse no dado errado:\n'
      printf '%s\n' "$_saida_ruim" | sed 's/^/   /' | head -12
    fi
    return 1
  fi

  # CAMADA 1 (controle POSITIVO obrigatorio): sem <dados_ok> nao ha PROVA FORTE.
  # Ate aqui: reprovou o ruim limpo (exit != 0, nao-timeout, nao-crash). MAS sem um caso BOM pra comparar
  # nao da pra separar "reprova de proposito" de "reprova tudo / esta so meio quebrado". No maximo indicio.
  if [ -z "$_ok" ]; then
    printf '🟡 INDICIO FRACO: reprovou o erro plantado (exit %s), mas SEM um caso BOM pra comparar nao da\n' "$_rc_ruim"
    printf '   pra afirmar que ele tem dentes — ele pode estar so quebrado, ou reprovar qualquer coisa.\n'
    printf '   passe tambem um <dados_ok> (uma planilha BOA) pra virar PROVA FORTE: o par "passa no bom E\n'
    printf '   reprova no ruim" e o que prova o dente de verdade.\n'
    if [ -n "$_saida_ruim" ]; then
      printf '   o que ele disse no dado errado:\n'
      printf '%s\n' "$_saida_ruim" | sed 's/^/   /' | head -12
    fi
    return 2
  fi

  # AQUI: o par bate — passou no dado BOM (exit 0) E reprovou o erro plantado (exit != 0, nao-timeout,
  # nao-crash). -> PROVA FORTE. Grava o artefato na arvore controlada e amarra o vinculo A3 na fichinha.
  {
    printf 'PROVA FORTE norte-box (prova que reprova — negative control, NRT-_990429)\n'
    printf 'quando: %s\n' "$(date -u +%FT%TZ 2>/dev/null || echo t)"
    printf 'veredito: PROVA FORTE — o PAR bate: passou no caso BOM E reprovou PELO MENOS UM erro plantado.\n'
    printf 'MOLDURA HONESTA: isto NAO prova que o conferidor e completo/perfeito. So que ele tem dentes\n'
    printf '                 pra pelo menos este erro plantado E aprova um caso bom (nao reprova tudo cego).\n'
    printf '                 Um unico controle negativo nao mede cobertura.\n'
    printf 'tipo_checker: %s\n' "$_tipo"
    printf 'checker_hash: %s\n' "$_chash"
    printf 'dados_ruim_hash: %s\n' "$_rhash"
    printf 'exit_no_dado_errado: %s (reprovou = tem dente)\n' "$_rc_ruim"
    # a PROVA FORTE agora EXIGE o par: chega aqui so com <dados_ok> que passou (exit 0). Sempre registra.
    printf 'exit_no_dado_bom: %s (passou = nao reprova tudo cego)\n' "$_rc_ok"
    # entrega_hash: o vinculo A3 e o hash do CHECKER (o script que decide o veredito), igual ao motor.
    printf 'entrega_hash: %s\n' "$_chash"
    printf '---- o que o conferidor disse no dado ERRADO (redigido) ----\n'
    printf '%s\n' "$_saida_ruim"
    printf '---- o que o conferidor disse no dado BOM (redigido) ----\n'
    printf '%s\n' "$_saida_ok"
  } > "$_prova" 2>/dev/null

  # amarra na fichinha (reusa o marcador do motor: provado:true + prova.artefato + prova.entrega=A3).
  if command -v _norte_provar_marcar_provado >/dev/null 2>&1; then
    _norte_provar_marcar_provado "$_prova" "$_chash" 2>/dev/null || true
  fi

  printf '🟢 PROVA FORTE: rodei o seu conferidor num erro plantado e ele REPROVOU (exit %s) — tem dentes,\n' "$_rc_ruim"
  printf '   e passou no caso bom (exit %s), entao nao reprova tudo cego. O par bate.\n' "$_rc_ok"
  printf '   moldura honesta: isto prova que ele reprova PELO MENOS ESTE erro E aprova o bom — nao que ele e completo.\n'
  if [ -n "$_saida_ruim" ]; then
    printf '   ele reclamou assim do erro plantado:\n'
    printf '%s\n' "$_saida_ruim" | sed 's/^/   /' | head -12
  fi
  printf 'NB_PROVA_ARTEFATO=%s\n' "$_prova"
  return 0
}
