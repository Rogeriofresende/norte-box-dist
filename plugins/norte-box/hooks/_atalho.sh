#!/usr/bin/env bash
# _atalho.sh — biblioteca da FATIA "OFERECER DORMENTE" (NRT oferta-dormente).
# NAO e um hook (nome com _ inicial, fora do hooks.json). E sourceada por ritual-oferta.sh
# (SessionStart) e legivel pelo comando /norte-box:ritual (verbos atalho / atalho-nao).
#
# ============================================================================================
# O QUE ESTA FATIA FAZ (e o que NAO faz):
#   - A caixa, DEPOIS que o OBSERVADOR (fatia anterior) contou >=3 rituais mandato_pr_v1
#     COMPLETOS, OFERECE UMA VEZ, de forma SUTIL, na ABERTURA da sessao: "quer virar atalho?".
#   - A pessoa ACEITA EXPLICITAMENTE rodando /norte-box:ritual atalho mandato_pr_v1.
#   - O dado registra se ela VOLTA ao atalho em OUTRO DIA (o sinal de valor NAO e o "sim" — e o
#     RETORNO espontaneo em dia civil distinto).
#   - NAO gera kit. NAO envia nada. NAO le conteudo. So rotulos do vocab fechado + timestamps
#     + datas civis. 100% LOCAL.
#
# INVARIANTE AUDITAVEL (nao-negociavel): os UNICOS strings gravados sao a chave do ritual
#   (vocab fechado: `mandato_pr_v1`), chaves fixas de JSON, timestamps ISO e datas civis
#   (YYYY-MM-DD). NENHUM path, comando, nome-de-arquivo, argumento ou texto do trabalho.
#
# LEIS (iguais ao observador):
#   - FAIL-OPEN: o hook nunca trava a sessao (exit 0 sempre). Erro interno -> silencioso.
#   - Opt-in FAIL-CLOSED: sem a flag .enabled -> nao oferta.
#   - Kill-switch NORTE_RITUAL_OFF=1 respeitado.
#   - ZERO rede. Escreve SO em $HOME/.norte-box.
#   - Escrita ATOMICA (tmp+mv) + LOCK (mkdir). bash 3.2 (sem mapfile/assoc arrays/EPOCHREALTIME).
#
# REUSO deliberado: lock/atomic/now_ms vem do _ritual.sh (sourceado antes desta lib). Se por
#   algum motivo a lib do observador nao estiver carregada, degrada com fallbacks locais
#   (nunca trava).

# ---------------------------------------------------------------------------------------------
# 0) CONSTANTES
# ---------------------------------------------------------------------------------------------
# Nome do ritual que esta fatia oferece (mesmo do observador — vocab fechado).
_NB_ATALHO_RITUAL="mandato_pr_v1"
# Gatilho: precisa de >=3 rituais COMPLETOS pra a caixa considerar o ritual "maduro".
_NB_ATALHO_MIN_COMPLETOS=3
# Re-oferta so depois de 14 dias de silencio (em segundos).
_NB_ATALHO_REOFERTA_SEG=$(( 14 * 24 * 60 * 60 ))
# Teto de ofertas: depois de 2 ofertas sem aceite/recusa, cala pra sempre.
_NB_ATALHO_TETO_OFERTAS=2

_nb_atalho_arquivo()  { printf '%s/ritual-atalhos.json' "${HOME}/.norte-box"; }
_nb_atalho_contagem() { printf '%s/ritual-contagem.json' "${HOME}/.norte-box"; }
_nb_atalho_flag()     { printf '%s/ritual-observador.enabled' "${HOME}/.norte-box"; }

# ---------------------------------------------------------------------------------------------
# 1) TEMPO. Reusa _nb_ritual_now_ms se disponivel; senao fallback local. epoch em SEGUNDOS.
#    Override de teste (SO teste, hermetico): NORTE_ATALHO_NOW_EPOCH força o "agora" em segundos.
# ---------------------------------------------------------------------------------------------
_nb_atalho_now_epoch() {
  case "${NORTE_ATALHO_NOW_EPOCH:-}" in
    ''|*[!0-9]*) : ;;
    *) printf '%s' "$NORTE_ATALHO_NOW_EPOCH"; return 0 ;;
  esac
  local _s; _s="$(date -u +%s 2>/dev/null || true)"
  case "$_s" in ''|*[!0-9]*) printf '0' ;; *) printf '%s' "$_s" ;; esac
  return 0
}

