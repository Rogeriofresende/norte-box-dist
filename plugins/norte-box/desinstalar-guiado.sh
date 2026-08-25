#!/usr/bin/env bash
# desinstalar-guiado.sh — a versao "APERTA ENTER E ASSISTE" do DESINSTALAR (peca #4 do corte de
# entrega, NRT-_990148). Irmao dos guiados sombra/aplicar/freio/privacidade.
#
# POR QUE ESTE ARQUIVO EXISTE:
#   O provar-desinstalar-test.sh prova por FATO (diff do HOME inteiro) que o desinstalador deixa a
#   maquina como estava ANTES de instalar. Este guiado mostra ISSO ao CEO, pela mao, numa CASA DE
#   MENTIRA descartavel: instala a norte-box REAL (pacote da tag), tira um RETRATO do "antes",
#   desinstala de verdade, tira o retrato do "depois" e mostra que os dois batem — ZERO rastro E
#   ZERO coisa de terceiro apagada. Tudo numa casa que some sozinha no fim. ZERO copiar-colar.
#   Nunca toca o ~/.claude nem o ~/.norte-box REAIS do CEO — so a casa de mentira.
#
# COMO ELE FAZ (sem gambiarra):
#   - Cria um $HOME descartavel em /tmp (mktemp -d), com um "inquilino inocente" plantado
#     (um settings do usuario + outro plugin no cache) pra o CEO VER que isso NAO some.
#   - INSTALA o footprint da norte-box derivado do pacote REAL da tag (git archive) — nunca a arvore suja.
#   - Roda o nb-desinstalar.sh REAL (o mesmo binario do /norte-box:desinstalar).
#   - LE O DISCO antes e depois e mostra que o retrato bateu (o juiz e o diff, nao a narracao).
#   - trap ... EXIT apaga a casa de mentira MESMO se o CEO apertar Ctrl-C.
#   - Banner de fecho HONESTO: so pinta 🟢 se o diff do HOME der VAZIO de verdade (norte-box saiu
#     inteira E o inquilino sobreviveu byte-identico).
#
# USO (o CEO):  bash desinstalar-guiado.sh      (aperta Enter a cada passo e le)
# USO (a suite):  bash desinstalar-guiado.sh --auto   (ou stdin nao-tty) -> nao espera Enter.
#
# NAO TOCA bin/nb-desinstalar.sh (a LEI). So o roda. kill-switch: NORTE_DESINSTALAR=0 -> nao roda.
set -u

if [ "${NORTE_DESINSTALAR:-1}" = "0" ]; then
  echo "(desinstalar desligado por NORTE_DESINSTALAR=0)"; exit 0
fi

# ---------------------------------------------------------------------------
# 0) modo interativo vs automatico (--auto OU stdin nao-tty -> nao espera Enter)
# ---------------------------------------------------------------------------
AUTO=0
for _a in "$@"; do case "$_a" in --auto|-y|--sim) AUTO=1 ;; esac; done
if [ ! -t 0 ]; then AUTO=1; fi
_enter() { printf '%s' "$1"; if [ "$AUTO" = "1" ]; then printf '\n'; else IFS= read -r _lixo || true; printf '\n'; fi; }

# ---------------------------------------------------------------------------
# 1) localiza o repo git (pra git archive da tag) + o binario REAL do desinstalador
# ---------------------------------------------------------------------------
_here="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"   # .../plugins/norte-box
_repo="$(cd "$_here" && git rev-parse --show-toplevel 2>/dev/null || true)"
if [ -z "${_repo:-}" ]; then
  echo "ERRO: rode este comando de dentro do worktree git do Norte-box." >&2
  exit 1
fi
TAG="${NB_DESINST_TAG:-v0.3.0-corte}"
if ! ( cd "$_repo" && git rev-parse -q --verify "refs/tags/$TAG" >/dev/null 2>&1 ); then
  echo "ERRO: a tag $TAG nao existe neste checkout — nao da pra instalar o pacote do corte." >&2
  exit 1
fi
UNINST="$_here/bin/nb-desinstalar.sh"
[ -f "$UNINST" ] || { echo "ERRO: nao achei o bin/nb-desinstalar.sh." >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "ERRO: preciso do python3 pra parsear o settings com seguranca." >&2; exit 1; }

# ---------------------------------------------------------------------------
# 2) casa de mentira descartavel + AUTO-LIMPEZA a prova de interrupcao (trap EXIT)
# ---------------------------------------------------------------------------
LAB="$(mktemp -d "${TMPDIR:-/tmp}/desinst-guiado.XXXXXX")"
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

FAKE_HOME="$LAB/home"
mkdir -p "$FAKE_HOME/.claude"

