#!/usr/bin/env bash
# nb-desinstalar.sh — DESINSTALA a norte-box de forma CIRURGICA e IDEMPOTENTE (NRT-_990148, peca #4
# do corte de entrega). Remove SO o que a norte-box instalou; NAO toca em NADA de terceiros.
#
# O QUE REMOVE (por assinatura INEQUIVOCA de norte-box, nunca por posicao/indice):
#   1. ~/.norte-box/                          (estado local inteiro: .env, device_id, identity.json,
#                                              consent.json, modo, telemetry-*, marketplace/, backups,
#                                              diario/situacao/correcoes... e os _ada-backup-*).
#   2. ~/.claude/plugins/cache/norte-box/     (o cache do plugin, por VERSAO).
#   3. registro do plugin no ~/.claude/settings.json E settings.local.json, com PARSER DE VERDADE:
#        - enabledPlugins["norte-box@norte-box"]        (o liga/desliga do plugin)
#        - extraKnownMarketplaces["norte-box"]          (o marketplace)
#        - .statusLine  SOMENTE se aponta pro norte-statusline da caixa (nunca a do usuario)
#        - qualquer hook inline cujo comando seja INEQUIVOCAMENTE norte-box
#          (${CLAUDE_PLUGIN_ROOT}/hooks/... OU .../plugins/cache/norte-box/... OU .norte-box/marketplace/...)
#          — cobre o caso HISTORICO de hooks DUPLICADOS: remove TODAS as copias, nao "a primeira".
#
# O QUE NUNCA TOCA: hooks/arquivos/chaves de terceiros. Os hooks PESSOAIS do CEO em
#   ~/.claude/hooks/norte-*.sh (norte-heartbeat, norte-sessao-estado...) NAO sao norte-box:
#   a palavra "norte" nao basta — a assinatura tem que ser o CAMINHO do plugin. Por isso o filtro
#   e por ASSINATURA de plugin, nunca por substring "norte".
#
# LEIS: 100% LOCAL (zero rede), bash 3.2 (macOS), FAIL-OPEN (qualquer falha ao editar um settings ->
#   ABORTA aquele arquivo e PRESERVA o original intocado; nunca deixa a maquina com JSON quebrado).
#   IDEMPOTENTE: rodar 2x nao quebra e a 2a e no-op. Parser JSON = python3 OU node (NUNCA sed/grep no JSON).
#   kill-switch: NORTE_DESINSTALAR=0 -> nao faz nada (exit 0).
#
# USO:  nb-desinstalar.sh [--home DIR] [--claude DIR] [--dry-run] [--check-limpo]
#   --home DIR     raiz do HOME a limpar (default $HOME). Pro teste E2E apontar pro sandbox.
#   --claude DIR   dir do ~/.claude (default $HOME_DIR/.claude). Idem.
#   --dry-run      mostra o que FARIA, nao escreve nada.
#   --check-limpo  NAO remove: so VERIFICA se sobrou algum rastro norte-box. exit 0 = limpo, exit 3 = sobrou.
#
# SAIDA (stdout, humano de padaria): narracao do que removeu. O JUIZ da prova NAO e esta narracao —
#   e o diff do HOME inteiro (build/provar-desinstalar-test.sh). Aqui so contamos o que fizemos.
set -u

# --- kill-switch ---
if [ "${NORTE_DESINSTALAR:-1}" = "0" ]; then
  echo "SKIP: NORTE_DESINSTALAR=0 (kill-switch) — nao removi nada."
  exit 0
fi

HOME_DIR="$HOME"
CLAUDE_DIR=""
DRY=""
CHECK_ONLY=""
while [ $# -gt 0 ]; do
  case "$1" in
    --home)    HOME_DIR="${2:-}"; shift 2 ;;
    --claude)  CLAUDE_DIR="${2:-}"; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    --check-limpo) CHECK_ONLY=1; shift ;;
    *) echo "aviso: argumento ignorado: $1" >&2; shift ;;
  esac
done
[ -n "$CLAUDE_DIR" ] || CLAUDE_DIR="$HOME_DIR/.claude"

NB_STATE="$HOME_DIR/.norte-box"
PLUGIN_CACHE="$CLAUDE_DIR/plugins/cache/norte-box"

# --- parser JSON real: python3 (preferido) OU node. NUNCA sed/grep no JSON. ---
JSON_ENGINE=""
if command -v python3 >/dev/null 2>&1; then JSON_ENGINE="python3"
elif command -v node >/dev/null 2>&1; then JSON_ENGINE="node"; fi

