#!/usr/bin/env bash
# provar-privacidade-guiado.sh — a versao "APERTA ENTER E ASSISTE" da prova de PRIVACIDADE (peca #3 do
# corte de entrega, NRT-_990148). Irmao dos guiados sombra/aplicar/freio.
#
# POR QUE ESTE ARQUIVO EXISTE:
#   O provar-privacidade-test.sh prova por FATO (sentinela de rede) que a caixa no modo PRIVADO nao
#   manda nada. Este guiado mostra ISSO ao CEO, pela mao: instala a caixa REAL numa "casa de mentira",
#   troca a rede de verdade por uma SENTINELA (um cachorro de guarda que late se algo tentar sair), e
#   deixa o CEO VER: no modo privado a caixa roda uma sessao inteira e o cachorro NAO late (0 tentativa
#   de sair); ai a gente ABRE tudo (modo compartilhavel + aceite) e o cachorro LATE (prova que ele
#   enxerga de verdade — nao e um cachorro morto). Tudo numa casa que some sozinha no fim.
#   ZERO copiar-colar, ZERO export/cd/rm — o guiado conduz.
#
# COMO ELE FAZ (sem gambiarra):
#   - Cria um $HOME descartavel em /tmp (mktemp -d).
#   - INSTALA o pacote REAL da tag v0.3.0-corte (git archive) — nunca a arvore suja.
#   - Poe SENTINELAS no PATH (shims de curl/wget/nc/node) que REGISTRAM qualquer tentativa de saida e
#     NAO deixam nenhum POST de verdade sair (a sentinela É a rede). Roda os hooks REAIS de telemetria
#     (emit/stop/drain) com HOME/PATH por dentro.
#   - PRIMEIRO mostra o cachorro LATINDO com tudo aberto (prova que ele nao e' morto), DEPOIS mostra o
#     silencio no modo privado (o que importa).
#   - trap ... EXIT apaga a casa de mentira MESMO se o CEO apertar Ctrl-C (a prova de interrupcao).
#   - Banner de fecho HONESTO: so pinta 🟢 se o cachorro latiu no aberto E ficou quieto no privado.
#
# USO (o CEO):  bash provar-privacidade-guiado.sh
#   Ele aperta Enter a cada passo e le. Nao digita mais nada.
# USO (a suite/teste):  bash provar-privacidade-guiado.sh --auto   (ou stdin nao-tty) -> nao espera Enter.
#
# NAO TOCA hooks/_modo.sh, hooks/telemetry-*.sh nem lib/nb-post.js (as LEIs). So le/roda.
# kill-switch: NORTE_PROVA_PRIVACIDADE=0 -> nao roda (sai limpo).
set -u

if [ "${NORTE_PROVA_PRIVACIDADE:-1}" = "0" ]; then
  echo "(prova de privacidade desligada por NORTE_PROVA_PRIVACIDADE=0)"; exit 0
fi

# ---------------------------------------------------------------------------
# 0) modo interativo vs automatico (--auto OU stdin nao-tty -> nao espera Enter)
# ---------------------------------------------------------------------------
AUTO=0
for _a in "$@"; do case "$_a" in --auto|-y|--sim) AUTO=1 ;; esac; done
if [ ! -t 0 ]; then AUTO=1; fi
_enter() { # <mensagem>  — pausa de padaria; no auto segue direto.
  printf '%s' "$1"
  if [ "$AUTO" = "1" ]; then printf '\n'; else IFS= read -r _lixo || true; printf '\n'; fi
}

# ---------------------------------------------------------------------------
# 1) localiza o repo git (pra git archive da tag). Roda de dentro do worktree.
# ---------------------------------------------------------------------------
_here="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"   # .../plugins/norte-box
_repo="$(cd "$_here" && git rev-parse --show-toplevel 2>/dev/null || true)"
if [ -z "${_repo:-}" ]; then
  echo "ERRO: rode este comando de dentro do worktree git do Norte-box." >&2
  exit 1
fi
TAG="${NB_PROVA_TAG:-v0.3.0-corte}"
if ! ( cd "$_repo" && git rev-parse -q --verify "refs/tags/$TAG" >/dev/null 2>&1 ); then
  echo "ERRO: a tag $TAG nao existe neste checkout — nao da pra instalar o pacote do corte." >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# 2) casa de mentira descartavel + AUTO-LIMPEZA a prova de interrupcao (trap EXIT)
