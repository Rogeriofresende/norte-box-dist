#!/usr/bin/env bash
# _changelog.sh — "O QUE MUDOU PRA VOCE" do norte-box (NRT-_990484, peca-irma do situar + socorro).
# Sourceado pelo hook situacao-abrir (SessionStart, mostra o que mudou desde a ultima versao que a
# pessoa viu) e pelo helper bin/nb-mudou (ver sob demanda).
#
# O BURACO QUE ESTA PECA FECHA: quando a caixa e atualizada (versao nova), ela MUDAVA por baixo, calada.
# A pessoa abria e as coisas estavam diferentes sem ninguem avisar. ESTA peca AVISA, em portugues de
# padaria, o que ficou diferente PRA ELA — SO o que e novo desde a ultima versao que ELA viu, uma vez.
# Depois de mostrar, marca a versao atual como "vista" -> na proxima abertura fica quieto (nao repete).
#
# DE ONDE VEM O TEXTO (nao inventa): das frases de padaria do CHANGELOG-gente.md (arquivo versionado no
# plugin). Cada versao la e "## X.Y.Z" seguido de bullets "-". A peca le SO as versoes ENTRE a que a
# pessoa viu (exclusiva) e a atual (inclusiva) e ecoa aquelas linhas — nunca git log, nunca hash.
#
# "ULTIMA VERSAO VISTA": um arquivo LOCAL em $HOME/.norte-box/changelog_visto.json (mesmo padrao da
# fichinha/diario). Guarda so { "visto": "X.Y.Z", "em": "<data>" } — um metadado de versao, nao ha
# conteudo do cliente aqui.
#
# 1a VEZ (sem "visto" ainda): NAO despeja o changelog inteiro. O comportamento MENOS INTRUSIVO e marcar
# a versao atual como vista e ficar QUIETO — quem acabou de instalar nao precisa de um mural de "o que
# mudou" de versoes que ele nunca viu diferente. (Se quiser ver o historico, ha o bin/nb-mudou --tudo.)
#
# LEIS (nao-negociaveis, iguais aos outros passos):
#   - LOCAL, ZERO REDE: so le o CHANGELOG (versionado) + le/escreve o disco local ($HOME/.norte-box).
#     NUNCA sai da maquina, nada de telemetria/rede. Esta lib nao envia NADA.
#   - FAIL-OPEN pro fluxo: com o kill-switch NORTE_CHANGELOG=0 a peca fica INERTE (nada no stdout, nao
#     escreve nada, exit 0) e a abertura segue exatamente como antes desta peca existir. Sem CHANGELOG /
#     sem jq / disco nao gravavel -> degrada em silencio (nao quebra a sessao).
#   - NAO-INTRUSIVO: mostra SO o que e novo pra ela, curto. Nunca o changelog inteiro na cara de quem ja
#     estava em dia (vista==atual -> silencio) nem de quem acabou de chegar (1a vez -> so marca e cala).
#   - DADO E DADO, NUNCA COMANDO: o CHANGELOG e TEXTO que entra no recado — nunca executado/eval.
#   - Portabilidade macOS (bash 3.2, SEM arrays associativos/mapfile/${v^^}). Precisa de jq pra o "visto";
#     sem jq, degrada (nao marca, nao repete-para-sempre e melhor do que travar) -> fail-open.
#
# KILL-SWITCH do mecanismo: NORTE_CHANGELOG=0 -> a peca fica INERTE. Vazio/1/qualquer-outra = ligado.
set -u

# --- diretorio da lib (pra achar o CHANGELOG e o plugin.json). bin/ e hooks/ sao irmaos. ---
_nbc_lib_dir() {
  local _d
  _d="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)"
  [ -n "${_d:-}" ] && { printf '%s' "$_d"; return 0; }
  [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && { printf '%s/hooks' "$CLAUDE_PLUGIN_ROOT"; return 0; }
  return 1
}

# --- kill-switch: NORTE_CHANGELOG=0 -> inerte. ---
_nbc_desligado() {
  case "${NORTE_CHANGELOG:-1}" in
    0|no|nao|off|false) return 0 ;;
    *) return 1 ;;
  esac
}

