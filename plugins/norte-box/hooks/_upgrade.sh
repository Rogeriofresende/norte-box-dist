#!/usr/bin/env bash
# _upgrade.sh — "ATUALIZA SEM QUEBRAR" do norte-box (NRT-_990484, peca-irma do changelog + socorro).
# Sourceado pelo hook situacao-abrir (SessionStart) e pelo helper bin/nb-atualizar (ver sob demanda).
#
# O BURACO QUE ESTA PECA FECHA: quando a caixa e ATUALIZADA (versao nova), a pessoa podia acabar rodando
# uma versao QUEBRADA/inconsistente sem saber — a caixa mudava por baixo e seguia como se estivesse boa.
# ESTA peca e o PORTAO NO MOMENTO DA TROCA DE VERSAO: ao abrir depois de uma troca, ela CONFERE que a
# versao nova esta SA; se estiver quebrada, AVISA CLARO ("esta versao parece com problema — nao confie
# nela, avise a Norte") em vez de rodar quebrada calada. Se esta sa, fica quieta (nao incomoda) e marca
# a versao como CONFERIDA -> na proxima abertura nao repete.
#
# NAO E o vigia-doctor (NRT-_990419): o vigia roda o doctor em TODA sessao e avisa se algo esta FALHA
# AGORA (janela continua, TTL 30min). ESTA peca so fala no EVENTO de troca de versao (uma vez por
# upgrade) E acrescenta uma checagem que o doctor NAO faz: os 2 manifestos concordarem na versao
# (plugin.json == marketplace.json) e os arquivos-chave passarem `bash -n`. As duas convivem: o vigia
# cuida do "quebrou no meio do caminho", esta cuida do "acabei de atualizar — a nova esta inteira?".
#
# O QUE "ESTA SA?" CHECA (o minimo — o grosso reusa o doctor, motor unico de saude):
#   1. os 2 manifestos concordam na versao (plugin.json == marketplace.json) — divergencia = release meio-feito;
#   2. os arquivos-chave existem e passam `bash -n` (parse limpo, sem erro de sintaxe);
#   3. o doctor (doctor-check.sh) NAO acusa nenhum item FALHA (PENDENTE/NAO_VERIFICADO NAO contam — sao
#      onboarding/ambiente, nao "instalacao quebrada").
# Se qualquer um falhar -> NAO esta sa (ecoa o motivo). REUSA doctor-check.sh; nao reimplementa o doctor.
#
# "VERSAO CONFERIDA": um arquivo LOCAL em $HOME/.norte-box/upgrade_conferido.json (mesmo padrao da
# fichinha/diario/changelog_visto). Guarda so { "conferido": "X.Y.Z", "em": "<data>" } — metadado de
# versao, sem conteudo do cliente. So grava quando a versao passa na checagem (versao quebrada NUNCA
# vira "conferida" — senao a caixa esqueceria de avisar na proxima).
#
# LEIS (nao-negociaveis, iguais aos outros passos):
#   - LOCAL, ZERO REDE: so le manifestos/arquivos do plugin (versionados) + roda o doctor local + le/
#     escreve o disco local ($HOME/.norte-box). NUNCA sai da maquina, nada de telemetria/rede.
#   - FAIL-OPEN pro fluxo: com o kill-switch NORTE_UPGRADE=0 a peca fica INERTE (nada no stdout, nao
#     escreve nada, exit 0) e a abertura segue exatamente como antes desta peca existir. Sem doctor /
#     sem jq / disco nao gravavel / manifesto ilegivel -> degrada em silencio (NUNCA trava a sessao).
#     Regra dura: na DUVIDA (nao consegui checar), NAO alarma — so alarma com prova POSITIVA de quebra.
#   - NAO-INTRUSIVO: so fala quando a versao MUDOU E a nova esta QUEBRADA. Versao sa -> silencio (ou, na
#     1a abertura pos-upgrade sa, UMA linha curtissima "✓ atualizacao conferida"; depois cala pra sempre).
#     Sem troca de versao -> silencio. Nunca despeja diagnostico no rosto de quem esta bem.
#   - DADO E DADO, NUNCA COMANDO: manifestos e saida do doctor sao TEXTO — nunca executados/eval.
#   - Portabilidade macOS (bash 3.2, SEM arrays associativos/mapfile/${v^^}). Precisa de jq pro "conferido"
#     e pra ler versao; sem jq degrada (nao marca, fail-open — nao alarma).
#
# KILL-SWITCH do mecanismo: NORTE_UPGRADE=0 -> a peca fica INERTE. Vazio/1/qualquer-outra = ligado.
set -u