# ISO (UTC) do "agora" — respeita o override de teste convertendo epoch->ISO quando possivel.
_nb_atalho_now_iso() {
  local _e
  case "${NORTE_ATALHO_NOW_EPOCH:-}" in
    ''|*[!0-9]*)
      date -u +%FT%TZ 2>/dev/null || printf 'unknown'
      return 0 ;;
    *) _e="$NORTE_ATALHO_NOW_EPOCH" ;;
  esac
  # macOS: date -r <epoch>; GNU: date -d @<epoch>. Tenta os dois; senao 'unknown'.
  date -u -r "$_e" +%FT%TZ 2>/dev/null && return 0
  date -u -d "@${_e}" +%FT%TZ 2>/dev/null && return 0
  printf 'unknown'
  return 0
}

# Data civil LOCAL (YYYY-MM-DD) do "agora" — respeita o override de teste.
_nb_atalho_hoje() {
  local _e
  case "${NORTE_ATALHO_NOW_EPOCH:-}" in
    ''|*[!0-9]*)
      date +%F 2>/dev/null || printf 'unknown'
      return 0 ;;
    *) _e="$NORTE_ATALHO_NOW_EPOCH" ;;
  esac
  date -r "$_e" +%F 2>/dev/null && return 0
  date -d "@${_e}" +%F 2>/dev/null && return 0
  printf 'unknown'
  return 0
}

# Converte um timestamp ISO (YYYY-MM-DDThh:mm:ssZ) pra epoch(segundos). Vazio se nao der.
_nb_atalho_iso_epoch() {
  local _iso="$1"
  [ -z "$_iso" ] && { printf ''; return 0; }
  case "$_iso" in unknown|null) printf ''; return 0 ;; esac
  # macOS: -j -f; GNU: -d. Tenta os dois.
  date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$_iso" +%s 2>/dev/null && return 0
  date -u -d "$_iso" +%s 2>/dev/null && return 0
  printf ''
  return 0
}

# ---------------------------------------------------------------------------------------------
# 2) LOCK + ESCRITA ATOMICA — reusa _ritual.sh; fallback local se a lib nao estiver carregada.
#    _nb_atalho_lock <lockdir> [tentativas]: espera pegando o lock; retorna 0 (pegou) ou 1.
#    O 2o argumento (tentativas) permite ESPERA CURTA no caminho SessionStart (sincrono, async:false):
#    se o lock estiver preso, o hook desiste RAPIDO e pula a oferta (falha pro SILENCIO), sem
#    NUNCA segurar a abertura da sessao do CEO. Sem argumento -> default 200 (~10s, caminho gravacao).
# ---------------------------------------------------------------------------------------------
_nb_atalho_lock() {
  local _ld="$1" _max="${2:-200}" _i=0
  # lock ORFAO (dono morreu): mkdir com mtime > 60s e considerado abandonado -> remove.
  # (Fix Val red-team no _ritual: testar a SAIDA do find, nao o rc — find ...>/dev/null da rc=0
  #  mesmo sem match, o que removeria lock FRESCO de processo vivo.)
  if [ -d "$_ld" ] && [ -n "$(find "$_ld" -maxdepth 0 -mmin +1 2>/dev/null)" ]; then
    rmdir "$_ld" 2>/dev/null || true
  fi
  while [ "$_i" -lt "$_max" ]; do
    if mkdir "$_ld" 2>/dev/null; then return 0; fi
    _i=$(( _i + 1 )); sleep 0.05 2>/dev/null || sleep 1
  done
  return 1
}
_nb_atalho_unlock() {
  if command -v _nb_ritual_unlock >/dev/null 2>&1; then _nb_ritual_unlock "$1"; return 0; fi
  rmdir "$1" 2>/dev/null || true
}
_nb_atalho_write_atomic() {
  if command -v _nb_ritual_write_atomic >/dev/null 2>&1; then _nb_ritual_write_atomic "$1" "$2"; return $?; fi
  local _dest="$1" _content="$2" _tmp
  _tmp="${_dest}.$$.$(date +%s 2>/dev/null || echo 0).tmp"
  printf '%s' "$_content" > "$_tmp" 2>/dev/null || { rm -f "$_tmp" 2>/dev/null; return 1; }
  mv -f "$_tmp" "$_dest" 2>/dev/null || { rm -f "$_tmp" 2>/dev/null; return 1; }
  return 0
}

