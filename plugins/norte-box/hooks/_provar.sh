#!/usr/bin/env bash
# _provar.sh — FONTE UNICA do "motor de prova" (Val de bolso) do Norte-box.
# Sourceado pelo helper bin/nb-provar e pelo comando /norte-box:provar.
#
# A ideia (padaria): antes de a caixa dizer "pronto", ela RODA a entrega e CAPTURA a prova. So com
# a prova capturada o selo do passo 1 vira 🟢 PROVADO. Sem prova -> continua 🟡 NAO-PROVADO com o
# ERRO REAL ("falhou aqui: <erro>"). O motor e quem ESCREVE provado:true na fichinha — e so escreve
# com prova de verdade.
#
# FATIA FINA — 1 TIPO SO: "codigo roda". A entrega e um SCRIPT (.py / .js / .sh) que a caixa criou;
# o motor EXECUTA num sandbox contido (timeout + dir temporario descartavel + rede cortada quando da);
# exit 0 -> PROVADO (captura stdout/stderr como prova); exit !=0 / travou -> NAO-PROVADO com o erro.
# (Pagina HTML NAO entra: o container do lab nao tem navegador, entao "abrir de verdade" seria mentira;
#  "validar estrutura" nao e prova de que FUNCIONA. Um tipo provavel de verdade > dois pela metade.)
#
# LEIS (nao-negociaveis, iguais aos outros passos):
#   - PRIVADO POR PADRAO: a prova mora num arquivo LOCAL em $HOME/.norte-box/provas/<sessao>/. NUNCA
#     sai da maquina, NUNCA passa por telemetria/rede. Esta lib so le/escreve o disco local.
#   - HONESTO POR PADRAO (fail-honest): so escreve provado:true quando a execucao REALMENTE deu exit 0.
#     Quebrou/timeout/tipo-nao-suportado -> mantem provado:false (amarelo) e devolve o erro real.
#   - SANDBOX CONTIDO: roda a entrega num diretorio temporario proprio, com timeout duro, e (quando o
#     runtime deixa) SEM rede. A execucao da entrega do cliente NAO pode virar buraco: nao roda como
#     root deliberadamente, nao herda o CWD do projeto, limpa o temp depois.
#   - HARDENING (o Val pediu): a prova.artefato SEMPRE nasce DENTRO de $HOME/.norte-box/provas/. O selo
#     (passo 1) so aceita 🟢 se o artefato estiver nessa arvore (ver _situacao.sh) — assim ninguem
#     forja /etc/hosts como "prova".
#   - Portabilidade macOS (bash 3.2). Precisa de jq; sem jq, degrada sem travar (fail-open).
set -u

# --- raiz controlada das provas (a UNICA arvore que o selo aceita como prova) ---
_norte_provas_raiz() { printf '%s/.norte-box/provas' "${HOME}"; }

# _norte_provar_tipo <arquivo> — ecoa o "runtime" pelo sufixo do arquivo: py | js | sh | "" (nao-suportado).
# So olha a extensao; nao le o conteudo (nao adivinha shebang — fatia fina, 3 tipos explicitos).
_norte_provar_tipo() {
  case "${1:-}" in
    *.py) printf 'py' ;;
    *.js|*.mjs|*.cjs) printf 'js' ;;
    *.sh|*.bash) printf 'sh' ;;
    *) printf '' ;;
  esac
}

# _norte_provar_runner <tipo> — ecoa o binario que roda aquele tipo, se existir no PATH. Vazio se falta.
_norte_provar_runner() {
  case "${1:-}" in
    py) command -v python3 2>/dev/null || command -v python 2>/dev/null ;;
    js) command -v node 2>/dev/null ;;
    sh) command -v bash 2>/dev/null ;;
    *)  : ;;
  esac
}

# _norte_provar_timeout_bin — ecoa timeout|gtimeout se existir; vazio se nenhum (roda sem cerca dura).
_norte_provar_timeout_bin() {
  command -v timeout 2>/dev/null || command -v gtimeout 2>/dev/null || true
}