# ====================================================================================================
# ASSINATURA norte-box de um comando de hook. Retorna 0 (sim) se o comando e' INEQUIVOCAMENTE do plugin.
# NAO casa a palavra "norte" solta (senao mataria os hooks pessoais do CEO ~/.claude/hooks/norte-*.sh).
# ====================================================================================================
# (usado tanto pelo shell quanto injetado no parser — a fonte da verdade e a lista abaixo)
# padroes (substring): '${CLAUDE_PLUGIN_ROOT}/hooks/'  |  '/plugins/cache/norte-box/'  |  '/.norte-box/marketplace/'
# (o CLAUDE_PLUGIN_ROOT literal e sempre da caixa; o cache e o marketplace tem 'norte-box' no PROPRIO caminho)

_norte_hook_sig_py='(("${CLAUDE_PLUGIN_ROOT}/hooks/" in c) or ("/plugins/cache/norte-box/" in c) or ("/.norte-box/marketplace/" in c) or ("/norte-statusline" in c))'

# ----------------------------------------------------------------------------------------------------
# _limpa_settings <arquivo_json>  -> edita 1 settings.json/settings.local.json com parser de verdade.
#   Fluxo seguro: valida JSON -> filtra SO entradas norte-box -> valida o resultado -> backup .bak.<ts>
#   -> mv atomico. Qualquer falha ANTES do mv: aborta e preserva o original. Idempotente (no-op se nada).
#   Imprime "MUDOU <arquivo>" se removeu algo; "sem-mudanca <arquivo>" se ja estava limpo.
#   Retorna 0 sempre (fail-open: um settings problematico nao pode travar o desinstalador inteiro).
# ----------------------------------------------------------------------------------------------------
_limpa_settings() {
  _f="$1"
  [ -f "$_f" ] || { return 0; }

  if [ -z "$JSON_ENGINE" ]; then
    echo "  AVISO: sem python3 nem node — NAO mexo em $_f (fail-open; parser JSON obrigatorio)." >&2
    return 0
  fi

  # o parser roda em modo --plan (so diz se mudaria) OU --apply (edita atomico + backup).
  _mode="apply"; [ -n "$DRY" ] && _mode="plan"

  if [ "$JSON_ENGINE" = "python3" ]; then
    python3 - "$_f" "$_mode" <<'PYEOF'
import json, sys, os, time, tempfile
f, mode = sys.argv[1], sys.argv[2]
try:
    with open(f, "r") as fh:
        raw = fh.read()
    d = json.loads(raw)
except Exception as e:
    # JSON invalido ou ilegivel -> NAO mexe (fail-open). Preserva o original.
    print(f"  AVISO: {f} nao e JSON valido ({type(e).__name__}) — preservado, nada removido.", file=sys.stderr)
    sys.exit(0)

if not isinstance(d, dict):
    print(f"  AVISO: {f} nao e um objeto JSON — preservado.", file=sys.stderr)
    sys.exit(0)

def is_nb_cmd(c):
    if not isinstance(c, str):
        return False
    return (("${CLAUDE_PLUGIN_ROOT}/hooks/" in c)
            or ("/plugins/cache/norte-box/" in c)
            or ("/.norte-box/marketplace/" in c)
            or ("/norte-statusline" in c))

changed = 0

# 1) enabledPlugins["norte-box@norte-box"]
ep = d.get("enabledPlugins")
if isinstance(ep, dict) and "norte-box@norte-box" in ep:
    del ep["norte-box@norte-box"]; changed += 1

# 2) extraKnownMarketplaces["norte-box"]
ekm = d.get("extraKnownMarketplaces")
if isinstance(ekm, dict) and "norte-box" in ekm:
    del ekm["norte-box"]; changed += 1
elif isinstance(ekm, list):
    keep = [it for it in ekm if not (isinstance(it, dict) and it.get("name") == "norte-box")]
    if len(keep) != len(ekm):
        d["extraKnownMarketplaces"] = keep; changed += 1

# 3) statusLine SOMENTE se for a da caixa (aponta pro norte-statusline)
sl = d.get("statusLine")
if isinstance(sl, dict) and is_nb_cmd(sl.get("command", "")):
    del d["statusLine"]; changed += 1

# 4) hooks inline INEQUIVOCAMENTE norte-box (remove TODAS as copias — cobre duplicados)
hooks = d.get("hooks")
if isinstance(hooks, dict):
    for ev in list(hooks.keys()):
        arr = hooks[ev]
        if not isinstance(arr, list):
            continue
        new_arr = []
        for block in arr:
            if not isinstance(block, dict):
                new_arr.append(block); continue
            hs = block.get("hooks")
            if not isinstance(hs, list):
                new_arr.append(block); continue
            kept = [h for h in hs if not (isinstance(h, dict) and is_nb_cmd(h.get("command", "")))]
            removed = len(hs) - len(kept)
            if removed:
                changed += removed
            block["hooks"] = kept
            # bloco que ficou VAZIO (so tinha hooks norte-box) some tambem — nao deixa lixo estrutural
            if kept:
                new_arr.append(block)
        # evento que ficou sem nenhum bloco some (nao deixa "hooks":{"X":[]} orfao) — mas so se ESVAZIOU
        if new_arr:
            hooks[ev] = new_arr
        else:
            del hooks[ev]
    # objeto hooks que ficou vazio: some tambem (limpeza estrutural)
    if not hooks:
        del d["hooks"]

if changed == 0:
    print(f"  sem-mudanca {f}")
    sys.exit(0)

if mode == "plan":
    print(f"  [dry-run] MUDARIA {f} (removeria {changed} entrada(s) norte-box)")
    sys.exit(0)

# --- escrita ATOMICA com backup timestampado ANTES ---
# O backup vai pra FORA do HOME (NB_DESINST_BAKDIR): assim ele e' rede de seguranca do fail-open,
# mas NAO deixa rastro no HOME que o desinstalador diz ter limpado (o backup .bak dentro do
# ~/.claude seria, ele mesmo, um novo rastro no diff-do-HOME). Se o dir de backup nao der pra
# criar, cai pro backup AO LADO do arquivo (comportamento antigo) — nunca escreve sem backup.
ts = int(time.time())
bakdir = os.environ.get("NB_DESINST_BAKDIR", "")
bak = None
bak_no_tmpdir = False  # True = backup mora FORA do HOME (some no caminho feliz); False = ao-lado (persiste)
if bakdir:
    try:
        os.makedirs(bakdir, exist_ok=True)
        safe = os.path.abspath(f).replace(os.sep, "_").lstrip("_")
        bak = os.path.join(bakdir, f"{safe}.bak.{ts}")
        with open(bak, "w") as bh:
            bh.write(raw)
        bak_no_tmpdir = True
    except Exception:
        bak = None  # cai no fallback ao-lado
if bak is None:
    bak = f"{f}.nb-desinstalar.bak.{ts}"
    try:
        with open(bak, "w") as bh:
            bh.write(raw)
    except Exception as e:
        print(f"  AVISO: nao consegui backup de {f} ({type(e).__name__}) — ABORTO, original intocado.", file=sys.stderr)
        sys.exit(0)

new_text = json.dumps(d, indent=2, ensure_ascii=False) + "\n"
# valida o resultado antes de gravar (nunca grava JSON quebrado)
try:
    json.loads(new_text)
except Exception as e:
    print(f"  AVISO: resultado nao seria JSON valido ({type(e).__name__}) — ABORTO, original intocado.", file=sys.stderr)
    sys.exit(0)

try:
    dfd, tmp = tempfile.mkstemp(dir=os.path.dirname(os.path.abspath(f)), prefix=".nb-desinstalar.", suffix=".tmp")
    with os.fdopen(dfd, "w") as th:
        th.write(new_text)
    os.replace(tmp, f)  # mv atomico
except Exception as e:
    try:
        if 'tmp' in dir() and os.path.exists(tmp): os.remove(tmp)
    except Exception:
        pass
    print(f"  AVISO: falha ao gravar {f} ({type(e).__name__}) — original intocado (backup em {bak}).", file=sys.stderr)
    sys.exit(0)

# mv atomico DEU CERTO: o backup no TMPDIR ja cumpriu seu papel (era so rede do fail-open). Apaga pra
# NAO deixar copia do settings do CEO largada em /tmp ate o reboot (furo 5c). No caminho feliz: zero
# acumulo. Se falhar de apagar, so nao suja o relatorio — nao e' erro (a linha de gravacao ja passou).
# O backup ao-lado (fallback) NAO e' apagado: ali ele nasceu DENTRO do HOME e o dono decide.
if bak_no_tmpdir:
    try:
        os.remove(bak)
    except Exception:
        pass
    print(f"  MUDOU {f} (removidas {changed} entrada(s) norte-box; copia de seguranca temporaria ja apagada)")
else:
    print(f"  MUDOU {f} (removidas {changed} entrada(s) norte-box; backup {os.path.basename(bak)})")
sys.exit(0)
PYEOF
  else
    # engine node (mesma logica, sem sed/grep)
    node - "$_f" "$_mode" <<'NODEEOF'
const fs = require("fs"), path = require("path");
const f = process.argv[2], mode = process.argv[3];
let raw, d;
try { raw = fs.readFileSync(f, "utf8"); d = JSON.parse(raw); }
catch (e) { console.error(`  AVISO: ${f} nao e JSON valido (${e.name}) — preservado.`); process.exit(0); }
if (typeof d !== "object" || d === null || Array.isArray(d)) {
  console.error(`  AVISO: ${f} nao e um objeto JSON — preservado.`); process.exit(0);
}
const isNb = (c) => typeof c === "string" && (
  c.includes("${CLAUDE_PLUGIN_ROOT}/hooks/") ||
  c.includes("/plugins/cache/norte-box/") ||
  c.includes("/.norte-box/marketplace/") ||
  c.includes("/norte-statusline"));
let changed = 0;
if (d.enabledPlugins && typeof d.enabledPlugins === "object" && "norte-box@norte-box" in d.enabledPlugins) {
  delete d.enabledPlugins["norte-box@norte-box"]; changed++;
}
if (d.extraKnownMarketplaces) {
  const ekm = d.extraKnownMarketplaces;
  if (Array.isArray(ekm)) {
    const keep = ekm.filter(it => !(it && typeof it === "object" && it.name === "norte-box"));
    if (keep.length !== ekm.length) { d.extraKnownMarketplaces = keep; changed++; }
  } else if (typeof ekm === "object" && "norte-box" in ekm) {
    delete ekm["norte-box"]; changed++;
  }
}
if (d.statusLine && typeof d.statusLine === "object" && isNb(d.statusLine.command)) {
  delete d.statusLine; changed++;
}
if (d.hooks && typeof d.hooks === "object") {
  for (const ev of Object.keys(d.hooks)) {
    const arr = d.hooks[ev];
    if (!Array.isArray(arr)) continue;
    const newArr = [];
    for (const block of arr) {
      if (!block || typeof block !== "object" || !Array.isArray(block.hooks)) { newArr.push(block); continue; }
      const kept = block.hooks.filter(h => !(h && typeof h === "object" && isNb(h.command)));
      changed += block.hooks.length - kept.length;
      block.hooks = kept;
      if (kept.length) newArr.push(block);
    }
    if (newArr.length) d.hooks[ev] = newArr; else delete d.hooks[ev];
  }
  if (Object.keys(d.hooks).length === 0) delete d.hooks;
}
if (changed === 0) { console.log(`  sem-mudanca ${f}`); process.exit(0); }
if (mode === "plan") { console.log(`  [dry-run] MUDARIA ${f} (removeria ${changed} entrada(s) norte-box)`); process.exit(0); }
const ts = Math.floor(Date.now()/1000);
// backup FORA do HOME (NB_DESINST_BAKDIR) pra nao virar rastro no diff-do-HOME; fallback ao-lado.
const bakdir = process.env.NB_DESINST_BAKDIR || "";
let bak = null;
let bakNoTmpdir = false;  // true = backup FORA do HOME (some no caminho feliz); false = ao-lado (persiste)
if (bakdir) {
  try {
    fs.mkdirSync(bakdir, {recursive:true});
    const safe = path.resolve(f).split(path.sep).join("_").replace(/^_/, "");
    bak = path.join(bakdir, `${safe}.bak.${ts}`);
    fs.writeFileSync(bak, raw);
    bakNoTmpdir = true;
  } catch (e) { bak = null; }
}
if (bak === null) {
  bak = `${f}.nb-desinstalar.bak.${ts}`;
  try { fs.writeFileSync(bak, raw); }
  catch (e) { console.error(`  AVISO: nao consegui backup de ${f} (${e.name}) — ABORTO, original intocado.`); process.exit(0); }
}
const out = JSON.stringify(d, null, 2) + "\n";
try { JSON.parse(out); } catch (e) { console.error(`  AVISO: resultado nao seria JSON valido — ABORTO.`); process.exit(0); }
const tmp = path.join(path.dirname(path.resolve(f)), `.nb-desinstalar.${process.pid}.tmp`);
try { fs.writeFileSync(tmp, out); fs.renameSync(tmp, f); }
catch (e) { try { fs.existsSync(tmp) && fs.unlinkSync(tmp); } catch(_) {}
  console.error(`  AVISO: falha ao gravar ${f} (${e.name}) — original intocado (backup ${bak}).`); process.exit(0); }
// mv atomico DEU CERTO: o backup no TMPDIR ja cumpriu o papel (rede do fail-open). Apaga pra nao deixar
// copia do settings do CEO largada em /tmp (furo 5c). Caminho feliz = zero acumulo. Backup ao-lado
// (fallback DENTRO do HOME) NAO some — o dono decide.
if (bakNoTmpdir) {
  try { fs.unlinkSync(bak); } catch (_) {}
  console.log(`  MUDOU ${f} (removidas ${changed} entrada(s) norte-box; copia de seguranca temporaria ja apagada)`);
} else {
  console.log(`  MUDOU ${f} (removidas ${changed} entrada(s) norte-box; backup ${path.basename(bak)})`);
}
process.exit(0);
NODEEOF
  fi
  return 0
}