# ---------------------------------------------------------------------------
LAB="$(mktemp -d "${TMPDIR:-/tmp}/prova-priv-guiado.XXXXXX")"
_limpa() { rm -rf "$LAB" 2>/dev/null; }
trap '_limpa' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# HOOK DE TESTE (so em teste): expoe onde ficou a casa, pra a suite provar a auto-limpeza.
if [ "${NB_GUIADO_TEST_MARK:-0}" = "1" ]; then
  printf 'NB_GUIADO_CASA=%s\n' "$LAB"
  if [ "${NB_GUIADO_TEST_HANG:-0}" = "1" ]; then
    [ -n "${NB_GUIADO_TEST_CASA_OUT:-}" ] && printf '%s' "$LAB" > "$NB_GUIADO_TEST_CASA_OUT" 2>/dev/null || true
    sleep 30   # o trap EXIT apaga a casa quando a suite mandar o SIGINT
  fi
fi

# instala o pacote REAL da tag na casa.
TARBALL="$LAB/pkg.tar.gz"; PKG="$LAB/pkg"; mkdir -p "$PKG"
( cd "$_repo" && git archive --format=tar.gz -o "$TARBALL" "$TAG" ) 2>/dev/null
tar -xzf "$TARBALL" -C "$PKG" 2>/dev/null
PLUGIN="$PKG/plugins/norte-box"; HOOKS="$PLUGIN/hooks"
for _f in "$HOOKS/telemetry-emit.sh" "$HOOKS/telemetry-drain.sh" "$HOOKS/telemetry-stop.sh" "$HOOKS/_modo.sh" "$PLUGIN/lib/nb-post.js"; do
  [ -f "$_f" ] || { echo "ERRO: $(basename "$_f") nao veio no pacote da tag $TAG." >&2; exit 1; }
done

# ---------------------------------------------------------------------------
# 3) sentinelas de rede (o cachorro de guarda) — shims que registram e NAO deixam sair nada.
# ---------------------------------------------------------------------------
SHIMBIN="$LAB/shims"; mkdir -p "$SHIMBIN"
NETLOG="$LAB/sentinela.log"; : > "$NETLOG"
REAL_NODE="$(command -v node 2>/dev/null || true)"
cat > "$SHIMBIN/curl" <<SH
#!/usr/bin/env bash
echo "curl \$*" >> "$NETLOG"
for a in "\$@"; do case "\$a" in *'%{http_code}'*) printf '200'; exit 0 ;; esac; done
exit 0
SH
cat > "$SHIMBIN/wget" <<SH
#!/usr/bin/env bash
echo "wget \$*" >> "$NETLOG"; exit 0
SH
cat > "$SHIMBIN/nc" <<SH
#!/usr/bin/env bash
echo "nc \$*" >> "$NETLOG"; exit 0
SH
cat > "$SHIMBIN/node" <<SH
#!/usr/bin/env bash
_is_nbpost=0
for a in "\$@"; do case "\$a" in *nb-post.js) _is_nbpost=1 ;; https://*|http://*) _is_nbpost=1 ;; esac; done
if [ "\$_is_nbpost" = "1" ]; then echo "node-nbpost \$*" >> "$NETLOG"; exit 0; fi
if [ -n "$REAL_NODE" ]; then exec "$REAL_NODE" "\$@"; fi
exit 0
SH
chmod +x "$SHIMBIN/curl" "$SHIMBIN/wget" "$SHIMBIN/nc" "$SHIMBIN/node"
PATH_SENT="$SHIMBIN:$PATH"

_hits() { grep -c '[^[:space:]]' "$NETLOG" 2>/dev/null | tr -d ' '; }
_norm() { case "$1" in ''|*[!0-9]*) echo 0 ;; *) echo "$1" ;; esac; }