# _norte_provar_slug — sanitiza uma string pra virar nome de diretorio seguro (so [A-Za-z0-9._-]).
_norte_provar_slug() {
  printf '%s' "${1:-}" | tr -c 'A-Za-z0-9._-' '_' | cut -c1-64
}

# _norte_provar_rodar <arquivo> [sessao]
#   Roda a entrega no sandbox e ESCREVE a prova. Ecoa no stdout um bloco humano (o que aconteceu) e
#   devolve o exit code do MOTOR:
#     0  -> PROVOU (exit 0 do script): gravou prova.artefato + provado:true na fichinha.
#     1  -> NAO PROVOU (script quebrou/timeout): fichinha fica amarela; a prova guarda o erro real.
#     2  -> nao deu pra provar (arquivo ausente / tipo nao-suportado / runtime ausente / sem jq).
#   O bloco impresso e curto e de padaria; a prova completa fica no arquivo (caminho ecoado numa linha
#   marcada NB_PROVA_ARTEFATO=... pra o chamador citar sem inventar).
_norte_provar_rodar() {
  local _arq="${1:-}" _sess="${2:-}"
  # --- pre-condicoes (fail-honest: sem provar de verdade, nao mente verde) ---
  if [ -z "$_arq" ] || [ ! -f "$_arq" ]; then
    printf '🟡 nao consegui provar: o arquivo indicado nao existe.\n'
    return 2
  fi
  command -v jq >/dev/null 2>&1 || { printf '🟡 nao consegui provar: falta o jq nesta maquina.\n'; return 2; }
  local _tipo _runner
  _tipo="$(_norte_provar_tipo "$_arq")"
  if [ -z "$_tipo" ]; then
    printf '🟡 nao sei rodar esse tipo de arquivo ainda (por enquanto so provo scripts .py, .js ou .sh).\n'
    return 2
  fi
  _runner="$(_norte_provar_runner "$_tipo")"
  if [ -z "$_runner" ]; then
    printf '🟡 nao consegui provar: falta o programa pra rodar esse tipo de arquivo nesta maquina.\n'
    return 2
  fi

  # --- diretorio da prova (arvore CONTROLADA — a unica que o selo aceita) ---
  local _raiz _sslug _dir _ts
  _raiz="$(_norte_provas_raiz)"
  _sslug="$(_norte_provar_slug "${_sess:-sessao}")"
  [ -n "$_sslug" ] || _sslug="sessao"
  _ts="$(date -u +%Y%m%dT%H%M%SZ 2>/dev/null || echo t)"
  _dir="${_raiz}/${_sslug}"
  mkdir -p "$_dir" 2>/dev/null || { printf '🟡 nao consegui gravar a prova (disco nao gravavel).\n'; return 2; }
  local _prova="${_dir}/prova-${_ts}.txt"

  # --- sandbox de execucao: dir temporario proprio DENTRO da arvore local controlada
  #     ($HOME/.norte-box/.sbx/...) — a entrega roda COPIADA pra la (nao no lugar original nem herdando
  #     o CWD do projeto), com timeout duro, e o dir e descartado no fim. Ficar sob $HOME/.norte-box
  #     (e nao no /tmp do sistema) mantem tudo na mesma arvore local e evita depender do TMPDIR global.
  local _sbx _copia _rc _tobin _out
  _sbx="${_dir}/.sbx.$$.${_ts}"
  mkdir -p "$_sbx" 2>/dev/null || { printf '🟡 nao consegui preparar o sandbox (disco nao gravavel).\n'; return 2; }
  # nome da copia preserva a extensao (o runner as vezes olha o sufixo).
  case "$_tipo" in
    py) _copia="${_sbx}/entrega.py" ;;
    js) _copia="${_sbx}/entrega.js" ;;
    sh) _copia="${_sbx}/entrega.sh" ;;
  esac
  cp -- "$_arq" "$_copia" 2>/dev/null || { rm -rf "$_sbx" 2>/dev/null; printf '🟡 nao consegui preparar o sandbox.\n'; return 2; }

  _tobin="$(_norte_provar_timeout_bin)"
  local _dur="${NB_PROVAR_TIMEOUT:-20}"
  case "$_dur" in ''|*[!0-9]*) _dur=20 ;; esac

  # Monta o comando de execucao COMPLETO num unico array _cmd (nunca vazio na expansao — arrays vazios
  # com set -u quebram no bash 3.2 do macOS). Camadas de cerca, da mais externa pra mais interna:
  #   [unshare -rn]?  ->  [timeout -k 2 <dur>]?  ->  <runner> <copia>
  # Rede cortada quando ha jeito barato e portavel (unshare -n sem privilegio; muitos ambientes
  # bloqueiam -> best-effort, ignora se nao der). Timeout duro se timeout/gtimeout existir. A cerca
  # principal e SEMPRE o dir descartavel + o CWD = sandbox (nunca herda o diretorio do projeto).
  _out="${_sbx}/saida.txt"
  local _cmd
  _cmd=()
  if command -v unshare >/dev/null 2>&1 && unshare -rn true >/dev/null 2>&1; then
    _cmd+=( unshare -rn )
  fi
  if [ -n "$_tobin" ]; then
    _cmd+=( "$_tobin" -k 2 "$_dur" )
  fi
  _cmd+=( "$_runner" "$_copia" )

  # Executa. CWD = sandbox, HOME preservado (o script pode precisar). stdout+stderr juntos no arquivo.
  ( cd "$_sbx" 2>/dev/null && "${_cmd[@]}" ) >"$_out" 2>&1
  _rc=$?

  # Cap de tamanho da saida capturada (nao guardar um dump gigante; a prova e curta).
  local _saida
  _saida="$(head -c 4000 "$_out" 2>/dev/null || true)"

  # --- VINCULO com a ENTREGA (A3): carimba na prova o hash do CONTEUDO do arquivo que o motor RODOU.
  # NAO usa o .objetivo (que fica VAZIO no meio do turno — o Stop so grava o objetivo no fim); usa o que
  # foi efetivamente entregue, que o motor tem em mao AGORA. O selo (_situacao.sh) le esse hash DO
  # ARQUIVO e exige que bata com prova.entrega da fichinha (escrito na mesma marcacao do provado:true),
  # entao trocar a prova por uma de OUTRA entrega (hash de conteudo diferente) NAO abre o verde. Se nao
  # der pra hashear (arquivo sumiu), grava vazio -> o selo trata como nao-vinculado (amarelo), fail-honest.
  local _ehash=""
  if command -v _norte_prova_hash_arquivo >/dev/null 2>&1; then
    _ehash="$(_norte_prova_hash_arquivo "$_arq" 2>/dev/null || true)"
  fi

  # --- grava o arquivo de prova (LOCAL, dentro da arvore controlada) ---
  {
    printf 'PROVA norte-box (motor Val de bolso)\n'
    printf 'quando: %s\n' "$(date -u +%FT%TZ 2>/dev/null || echo t)"
    printf 'tipo: %s\n' "$_tipo"
    printf 'exit: %s\n' "$_rc"
    printf 'entrega_hash: %s\n' "$_ehash"
    printf '---- saida (stdout+stderr) ----\n'
    printf '%s\n' "$_saida"
  } > "$_prova" 2>/dev/null

  rm -rf "$_sbx" 2>/dev/null

  # --- veredito honesto ---
  if [ "$_rc" -eq 0 ]; then
    # PROVOU: escreve provado:true + prova.artefato + prova.entrega na fichinha (o UNICO caminho pro verde).
    _norte_provar_marcar_provado "$_prova" "$_ehash" 2>/dev/null || true
    printf '✅ provei assim: rodei a sua entrega e deu certo (exit 0).\n'
    printf '   saida:\n'
    printf '%s\n' "$_saida" | sed 's/^/   /' | head -20
    printf 'NB_PROVA_ARTEFATO=%s\n' "$_prova"
    return 0
  else
    # NAO PROVOU: fichinha continua amarela. Guarda o erro real na prova (pra a caixa dizer "falhou aqui").
    local _erro
    if [ "$_rc" -eq 124 ] && [ -n "$_tobin" ]; then
      _erro="passou de ${_dur}s e foi interrompido (pode estar travado ou esperando algo)"
    else
      _erro="terminou com erro (exit ${_rc})"
    fi
    printf '🟡 ainda nao provei: rodei a sua entrega e %s.\n' "$_erro"
    printf '   falhou aqui:\n'
    printf '%s\n' "$_saida" | sed 's/^/   /' | tail -20
    printf 'NB_PROVA_ARTEFATO=%s\n' "$_prova"
    return 1
  fi
}