# ---------------------------------------------------------------------------------------------
# 3) LEITURA do estado do ritual no atalhos.json (campos por ritual). jq obrigatorio.
#    Cada getter ecoa vazio quando ausente/erro.
# ---------------------------------------------------------------------------------------------
_nb_atalho_get() { # $1=jq-path relativo ao objeto do ritual (ex: .oferta_ts)
  local _f _sig="$_NB_ATALHO_RITUAL"
  _f="$(_nb_atalho_arquivo)"
  [ -f "$_f" ] || { printf ''; return 0; }
  command -v jq >/dev/null 2>&1 || { printf ''; return 0; }
  jq -r --arg s "$_sig" "(.atalhos[\$s]$1) // empty" "$_f" 2>/dev/null || printf ''
}

# completos contados pelo OBSERVADOR (fonte do gatilho). 0 se ausente.
_nb_atalho_completos() {
  local _c v
  _c="$(_nb_atalho_contagem)"
  [ -f "$_c" ] || { printf '0'; return 0; }
  command -v jq >/dev/null 2>&1 || { printf '0'; return 0; }
  v="$(jq -r '.rituais.mandato_pr_v1.completos // 0' "$_c" 2>/dev/null)"
  case "$v" in ''|*[!0-9]*) v=0 ;; esac
  printf '%s' "$v"
}

# ---------------------------------------------------------------------------------------------
# 4) GATILHO: a caixa deve OFERTAR agora?
#    Retorna 0 (ofertar) sse: kill off + flag on + completos>=MIN + ainda-elegivel.
#    Elegivel = (sem aceite) E (sem recusa) E (sem oferta OU (ofertas<teto E passou reoferta_seg)).
#    Depois do aceite ou recusa -> NUNCA mais oferta (fecha o furo "empurrao pos-aceite").
# ---------------------------------------------------------------------------------------------
_nb_atalho_deve_ofertar() {
  [ "${NORTE_RITUAL_OFF:-0}" = "1" ] && return 1
  [ -f "$(_nb_atalho_flag)" ] || return 1
  command -v jq >/dev/null 2>&1 || return 1

  local _comp; _comp="$(_nb_atalho_completos)"
  [ "$_comp" -ge "$_NB_ATALHO_MIN_COMPLETOS" ] 2>/dev/null || return 1

  local _aceite _recusa _oferta_ts _ofertas
  _aceite="$(_nb_atalho_get .aceite_ts)"
  _recusa="$(_nb_atalho_get .recusado_ts)"
  [ -n "$_aceite" ] && return 1     # ja aceitou -> nunca mais oferta
  [ -n "$_recusa" ] && return 1     # ja recusou -> nunca mais oferta

  _oferta_ts="$(_nb_atalho_get .oferta_ts)"
  # nunca ofertado -> ofertar.
  [ -z "$_oferta_ts" ] && return 0

  # ja ofertado: so re-oferta se ofertas<teto E passou a janela de silencio.
  _ofertas="$(_nb_atalho_get .ofertas)"
  case "$_ofertas" in ''|*[!0-9]*) _ofertas=0 ;; esac
  [ "$_ofertas" -ge "$_NB_ATALHO_TETO_OFERTAS" ] 2>/dev/null && return 1

  local _e_of _e_now _delta
  _e_of="$(_nb_atalho_iso_epoch "$_oferta_ts")"
  _e_now="$(_nb_atalho_now_epoch)"
  # sem conseguir converter a data da oferta -> conservador: NAO re-oferta (nao insiste).
  [ -z "$_e_of" ] && return 1
  _delta=$(( _e_now - _e_of ))
  [ "$_delta" -ge "$_NB_ATALHO_REOFERTA_SEG" ] && return 0
  return 1
}

