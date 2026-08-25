#!/usr/bin/env bash
# _red-team.sh — RED-TEAM LEVE do Norte-box (Camada 2). FONTE UNICA da lib.
# Sourceado pelo helper bin/nb-red-team.
#
# A ideia (padaria): o motor (_provar.sh) ja RODOU a entrega no sandbox e, se deu exit 0, marcou 🟢.
# O red-team leve entra LOGO DEPOIS, ANTES de o verde poder valer: ele TENTA QUEBRAR a propria entrega
# — roda o MESMO script mais algumas vezes, na MESMA caixa-de-areia (rede cortada + timeout + dir
# descartavel), agora com ENTRADAS RUINS no stdin (vazia, lixo/binario, gigante) — e confere que:
#   (a) NAO trava / NAO estoura o tempo (nenhum ataque bateu no timeout duro), e
#   (b) NAO vaza algo com cara de segredo na saida (o _redact reconhece -> vazou).
# Se algum ataque quebra OU vaza  -> rebaixa o selo pra 🟡 com o MOTIVO ("red-team achou: <o que>").
# Se passa tudo                   -> 🟢 continua (nao mexe no selo do motor).
#
# LEIS (nao-negociaveis, herdadas do motor):
#   - LOCAL, ZERO REDE: reusa a MESMA cerca do motor (unshare -rn best-effort) — a entrega roda offline.
#     Esta lib NAO faz nenhum POST/telemetria/curl. So le/escreve o disco local (a fichinha situacao.json).
#   - KILL-SWITCH: NORTE_RED_TEAM=0 desliga tudo (volta ao motor puro). Default = ligado.
#   - FAIL-OPEN: se o red-team NAO consegue rodar (sandbox indisponivel, sem runner, sem jq), NAO trava
#     e NAO rebaixa — anota red_team.status="nao_rodou" e o selo segue o que o MOTOR decidiu.
#   - REUSA A INFRA: pega tipo/runner/timeout/cerca do _provar.sh (nao reescreve o motor). So ADICIONA
#     o passo adversarial; nunca re-chama _norte_provar_rodar (que gravaria selo por conta propria).
#   - HONESTO: so rebaixa quando um ataque REALMENTE quebrou/vazou. Nunca "acha por achar".
#   - Portabilidade macOS (bash 3.2 / BSD sed). Precisa de jq pra escrever a fichinha; sem jq -> fail-open.
set -u

# Cap de tamanho da entrada gigante (bytes). Grande o bastante pra estressar buffer/loop, pequeno o
# bastante pra nao encher o disco do sandbox. Sobrescritivel por env pra teste.
_NORTE_RT_BIG_BYTES="${NORTE_RED_TEAM_BIG_BYTES:-200000}"

# _norte_red_team_off — 0/1: red-team desligado?
_norte_red_team_off() { [ "${NORTE_RED_TEAM:-1}" = "0" ]; }

# _norte_rt_slug <str> — nome de dir seguro (mesma politica do motor).
_norte_rt_slug() { printf '%s' "${1:-}" | tr -c 'A-Za-z0-9._-' '_' | cut -c1-64; }

# _norte_rt_gera_ataque <nome> <arquivo-saida>
#   Escreve no <arquivo-saida> o corpo do stdin de UM ataque. Nomes: vazia | lixo | gigante.
#   Mantido em disco (nao em variavel) pra o gigante nao explodir a RAM do bash 3.2.
_norte_rt_gera_ataque() {
  local _nome="${1:-}" _dst="${2:-}"
  [ -n "$_dst" ] || return 1
  case "$_nome" in
    vazia)
      : > "$_dst" 2>/dev/null ;;
    lixo)
      # bytes binarios + control chars + aspas/backslash/nulls-ish — "lixo" que quebra parser ingenuo.
      { head -c 4096 /dev/urandom 2>/dev/null || printf '\001\002\003\377"\\\t\r\n{[<&|;`$(' ; } > "$_dst" 2>/dev/null
      # garante ao menos algum conteudo mesmo sem /dev/urandom
      [ -s "$_dst" ] || printf '\001\002\003"\\`$();|&<>{[]}\r\t' > "$_dst" 2>/dev/null ;;
    gigante)
      # entrada grande num filete so (sem newlines) pra estressar leitura de linha/buffer.
      if command -v head >/dev/null 2>&1 && [ -r /dev/zero ]; then
        head -c "$_NORTE_RT_BIG_BYTES" /dev/zero 2>/dev/null | tr '\0' 'A' > "$_dst" 2>/dev/null
      fi
      # fallback portavel se /dev/zero nao deu
      if [ ! -s "$_dst" ]; then
        local _n=0; : > "$_dst"
        while [ "$_n" -lt "$_NORTE_RT_BIG_BYTES" ]; do
          printf 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA' >> "$_dst"
          _n=$((_n+64))
        done
      fi ;;
    *) return 1 ;;
  esac
  return 0
}