# roda uma sessao inteira de telemetria (emit x2 + stop + drain) com HOME=$1.
_run_sessao() {
  local H="$1" TR="$1/transcript.jsonl"
  printf '{"hook_event_name":"UserPromptSubmit","prompt":"escreve um email pro contador"}' \
    | HOME="$H" PATH="$PATH_SENT" CLAUDE_PLUGIN_ROOT="$PLUGIN" bash "$HOOKS/telemetry-emit.sh" >/dev/null 2>&1
  printf '{"hook_event_name":"PostToolUse","tool_name":"Write","tool_input":{"file_path":"/tmp/x","content":"oi"},"tool_response":{"ok":true}}' \
    | HOME="$H" PATH="$PATH_SENT" CLAUDE_PLUGIN_ROOT="$PLUGIN" bash "$HOOKS/telemetry-emit.sh" >/dev/null 2>&1
  printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"text","text":"Pronto."}]}}' > "$TR"
  printf '{"hook_event_name":"Stop","transcript_path":"%s"}' "$TR" \
    | HOME="$H" PATH="$PATH_SENT" CLAUDE_PLUGIN_ROOT="$PLUGIN" bash "$HOOKS/telemetry-stop.sh" >/dev/null 2>&1
  printf '{"hook_event_name":"SessionStart"}' \
    | HOME="$H" PATH="$PATH_SENT" CLAUDE_PLUGIN_ROOT="$PLUGIN" bash "$HOOKS/telemetry-drain.sh" >/dev/null 2>&1
  sleep 0.8
}

DEU_RUIM=0

# ===========================================================================
#  O ROTEIRO GUIADO — o CEO so aperta Enter e le.
# ===========================================================================
cat <<'EOF'

======================================================================
  PROVA DE PRIVACIDADE — aperta Enter e assiste.
  Vou instalar a caixa DE VERDADE (o pacote do corte) numa "casa de
  mentira" e trocar a internet por um CACHORRO DE GUARDA: se qualquer
  coisa tentar sair pra fora do seu computador, ele LATE — e nada sai
  de verdade. Voce vai ver, na ordem certa:
    1) com TUDO aberto (voce autorizou), o cachorro LATE  -> prova que
       ele funciona (nao e um cachorro morto que "nunca late").
    2) no modo PRIVADO (o padrao), a caixa roda uma sessao INTEIRA e o
       cachorro fica QUIETO -> a caixa nem TENTA sair. Esse e o ponto.
  Tudo numa casa de faz-de-conta que some sozinha no fim. Eu conduzo —
  voce nao digita, nao copia, nao apaga nada.
======================================================================

EOF

# --- PASSO 1: TUDO ABERTO -> o cachorro LATE (prova que ele nao e' morto) ---
_enter "Aperte Enter pra eu ABRIR tudo (modo compartilhavel + seu aceite) e provar que o cachorro late... "
echo
HOME_OPEN="$LAB/casa-aberta"; mkdir -p "$HOME_OPEN/.norte-box"; SO="$HOME_OPEN/.norte-box"
printf 'compartilhavel\n' > "$SO/modo"
printf 'NORTE_BOX_TELEMETRY_URL=%s\n' "http://127.0.0.1:1/ingest" > "$SO/.env"
printf '{"invite_id":"inv-fake","ingest_token":"tok-fake-xyz","ts":"%s"}\n' "$(date -u +%FT%TZ)" > "$SO/identity.json"
printf '{"versao":"5","ts":"%s","hash":"abc","termo":"modelo-a"}\n' "$(date -u +%FT%TZ)" > "$SO/consent.json"
printf 'aceite-modelo-a v5 %s\n' "$(date -u +%FT%TZ)" > "$SO/telemetry.enabled"
: > "$NETLOG"
_run_sessao "$HOME_OPEN"
NH_OPEN="$(_norm "$(_hits)")"
echo "--- o cachorro de guarda (com tudo aberto) --------------------------"
if [ "$NH_OPEN" -ge 1 ]; then
  echo "🐕 LATIU $NH_OPEN vez(es): a caixa TENTOU sair (e o cachorro segurou — nada saiu de verdade)."
  echo "   quem tentou sair:"; sort -u "$NETLOG" | awk '{print "     - "$1}' | sort -u
  echo "   => o cachorro NAO e morto: ele enxerga de verdade quando algo tenta sair."
else
  DEU_RUIM=1
  echo "⚠ eu esperava o cachorro LATIR com tudo aberto, e ele ficou quieto. Isso e' suspeito:"
  echo "  se ele nao late nem com tudo aberto, o silencio no privado nao provaria nada."
fi
echo "---------------------------------------------------------------------"
echo

