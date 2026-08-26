#!/usr/bin/env bash
# doctor-check.sh — checagens DETERMINISTICAS e HONESTAS do norte-box.
# Uma linha por item: ITEM|STATUS|DETALHE.  STATUS ∈ OK | FALHA | NAO_VERIFICADO | PENDENTE.
#   OK            = checado de fato e passou.
#   FALHA         = checado e a instalacao esta quebrada (tem conserto).
#   NAO_VERIFICADO= a checagem nao pode rodar (arquivo/var ausente) — nao afirmamos nada.
#   PENDENTE      = passo do ONBOARDING (convite/consent) ainda nao feito — nao e defeito da
#                   instalacao, e "falta voce fazer X". Distingue CASCA (plugin instalado) de
#                   ONBOARDING COMPLETO (convite+consent+telemetria). Um "OK 5/5" so da casca
#                   fez o CEO achar que estava ligado com NADA instalado — isto conserta.
# REGRA DURA: NUNCA imprime OK sem ter checado DE FATO. Se uma checagem nao pode rodar
# (arquivo/var ausente), imprime NAO_VERIFICADO — jamais chuta verde.
# Fonte confiavel: filesystem (cache de plugins), NUNCA `claude plugin list` (nao-confiavel:
# nao lista nem plugins instalados em contexto nao-interativo).
# Nao escreve fora de $HOME/.norte-box e ./norte-out. Uso: bash doctor-check.sh
set -u

# Raiz do plugin. Preferencia: CLAUDE_PLUGIN_ROOT (setado pelo Claude Code quando o comando roda
# via /norte-box:doctor). Mas o doctor tambem roda com essa var AUSENTE (ex: `bash doctor-check.sh`
# solto, ou o Claude nao exportou a var pro subshell) — foi o que fez o CEO ver "Prova de vida" e
# "Freios" como NAO_VERIFICADO com o plugin instalado e SAO na maquina (NRT-_1770). Resolvemos a
# raiz por conta propria em cascata:
#   1. CLAUDE_PLUGIN_ROOT (se setado E tem o plugin.json — a fonte canonica);
#   2. o diretorio DESTE proprio script (o doctor-check.sh MORA na raiz do plugin) — sempre certo
#      quando o script foi achado, e nao depende de env var nenhuma;
#   3. a copia do marketplace (~/.norte-box/marketplace/plugins/norte-box) — o plugin roda de la;
#   4. o cache de plugins do Claude (~/.claude/plugins/cache/norte-box/norte-box/<versao mais nova>).
# So contamos como raiz um caminho que TEM o plugin.json — senao seguimos pro proximo candidato.
_has_plugin() { [ -n "$1" ] && [ -f "$1/.claude-plugin/plugin.json" ]; }

# diretorio deste script (resolve symlink de 1 nivel; sem depender de realpath/GNU)
_self="${BASH_SOURCE[0]:-$0}"
_self_dir="$(cd "$(dirname "$_self")" 2>/dev/null && pwd || true)"

ROOT=""
for _cand in \
  "${CLAUDE_PLUGIN_ROOT:-}" \
  "$_self_dir" \
  "$HOME/.norte-box/marketplace/plugins/norte-box"
do
  if _has_plugin "$_cand"; then ROOT="$_cand"; break; fi
done
# ultimo recurso: versao mais nova no cache de plugins do Claude
if [ -z "$ROOT" ]; then
  _cache_base="$HOME/.claude/plugins/cache/norte-box/norte-box"
  if [ -d "$_cache_base" ]; then
    _newest="$(ls -1 "$_cache_base" 2>/dev/null | sort -V | tail -1)"
    _has_plugin "$_cache_base/$_newest" && ROOT="$_cache_base/$_newest"
  fi
fi

emit() { printf '%s|%s|%s\n' "$1" "$2" "$3"; }