# --- diretorio da lib (pra achar plugin.json, marketplace.json, doctor-check.sh). bin/ e hooks/ sao
# irmaos sob plugins/norte-box/; a raiz do plugin e' o pai de hooks/. ---
_nbu_lib_dir() {
  local _d
  _d="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)"
  [ -n "${_d:-}" ] && { printf '%s' "$_d"; return 0; }
  [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && { printf '%s/hooks' "$CLAUDE_PLUGIN_ROOT"; return 0; }
  return 1
}

# raiz do plugin (o diretorio que tem .claude-plugin/plugin.json).
_nbu_plugin_root() {
  local _dir; _dir="$(_nbu_lib_dir)" || { printf ''; return 1; }
  local _r; _r="$(cd "$_dir/.." 2>/dev/null && pwd)" || { printf ''; return 1; }
  printf '%s' "$_r"
}

# --- kill-switch: NORTE_UPGRADE=0 -> inerte. ---
_nbu_desligado() {
  case "${NORTE_UPGRADE:-1}" in
    0|no|nao|off|false) return 0 ;;
    *) return 1 ;;
  esac
}

# _nbu_versao_atual — versao do plugin.json (a versao vigente da caixa). So o numero; sem jq/arquivo -> vazio.
# (Mesma fonte de leitura do _nbc_versao_atual da peca-irma changelog.)
_nbu_versao_atual() {
  local _r; _r="$(_nbu_plugin_root)" || { printf ''; return 1; }
  local _pj="$_r/.claude-plugin/plugin.json"
  [ -f "$_pj" ] || { printf ''; return 1; }
  command -v jq >/dev/null 2>&1 || { printf ''; return 1; }
  jq -r '.version // "" | if type=="string" then . else "" end' "$_pj" 2>/dev/null
}

# _nbu_marketplace_path — acha o marketplace.json. No repo dev ele mora em <repo>/.claude-plugin/, e a
# raiz do plugin e' <repo>/plugins/norte-box -> DOIS niveis acima. Mas em outros layouts (cache do
# Claude) pode estar UM nivel acima. Procura nos dois lugares; ecoa o 1o que existir, ou vazio.
_nbu_marketplace_path() {
  local _r; _r="$(_nbu_plugin_root)" || { printf ''; return 1; }
  local _c
  for _c in "$_r/../../.claude-plugin/marketplace.json" "$_r/../.claude-plugin/marketplace.json"; do
    [ -f "$_c" ] && { printf '%s' "$_c"; return 0; }
  done
  printf ''; return 1
}

# _nbu_versao_marketplace — a versao declarada pro plugin "norte-box" dentro do marketplace.json.
# Fonte: o objeto em .plugins[] com name=="norte-box". Sem jq/arquivo/entrada -> vazio.
_nbu_versao_marketplace() {
  local _mp; _mp="$(_nbu_marketplace_path)" || { printf ''; return 1; }
  [ -n "$_mp" ] || { printf ''; return 1; }
  command -v jq >/dev/null 2>&1 || { printf ''; return 1; }
  jq -r '(.plugins // []) | map(select(.name=="norte-box")) | (.[0].version // "") | if type=="string" then . else "" end' "$_mp" 2>/dev/null
}

# caminho do "conferido" (metadado local; mesmo padrao da fichinha/diario/changelog_visto).
_nbu_conferido_path() { printf '%s/.norte-box/upgrade_conferido.json' "${HOME}"; }

# _nbu_conferido_ler — ecoa a ultima versao CONFERIDA (X.Y.Z), ou vazio se nunca / sem jq / sem arquivo.
_nbu_conferido_ler() {
  local _f; _f="$(_nbu_conferido_path)"
  [ -f "$_f" ] || { printf ''; return 1; }
  command -v jq >/dev/null 2>&1 || { printf ''; return 1; }
  jq -r '.conferido // "" | if type=="string" then . else "" end' "$_f" 2>/dev/null
}

# _nbu_conferido_gravar <versao> — grava { conferido, em } no disco local (escrita atomica). Arquivo
# dedicado. Retorna 0 se gravou; 1 se nao deu (sem jq / disco nao gravavel) -> chamador ignora (fail-open).
_nbu_conferido_gravar() {
  local _v="${1:-}"
  [ -n "$_v" ] || return 1
  command -v jq >/dev/null 2>&1 || return 1
  local _dir="${HOME}/.norte-box" _f _tmp _ts
  _f="$(_nbu_conferido_path)"
  mkdir -p "$_dir" 2>/dev/null || return 1
  _ts="$(date -u +%FT%TZ 2>/dev/null || echo unknown)"
  _tmp="$_f.tmp.$$"
  if jq -n --arg v "$_v" --arg em "$_ts" '{conferido:$v, em:$em}' > "$_tmp" 2>/dev/null; then
    mv -f "$_tmp" "$_f" 2>/dev/null && return 0
  fi
  rm -f "$_tmp" 2>/dev/null
  return 1
}