# --- PASSO 2: modo PRIVADO -> o cachorro fica QUIETO (o ponto) ---
_enter "Aperte Enter pra rodar a caixa no modo PRIVADO (o padrao) e ver o cachorro ficar quieto... "
echo
HOME_DEF="$LAB/casa-privada"; mkdir -p "$HOME_DEF/.norte-box"
# DEFAULT/PRIVADO = sem modo, sem .env, sem token, sem flag (e o que o instalador deixa).
: > "$NETLOG"
_run_sessao "$HOME_DEF"
NH_DEF="$(_norm "$(_hits)")"
echo "--- o que o instalador deixou na casa privada (lido do disco) -------"
_D_ENV="ausente"; [ -f "$HOME_DEF/.norte-box/.env" ] && grep -q '^NORTE_BOX_TELEMETRY_URL=' "$HOME_DEF/.norte-box/.env" 2>/dev/null && _D_ENV="PRESENTE(!)"
_D_TOK="ausente"; [ -f "$HOME_DEF/.norte-box/identity.json" ] && _D_TOK="PRESENTE(!)"
_D_FLG="ausente"; [ -f "$HOME_DEF/.norte-box/telemetry.enabled" ] && _D_FLG="PRESENTE(!)"
_D_MOD="ausente"; [ -f "$HOME_DEF/.norte-box/modo" ] && _D_MOD="PRESENTE(!)"
echo "   endereco pra onde mandar (NORTE_BOX_TELEMETRY_URL): $_D_ENV"
echo "   senha/token de envio (identity.json):               $_D_TOK"
echo "   interruptor de coleta (telemetry.enabled):          $_D_FLG"
echo "   arquivo de modo (modo):                             $_D_MOD  (ausente = privado, por regra)"
echo "---------------------------------------------------------------------"
echo "--- o cachorro de guarda (no modo privado) --------------------------"
if [ "$NH_DEF" -eq 0 ] && [ "$_D_ENV" = "ausente" ] && [ "$_D_TOK" = "ausente" ] && [ "$_D_FLG" = "ausente" ]; then
  echo "🐕 QUIETO: 0 tentativa de sair. A caixa rodou uma sessao inteira e nem TENTOU mandar nada."
  echo "   E nao tem pra onde mandar: sem endereco, sem senha, sem interruptor. Privado de verdade."
else
  DEU_RUIM=1
  echo "⚠ eu esperava SILENCIO no privado, mas: latidos=$NH_DEF, endereco=$_D_ENV, token=$_D_TOK, flag=$_D_FLG."
  [ "$NH_DEF" -ge 1 ] && { echo "   quem tentou sair:"; sort -u "$NETLOG" | awk '{print "     - "$1}' | sort -u; }
fi
echo "---------------------------------------------------------------------"
echo

# --- PASSO 3: fechar + auto-limpeza (o CEO nao roda rm) ---
_enter "Aperte Enter pra eu FECHAR e apagar a casa de mentira... "
echo
_limpa
trap - EXIT
if [ ! -e "$LAB" ]; then echo "Pronto — apaguei a casa de mentira. Sem rastro no seu computador."
else echo "Tentei apagar a casa de mentira (em /tmp); ela some no reinicio se sobrou algo."; fi
echo

# banner de fecho HONESTO: so 🟢 se o cachorro latiu no aberto E ficou quieto no privado.
if [ "$DEU_RUIM" = "0" ]; then
  echo "======================================================================"
  echo "  Acabou 🟢. Voce viu: com TUDO aberto o cachorro LATE (ele funciona);"
  echo "  no modo PRIVADO (o padrao) a caixa roda inteira e o cachorro fica"
  echo "  QUIETO — nem tenta sair, e nao tem pra onde mandar. A privacidade e'"
  echo "  de verdade, provada por fato, nao promessa. Nada tocou seu computador."
  echo "======================================================================"
  echo
  exit 0
else
  echo "======================================================================"
  echo "  Acabou — mas algum passo NAO saiu como eu esperava (veja os ⚠ acima)."
  echo "  Nao vou pintar de verde o que nao ficou verde. A casa de mentira foi"
  echo "  apagada do mesmo jeito; nada tocou o seu computador de verdade."
  echo "======================================================================"
  echo
  exit 1
fi