# ---------------------------------------------------------------------------------------------
# 5) GRAVACAO — todas sob lock + escrita atomica. Sempre normalizam o schema minimo.
#    schema: {"versao":1,"atalhos":{"mandato_pr_v1":{
#              "oferta_ts":ISO,"ofertas":N,"aceite_ts":ISO|null,
#              "dias_retorno":["YYYY-MM-DD"],"recusado_ts":ISO|null}}}
# ---------------------------------------------------------------------------------------------

# helper: aplica um filtro jq ao objeto do ritual (criando o esqueleto se preciso) sob lock.
# $1 = filtro jq que recebe o objeto-do-ritual em `.` e devolve o objeto-do-ritual modificado,
#      com acesso a --arg sig, --arg now (ISO), --arg now_ep (epoch), --arg hoje (YYYY-MM-DD local)
#      e --arg diaAceite (YYYY-MM-DD local do aceite, ""  se ausente).
# $2 (opcional) = maximo de tentativas de lock (repassado ao _nb_atalho_lock). Default 200.
_nb_atalho_mut() {
  local _filtro="$1" _maxlock="${2:-200}"
  command -v jq >/dev/null 2>&1 || return 1
  local _f _lock _cur _new _sig="$_NB_ATALHO_RITUAL" _now _now_ep _hoje
  _f="$(_nb_atalho_arquivo)"
  _lock="${_f}.lock"
  mkdir -p "$(dirname "$_f")" 2>/dev/null || return 1
  _now="$(_nb_atalho_now_iso)"
  _now_ep="$(_nb_atalho_now_epoch)"
  _hoje="$(_nb_atalho_hoje)"

  _nb_atalho_lock "$_lock" "$_maxlock" || return 1
  if [ -f "$_f" ]; then _cur="$(cat "$_f" 2>/dev/null || echo '{}')"; else _cur='{}'; fi

  _new="$(printf '%s' "$_cur" | jq -c \
      --arg sig "$_sig" --arg now "$_now" --arg now_ep "$_now_ep" --arg hoje "$_hoje" "
      def base: {\"versao\":1,\"atalhos\":{}};
      def ritbase: {\"oferta_ts\":null,\"ofertas\":0,\"aceite_ts\":null,\"aceite_dia\":null,\"dias_retorno\":[],\"recusado_ts\":null};
      ( if (.versao? // null)==1 then . else base end ) as \$b
      | ( \$b.atalhos // {} ) as \$at
      | ( \$at[\$sig] // ritbase ) as \$r0
      | ( \$r0 | ( $_filtro ) ) as \$r1
      | \$b + {\"atalhos\": (\$at + {(\$sig): \$r1})}
    " 2>/dev/null || true)"

  if [ -n "$_new" ]; then _nb_atalho_write_atomic "$_f" "$_new" || true; fi
  _nb_atalho_unlock "$_lock"
  return 0
}

# marca UMA oferta: grava oferta_ts=agora e ofertas+=1. (mantido p/ compat; o caminho vivo
# do hook usa _nb_atalho_reivindica_oferta, que decide+grava SOB O MESMO LOCK).
_nb_atalho_marca_oferta() {
  _nb_atalho_mut '.oferta_ts = $now | .ofertas = ((.ofertas // 0) + 1)'
}

# ---------------------------------------------------------------------------------------------
# 5b) REIVINDICA A OFERTA (atomico de verdade — fix furos 1+2 do Val red-team).
#     A decisao "vou ofertar?" e a gravacao de oferta_ts/ofertas acontecem SOB O MESMO LOCK,
#     e a gravacao ocorre ANTES de qualquer impressao (o hook so imprime se esta funcao ecoar
#     "1", i.e. FOI o vencedor que gravou). Sob N SessionStart paralelos, so UM pega o lock,
#     re-le o estado ja dentro do lock (double-check), grava e ecoa "1"; todos os outros veem
#     oferta_ts ja gravado e ecoam "0" (nao imprimem, nao regravam) -> ofertas==1, impressa 1x.
#
#     ESPERA CURTA: no caminho SessionStart (sincrono, async:false) o lock so gira ~$2 tentativas
#     (default 20 = ~1s). Se nao pegar rapido, ecoa "0" -> o hook NAO imprime e NAO trava a
#     abertura (falha pro SILENCIO; oferta na proxima abertura). Nunca segura a sessao do CEO.
#
#     Ecoa exatamente "1" (reivindicou -> pode imprimir) ou "0" (nao reivindicou -> silencia).
# ---------------------------------------------------------------------------------------------
_nb_atalho_reivindica_oferta() {
  local _max="${1:-20}"
  # pre-gates BARATOS fora do lock (kill/flag/jq/completos): so pra evitar pegar lock a toa.
  # A decisao AUTORITATIVA (aceite/recusa/oferta_ts/teto/janela) e RE-FEITA dentro do lock.
  [ "${NORTE_RITUAL_OFF:-0}" = "1" ] && { printf '0'; return 0; }
  [ -f "$(_nb_atalho_flag)" ] || { printf '0'; return 0; }
  command -v jq >/dev/null 2>&1 || { printf '0'; return 0; }
  local _comp; _comp="$(_nb_atalho_completos)"
  [ "$_comp" -ge "$_NB_ATALHO_MIN_COMPLETOS" ] 2>/dev/null || { printf '0'; return 0; }

  local _f _lock _cur _new _sig="$_NB_ATALHO_RITUAL" _now _now_ep _reofseg="$_NB_ATALHO_REOFERTA_SEG" _teto="$_NB_ATALHO_TETO_OFERTAS"
  _f="$(_nb_atalho_arquivo)"
  _lock="${_f}.lock"
  mkdir -p "$(dirname "$_f")" 2>/dev/null || { printf '0'; return 0; }
  _now="$(_nb_atalho_now_iso)"
  _now_ep="$(_nb_atalho_now_epoch)"
  case "$_now_ep" in ''|*[!0-9]*) _now_ep=0 ;; esac

  # ESPERA CURTA: se nao pegar o lock rapido -> nao reivindica (silencio), sem travar a sessao.
  _nb_atalho_lock "$_lock" "$_max" || { printf '0'; return 0; }

  if [ -f "$_f" ]; then _cur="$(cat "$_f" 2>/dev/null || echo '{}')"; else _cur='{}'; fi

  # DECIDE + GRAVA dentro do lock, em UMA passada jq. O jq ecoa (stderr) "CLAIM=1"/"CLAIM=0" e
  # devolve (stdout) o JSON final. Convertendo em epoch a data da oferta pra a janela de 14d.
  #   Elegivel = sem aceite E sem recusa E ( sem oferta_ts
  #              OR (ofertas<teto E delta(now,oferta)>=reoferta_seg) ).
  #   Se elegivel: grava oferta_ts=now, ofertas+=1 -> reivindicou (retorna 0 no shell).
  #   O marker do CLAIM fica DENTRO de $HOME/.norte-box (lei: escreve so aqui), unico por processo.
  local _claim_marker="${_f}.claim.$$"
  _new="$(printf '%s' "$_cur" | jq -c \
      --arg sig "$_sig" --arg now "$_now" \
      --argjson now_ep "$_now_ep" --argjson reofseg "$_reofseg" --argjson teto "$_teto" '
      def base: {"versao":1,"atalhos":{}};
      def ritbase: {"oferta_ts":null,"ofertas":0,"aceite_ts":null,"aceite_dia":null,"dias_retorno":[],"recusado_ts":null};
      # epoch de um ISO "YYYY-MM-DDThh:mm:ssZ" (UTC). null se nao parsear.
      def iso_ep($s):
        if ($s|type)=="string" and ($s|test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T"))
        then ($s | strptime("%Y-%m-%dT%H:%M:%SZ") | mktime) else null end;
      ( if (.versao? // null)==1 then . else base end ) as $b
      | ( $b.atalhos // {} ) as $at
      | ( $at[$sig] // ritbase ) as $r0
      | ( ($r0.aceite_ts // null) != null ) as $temAceite
      | ( ($r0.recusado_ts // null) != null ) as $temRecusa
      | ( $r0.oferta_ts // null ) as $ots
      | ( ($r0.ofertas // 0) ) as $ofn
      | ( iso_ep($ots) ) as $oep
      | ( if $temAceite or $temRecusa then false
          elif ($ots == null) then true
          elif ($ofn >= $teto) then false
          elif ($oep == null) then false            # nao converteu a data -> conservador
          elif (($now_ep - $oep) >= $reofseg) then true
          else false end ) as $eleg
      | ( if $eleg
            then ($r0 + {"oferta_ts": $now, "ofertas": ($ofn + 1)})
            else $r0 end ) as $r1
      | ( if $eleg then "CLAIM=1" else "CLAIM=0" end | stderr | "" ) as $_marker
      | $b + {"atalhos": ($at + {($sig): $r1})}
    ' 2>"$_claim_marker" || true)"

  local _claim="0"
  if [ -s "$_claim_marker" ]; then
    grep -q 'CLAIM=1' "$_claim_marker" 2>/dev/null && _claim="1"
  fi
  rm -f "$_claim_marker" 2>/dev/null || true

  # so grava se reivindicou (o JSON so muda no ramo eligivel; mas evita reescrita a toa).
  if [ "$_claim" = "1" ] && [ -n "$_new" ]; then
    _nb_atalho_write_atomic "$_f" "$_new" || _claim="0"
  fi
  _nb_atalho_unlock "$_lock"
  printf '%s' "$_claim"
  return 0
}

# ACEITE (1a vez): grava aceite_ts (ISO UTC, carimbo) E aceite_dia (data civil LOCAL) se ainda
#   nulos. Sempre anexa o dia civil LOCAL de hoje em dias_retorno (unico).
#   FURO 3 (Val): o CALCULO do retorno usa SO datas civis LOCAIS (aceite_dia vs dias_retorno,
#   ambos `date +%F` local) — antes comparava dias_retorno (local) contra o split do aceite_ts
#   (UTC), o que perto da meia-noite BRT podia NAO contar o 1o retorno genuino.
_nb_atalho_marca_aceite() {
  _nb_atalho_mut '
      ( if (.aceite_ts  // null) == null then .aceite_ts  = $now  else . end )
    | ( if (.aceite_dia // null) == null then .aceite_dia = $hoje else . end )
    | ( .dias_retorno = ( ((.dias_retorno // []) + [$hoje]) | unique ) )
  '
}

# USO/RETORNO: so anexa o dia civil de hoje (unico). Nao mexe em aceite_ts.
_nb_atalho_registra_dia() {
  _nb_atalho_mut '.dias_retorno = ( ((.dias_retorno // []) + [$hoje]) | unique )'
}

# RECUSA: grava recusado_ts (se ainda nulo) -> gatilho nunca mais oferta.
_nb_atalho_marca_recusa() {
  _nb_atalho_mut '( if (.recusado_ts // null) == null then .recusado_ts = $now else . end )'
}

# ---------------------------------------------------------------------------------------------
# 6) SINAL DE VALOR (derivado, leitura): retorno espontaneo = existe >=1 dia em dias_retorno
#    DEPOIS do dia civil LOCAL do aceite. Ecoa "sim" | "nao" (nunca grava — e derivacao).
#    FURO 3 (Val): compara contra aceite_dia (LOCAL, mesmo calendario que dias_retorno).
#    Fallback pra dados ANTIGOS sem aceite_dia -> usa o split do aceite_ts (comportamento legado).
# ---------------------------------------------------------------------------------------------
_nb_atalho_teve_retorno() {
  local _f _sig="$_NB_ATALHO_RITUAL" _r
  _f="$(_nb_atalho_arquivo)"
  [ -f "$_f" ] || { printf 'nao'; return 0; }
  command -v jq >/dev/null 2>&1 || { printf 'nao'; return 0; }
  _r="$(jq -r --arg s "$_sig" '
      (.atalhos[$s]) as $r
      | if ($r.aceite_ts // null) == null then "nao"
        else
          ( ($r.aceite_dia // ($r.aceite_ts | split("T")[0])) ) as $diaAceite
          | ( ($r.dias_retorno // []) | map(select(. > $diaAceite)) | length ) as $n
          | if $n > 0 then "sim" else "nao" end
        end
    ' "$_f" 2>/dev/null || printf 'nao')"
  case "$_r" in sim) printf 'sim' ;; *) printf 'nao' ;; esac
  return 0
}