# ----------------------------------------------------------------------------------------------------
# _sobrou_settings <arquivo> -> ecoa "SOBROU" se AINDA ha rastro norte-box no JSON. Usado pelo check-limpo.
# ----------------------------------------------------------------------------------------------------
_sobrou_settings() {
  _f="$1"
  [ -f "$_f" ] || return 0
  [ -n "$JSON_ENGINE" ] || return 0
  if [ "$JSON_ENGINE" = "python3" ]; then
    python3 - "$_f" <<'PYEOF'
import json, sys
f = sys.argv[1]
try:
    d = json.load(open(f))
except Exception:
    sys.exit(0)  # ilegivel: nao afirmamos que sobrou (fail-open)
if not isinstance(d, dict): sys.exit(0)
def is_nb(c):
    return isinstance(c, str) and (("${CLAUDE_PLUGIN_ROOT}/hooks/" in c) or ("/plugins/cache/norte-box/" in c) or ("/.norte-box/marketplace/" in c) or ("/norte-statusline" in c))
found = []
ep = d.get("enabledPlugins")
if isinstance(ep, dict) and "norte-box@norte-box" in ep: found.append("enabledPlugins")
ekm = d.get("extraKnownMarketplaces")
if isinstance(ekm, dict) and "norte-box" in ekm: found.append("extraKnownMarketplaces")
if isinstance(ekm, list) and any(isinstance(it,dict) and it.get("name")=="norte-box" for it in ekm): found.append("extraKnownMarketplaces[]")
sl = d.get("statusLine")
if isinstance(sl, dict) and is_nb(sl.get("command","")): found.append("statusLine")
hooks = d.get("hooks") or {}
if isinstance(hooks, dict):
    for ev, arr in hooks.items():
        if not isinstance(arr, list): continue
        for block in arr:
            if not isinstance(block, dict): continue
            for h in (block.get("hooks") or []):
                if isinstance(h, dict) and is_nb(h.get("command","")): found.append(f"hook:{ev}")
if found:
    print("SOBROU " + f + " :: " + ",".join(sorted(set(found))))
PYEOF
  else
    node - "$_f" <<'NODEEOF'
const fs=require("fs"); const f=process.argv[2];
let d; try{ d=JSON.parse(fs.readFileSync(f,"utf8")); }catch(e){ process.exit(0); }
if(typeof d!=="object"||d===null||Array.isArray(d)) process.exit(0);
const isNb=(c)=>typeof c==="string"&&(c.includes("${CLAUDE_PLUGIN_ROOT}/hooks/")||c.includes("/plugins/cache/norte-box/")||c.includes("/.norte-box/marketplace/")||c.includes("/norte-statusline"));
const found=[];
if(d.enabledPlugins&&"norte-box@norte-box" in d.enabledPlugins) found.push("enabledPlugins");
const ekm=d.extraKnownMarketplaces;
if(ekm&&!Array.isArray(ekm)&&typeof ekm==="object"&&"norte-box" in ekm) found.push("extraKnownMarketplaces");
if(Array.isArray(ekm)&&ekm.some(it=>it&&it.name==="norte-box")) found.push("extraKnownMarketplaces[]");
if(d.statusLine&&isNb(d.statusLine.command)) found.push("statusLine");
const hooks=d.hooks||{};
for(const ev of Object.keys(hooks)){const arr=hooks[ev]; if(!Array.isArray(arr))continue;
  for(const b of arr){ if(!b||!Array.isArray(b.hooks))continue; for(const h of b.hooks){ if(h&&isNb(h.command)) found.push("hook:"+ev); }}}
if(found.length) console.log("SOBROU "+f+" :: "+[...new Set(found)].sort().join(","));
NODEEOF
  fi
}