# 1. Prova de vida — versao no plugin.json
if [ -n "$ROOT" ] && [ -f "$ROOT/.claude-plugin/plugin.json" ]; then
  V="$(grep -o '"version"[[:space:]]*:[[:space:]]*"[^"]*"' "$ROOT/.claude-plugin/plugin.json" 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
  if [ -n "$V" ]; then emit "Prova de vida" "OK" "plugin v$V carregado"
  else emit "Prova de vida" "NAO_VERIFICADO" "plugin.json sem version legivel"; fi
else
  emit "Prova de vida" "NAO_VERIFICADO" "CLAUDE_PLUGIN_ROOT/.claude-plugin/plugin.json nao acessivel"
fi

# 2. Superpowers presente — fonte CONFIAVEL (cache dir OU installed_plugins.json)
SP=""
[ -d "$HOME/.claude/plugins/cache/superpowers-marketplace" ] && SP="cache"
if [ -z "$SP" ] && [ -f "$HOME/.claude/plugins/installed_plugins.json" ]; then
  grep -qi "superpowers" "$HOME/.claude/plugins/installed_plugins.json" 2>/dev/null && SP="installed_plugins"
fi
if [ -n "$SP" ]; then
  emit "Superpowers" "OK" "presente ($SP)"
elif [ ! -e "$HOME/.claude/plugins" ]; then
  emit "Superpowers" "NAO_VERIFICADO" "~/.claude/plugins nao acessivel"
else
  emit "Superpowers" "FALHA" "instale: claude plugin marketplace add obra/superpowers-marketplace && claude plugin install superpowers@superpowers-marketplace"
fi

# 3. Freios (5 hooks) com +x
if [ -n "$ROOT" ] && [ -f "$ROOT/hooks/hooks.json" ]; then
  miss=""
  for h in secret-guard confirmar-antes consent-gate telemetry-emit telemetry-drain; do
    [ -x "$ROOT/hooks/$h.sh" ] || miss="$miss $h"
  done
  if [ -z "$miss" ]; then emit "Freios (5 hooks)" "OK" "5/5 com +x"
  else emit "Freios (5 hooks)" "FALHA" "sem +x ou faltando:$miss (rode: chmod +x nos hooks)"; fi
else
  emit "Freios (5 hooks)" "NAO_VERIFICADO" "CLAUDE_PLUGIN_ROOT/hooks/hooks.json nao acessivel"
fi

# 3b/3c/3d — ITENS NOVOS (NRT-_990419): red-team (Peca 1), /objetivo (Peca 2), freio de mao. Regra dura
# herdada: OK so' se checou DE FATO. Ausencia com RAIZ RESOLVIDA = FALHA (esta versao do doctor-check
# mora na MESMA arvore que devia ter o item; faltar = instalacao quebrada, com conserto). Raiz nao
# resolvida = NAO_VERIFICADO (nao afirmamos nada).
if [ -n "$ROOT" ]; then
  if [ -x "$ROOT/bin/nb-red-team" ]; then emit "Red-team" "OK" "bin/nb-red-team presente e executavel"
  elif [ -f "$ROOT/bin/nb-red-team" ]; then emit "Red-team" "FALHA" "sem +x (rode: chmod +x bin/nb-red-team)"
  else emit "Red-team" "FALHA" "bin/nb-red-team ausente (reinstale/atualize o plugin)"; fi
else emit "Red-team" "NAO_VERIFICADO" "raiz do plugin nao acessivel"; fi

if [ -n "$ROOT" ]; then
  _oc=""; _of=""
  [ -f "$ROOT/commands/objetivo.md" ] && _oc=1
  grep -q '_norte_objetivo_definir()' "$ROOT/hooks/_situacao.sh" 2>/dev/null && _of=1
  if [ -n "$_oc" ] && [ -n "$_of" ]; then emit "Objetivo" "OK" "commands/objetivo.md + funcoes em _situacao.sh"
  else
    _falta=""
    [ -z "$_oc" ] && _falta="$_falta commands/objetivo.md"
    [ -z "$_of" ] && _falta="$_falta _norte_objetivo_definir"
    emit "Objetivo" "FALHA" "faltando:$_falta (reinstale/atualize o plugin)"
  fi
else emit "Objetivo" "NAO_VERIFICADO" "raiz do plugin nao acessivel"; fi

# 3e — Objetivo confere (NRT-_990429): o 2o portao do selo. Checa DE FATO que (1) a funcao
# _norte_situacao_objetivo_ok existe em _situacao.sh E (2) ela esta ENCAIXADA no selo (o
# _norte_situacao_selo chama _norte_situacao_objetivo_ok — senao o portao esta orfao e nao vale nada).
if [ -n "$ROOT" ]; then
  _sit="$ROOT/hooks/_situacao.sh"
  if [ -f "$_sit" ]; then
    _ofn=""; _owired=""
    grep -q '_norte_situacao_objetivo_ok()' "$_sit" 2>/dev/null && _ofn=1
    # encaixe no selo: dentro do corpo de _norte_situacao_selo tem que haver chamada a _norte_situacao_objetivo_ok.
    awk '/^_norte_situacao_selo\(\)/{f=1} f&&/_norte_situacao_objetivo_ok/{print "WIRED"; exit} f&&/^\}/{exit}' "$_sit" 2>/dev/null | grep -q WIRED && _owired=1
    if [ -n "$_ofn" ] && [ -n "$_owired" ]; then
      emit "Objetivo confere" "OK" "_norte_situacao_objetivo_ok existe e esta encaixada no selo"
    else
      _falta=""
      [ -z "$_ofn" ] && _falta="$_falta _norte_situacao_objetivo_ok"
      [ -z "$_owired" ] && _falta="$_falta encaixe-no-selo"
      emit "Objetivo confere" "FALHA" "faltando:$_falta (reinstale/atualize o plugin)"
    fi
  else
    emit "Objetivo confere" "FALHA" "hooks/_situacao.sh ausente (reinstale/atualize o plugin)"
  fi
else emit "Objetivo confere" "NAO_VERIFICADO" "raiz do plugin nao acessivel"; fi

if [ -n "$ROOT" ]; then
  if [ -x "$ROOT/bin/nb-freio" ]; then emit "Freio de mao" "OK" "bin/nb-freio presente e executavel"
  elif [ -f "$ROOT/bin/nb-freio" ]; then emit "Freio de mao" "FALHA" "sem +x (rode: chmod +x bin/nb-freio)"
  else emit "Freio de mao" "FALHA" "bin/nb-freio ausente (reinstale/atualize o plugin)"; fi
else emit "Freio de mao" "NAO_VERIFICADO" "raiz do plugin nao acessivel"; fi

# 4. Estado gravavel
if mkdir -p "$HOME/.norte-box" ./norte-out >/dev/null 2>&1 && touch ./norte-out/.probe >/dev/null 2>&1; then
  rm -f ./norte-out/.probe >/dev/null 2>&1
  emit "Estado gravavel" "OK" "~/.norte-box + ./norte-out gravaveis"
else
  emit "Estado gravavel" "FALHA" "nao consegui escrever em ./norte-out (permissao/pasta)"
fi

# 5. git disponivel
if command -v git >/dev/null 2>&1; then
  emit "git" "OK" "$(git --version 2>/dev/null | head -1)"
else
  emit "git" "FALHA" "instale o git"
fi

# ---------------------------------------------------------------------------
# ONBOARDING (o que faltava — o doctor so via a CASCA e dizia "OK" com NADA instalado).
# STATUS extra aqui: PENDENTE = passo do onboarding ainda NAO feito. NAO e OK (nao esta ligado)
# nem FALHA (a instalacao nao esta quebrada) — e "falta voce fazer X". Assim um nao-dev entende
# se ESTA ou NAO ligado, e o doctor deixa de MENTIR "tudo OK" quando o convite/consent nao rolou.
# So checa filesystem em $HOME/.norte-box (nunca imprime conteudo de arquivo do usuario).
STATE="$HOME/.norte-box"

# 6. Convite validado? -> identity.json existe E tem ingest_token nao-vazio.
if [ -f "$STATE/identity.json" ]; then
  # extrai o ingest_token sem sourcing nem imprimir o valor (so testa se e nao-vazio).
  if command -v jq >/dev/null 2>&1; then
    HASTOK="$(jq -r 'if (.ingest_token // "") != "" then "1" else "0" end' "$STATE/identity.json" 2>/dev/null)"
  else
    grep -q '"ingest_token"[[:space:]]*:[[:space:]]*"[^"]\{1,\}"' "$STATE/identity.json" 2>/dev/null && HASTOK=1 || HASTOK=0
  fi
  if [ "$HASTOK" = "1" ]; then
    emit "Convite validado" "OK" "identity.json presente com token do convite"
  else
    emit "Convite validado" "PENDENTE" "rode /norte-box:convite (identity.json existe mas sem token — revalide)"
  fi
else
  emit "Convite validado" "PENDENTE" "rode /norte-box:convite (ainda nao validou o codigo de convite)"
fi

# 7. Consent dado / telemetria LIGADA? -> recibo consent.json + flag telemetry.enabled.
if [ -f "$STATE/consent.json" ] && [ -f "$STATE/telemetry.enabled" ]; then
  emit "Telemetria ligada" "OK" "consent.json + telemetry.enabled presentes (coleta ON)"
elif [ -f "$STATE/consent.json" ] || [ -f "$STATE/telemetry.enabled" ]; then
  emit "Telemetria ligada" "PENDENTE" "aceite incompleto — rode /norte-box:consent (falta consent.json ou a flag)"
else
  emit "Telemetria ligada" "PENDENTE" "rode /norte-box:consent (termo nao aceito — coleta DESLIGADA)"
fi

# 8. MODO (Fase 2) — reporta o modo E checa COERENCIA (o selo bate com o .env real): no privado
# nao pode haver URL de coletor no disco; no compartilhavel a URL precisa existir. Fail-closed:
# arquivo modo ausente/ilegivel -> privado.
MODO="privado"
if [ -r "$STATE/modo" ]; then
  _mv="$(head -n1 "$STATE/modo" 2>/dev/null | tr -d ' \t\r\n')"
  [ "$_mv" = "compartilhavel" ] && MODO="compartilhavel"
fi
HAS_URL=0
[ -f "$STATE/.env" ] && grep -q '^NORTE_BOX_TELEMETRY_URL=' "$STATE/.env" 2>/dev/null && HAS_URL=1
# ONBOARDING COMPLETO? = consent aceito na versao vigente do termo (mesma regra do gate real de
# envio _norte_consent_aceito). O fluxo do zero passa por: clone -> bootstrap (SEMPRE grava a URL
# no .env) -> /norte-box:doctor ANTES do convite/consent. Nesse ponto o arquivo `modo` ainda nem
# nasceu (so nasce no consent), entao o modo e privado (default) E o .env ja tem URL. Isso NAO e
# defeito: e o estado NORMAL pos-bootstrap-pre-consent. A URL no disco aqui e INOCUA — o gate
# _norte_pode_enviar exige modo compartilhavel E consent v5, entao nada envia. So depois do consent
# a regra antiga (privado + URL = incoerencia) volta a valer: ai a URL residual sinaliza que a
# reversao pra privado nao limpou (furo BAIXA #2, ja consertado no /norte-box:modo).
ONBOARDING_COMPLETO=0
_NC_VER="${NORTE_CONSENT_VERSION:-5}"
if [ -f "$STATE/consent.json" ]; then
  if command -v jq >/dev/null 2>&1; then
    jq -e --arg v "$_NC_VER" '.versao == $v' "$STATE/consent.json" >/dev/null 2>&1 && ONBOARDING_COMPLETO=1
  else
    grep -q "\"versao\"[[:space:]]*:[[:space:]]*\"${_NC_VER}\"" "$STATE/consent.json" 2>/dev/null && ONBOARDING_COMPLETO=1
  fi
fi
if [ "$MODO" = "privado" ]; then
  if [ "$HAS_URL" = 0 ]; then
    emit "Modo" "OK" "privado — a Norte NAO ve este trabalho (sem endereco de coletor no disco)"
  elif [ "$ONBOARDING_COMPLETO" = 0 ]; then
    # pos-bootstrap-pre-consent: .env com URL + modo privado e ESPERADO (a URL e inocua ate o consent).
    emit "Modo" "PENDENTE" "privado (pos-instalacao, antes do consent) — a URL no .env e inofensiva ate voce ligar; nada e enviado. Ligue com /norte-box:convite + /norte-box:consent"
  else
    # onboarding JA feito porem modo privado + URL residual = incoerencia real (a reversao nao limpou).
    emit "Modo" "FALHA" "diz privado MAS o .env ainda tem NORTE_BOX_TELEMETRY_URL — rode /norte-box:modo privado pra apagar"
  fi
else
  if [ "$HAS_URL" = 1 ]; then
    emit "Modo" "OK" "compartilhavel — a Norte melhora este trabalho (coletor configurado)"
  else
    emit "Modo" "FALHA" "diz compartilhavel MAS falta o endereco do coletor no .env — rode /norte-box:convite"
  fi
fi