# _norte_provar_dados_tipo <arquivo> — ecoa "csv" | "json" pelo sufixo; "" se nao-suportado.
# Portao planilha SO aceita dados tabulares/estruturados; nao adivinha conteudo, so a extensao.
_norte_provar_dados_tipo() {
  case "${1:-}" in
    *.csv) printf 'csv' ;;
    *.json) printf 'json' ;;
    *) printf '' ;;
  esac
}

# _norte_provar_planilha <checker> <dados> [sessao]
#   PORTAO NOVO "planilha→confere" (NRT-_990212 passo 5). ADITIVO: nao toca o _norte_provar_rodar acima.
#   A entrega e um PAR: um CHECKER (script .py/.js/.sh que ASSERTA sobre valores) + um arquivo de DADOS
#   (.csv/.json). O motor copia OS DOIS pro MESMO sandbox contido (dir descartavel, timeout, HOME
#   preservado, CWD = sandbox) e roda o checker com os dados acessiveis em ./dados.<ext> no CWD.
#     exit 0  -> PROVOU (todas as asseroes passaram): grava prova.artefato + provado:true (verde).
#     exit!=0 -> NAO PROVOU (o checker reprovou): fichinha fica amarela; a prova guarda o erro real.
#     2       -> nao deu pra provar (arquivo ausente / tipo nao-suportado / runtime ausente / sem jq /
#                kill-switch NORTE_PLANILHA=0).
#   A ARMADILHA nº1: "rodou" != "conferiu". O motor NAO le a mente do checker — o exit 0 do checker E a
#   asseraco. A defesa honesta que a caixa entrega ao cliente e o TEMPLATE (planilha_confere.py), que
#   asserta e sai !=0 em falha. Por isso planilha QUEBRADA fica VERMELHA (o checker reprova).
#   O VINCULO A3 (anti-reuso) usa o hash do CHECKER (o script que decide o veredito) — trocar a prova por
#   uma de outro checker nao abre verde.
_norte_provar_planilha() {
  local _chk="${1:-}" _dados="${2:-}" _sess="${3:-}"
  # kill-switch: NORTE_PLANILHA=0 desliga o portao -> volta ao comportamento de hoje (so script→roda).
  case "${NORTE_PLANILHA:-1}" in
    0|no|nao|off|false)
      printf '🟡 o portao "planilha confere" nao esta ligado nesta maquina (NORTE_PLANILHA=0).\n'
      return 2 ;;
  esac
  # --- pre-condicoes (fail-honest) ---
  if [ -z "$_chk" ] || [ ! -f "$_chk" ]; then
    printf '🟡 nao consegui provar: o conferidor (checker) indicado nao existe.\n'; return 2
  fi
  if [ -z "$_dados" ] || [ ! -f "$_dados" ]; then
    printf '🟡 nao consegui provar: o arquivo de dados (a planilha) indicado nao existe.\n'; return 2
  fi
  command -v jq >/dev/null 2>&1 || { printf '🟡 nao consegui provar: falta o jq nesta maquina.\n'; return 2; }
  local _tipo _runner _dtipo
  _tipo="$(_norte_provar_tipo "$_chk")"
  if [ -z "$_tipo" ]; then
    printf '🟡 nao sei rodar esse tipo de conferidor (por enquanto so .py, .js ou .sh).\n'; return 2
  fi
  _dtipo="$(_norte_provar_dados_tipo "$_dados")"
  if [ -z "$_dtipo" ]; then
    printf '🟡 nao sei ler esse tipo de dado (por enquanto so planilha .csv ou .json).\n'; return 2
  fi
  _runner="$(_norte_provar_runner "$_tipo")"
  if [ -z "$_runner" ]; then
    printf '🟡 nao consegui provar: falta o programa pra rodar o conferidor nesta maquina.\n'; return 2
  fi

  # --- diretorio da prova (arvore CONTROLADA — a unica que o selo aceita) ---
  local _raiz _sslug _dir _ts _prova
  _raiz="$(_norte_provas_raiz)"
  _sslug="$(_norte_provar_slug "${_sess:-sessao}")"; [ -n "$_sslug" ] || _sslug="sessao"
  _ts="$(date -u +%Y%m%dT%H%M%SZ 2>/dev/null || echo t)"
  _dir="${_raiz}/${_sslug}"
  mkdir -p "$_dir" 2>/dev/null || { printf '🟡 nao consegui gravar a prova (disco nao gravavel).\n'; return 2; }
  _prova="${_dir}/prova-${_ts}.txt"

  # --- sandbox: dir temporario proprio DENTRO da arvore controlada. Copia CHECKER + DADOS pra la; o
  #     checker roda com CWD = sandbox e le ./dados.<ext>. Descartado no fim (mesma cerca do motor).
  local _sbx _copia _cdados _rc _tobin _out
  _sbx="${_dir}/.sbx.$$.${_ts}"
  mkdir -p "$_sbx" 2>/dev/null || { printf '🟡 nao consegui preparar o sandbox (disco nao gravavel).\n'; return 2; }
  case "$_tipo" in
    py) _copia="${_sbx}/check.py" ;;
    js) _copia="${_sbx}/check.js" ;;
    sh) _copia="${_sbx}/check.sh" ;;
  esac
  _cdados="${_sbx}/dados.${_dtipo}"
  cp -- "$_chk" "$_copia" 2>/dev/null && cp -- "$_dados" "$_cdados" 2>/dev/null \
    || { rm -rf "$_sbx" 2>/dev/null; printf '🟡 nao consegui preparar o sandbox.\n'; return 2; }

  _tobin="$(_norte_provar_timeout_bin)"
  local _dur="${NB_PROVAR_TIMEOUT:-20}"
  case "$_dur" in ''|*[!0-9]*) _dur=20 ;; esac

  # Mesma cerca do motor: [unshare -rn]? -> [timeout -k 2 <dur>]? -> <runner> <checker>. CWD = sandbox.
  _out="${_sbx}/saida.txt"
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

  local _saida
  _saida="$(head -c 4000 "$_out" 2>/dev/null || true)"

  # VINCULO A3: hash do CONTEUDO do CHECKER (o script que decide o veredito). Trocar a prova por uma de
  # outro checker faz o hash divergir -> amarelo. (Nao hasheia os dados: o checker e quem "prova".)
  local _ehash=""
  if command -v _norte_prova_hash_arquivo >/dev/null 2>&1; then
    _ehash="$(_norte_prova_hash_arquivo "$_chk" 2>/dev/null || true)"
  fi

  {
    printf 'PROVA norte-box (motor Val de bolso — portao planilha confere)\n'
    printf 'quando: %s\n' "$(date -u +%FT%TZ 2>/dev/null || echo t)"
    printf 'tipo: %s+%s\n' "$_tipo" "$_dtipo"
    printf 'exit: %s\n' "$_rc"
    printf 'entrega_hash: %s\n' "$_ehash"
    printf '---- saida (stdout+stderr) ----\n'
    printf '%s\n' "$_saida"
  } > "$_prova" 2>/dev/null

  rm -rf "$_sbx" 2>/dev/null

  if [ "$_rc" -eq 0 ]; then
    _norte_provar_marcar_provado "$_prova" "$_ehash" 2>/dev/null || true
    printf '✅ conferi assim: rodei o seu conferidor na planilha e todas as conferencias passaram (exit 0).\n'
    printf '   conferido:\n'
    printf '%s\n' "$_saida" | sed 's/^/   /' | head -20
    printf 'NB_PROVA_ARTEFATO=%s\n' "$_prova"
    return 0
  else
    local _erro
    if [ "$_rc" -eq 124 ] && [ -n "$_tobin" ]; then
      _erro="passou de ${_dur}s e foi interrompido (pode estar travado ou esperando algo)"
    else
      _erro="a planilha nao passou na conferencia (o conferidor reprovou, exit ${_rc})"
    fi
    printf '🟡 ainda nao provei: %s.\n' "$_erro"
    printf '   falhou aqui:\n'
    printf '%s\n' "$_saida" | sed 's/^/   /' | tail -20
    printf 'NB_PROVA_ARTEFATO=%s\n' "$_prova"
    return 1
  fi
}

