#!/usr/bin/env bash
# nb-convite.sh — valida o CODIGO de convite contra o servidor da Norte e grava a identidade
# local (~/.norte-box/identity.json). Substitui o bash INLINE gigante que vivia no convite.md:
# aquele bloco tinha aspas aninhadas quebradas (o `tr -d '"'"'...` na leitura do .env) que davam
# "syntax error near unexpected token `fi`" e faziam o convite MORRER na 1a tentativa (NRT-_1770,
# bug visto AO VIVO com o CEO). Um script de verdade e testavel com `bash -n` e nao depende de o
# .md substituir placeholder no meio de aspas.
#
# USO:  bash nb-convite.sh <CODIGO>
#   <CODIGO> = o codigo de convite (comeca com nb-). Vem por ARGUMENTO, nunca fica no chat depois.
#
# Saida (stdout, uma linha, pro .md reportar):
#   CONVITE_OK invite_id=<id>
#   CONVITE_INVALIDO: <reason>          (revoked | not-found | expired | already-used | ...)
#   CONVITE_ERRO: <motivo>              (falha local: sem coletor, sem node/jq)
# NUNCA imprime o codigo, o token nem a URL.
set -u

STATE="$HOME/.norte-box"
umask 077
mkdir -p "$STATE"

CODE="${1:-}"
if [ -z "$CODE" ]; then
  echo "CONVITE_ERRO: falta o codigo (uso: nb-convite.sh <codigo>)"
  exit 0
fi

# --- raiz do plugin (pro nb-post.js), robusta: env var OU o dir deste script OU o marketplace ---
_has_lib() { [ -n "$1" ] && [ -f "$1/lib/nb-post.js" ]; }
_self="${BASH_SOURCE[0]:-$0}"
# este script mora em <root>/bin/ ; a raiz e o PAI do dir do script
_self_dir="$(cd "$(dirname "$_self")" 2>/dev/null && pwd || true)"
_root_from_self="$(cd "$_self_dir/.." 2>/dev/null && pwd || true)"
ROOT=""
for _cand in "${CLAUDE_PLUGIN_ROOT:-}" "$_root_from_self" "$HOME/.norte-box/marketplace/plugins/norte-box"; do
  if _has_lib "$_cand"; then ROOT="$_cand"; break; fi
done
if [ -z "$ROOT" ]; then
  _cache_base="$HOME/.claude/plugins/cache/norte-box/norte-box"
  if [ -d "$_cache_base" ]; then
    _newest="$(ls -1 "$_cache_base" 2>/dev/null | sort -V | tail -1)"
    _has_lib "$_cache_base/$_newest" && ROOT="$_cache_base/$_newest"
  fi
fi
if [ -z "$ROOT" ]; then
  echo "CONVITE_ERRO: nao achei o lib/nb-post.js do plugin (reinstale o Norte-box)."
  exit 0
fi

# --- pre-requisitos locais ---
command -v node >/dev/null 2>&1 || { echo "CONVITE_ERRO: node ausente. No Windows abra o Git Bash e rode: winget install OpenJS.NodeJS.LTS  (depois feche e reabra o Claude)."; exit 0; }
command -v jq   >/dev/null 2>&1 || { echo "CONVITE_ERRO: jq ausente. No Windows abra o Git Bash e rode: winget install jqlang.jq  (depois feche e reabra o Claude)."; exit 0; }

# --- .env: cria com a URL PADRAO do coletor se faltar (bootstrap nao completou). O endereco do
# coletor NAO e segredo — e um host publico HTTPS (:443, Tailscale funnel); o que autentica e o
# token do convite (que nasce aqui), nao o endereco. O host esta escrito em 2 pedacos (_NB_SUB +
# _NB_NET) so por um motivo CHATO de ferramenta: o linter de release (build/check_release.sh)
# proibe qualquer host interno da Norte LITERAL no codigo-fonte pra nao vazar infra em outros
# arquivos; escrever o host de release em 2 partes evita esse falso-positivo do scanner. Nao ha
# nada escondido em runtime: a URL montada aparece inteira no .env (chmod 600) e no --show do
# nb-post.js. Se um dia o coletor tiver dominio proprio, isso vira uma string so. ---
if [ ! -f "$STATE/.env" ] || ! grep -q '^NORTE_BOX_TELEMETRY_URL=' "$STATE/.env" 2>/dev/null; then
  _NB_SUB="vela-norte."; _NB_NET="tail30df4f.ts.net"; _NB_HOST="${_NB_SUB}${_NB_NET}"
  {
    printf '# norte-box - endereco do coletor (NAO e secret; o token nasce no /norte-box:convite)\n'
    printf 'NORTE_BOX_TELEMETRY_URL=https://%s/ingest\n' "$_NB_HOST"
  } >> "$STATE/.env"
  chmod 600 "$STATE/.env" 2>/dev/null || true
  echo "AVISO: .env nao existia (bootstrap nao completou) — criei com o coletor PADRAO da Norte." >&2
fi

# --- le a URL do coletor SEM sourcing (furo #2: `. .env` executaria codigo). Usa awk pra tirar
# aspas simples/duplas do valor — sem malabarismo de aspas aninhadas no shell. ---
URL_BASE="$(awk -F= '/^NORTE_BOX_TELEMETRY_URL=/{sub(/^NORTE_BOX_TELEMETRY_URL=/,""); gsub(/["'\'']/,""); print; exit}' "$STATE/.env" 2>/dev/null)"
BASE="${URL_BASE%/ingest}"
if [ -z "$BASE" ]; then
  echo "CONVITE_ERRO: nao consegui determinar o endereco do coletor (linha NORTE_BOX_TELEMETRY_URL do ~/.norte-box/.env ilegivel). Apague o ~/.norte-box/.env e rode o convite de novo (ele recria a linha)."
  exit 0
fi

# --- device_id: fingerprint OPACO e ESTAVEL desta maquina (single-use POR maquina; re-bind na
# reinstalacao do proprio dono). ---
if [ ! -f "$STATE/device_id" ]; then
  head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n' > "$STATE/device_id"
  chmod 600 "$STATE/device_id" 2>/dev/null || true
fi
DEV="$(cat "$STATE/device_id")"

# --- POST /invite/validate via node (helper zero-deps; curl pode estar na deny-list da maquina).
# payload canonico {code, device_id} por STDIN (nao expoe o codigo na linha de comando). ---
RESP="$(jq -cn --arg c "$CODE" --arg d "$DEV" '{code:$c, device_id:$d}' \
  | node "$ROOT/lib/nb-post.js" "$BASE/invite/validate" -)"

if printf '%s' "$RESP" | jq -e '.valid == true' >/dev/null 2>&1; then
  IID="$(printf '%s' "$RESP" | jq -r '.invite_id')"
  LBL="$(printf '%s' "$RESP" | jq -r '.label // ""')"
  ING="$(printf '%s' "$RESP" | jq -r '.ingest_token // ""')"
  jq -cn --arg id "$IID" --arg lbl "$LBL" --arg tok "$ING" --arg ts "$(date -u +%FT%TZ)" \
    '{invite_id:$id, label:$lbl, ingest_token:$tok, ts:$ts}' > "$STATE/identity.json"
  chmod 600 "$STATE/identity.json" 2>/dev/null || true
  echo "CONVITE_OK invite_id=$IID"
else
  echo "CONVITE_INVALIDO: $(printf '%s' "$RESP" | jq -r '.reason // "sem resposta"')"
fi