# ----------------------------------------------------------------------------------------------------
# _bak_e_da_norte <arquivo.bak> <settings_atual_ja_limpo>
#   Decide, POR PROVA, se um ~/.claude/settings.json.bak.<epoch> foi o backup que o INSTALADOR da
#   norte-box (instalar-barrinha.sh:101 -> `cp settings settings.bak.<epoch>`) deixou pra tras.
#   PROVA (nunca chute): tira as entradas norte-box do .bak E do settings ATUAL (que ja foi limpo).
#   Se os dois batem CANONICAMENTE **e** o .bak cru continha ao menos uma entrada norte-box, entao o
#   .bak e' inequivocamente a foto do settings no momento da instalacao da norte-box -> "NORTEBOX".
#   Se NAO bate (o CEO editou depois, ou e' backup de OUTRA ferramenta) -> nada (preserva, zero risco).
#   Imprime "NORTEBOX" so no caso provado. Sem parser -> nada (fail-open: nunca afirma sem prova).
# ----------------------------------------------------------------------------------------------------
_bak_e_da_norte() {
  _bk="$1"; _cur="$2"
  [ -f "$_bk" ] || return 0
  [ -f "$_cur" ] || return 0
  [ -n "$JSON_ENGINE" ] || return 0
  if [ "$JSON_ENGINE" = "python3" ]; then
    python3 - "$_bk" "$_cur" <<'PYEOF'
import json, sys
bk, cur = sys.argv[1], sys.argv[2]
def is_nb(c):
    return isinstance(c, str) and (("${CLAUDE_PLUGIN_ROOT}/hooks/" in c) or ("/plugins/cache/norte-box/" in c) or ("/.norte-box/marketplace/" in c) or ("/norte-statusline" in c))
def strip_nb(d):
    # remove TODAS as marcas norte-box de um dict de settings; devolve (dict_limpo, tinha_norte_box?)
    had = False
    if not isinstance(d, dict): return d, had
    d = json.loads(json.dumps(d))  # copia
    ep = d.get("enabledPlugins")
    if isinstance(ep, dict) and "norte-box@norte-box" in ep:
        del ep["norte-box@norte-box"]; had = True
    ekm = d.get("extraKnownMarketplaces")
    if isinstance(ekm, dict) and "norte-box" in ekm:
        del ekm["norte-box"]; had = True
    elif isinstance(ekm, list):
        keep = [it for it in ekm if not (isinstance(it, dict) and it.get("name") == "norte-box")]
        if len(keep) != len(ekm): d["extraKnownMarketplaces"] = keep; had = True
    sl = d.get("statusLine")
    if isinstance(sl, dict) and is_nb(sl.get("command", "")):
        del d["statusLine"]; had = True
    hk = d.get("hooks")
    if isinstance(hk, dict):
        for ev in list(hk.keys()):
            arr = hk[ev]
            if not isinstance(arr, list): continue
            na = []
            for b in arr:
                if not isinstance(b, dict) or not isinstance(b.get("hooks"), list): na.append(b); continue
                kept = [h for h in b["hooks"] if not (isinstance(h, dict) and is_nb(h.get("command", "")))]
                if len(kept) != len(b["hooks"]): had = True
                b["hooks"] = kept
                if kept: na.append(b)
            if na: hk[ev] = na
            else: del hk[ev]
        if not hk: d.pop("hooks", None)
    return d, had
try:
    with open(bk) as fh: db = json.load(fh)
    with open(cur) as fh: dc = json.load(fh)
except Exception:
    sys.exit(0)  # ilegivel -> nao afirma nada (preserva)
if not isinstance(db, dict) or not isinstance(dc, dict):
    sys.exit(0)
cb, had = strip_nb(db)
cc, _ = strip_nb(dc)
def canon(x): return json.dumps(x, sort_keys=True, ensure_ascii=False, separators=(",", ":"))
# so afirma "e da norte-box" se: (1) o .bak CRU tinha marca norte-box  E  (2) tirando a norte-box dos
# dois, o resto e' IDENTICO. Isso prova que a UNICA diferenca entre o .bak e o hoje-limpo era a norte-box.
if had and canon(cb) == canon(cc):
    print("NORTEBOX")
PYEOF
  else
    node - "$_bk" "$_cur" <<'NODEEOF'
const fs=require("fs");
const bk=process.argv[2], cur=process.argv[3];
const isNb=(c)=>typeof c==="string"&&(c.includes("${CLAUDE_PLUGIN_ROOT}/hooks/")||c.includes("/plugins/cache/norte-box/")||c.includes("/.norte-box/marketplace/")||c.includes("/norte-statusline"));
function stripNb(d){
  let had=false;
  if(typeof d!=="object"||d===null||Array.isArray(d)) return [d,had];
  d=JSON.parse(JSON.stringify(d));
  if(d.enabledPlugins&&typeof d.enabledPlugins==="object"&&"norte-box@norte-box" in d.enabledPlugins){delete d.enabledPlugins["norte-box@norte-box"];had=true;}
  const ekm=d.extraKnownMarketplaces;
  if(ekm&&Array.isArray(ekm)){const keep=ekm.filter(it=>!(it&&it.name==="norte-box"));if(keep.length!==ekm.length){d.extraKnownMarketplaces=keep;had=true;}}
  else if(ekm&&typeof ekm==="object"&&"norte-box" in ekm){delete ekm["norte-box"];had=true;}
  if(d.statusLine&&typeof d.statusLine==="object"&&isNb(d.statusLine.command)){delete d.statusLine;had=true;}
  if(d.hooks&&typeof d.hooks==="object"){
    for(const ev of Object.keys(d.hooks)){const arr=d.hooks[ev];if(!Array.isArray(arr))continue;
      const na=[];for(const b of arr){if(!b||!Array.isArray(b.hooks)){na.push(b);continue;}
        const kept=b.hooks.filter(h=>!(h&&isNb(h.command)));if(kept.length!==b.hooks.length)had=true;b.hooks=kept;if(kept.length)na.push(b);}
      if(na.length)d.hooks[ev]=na;else delete d.hooks[ev];}
    if(Object.keys(d.hooks).length===0)delete d.hooks;
  }
  return [d,had];
}
let db,dc;
try{ db=JSON.parse(fs.readFileSync(bk,"utf8")); dc=JSON.parse(fs.readFileSync(cur,"utf8")); }catch(e){ process.exit(0); }
if(typeof db!=="object"||db===null||Array.isArray(db)||typeof dc!=="object"||dc===null||Array.isArray(dc)) process.exit(0);
const canon=(x)=>{const s=(o)=>{if(Array.isArray(o))return o.map(s);if(o&&typeof o==="object"){const r={};for(const k of Object.keys(o).sort())r[k]=s(o[k]);return r;}return o;};return JSON.stringify(s(x));};
const [cb,had]=stripNb(db); const [cc]=stripNb(dc);
if(had && canon(cb)===canon(cc)) console.log("NORTEBOX");
NODEEOF
  fi
}