# _nbu_cmp <a> <b> — compara duas versoes X.Y.Z NUMERICAMENTE. Ecoa: -1 se a<b, 0 se a==b, 1 se a>b.
# (Copia do _nbc_cmp da peca-irma changelog — fonte unica de comparacao de versao; bash 3.2, sem arrays.)
_nbu_cmp() {
  local _a="${1:-0}" _b="${2:-0}" i _pa _pb _na _nb
  _a="${_a%%[!0-9.]*}"; _b="${_b%%[!0-9.]*}"
  for i in 1 2 3; do
    _pa="$(printf '%s' "$_a" | cut -d. -f"$i")"; _pb="$(printf '%s' "$_b" | cut -d. -f"$i")"
    case "$_pa" in ''|*[!0-9]*) _na=0 ;; *) _na=$_pa ;; esac
    case "$_pb" in ''|*[!0-9]*) _nb=0 ;; *) _nb=$_pb ;; esac
    if [ "$_na" -lt "$_nb" ]; then printf '%s' -1; return 0; fi
    if [ "$_na" -gt "$_nb" ]; then printf '%s' 1;  return 0; fi
  done
  printf '%s' 0
}

# --- os arquivos-chave que TEM que passar `bash -n` (parse limpo). Relativos a raiz do plugin. So os
# que a caixa carrega/executa em TODA sessao — se um deles nao "parseia", a caixa esta quebrada. ---
_nbu_arquivos_chave() {
  cat <<'EOF'
doctor-check.sh
hooks/situacao-abrir.sh
hooks/_situacao.sh
hooks/_changelog.sh
hooks/_upgrade.sh
hooks/vigia-doctor.sh
hooks/secret-guard.sh
hooks/confirmar-antes.sh
EOF
}

# _nbu_sanidade — a CHECAGEM "esta sa?". Ecoa VAZIO se sa; senao ecoa UMA linha com o motivo (curta,
# padaria). Ordem: manifestos concordam -> arquivos-chave parseiam -> doctor sem FALHA. REUSA o doctor
# (doctor-check.sh) como motor de saude; so acrescenta manifestos + parse (o que o doctor nao cobre).
# Retorna 0 se sa, 1 se quebrada, 2 se NAO deu pra checar (fail-open: chamador trata como "nao alarma").
_nbu_sanidade() {
  local _r; _r="$(_nbu_plugin_root)" || { printf 'nao achei a caixa no disco pra conferir'; return 2; }

  # 0. sem jq nao da pra ler versao dos manifestos com seguranca -> nao afirma nada (fail-open).
  command -v jq >/dev/null 2>&1 || { printf 'nao consegui conferir (falta jq)'; return 2; }

  # 1. manifestos concordam na versao.
  local _vp _vm
  _vp="$(_nbu_versao_atual)"
  _vm="$(_nbu_versao_marketplace)"
  if [ -z "$_vp" ] || [ -z "$_vm" ]; then
    # nao consegui ler uma das versoes -> nao afirmo quebra (fail-open).
    printf 'nao consegui ler a versao dos manifestos'
    return 2
  fi
  if [ "$_vp" != "$_vm" ]; then
    printf 'os dois cadastros de versao nao batem (plugin diz %s, marketplace diz %s)' "$_vp" "$_vm"
    return 1
  fi

  # 2. arquivos-chave existem e parseiam (bash -n).
  local _f _abs
  while IFS= read -r _f || [ -n "$_f" ]; do
    [ -z "$_f" ] && continue
    _abs="$_r/$_f"
    if [ ! -f "$_abs" ]; then
      printf 'falta um arquivo essencial da caixa (%s)' "$_f"
      return 1
    fi
    if ! bash -n "$_abs" 2>/dev/null; then
      printf 'um arquivo essencial da caixa esta com defeito de sintaxe (%s)' "$_f"
      return 1
    fi
  done <<EOF
$(_nbu_arquivos_chave)
EOF

  # 3. doctor: SO contam as FALHAs de INTEGRIDADE-DA-INSTALACAO (as que uma troca de versao ruim quebraria).
  # PENDENTE/NAO_VERIFICADO nao contam. E — furo achado pelo Val — os itens de AMBIENTE/ESTADO do doctor
  # ("Estado gravavel"=disco RO, "git", "Superpowers", "Freio de mao", "Objetivo"...) NAO sao problema de
  # VERSAO: gritar "nao confie nesta versao" por causa deles e falso-alarme (viola a promessa da peca:
  # na duvida NAO alarma). Por isso usamos uma LISTA-BRANCA de itens de integridade — so eles, em FALHA,
  # significam "a atualizacao quebrou a caixa". Os proprios checks 1 (manifestos) e 2 (parse) ja sao o
  # piso de integridade; o doctor so acrescenta estes tres. (Fail-toward-nao-alarmar, de proposito.)
  local _dc="$_r/doctor-check.sh"
  if [ -f "$_dc" ] && [ -r "$_dc" ]; then
    local _out _falhas
    _out="$(CLAUDE_PLUGIN_ROOT="$_r" bash "$_dc" 2>/dev/null)"
    if [ -n "$_out" ]; then
      _falhas="$(printf '%s\n' "$_out" | awk -F'|' '
        $2=="FALHA" && ($1=="Prova de vida" || $1=="Freios (5 hooks)" || $1=="Red-team") {printf "%s%s", sep, $1; sep=", "}')"
      if [ -n "$_falhas" ]; then
        printf 'o autodiagnostico acusou problema em: %s' "$_falhas"
        return 1
      fi
    fi
    # doctor sem saida / so com falhas de ambiente -> nao afirma quebra (checks 1+2 ja deram o piso); segue sa.
  fi
  # se o doctor nem existe, as checagens 1+2 ja deram um piso honesto; nao inventa quebra.

  printf ''   # SA
  return 0
}