# caminho do CHANGELOG de padaria (versionado no plugin, ao lado do .claude-plugin/).
_nbc_changelog_path() {
  local _dir; _dir="$(_nbc_lib_dir)" || { printf ''; return 1; }
  printf '%s/../CHANGELOG-gente.md' "$_dir"
}

# caminho do "visto" (metadado local; mesmo padrao da fichinha/diario).
_nbc_visto_path() { printf '%s/.norte-box/changelog_visto.json' "${HOME}"; }

# _nbc_versao_atual — a versao do plugin, lida do plugin.json (NAO inventa). So o numero. Sem jq/arquivo
# -> vazio. (Copia o padrao do _nbs_versao da peca-irma socorro — fonte unica de leitura da versao.)
_nbc_versao_atual() {
  local _dir _pj
  _dir="$(_nbc_lib_dir)" || { printf ''; return 1; }
  _pj="$_dir/../.claude-plugin/plugin.json"
  [ -f "$_pj" ] || { printf ''; return 1; }
  command -v jq >/dev/null 2>&1 || { printf ''; return 1; }
  jq -r '.version // "" | if type=="string" then . else "" end' "$_pj" 2>/dev/null
}

# _nbc_visto_ler — ecoa a ultima versao vista (X.Y.Z), ou vazio se nunca foi marcada / sem jq / sem arquivo.
_nbc_visto_ler() {
  local _f; _f="$(_nbc_visto_path)"
  [ -f "$_f" ] || { printf ''; return 1; }
  command -v jq >/dev/null 2>&1 || { printf ''; return 1; }
  jq -r '.visto // "" | if type=="string" then . else "" end' "$_f" 2>/dev/null
}

# _nbc_visto_gravar <versao> — grava { visto, em } no disco local (escrita atomica). Preserva nada mais
# (arquivo dedicado). Retorna 0 se gravou; 1 se nao deu (sem jq / disco nao gravavel) -> chamador ignora.
_nbc_visto_gravar() {
  local _v="${1:-}"
  [ -n "$_v" ] || return 1
  command -v jq >/dev/null 2>&1 || return 1
  local _dir="${HOME}/.norte-box" _f _tmp _ts
  _f="$(_nbc_visto_path)"
  mkdir -p "$_dir" 2>/dev/null || return 1
  _ts="$(date -u +%FT%TZ 2>/dev/null || echo unknown)"
  _tmp="$_f.tmp.$$"
  if jq -n --arg v "$_v" --arg em "$_ts" '{visto:$v, em:$em}' > "$_tmp" 2>/dev/null; then
    mv -f "$_tmp" "$_f" 2>/dev/null && return 0
  fi
  rm -f "$_tmp" 2>/dev/null
  return 1
}