# ====================================================================================================
# MODO --check-limpo: NAO remove. So diz se sobrou rastro. exit 0 = limpo, exit 3 = sobrou.
# ====================================================================================================
if [ -n "$CHECK_ONLY" ]; then
  sobrou=0
  msgs=""
  [ -e "$NB_STATE" ] && { sobrou=1; msgs="$msgs\n  SOBROU $NB_STATE (estado local)"; }
  [ -e "$PLUGIN_CACHE" ] && { sobrou=1; msgs="$msgs\n  SOBROU $PLUGIN_CACHE (cache do plugin)"; }
  for s in "$CLAUDE_DIR/settings.json" "$CLAUDE_DIR/settings.local.json"; do
    out="$(_sobrou_settings "$s")"
    [ -n "$out" ] && { sobrou=1; msgs="$msgs\n  $out"; }
  done
  if [ "$sobrou" -eq 0 ]; then
    echo "🟢 CHECK-LIMPO: nenhum rastro norte-box em $HOME_DIR / $CLAUDE_DIR."
    exit 0
  else
    echo "🔴 CHECK-LIMPO: AINDA HA rastro norte-box:"
    printf '%b\n' "$msgs"
    exit 3
  fi
fi

# ====================================================================================================
# MODO REMOCAO (default). Idempotente: se nada existe, no-op limpo.
# ====================================================================================================
[ -n "$DRY" ] && echo "== nb-desinstalar (DRY-RUN: nao escreve nada) ==" || echo "== nb-desinstalar =="
removeu_algo=0