# hash portatil + retrato (settings JSON = hash canonico; resto = byte)
_sha() { if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" 2>/dev/null | awk '{print $1}';
         elif command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" 2>/dev/null | awk '{print $1}';
         else echo "NOHASH"; fi; }
_sha_json_canon() {
  python3 - "$1" <<'PYEOF' 2>/dev/null
import json,sys,hashlib
try: d=json.load(open(sys.argv[1]))
except Exception: sys.exit(3)
print(hashlib.sha256(json.dumps(d,sort_keys=True,ensure_ascii=False,separators=(",",":")).encode()).hexdigest())
PYEOF
}
_retrato() {
  ( cd "$1" 2>/dev/null || exit 0
    find . \( -type d -o -type f -o -type l \) 2>/dev/null | LC_ALL=C sort | while IFS= read -r p; do
      if [ -L "$p" ]; then printf 'l\t%s\t-> %s\n' "$p" "$(readlink "$p" 2>/dev/null)"
      elif [ -d "$p" ]; then printf 'd\t%s\t\n' "$p"
      else case "$p" in
             */settings.json|*/settings.local.json)
               _c="$(_sha_json_canon "$p")"; if [ -n "$_c" ]; then printf 'f\t%s\tJSON:%s\n' "$p" "$_c"; else printf 'f\t%s\t%s\n' "$p" "$(_sha "$p")"; fi ;;
             *) printf 'f\t%s\t%s\n' "$p" "$(_sha "$p")" ;;
           esac
      fi
    done ) > "$2"
}

echo
echo "======================================================================"
echo "  DESINSTALAR — teste na mao (casa de mentira, o seu computador nao e' tocado)"
echo "======================================================================"
echo "  Vou montar um computador DE MENTIRA aqui do lado, instalar a norte-box"
echo "  nele de verdade, e depois desinstalar — pra voce VER que a caixa sai"
echo "  inteira e NADA seu (outros programas, suas config) e' apagado junto."
echo

# ---------------------------------------------------------------------------
# PASSO 1: o "antes de instalar" — coisas do usuario que TEM que sobreviver
# ---------------------------------------------------------------------------
_enter "Aperte Enter pra eu montar o computador de mentira (com coisas SUAS ja nele)... "
python3 - "$FAKE_HOME/.claude/settings.json" <<'PYEOF'
import json,sys
d={"model":"opus","theme":"dark",
   "enabledPlugins":{"superpowers@superpowers-marketplace":True},
   "extraKnownMarketplaces":{"superpowers-marketplace":{"source":{"source":"github","repo":"obra/superpowers-marketplace"}}}}
json.dump(d, open(sys.argv[1],"w"), indent=2)
PYEOF
mkdir -p "$FAKE_HOME/.claude/plugins/cache/superpowers/superpowers/2.0.0"
printf 'plugin de terceiro que JA estava aqui\n' > "$FAKE_HOME/.claude/plugins/cache/superpowers/superpowers/2.0.0/SKILL.md"
mkdir -p "$FAKE_HOME/Documentos"; printf 'um arquivo pessoal qualquer\n' > "$FAKE_HOME/Documentos/meu.txt"
_RET_PRE="$LAB/ret_pre.txt"; _retrato "$FAKE_HOME" "$_RET_PRE"
echo "   Pronto. No computador de mentira ja tem (isso e' SEU, nao e' da norte-box):"
echo "     - suas configuracoes (settings.json) + OUTRO plugin instalado"
echo "     - um arquivo pessoal (Documentos/meu.txt)"
echo "   Tirei uma FOTO de tudo isso (o 'antes'). No fim eu comparo."
echo