# _norte_provar_marcar_provado <artefato-de-prova> [entrega-hash]
#   Escreve provado:true + prova.artefato=<artefato> + prova.entrega=<hash-da-entrega> na fichinha
#   situacao.json, PRESERVANDO os campos ja existentes (objetivo/entregou/proximo). O prova.entrega e o
#   VINCULO A3 (anti-reuso): o selo (_situacao.sh) exige que o entrega_hash gravado DENTRO do arquivo de
#   prova bata com este prova.entrega. So aceita artefato DENTRO da arvore controlada de provas (defesa em
#   profundidade — o _situacao.sh tambem re-checa no read). Retorna 0 se gravou.
_norte_provar_marcar_provado() {
  local _art="${1:-}" _ent="${2:-}"
  command -v jq >/dev/null 2>&1 || return 1
  [ -n "$_art" ] || return 1
  # HARDENING (defesa em profundidade, igual ao selo do _situacao.sh): recusa symlink DURO e exige que
  # o CANONICO do artefato (realpath) esteja dentro de $HOME/.norte-box/provas/ (mata traversal+symlink).
  [ -L "$_art" ] && return 1
  [ -f "$_art" ] || return 1
  local _raiz _canon
  if command -v _norte_realpath >/dev/null 2>&1; then
    _raiz="$(_norte_realpath "$(_norte_provas_raiz)")" || return 1
    _canon="$(_norte_realpath "$_art")" || return 1
  else
    _raiz="$(_norte_provas_raiz)"; _canon="$_art"
  fi
  [ -n "$_raiz" ] && [ -n "$_canon" ] || return 1
  case "$_canon" in
    "$_raiz"/*) : ;;
    *) return 1 ;;
  esac
  local _dir="${HOME}/.norte-box" _f _tmp _ts
  _f="${_dir}/situacao.json"
  mkdir -p "$_dir" 2>/dev/null || return 1
  _ts="$(date -u +%FT%TZ 2>/dev/null || echo unknown)"
  _tmp="${_f}.tmp.$$"
  if [ -f "$_f" ] && jq -e . "$_f" >/dev/null 2>&1; then
    # atualiza a fichinha existente sem perder objetivo/entregou/proximo.
    jq --arg a "$_art" --arg e "$_ent" --arg ts "$_ts" \
      '.provado=true | .prova={artefato:$a, entrega:$e} | .ultima_atualizacao=$ts' "$_f" > "$_tmp" 2>/dev/null \
      || { rm -f "$_tmp" 2>/dev/null; return 1; }
  else
    # sem fichinha ainda -> cria uma minima ja provada (o objetivo/entregou serao enriquecidos depois).
    jq -cn --arg a "$_art" --arg e "$_ent" --arg ts "$_ts" \
      '{objetivo:"", entregou:"", proximo:"", provado:true, prova:{artefato:$a, entrega:$e}, ultima_atualizacao:$ts}' > "$_tmp" 2>/dev/null \
      || { rm -f "$_tmp" 2>/dev/null; return 1; }
  fi
  mv -f "$_tmp" "$_f" 2>/dev/null || { rm -f "$_tmp" 2>/dev/null; return 1; }
  return 0
}