# 1) ~/.norte-box/ inteiro (estado local — tudo o que a caixa grava mora aqui, inclusive backups _ada-*)
if [ -e "$NB_STATE" ]; then
  if [ -n "$DRY" ]; then
    echo "  [dry-run] REMOVERIA $NB_STATE (estado local inteiro)"
  else
    rm -rf "$NB_STATE" && echo "  removido $NB_STATE (estado local)" || echo "  AVISO: falhei ao remover $NB_STATE" >&2
  fi
  removeu_algo=1
else
  echo "  ja-limpo $NB_STATE (nao existia)"
fi

# 2) ~/.claude/plugins/cache/norte-box/ (cache do plugin por versao)
if [ -e "$PLUGIN_CACHE" ]; then
  if [ -n "$DRY" ]; then
    echo "  [dry-run] REMOVERIA $PLUGIN_CACHE (cache do plugin)"
  else
    rm -rf "$PLUGIN_CACHE" && echo "  removido $PLUGIN_CACHE (cache do plugin)" || echo "  AVISO: falhei ao remover $PLUGIN_CACHE" >&2
  fi
  removeu_algo=1
  # os diretorios-PAI (cache/, plugins/) so somem se ficaram VAZIOS — restaura o estado pre-instalacao
  # se a instalacao os criou; se tiver OUTRO plugin/config la dentro, o `rmdir` FALHA (nao remove) e a
  # gente PRESERVA. Nunca `rm -rf` num pai: rmdir e' fail-safe por natureza (so remove dir vazio).
  if [ -z "$DRY" ]; then
    for _pai in "$CLAUDE_DIR/plugins/cache" "$CLAUDE_DIR/plugins"; do
      if [ -d "$_pai" ]; then
        rmdir "$_pai" 2>/dev/null && echo "  removido $_pai (ficou vazio apos tirar o norte-box)" || true
      fi
    done
  fi