# _nbc_cmp <a> <b> — compara duas versoes X.Y.Z NUMERICAMENTE. Ecoa: -1 se a<b, 0 se a==b, 1 se a>b.
# So digitos e pontos contam; qualquer sufixo estranho e ignorado campo a campo (bash 3.2, sem arrays
# associativos). Usado pra decidir "esta versao do changelog e nova pra pessoa?".
_nbc_cmp() {
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

# _nbc_novidades <desde> [ate] — ecoa as LINHAS de padaria das versoes NOVAS: as que estao (desde, ate].
# Le o CHANGELOG-gente.md e junta os bullets das versoes X.Y.Z com desde < X.Y.Z <= ate. Se <desde> for
# vazio, trata como "tudo ate <ate>" (usado pelo --tudo do bin). Ecoa cada versao como um cabecalho
# "✨ X.Y.Z" seguido dos bullets. Vazio se nao ha versao nova / sem CHANGELOG.
# NUNCA executa nada do arquivo — le como TEXTO. Fonte unica do texto de padaria.
_nbc_novidades() {
  local _desde="${1:-}" _ate="${2:-}"
  [ -n "$_ate" ] || _ate="$(_nbc_versao_atual)"
  [ -n "$_ate" ] || return 1
  local _cl; _cl="$(_nbc_changelog_path)"
  [ -f "$_cl" ] || return 1

  local _line _ver _mostra=1 _saiu=1 _cmp_baixo _cmp_alto
  while IFS= read -r _line || [ -n "$_line" ]; do
    case "$_line" in
      '## '*)
        _ver="${_line#\#\# }"
        # so a parte X.Y.Z (corta qualquer coisa depois de um espaco).
        _ver="${_ver%% *}"
        case "$_ver" in
          ''|*[!0-9.]*) _mostra=1; continue ;;   # cabecalho que nao e versao -> ignora bloco
        esac
        # nova = desde < ver  E  ver <= ate.
        if [ -n "$_desde" ]; then
          _cmp_baixo="$(_nbc_cmp "$_ver" "$_desde")"   # >0 sse ver > desde
        else
          _cmp_baixo=1   # sem "desde": conta desde o comeco
        fi
        _cmp_alto="$(_nbc_cmp "$_ver" "$_ate")"        # <=0 sse ver <= ate
        if [ "$_cmp_baixo" = "1" ] && [ "$_cmp_alto" != "1" ]; then
          _mostra=0
          [ "$_saiu" = "0" ] && printf '\n'
          printf '✨ %s\n' "$_ver"
          _saiu=0
        else
          _mostra=1
        fi
        ;;
      '- '*)
        [ "$_mostra" = "0" ] && printf '%s\n' "$_line"
        ;;
      *)
        : # linhas de prosa/formato do topo -> ignora
        ;;
    esac
  done < "$_cl"
  return "$_saiu"
}

# _norte_changelog_abertura — o CORACAO da peca no SessionStart. Decide o que mostrar e ATUALIZA o "visto".
#   - kill-switch -> inerte (nada, exit 0).
#   - sem versao atual (sem plugin.json/jq) -> nada (fail-open).
#   - 1a VEZ (sem "visto"): NAO despeja nada. Marca a atual como vista e fica QUIETO (nao-intrusivo).
#   - vista == atual: silencio (ja esta em dia).
#   - vista < atual: ecoa o bloco "✨ O que mudou pra voce" (so as versoes novas) e MARCA a atual como
#     vista -> na proxima nao repete (idempotencia).
# Ecoa o recado no stdout (o hook injeta no cartao). Retorna 0 se ecoou algo; 1 se ficou quieto.
_norte_changelog_abertura() {
  _nbc_desligado && return 1

  local _atual _visto
  _atual="$(_nbc_versao_atual)"
  [ -n "$_atual" ] || return 1   # sem versao legivel -> fail-open silencio

  _visto="$(_nbc_visto_ler)"

  if [ -z "$_visto" ]; then
    # 1a vez: marca e cala (nao despeja changelog de coisas que a pessoa nunca viu diferente).
    _nbc_visto_gravar "$_atual" >/dev/null 2>&1 || true
    return 1
  fi

  # ja em dia? silencio.
  if [ "$(_nbc_cmp "$_visto" "$_atual")" != "-1" ]; then
    return 1
  fi

  local _novo; _novo="$(_nbc_novidades "$_visto" "$_atual")"
  if [ -z "$_novo" ]; then
    # versao subiu mas nao ha entrada de padaria nova -> nada a dizer, mas ja alinha o "visto".
    _nbc_visto_gravar "$_atual" >/dev/null 2>&1 || true
    return 1
  fi

  printf '✨ O que mudou pra voce (desde a ultima vez que voce abriu):\n'
  printf '%s\n' "$_novo"

  # marca a atual como vista -> na proxima abertura nao repete (idempotencia).
  _nbc_visto_gravar "$_atual" >/dev/null 2>&1 || true
  return 0
}