# _norte_rt_vazou <arquivo-saida>  -> 0 se a saida tem cara de segredo (o _redact MUDA a saida), 1 se nao.
# Reusa o redator compartilhado (_redact) como detector: se redigir muda o texto, havia um formato de
# segredo reconhecido. Honesto: e best-effort (o _redact so pega o que reconhece), NAO promete zero.
#
# ANTI-FALSO-POSITIVO (licao do proprio teste): so olhamos a saida em modo TEXTO. Bytes binarios crus
# (ex.: o ataque "lixo" e /dev/urandom) ecoados de volta podem, POR ACASO, casar um regex de segredo
# (16 digitos = "cartao") sem ser vazamento nenhum — e' so ruido. Rebaixar a entrega honesta da pessoa
# por isso seria fail-CLOSED contra ela. Por isso: se a saida NAO e' texto imprimivel (tem bytes de
# controle/binarios), NAO acusamos vazamento aqui — quem estressa binario e' o gate de TRAVA, nao este.
_norte_rt_vazou() {
  local _f="${1:-}"; [ -f "$_f" ] || return 1
  command -v _redact >/dev/null 2>&1 || return 1
  # binario? (tem NUL ou bytes de controle nao-whitespace) -> nao classifica como vazamento (evita
  # falso-positivo por regex casando lixo aleatorio). LC_ALL=C pra o grep ver bytes crus.
  if LC_ALL=C grep -q '[^[:print:][:space:]]' "$_f" 2>/dev/null; then
    return 1
  fi
  local _raw _red
  _raw="$(head -c 100000 "$_f" 2>/dev/null || true)"
  _red="$(printf '%s' "$_raw" | _redact 2>/dev/null || printf '%s' "$_raw")"
  # So conta como VAZAMENTO se a redacao introduziu um marcador de SEGREDO/PII — NAO de caminho.
  # Por que: um traceback de erro naturalmente traz o CAMINHO do arquivo, e o _redact mascara caminho
  # ([arquivo:.py] / [REDACTED-PATH]). Isso muda o texto, mas nao e' segredo vazando — e' so o nome do
  # arquivo. Rebaixar a entrega da pessoa por um caminho num stack-trace seria fail-CLOSED contra ela.
  # Os marcadores de segredo/PII de verdade sao os de baixo (bate com _redact.sh).
  case "$_red" in
    *'[REDACTED-KEY]'*|*'[REDACTED-CARD]'*|*'[REDACTED-JWT]'*|*'[REDACTED-TOKEN]'*|\
    *'[REDACTED-CREDENTIAL]'*|*'[REDACTED-PRIVATE-KEY]'*|*'[REDACTED-APP-PASSWORD]'*|\
    *'[REDACTED-CPF]'*|*'[REDACTED-CNPJ]'*|*'[REDACTED]'*)
      # confirma que o marcador foi INTRODUZIDO pela redacao (nao ja vinha no texto original).
      [ "$_raw" != "$_red" ] && return 0 ;;
  esac
  return 1
}