else
  echo "  ja-limpo $PLUGIN_CACHE (nao existia)"
fi

# 3) settings.json + settings.local.json (parser de verdade, backup, atomico, fail-open).
# backup FORA do HOME (rede de seguranca sem deixar rastro no HOME que dizemos ter limpado).
: "${NB_DESINST_BAKDIR:=${TMPDIR:-/tmp}/nb-desinstalar-backups}"
export NB_DESINST_BAKDIR
for s in "$CLAUDE_DIR/settings.json" "$CLAUDE_DIR/settings.local.json"; do
  _limpa_settings "$s"
done

# 4) RASTRO do instalador da barrinha: instalar-barrinha.sh:101 grava ~/.claude/settings.json.bak.<epoch>
#    DENTRO do HOME (uma copia do SEU settings) e nunca limpa. Regra sagrada: NAO apagamos backup que
#    pode ser SEU — so REPORTAMOS, e SO os que PROVAMOS ser da norte-box (o conteudo, tirando a
#    norte-box, bate byte-a-byte com o seu settings de hoje). Backup de outra ferramenta / editado
#    depois por voce NAO bate -> nem mencionamos (fica intocado, zero risco). Report-e-preserva.
if [ -z "$DRY" ]; then
  _cur_settings="$CLAUDE_DIR/settings.json"
  for _bk in "$CLAUDE_DIR"/settings.json.bak.* "$CLAUDE_DIR"/settings.local.json.bak.*; do
    [ -f "$_bk" ] || continue
    if [ "$(_bak_e_da_norte "$_bk" "$_cur_settings")" = "NORTEBOX" ]; then
      echo "  NOTA: o instalador da barrinha deixou uma copia do SEU settings em:"
      echo "        $_bk"
      echo "        (nao apaguei — e' um backup do SEU arquivo. Se nao quiser, apague voce: rm \"$_bk\")"
    fi
  done
fi

echo "== fim. o JUIZ da limpeza e o diff do HOME (build/provar-desinstalar-test.sh), nao esta narracao. =="
exit 0