# _norte_upgrade_abertura — o CORACAO da peca no SessionStart. Decide o que mostrar e ATUALIZA o "conferido".
#   - kill-switch -> inerte (nada, exit 1 = "nao ecoou").
#   - sem versao atual (sem plugin.json/jq) -> nada (fail-open silencio).
#   - versao atual == conferida: silencio (ja conferi esta versao).
#   - 1a VEZ (sem "conferido"): a caixa acabou de nascer nesta maquina — trata como "conferir esta versao".
#     Se SA -> grava conferido + 1 linha curtissima "✓" (ou silencio se preferir; ver abaixo). Se QUEBRADA
#     -> avisa e NAO grava.
#   - versao mudou (conferido != atual): roda a checagem.
#       SA       -> grava conferido; ecoa UMA linha curtissima "✓ atualizacao conferida" (feedback positivo,
#                   uma vez; depois a versao vira "conferida" e cala pra sempre).
#       QUEBRADA -> ecoa o bloco de ALERTA ("nao confie nesta versao; avise a Norte") e NAO grava (pra
#                   continuar avisando enquanto nao consertar).
#       INDETERMINADO (return 2) -> fail-open: nao alarma, nao grava (revalida na proxima).
# Ecoa o recado no stdout (o hook injeta no cartao). Retorna 0 se ecoou algo; 1 se ficou quieto.
_norte_upgrade_abertura() {
  _nbu_desligado && return 1

  local _atual _conf
  _atual="$(_nbu_versao_atual)"
  [ -n "$_atual" ] || return 1   # sem versao legivel -> fail-open silencio

  _conf="$(_nbu_conferido_ler)"

  # ja conferi ESTA versao? silencio. (conferido == atual)
  if [ -n "$_conf" ] && [ "$(_nbu_cmp "$_conf" "$_atual")" = "0" ]; then
    return 1
  fi

  # aqui: 1a vez (sem conferido) OU a versao mudou desde a ultima conferida. Roda a checagem.
  local _motivo _rc
  _motivo="$(_nbu_sanidade)"; _rc=$?

  if [ "$_rc" = "0" ]; then
    # SA -> grava conferido e da um feedback curtissimo, uma vez.
    _nbu_conferido_gravar "$_atual" >/dev/null 2>&1 || true
    printf '✓ atualizacao conferida — a versao %s desta caixa foi checada e esta inteira.\n' "$_atual"
    return 0
  fi

  if [ "$_rc" = "1" ]; then
    # QUEBRADA -> alerta claro e NAO grava (segue avisando ate consertar).
    printf '⚠ Esta atualizacao parece com problema: %s.\n' "$_motivo"
    printf 'Nao confie nesta versao da caixa; avise a Norte (e, se puder, nao siga com trabalho importante ate confirmarem).\n'
    return 0
  fi

  # _rc=2 (indeterminado): fail-open. Nao alarma, nao grava -> revalida na proxima abertura.
  return 1
}
