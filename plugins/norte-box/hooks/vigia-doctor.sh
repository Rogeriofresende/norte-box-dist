#!/usr/bin/env bash
# vigia-doctor.sh — VIGIA LEVE (NRT-_990419 Camada 4): roda o /doctor MUDO no inicio da sessao e,
# SO se algum item QUEBROU (STATUS FALHA), avisa numa linha "algo travou — rode /norte-box:doctor".
# Assim, quando a caixa quebra numa maquina != CEO (Viviane/Ygor/Supren), a pessoa e' avisada sozinha
# em vez de virar SSH/suporte do dono. PENDENTE (onboarding nao feito) NAO e' quebra -> silencio.
#
# LEIS (nao-negociaveis):
#   - LEVE: nao roda o doctor em TODA sessao. Cache local $HOME/.norte-box/vigia.cache (epoch+versao+
#     resultado). Verde fresco (LIMPO, < TTL, mesma versao do plugin) -> sai MUDO sem rodar nada.
#     "Cacheia o verde, NUNCA o vermelho": enquanto ha FALHA, revalida toda sessao (o aviso some na
#     hora que o conserto acontece; nunca segura vermelho velho). Bust automatico quando a versao muda.
#   - KILL-SWITCH: NORTE_VIGIA=0|no|nao|off|false desliga tudo. Vazio/1 = ligado.
#   - FAIL-OPEN: qualquer erro (sem doctor-check, sem jq, disco, trava) -> exit 0 silencioso. NUNCA
#     trava/atrasa a sessao. So injeta additionalContext quando ha FALHA de verdade.
#   - LOCAL: nao faz rede. So le/roda o doctor-check e escreve a fichinha de cache. Imprime so os NOMES
#     dos itens quebrados (nunca o DETALHE — sem path de filesystem no rosto da pessoa).
#   - Portabilidade macOS (bash 3.2 / BSD).
set -u

# consome o JSON do SessionStart (dado, nao-confiavel; nao usamos o conteudo). Descarta sem segurar na
# memoria (roda em TODA sessao — mesmo padrao dos outros hooks SessionStart).
cat >/dev/null 2>&1 || true

# kill-switch flexivel.
case "${NORTE_VIGIA:-1}" in 0|no|nao|off|false) exit 0 ;; esac

# fail-open TOTAL: qualquer saida deste ponto em diante e' exit 0 (nunca trava a sessao).
trap 'exit 0' EXIT

# acha o doctor-check.sh (mora na RAIZ do plugin; este hook mora em hooks/).
_self="${BASH_SOURCE[0]:-$0}"
_self_dir="$(cd "$(dirname "$_self")" 2>/dev/null && pwd || true)"
_DC=""
for _c in "${CLAUDE_PLUGIN_ROOT:-}/doctor-check.sh" "${_self_dir}/../doctor-check.sh"; do
  [ -n "$_c" ] && [ -f "$_c" ] && [ -r "$_c" ] && { _DC="$_c"; break; }
done
[ -n "$_DC" ] || exit 0

# raiz do plugin (pra ler a versao -> cache-bust quando o plugin e' atualizado).
_root="$(cd "$(dirname "$_DC")" 2>/dev/null && pwd || true)"
_VER=""
[ -n "$_root" ] && [ -f "$_root/.claude-plugin/plugin.json" ] && \
  _VER="$(grep -o '"version"[^,]*' "$_root/.claude-plugin/plugin.json" 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"

_CACHE="$HOME/.norte-box/vigia.cache"
_NOW="$(date +%s 2>/dev/null || echo 0)"
_TTL=1800   # 30 min (juiz Gemini: equilibrio leveza x janela-cega)

# cache: linha1=epoch, linha2=versao, linha3=LIMPO ou lista de itens FALHA.
# So reusa como SILENCIO se: resultado LIMPO + mesma versao + dentro do TTL. Vermelho nunca vira silencio.
if [ -f "$_CACHE" ] && [ -r "$_CACHE" ]; then
  _cep="$(sed -n '1p' "$_CACHE" 2>/dev/null)"
  _cver="$(sed -n '2p' "$_CACHE" 2>/dev/null)"
  _cres="$(sed -n '3p' "$_CACHE" 2>/dev/null)"
  if [ "$_cres" = "LIMPO" ] && [ "$_cver" = "$_VER" ] && \
     [ -n "$_cep" ] && [ "$_NOW" -ge "$_cep" ] 2>/dev/null; then
    if [ "$((_NOW - _cep))" -lt "$_TTL" ] 2>/dev/null; then exit 0; fi   # verde fresco -> mudo
  fi
fi

# roda o doctor MUDO e extrai os itens com STATUS FALHA (so o nome, campo 1).
_out="$(bash "$_DC" 2>/dev/null)"
[ -n "$_out" ] || exit 0
_falhas="$(printf '%s\n' "$_out" | awk -F'|' '$2=="FALHA"{printf "%s%s", sep, $1; sep=", "}')"

# grava o cache (verde=LIMPO; vermelho grava a lista, mas nunca sera reusado como silencio).
mkdir -p "$HOME/.norte-box" 2>/dev/null || true
if [ -z "$_falhas" ]; then
  printf '%s\n%s\nLIMPO\n' "$_NOW" "$_VER" > "$_CACHE" 2>/dev/null || true
  exit 0
fi
printf '%s\n%s\n%s\n' "$_NOW" "$_VER" "$_falhas" > "$_CACHE" 2>/dev/null || true

# fala 1 linha (so os NOMES; nunca o DETALHE).
_msg="⚠ algo na caixa travou (${_falhas}) — rode /norte-box:doctor pra ver o conserto"
if command -v jq >/dev/null 2>&1; then
  jq -cn --arg m "$_msg" '{hookSpecificOutput:{hookEventName:"SessionStart", additionalContext:$m}}'
else
  printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' "$_msg"
fi
exit 0