# ---------------------------------------------------------------------------
# PASSO 2: instala a norte-box REAL (footprint derivado do pacote da tag)
# ---------------------------------------------------------------------------
_enter "Aperte Enter pra eu INSTALAR a norte-box no computador de mentira... "
TARBALL="$LAB/pkg.tar.gz"
( cd "$_repo" && git archive --format=tar.gz -o "$TARBALL" "$TAG" ) 2>/dev/null
_VER="$(python3 -c "import json,tarfile,io;t=tarfile.open('$TARBALL');f=t.extractfile('plugins/norte-box/.claude-plugin/plugin.json');print(json.load(f)['version'])" 2>/dev/null)"
[ -n "$_VER" ] || _VER="0.0.0"
mkdir -p "$FAKE_HOME/.norte-box" "$FAKE_HOME/.claude/plugins/cache/norte-box/norte-box/$_VER"
tar -xzf "$TARBALL" -C "$FAKE_HOME/.claude/plugins/cache/norte-box/norte-box/$_VER" 2>/dev/null
# ~/.norte-box (arquivos REAIS que convite/bootstrap/telemetria criam — conteudo fake, nunca token real)
printf 'NORTE_BOX_TELEMETRY_URL=https://COLETOR-EXEMPLO.invalido/ingest\n' > "$FAKE_HOME/.norte-box/.env"; chmod 600 "$FAKE_HOME/.norte-box/.env" 2>/dev/null || true
echo "deadbeefcafef00d0011223344556677" > "$FAKE_HOME/.norte-box/device_id"
printf '{"invite_id":"nb-exemplo","label":"teste","ingest_token":"FAKE","ts":"2026-01-01T00:00:00Z"}\n' > "$FAKE_HOME/.norte-box/identity.json"
printf '{"versao":"v5","aceito":true}\n' > "$FAKE_HOME/.norte-box/consent.json"
printf 'privado\n' > "$FAKE_HOME/.norte-box/modo"
printf '{"evento":"exemplo","n":1}\n' > "$FAKE_HOME/.norte-box/telemetry-queue.jsonl"
printf '1\n' > "$FAKE_HOME/.norte-box/telemetry.enabled"
mkdir -p "$FAKE_HOME/.norte-box/marketplace/plugins/norte-box"; printf 'clone-exemplo\n' > "$FAKE_HOME/.norte-box/marketplace/README.md"
# registro no settings (mesclado, como o install real faz)
python3 - "$FAKE_HOME/.claude/settings.json" <<'PYEOF'
import json,sys
f=sys.argv[1]
try: d=json.load(open(f))
except Exception: d={}
d.setdefault("enabledPlugins",{})["norte-box@norte-box"]=True
d.setdefault("extraKnownMarketplaces",{})["norte-box"]={"source":{"source":"github","repo":"Rogeriofresende/norte-box-dist"}}
json.dump(d,open(f,"w"),indent=2)
PYEOF
echo "   Instalei. Agora o computador de mentira tem, ALEM do que era seu:"
echo "     - ~/.norte-box/ (o estado da caixa: .env, identity, modo, fila...)"
echo "     - ~/.claude/plugins/cache/norte-box/norte-box/$_VER/ (o plugin)"
echo "     - a caixa registrada no settings.json (enabledPlugins + marketplace)"
echo

# ---------------------------------------------------------------------------
# PASSO 3: desinstala DE VERDADE (o mesmo binario do /norte-box:desinstalar)
# ---------------------------------------------------------------------------
_enter "Aperte Enter pra eu DESINSTALAR (rodando o desinstalador de verdade)... "
echo "--- o que o desinstalador diz que fez (isso e' so relato; o juiz vem depois) ---"
# _friendly: troca o caminho cru da casa de mentira (/var/folders/.../home) por "~" na saida que o CEO
# ve — o CEO nao precisa ver o /tmp; ele quer ver "removido ~/.norte-box". So cosmetico; o motor
# trabalhou no caminho real. Tambem esconde o nome comprido do arquivo de backup (fora do HOME).
_friendly() { sed -e "s#$FAKE_HOME#~#g" -e "s#$LAB#~#g" -e 's#backup [^)]*#backup guardado fora do HOME#g'; }
NORTE_DESINSTALAR=1 bash "$UNINST" --home "$FAKE_HOME" 2>&1 | _friendly | sed 's/^/   /'
echo "-------------------------------------------------------------------------------"
echo

# ---------------------------------------------------------------------------
# PASSO 4: o JUIZ — le o disco e compara a FOTO do antes com o depois
# ---------------------------------------------------------------------------
_enter "Aperte Enter pra eu CONFERIR (comparo a foto do 'antes' com o 'depois')... "
_RET_POS="$LAB/ret_pos.txt"; _retrato "$FAKE_HOME" "$_RET_POS"
DEU_RUIM=0
if diff -u "$_RET_PRE" "$_RET_POS" > "$LAB/diff.txt" 2>&1; then
  echo "🟢 A foto do 'depois' e' IDENTICA a do 'antes'. Ou seja:"
  echo "   - a norte-box saiu INTEIRA (nao sobrou rastro dela)"
  echo "   - e NADA seu foi apagado junto (suas config e o outro plugin continuam la)"
else
  DEU_RUIM=1
  echo "⚠ A foto mudou — ou sobrou rastro da norte-box, ou algo SEU foi mexido. Veja:"
  sed 's/^/     /' "$LAB/diff.txt" | head -30