# _norte_red_team_rodar <arquivo> [sessao]
#   Roda a bateria de ataques na MESMA caixa-de-areia do motor. Ecoa um bloco humano de padaria e devolve:
#     0 -> PASSOU (nenhum ataque quebrou/vazou). Nao mexe no selo.
#     1 -> ACHOU (um ataque quebrou ou vazou). Rebaixou o selo pra 🟡 com o motivo na fichinha.
#     2 -> NAO RODOU (kill-switch OFF / sem runner / sem sandbox / sem jq). Fail-open: nao mexe no selo,
#          so anota red_team.status="nao_rodou".
_norte_red_team_rodar() {
  local _arq="${1:-}" _sess="${2:-sessao}"

  if _norte_red_team_off; then
    printf 'ℹ️  red-team desligado (NORTE_RED_TEAM=0) — o selo segue so o que o motor decidiu.\n'
    _norte_rt_anota_status "nao_rodou" "desligado (NORTE_RED_TEAM=0)" 2>/dev/null || true
    return 2
  fi

  # Pre-condicoes iguais ao motor (fail-open: sem elas nao rebaixa, so anota).
  if [ -z "$_arq" ] || [ ! -f "$_arq" ]; then
    printf 'ℹ️  red-team nao rodou: nao achei o arquivo da entrega.\n'
    _norte_rt_anota_status "nao_rodou" "arquivo da entrega ausente" 2>/dev/null || true
    return 2
  fi
  command -v jq >/dev/null 2>&1 || { printf 'ℹ️  red-team nao rodou: falta o jq nesta maquina.\n'; return 2; }

  local _tipo _runner
  # reusa os helpers do MOTOR (ja sourceado pelo bin) pra descobrir tipo/runner.
  if command -v _norte_provar_tipo >/dev/null 2>&1; then _tipo="$(_norte_provar_tipo "$_arq")"; else _tipo=""; fi
  if [ -z "$_tipo" ]; then
    printf 'ℹ️  red-team nao rodou: nao sei rodar esse tipo de arquivo (so .py/.js/.sh).\n'
    _norte_rt_anota_status "nao_rodou" "tipo nao-suportado" 2>/dev/null || true
    return 2
  fi
  if command -v _norte_provar_runner >/dev/null 2>&1; then _runner="$(_norte_provar_runner "$_tipo")"; else _runner=""; fi
  if [ -z "$_runner" ]; then
    printf 'ℹ️  red-team nao rodou: falta o programa pra rodar esse tipo nesta maquina.\n'
    _norte_rt_anota_status "nao_rodou" "runner ausente" 2>/dev/null || true
    return 2
  fi

  # --- sandbox: MESMA cerca do motor (dir descartavel DENTRO da arvore controlada + CWD=sandbox +
  #     rede cortada best-effort + timeout duro). Nao herda o CWD do projeto; limpa no fim.
  local _raiz _sslug _dir _ts _sbx _copia
  if command -v _norte_provas_raiz >/dev/null 2>&1; then _raiz="$(_norte_provas_raiz)"; else _raiz="${HOME}/.norte-box/provas"; fi
  _sslug="$(_norte_rt_slug "${_sess:-sessao}")"; [ -n "$_sslug" ] || _sslug="sessao"
  _ts="$(date -u +%Y%m%dT%H%M%SZ 2>/dev/null || echo t)"
  _dir="${_raiz}/${_sslug}"
  mkdir -p "$_dir" 2>/dev/null || { printf 'ℹ️  red-team nao rodou: disco nao gravavel.\n'; _norte_rt_anota_status "nao_rodou" "disco nao gravavel" 2>/dev/null || true; return 2; }
  _sbx="${_dir}/.rt.$$.${_ts}"
  mkdir -p "$_sbx" 2>/dev/null || { printf 'ℹ️  red-team nao rodou: nao preparei o sandbox.\n'; _norte_rt_anota_status "nao_rodou" "sandbox indisponivel" 2>/dev/null || true; return 2; }
  case "$_tipo" in
    py) _copia="${_sbx}/entrega.py" ;;
    js) _copia="${_sbx}/entrega.js" ;;
    sh) _copia="${_sbx}/entrega.sh" ;;
    *)  _copia="${_sbx}/entrega" ;;
  esac
  cp -- "$_arq" "$_copia" 2>/dev/null || { rm -rf "$_sbx" 2>/dev/null; printf 'ℹ️  red-team nao rodou: nao preparei o sandbox.\n'; _norte_rt_anota_status "nao_rodou" "copia falhou" 2>/dev/null || true; return 2; }

  # cerca (mesma montagem do motor). Timeout um pouco MAIS CURTO que o do motor: um ataque que passa do
  # tempo ja e "travou" — nao precisa esperar o teto inteiro. Minimo 3s.
  local _tobin _dur _cmd_pre
  if command -v _norte_provar_timeout_bin >/dev/null 2>&1; then _tobin="$(_norte_provar_timeout_bin)"; else _tobin="$(command -v timeout 2>/dev/null || command -v gtimeout 2>/dev/null || true)"; fi
  _dur="${NORTE_RED_TEAM_TIMEOUT:-8}"; case "$_dur" in ''|*[!0-9]*) _dur=8 ;; esac
  [ "$_dur" -lt 3 ] 2>/dev/null && _dur=3
  # prefixo de cerca comum a todos os ataques (rede cortada best-effort — igual ao motor).
  _cmd_pre=()
  if command -v unshare >/dev/null 2>&1 && unshare -rn true >/dev/null 2>&1; then
    _cmd_pre+=( unshare -rn )
  fi
  if [ -n "$_tobin" ]; then
    _cmd_pre+=( "$_tobin" -k 2 "$_dur" )
  fi

  # --- bateria de ataques ---
  local _ataques="vazia lixo gigante" _nome _in _out _rc _achou="" _motivo=""
  for _nome in $_ataques; do
    _in="${_sbx}/in.${_nome}"
    _out="${_sbx}/out.${_nome}"
    _norte_rt_gera_ataque "$_nome" "$_in" || continue
    # roda a copia com o ataque no STDIN, CWD=sandbox. cmd nunca vazio (runner+copia sempre presentes).
    ( cd "$_sbx" 2>/dev/null && "${_cmd_pre[@]}" "$_runner" "$_copia" <"$_in" ) >"$_out" 2>&1
    _rc=$?
    # (a) travou/estourou o tempo? (124 = timeout; 137 = kill -9 do timeout -k)
    if [ "$_rc" -eq 124 ] || [ "$_rc" -eq 137 ]; then
      _achou=1; _motivo="trava com entrada ${_nome} (passou de ${_dur}s e foi interrompido)"; break
    fi
    # (b) vazou algo com cara de segredo na saida?
    if _norte_rt_vazou "$_out"; then
      _achou=1; _motivo="vaza algo com cara de segredo na saida quando recebe entrada ${_nome}"; break
    fi
  done

  rm -rf "$_sbx" 2>/dev/null

  if [ -n "$_achou" ]; then
    _norte_rt_rebaixa "$_motivo" 2>/dev/null || true
    printf '🟡 red-team achou: %s.\n' "$_motivo"
    printf '   o selo baixou de 🟢 pra 🟡 — a entrega roda no caminho feliz, mas quebra/vaza com entrada ruim.\n'
    return 1
  fi

  _norte_rt_anota_status "passou" "nenhum ataque quebrou ou vazou" 2>/dev/null || true
  printf '✅ red-team passou: tentei quebrar (entrada vazia, lixo e gigante) e a entrega aguentou sem travar nem vazar.\n'
  return 0
}