fi
echo
echo "--- conferindo no disco, item por item -------------------------------"
_c1="ainda existe(!)"; [ -e "$FAKE_HOME/.norte-box" ] || _c1="removido ✓"
_c2="ainda existe(!)"; [ -e "$FAKE_HOME/.claude/plugins/cache/norte-box" ] || _c2="removido ✓"
_c3="SUMIU(!)"; [ -f "$FAKE_HOME/.claude/plugins/cache/superpowers/superpowers/2.0.0/SKILL.md" ] && _c3="intacto ✓ (terceiro preservado)"
_c4="SUMIU(!)"; [ -f "$FAKE_HOME/Documentos/meu.txt" ] && _c4="intacto ✓ (seu arquivo preservado)"
_c5="ainda registrada(!)"; python3 -c "import json,sys;d=json.load(open('$FAKE_HOME/.claude/settings.json'));sys.exit(0 if 'norte-box@norte-box' in d.get('enabledPlugins',{}) else 1)" 2>/dev/null || _c5="tirada do settings ✓"
_c6="SUMIU(!)"; python3 -c "import json,sys;d=json.load(open('$FAKE_HOME/.claude/settings.json'));sys.exit(0 if 'superpowers@superpowers-marketplace' in d.get('enabledPlugins',{}) else 1)" 2>/dev/null && _c6="intacto ✓ (outro plugin preservado)"
echo "   estado ~/.norte-box ..................... $_c1"
echo "   cache do plugin norte-box ............... $_c2"
echo "   plugin de terceiro (SKILL.md) ........... $_c3"
echo "   seu arquivo pessoal ..................... $_c4"
echo "   norte-box no settings.json .............. $_c5"
echo "   outro plugin no settings.json ........... $_c6"
echo "----------------------------------------------------------------------"
case "$_c1$_c2$_c3$_c4$_c5$_c6" in *"(!)"*) DEU_RUIM=1 ;; esac
echo

# check-limpo do proprio desinstalador como segunda opiniao. Captura a saida E o exit code SEM deixar o
# pipe pro sed roubar o codigo (senao o `if` testaria o sed, nao o desinstalador). Saida saneada (~).
echo "--- segunda opiniao: o desinstalador se auto-confere (--check-limpo) ---"
_ck_out="$(NORTE_DESINSTALAR=1 bash "$UNINST" --home "$FAKE_HOME" --check-limpo 2>&1)"; _ck_rc=$?
printf '%s\n' "$_ck_out" | _friendly | sed 's/^/   /'
if [ "$_ck_rc" = "0" ]; then
  echo "   (check-limpo: VERDE)"
else
  DEU_RUIM=1; echo "   (check-limpo: VERMELHO — sobrou rastro)"
fi
echo

# ---------------------------------------------------------------------------
# PASSO 5: fechar + auto-limpeza (o CEO nao roda rm)
# ---------------------------------------------------------------------------
_enter "Aperte Enter pra eu FECHAR e apagar o computador de mentira... "
echo
_limpa; trap - EXIT
if [ ! -e "$LAB" ]; then echo "Pronto — apaguei a casa de mentira. Sem rastro no seu computador de verdade."
else echo "Tentei apagar a casa de mentira (em /tmp); ela some no reinicio se sobrou algo."; fi
echo

# banner de fecho HONESTO: so 🟢 se o diff do HOME deu VAZIO de verdade.
if [ "$DEU_RUIM" = "0" ]; then
  echo "======================================================================"
  echo "  Acabou 🟢. Voce viu, pela mao: a norte-box saiu INTEIRA (sem rastro)"
  echo "  e NADA seu foi apagado junto — o computador de mentira voltou a ficar"
  echo "  IDENTICO ao que era antes de instalar. E o seu computador de verdade"
  echo "  nunca foi tocado (tudo rodou numa casa de mentira que ja apaguei)."
  echo
  echo "  Detalhes de higiene (o que fizemos com as copias de seguranca):"
  echo "   - a copia de seguranca temporaria do seu settings (feita so por garantia"
  echo "     durante a limpeza) foi APAGADA no fim — nada largado no /tmp."
  echo "   - se o instalador da barrinha tinha deixado um backup do SEU settings"
  echo "     dentro do ~/.claude, eu NAO apago (e' SEU) — so te AVISO onde esta,"
  echo "     pra voce apagar se quiser. Backup de terceiro nem e' tocado."
  echo "======================================================================"
  echo
  exit 0
else
  echo "======================================================================"
  echo "  Acabou — mas algo NAO ficou como eu esperava (veja os ⚠/(!) acima)."
  echo "  Nao vou pintar de verde o que nao ficou verde. A casa de mentira foi"
  echo "  apagada do mesmo jeito; o seu computador de verdade nao foi tocado."
  echo "======================================================================"
  echo
  exit 1
fi