# --- escrita na fichinha (LOCAL). Preserva os campos existentes; so mexe no que o red-team decide. ---

# _norte_rt_rebaixa <motivo> — poe provado=false + red_team{status:"quebrou", motivo, quando}. Isso faz o
# selo (que le .provado) virar 🟡 pela porta ja existente do motor — sem tocar no motor. NAO apaga a
# .prova (o artefato do motor continua registrado; so o veredito baixou). Sem fichinha -> nao inventa.
_norte_rt_rebaixa() {
  local _mot="${1:-red-team achou um problema}"
  _norte_rt_escreve_ficha "false" "quebrou" "$_mot"
}

# _norte_rt_anota_status <status> <motivo> — anota red_team{status,motivo,quando} SEM tocar em .provado
# (fail-open: "passou" e "nao_rodou" nunca mudam o veredito do motor).
_norte_rt_anota_status() {
  _norte_rt_escreve_ficha "" "${1:-nao_rodou}" "${2:-}"
}

# _norte_rt_escreve_ficha <provado-novo|""> <status> <motivo>
#   provado-novo="false" -> seta .provado=false (rebaixa). ""(vazio) -> preserva .provado atual.
_norte_rt_escreve_ficha() {
  local _prov="${1:-}" _st="${2:-}" _mot="${3:-}"
  command -v jq >/dev/null 2>&1 || return 1
  local _dir="${HOME}/.norte-box" _f _tmp _ts
  _f="${_dir}/situacao.json"
  [ -f "$_f" ] || return 1               # sem fichinha -> nao inventa (fail-open)
  jq -e . "$_f" >/dev/null 2>&1 || return 1
  mkdir -p "$_dir" 2>/dev/null || return 1
  _ts="$(date -u +%FT%TZ 2>/dev/null || echo unknown)"
  _tmp="${_f}.tmp.$$"
  if [ "$_prov" = "false" ]; then
    jq --arg st "$_st" --arg mot "$_mot" --arg ts "$_ts" \
      '.provado=false | .red_team={status:$st, motivo:$mot, quando:$ts} | .ultima_atualizacao=$ts' \
      "$_f" > "$_tmp" 2>/dev/null || { rm -f "$_tmp" 2>/dev/null; return 1; }
  else
    jq --arg st "$_st" --arg mot "$_mot" --arg ts "$_ts" \
      '.red_team={status:$st, motivo:$mot, quando:$ts} | .ultima_atualizacao=$ts' \
      "$_f" > "$_tmp" 2>/dev/null || { rm -f "$_tmp" 2>/dev/null; return 1; }
  fi
  mv -f "$_tmp" "$_f" 2>/dev/null || { rm -f "$_tmp" 2>/dev/null; return 1; }
  return 0
}
