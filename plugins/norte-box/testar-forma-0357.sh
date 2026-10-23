#!/usr/bin/env bash
# Teste do "formato do bilhete sem objetivo" (0.3.57 em preparo · NRT-_998139) — roda SÓ no Mac, num HOME de
# mentira, sem a fonte de objetivo (igual à máquina de um cliente). Nada publicado, nada enviado.
# Prova: (1) cada formato vira o código certo · (2) a saída continua "SEM OBJETIVO" igual · (3) nenhum texto do
# bilhete sai · (4) o nb-passo junta o formato só se limpo e fresco · (5) bilhete COM objetivo não deixa rastro.
set -u
CX="$(cd "$(dirname "$0")" && pwd)"
T="$(mktemp -d /tmp/nb0357.XXXXXX)"
PASS=0; FAIL=0
ok() { PASS=$((PASS+1)); echo "  OK    $1"; }
ko() { FAIL=$((FAIL+1)); echo "  FALHA $1"; }

forma_de() { # $1 conteúdo → imprime a saída do conferente e o formato anotado (ou "—")
  local h; h="$(mktemp -d "$T/h.XXXX")"; local b="$h/bilhete.md"; printf -- "$1" > "$b"
  local s; s="$(HOME="$h" NORTE_BOX_PASSO=0 NORTE_OBJETIVO_FONTE=/nao/existe bash "$CX/bin/nb-bilhete-objetivo" "$b")"
  local f="—"; [ -f "$h/.norte-box/bilhete-forma" ] && f="$(cut -f2 "$h/.norte-box/bilhete-forma")"
  printf '%s\n%s' "$s" "$f"
}

caso() { # nome · esperado (trecho do formato, ou "—") · conteúdo
  local r s f; r="$(forma_de "$3")"; s="$(printf '%s' "$r" | head -1)"; f="$(printf '%s' "$r" | tail -1)"
  if [ "$2" = "—" ]; then
    case "$s" in OBJETIVO:*) [ "$f" = "—" ] && ok "$1 (achou objetivo, sem rastro)" || ko "$1 deixou rastro: $f" ;; *) ko "$1 saída: $s" ;; esac
    return
  fi
  [ "$s" = "SEM OBJETIVO" ] || { ko "$1 — saída mudou: '$s'"; return; }
  case "$f" in *"$2"*) ok "$1 → $f" ;; *) ko "$1 → $f   (esperado conter $2)" ;; esac
}

M='# Handoff — x\ndata: 2026-10-22\n\n## Onde estamos (mapa)\n- [x] a\n\n## Fatos verificados\n- b\n\n## Proximo passo (1, concreto)\nc\n\n## Cuidados\n- d\n'
echo "== Formatos que dão SEM OBJETIVO"
caso "molde sem a seção Objetivo"          "secao=ausente|palavra=nao|molde=sim" "$M"
caso "seção Objetivo vazia"                "secao=vazia"                        "## Objetivo (1 frase)\n\n$M"
caso "título diferente (Meu objetivo)"     "secao=outro_titulo"                 "## Meu objetivo\nvender\n$M"
caso "palavra solta no texto"              "secao=ausente|palavra=sim"          "$M\nO objetivo era medir.\n"
caso "topo com objetivo: vazio"            "topo=sim|obj_topo=vazia"            "---\nfio: NRT-_1\nobjetivo:\n---\n$M"
caso "topo com fio, sem fonte"             "fio=sim|fonte=nao"                  "---\nfio: NRT-_1\n---\n$M"
caso "sem molde, curto"                    "molde=nao|tamanho=curto"            "# nota\nfiz coisas\n"
echo "== Bilhete com objetivo (não pode anotar nada)"
caso "molde com objetivo"                  "—"                                  "## Objetivo (1 frase)\nvender mais\n$M"
caso "objetivo: no topo"                   "—"                                  "---\nobjetivo: vender mais\n---\n$M"

echo "== Nenhum texto do bilhete sai"
r="$(forma_de "## Senha secreta SEGREDO123 do cliente ACME\n$M\nCPF 123.456.789-00\n")"; f="$(printf '%s' "$r" | tail -1)"
printf '%s' "$f" | grep -Eqi 'segredo|acme|senha|123|cpf' && ko "formato carregou texto: $f" || ok "formato só tem rótulos fixos: $f"
printf '%s' "$f" | grep -Eq '^([a-z_]+=[a-z_]+)(\|[a-z_]+=[a-z_]+)*$' && ok "formato casa a lista permitida" || ko "formato fora da lista: $f"

echo "== nb-passo junta o formato (fila local de mentira; nada é enviado)"
P="$(mktemp -d "$T/p.XXXX")"; mkdir -p "$P/.norte-box"
printf 'compartilhavel\n' > "$P/.norte-box/modo"; printf '{"versao":"5"}' > "$P/.norte-box/consent.json"
touch "$P/.norte-box/telemetry.enabled"; printf '{"invite_id":"teste"}' > "$P/.norte-box/identity.json"
fila() { tail -1 "$P/.norte-box/telemetry-queue.jsonl" 2>/dev/null; }
passo() { HOME="$P" CLAUDE_CODE_SESSION_ID=sess-teste bash "$CX/bin/nb-passo" obrigado bilhete_com_objetivo --saida "$1"; }

printf '/x/b.md\ttopo=nao|obj_topo=ausente|secao=vazia|palavra=nao|molde=sim|tamanho=medio|fio=nao|fonte=nao\n' > "$P/.norte-box/bilhete-forma"
passo "SEM OBJETIVO"
l="$(fila)"; [ "$(printf '%s' "$l" | jq -r '.passo.forma')" = "topo=nao|obj_topo=ausente|secao=vazia|palavra=nao|molde=sim|tamanho=medio|fio=nao|fonte=nao" ] && ok "sem_objetivo leva o formato" || ko "formato não chegou: $l"
[ -f "$P/.norte-box/bilhete-forma" ] && ko "arquivo do formato não foi apagado" || ok "arquivo do formato apagado depois de usar"

printf '/x/b.md\ttopo=nao|obs=SEGREDO DO CLIENTE\n' > "$P/.norte-box/bilhete-forma"
passo "SEM OBJETIVO"; l="$(fila)"
printf '%s' "$l" | grep -qi segredo && ko "texto sujo passou: $l" || ok "formato sujo descartado (só o resultado sobe)"
[ "$(printf '%s' "$l" | jq -r '.passo.resultado')" = "sem_objetivo" ] && ok "o sem_objetivo continua contado" || ko "resultado errado: $l"

printf '/x/b.md\ttopo=nao|obj_topo=ausente|secao=vazia|palavra=nao|molde=sim|tamanho=medio|fio=nao|fonte=talvez\n' > "$P/.norte-box/bilhete-forma"
passo "SEM OBJETIVO"; l="$(fila)"
[ "$(printf '%s' "$l" | jq -r '.passo.forma // "—"')" = "—" ] && ok "valor fora da tabela fechada descartado" || ko "aceitou valor fora da tabela: $l"

printf '/x/b.md\ttopo=sim|secao=ausente\n' > "$P/.norte-box/bilhete-forma"; touch -t 202001010000 "$P/.norte-box/bilhete-forma"
passo "SEM OBJETIVO"; l="$(fila)"
[ "$(printf '%s' "$l" | jq -r '.passo.forma // "—"')" = "—" ] && ok "formato velho (>2 min) ignorado" || ko "usou formato velho: $l"

printf '/x/b.md\ttopo=sim|secao=ausente\n' > "$P/.norte-box/bilhete-forma"
passo "OBJETIVO: vender mais"; l="$(fila)"
[ "$(printf '%s' "$l" | jq -r '.passo.resultado + " " + (.passo.forma // "—")')" = "ok —" ] && ok "bilhete ok não leva formato" || ko "ok levou formato: $l"

echo "== Se a anotação falhar, nada muda pra pessoa"
h="$(mktemp -d "$T/ro.XXXX")"; printf 'x' > "$h/.norte-box"   # .norte-box vira ARQUIVO: impossível gravar o formato
printf -- "$M" > "$h/b.md"
s="$(HOME="$h" NORTE_BOX_PASSO=0 NORTE_OBJETIVO_FONTE=/nao/existe bash "$CX/bin/nb-bilhete-objetivo" "$h/b.md")"; rc=$?
[ "$s" = "SEM OBJETIVO" ] && [ "$rc" = 0 ] && ok "gravação falhou e a saída segue 'SEM OBJETIVO', código 0" || ko "saída mudou com a gravação falhando: '$s' rc=$rc"
h2="$(mktemp -d "$T/fo.XXXX")"; printf '#!/bin/sh\necho x\n' > "$h2/fonte"; chmod 644 "$h2/fonte"; printf -- "---\nfio: NRT-_1\n---\n$M" > "$h2/b.md"
HOME="$h2" NORTE_BOX_PASSO=0 NORTE_OBJETIVO_FONTE="$h2/fonte" bash "$CX/bin/nb-bilhete-objetivo" "$h2/b.md" >/dev/null
grep -q 'fonte=ilegivel' "$h2/.norte-box/bilhete-forma" && ok "fonte que existe mas não roda = ilegivel" || ko "fonte ilegível não marcada: $(cat "$h2/.norte-box/bilhete-forma" 2>/dev/null)"

echo "== Motivo do erro (0.3.58) — lista fechada, a saída não muda"
mot() { # nome · esperado · conteúdo · env extra
  local h; h="$(mktemp -d "$T/m.XXXX")"; printf -- "$3" > "$h/b.md"
  local s; s="$(env "$4" HOME="$h" NORTE_BOX_PASSO=0 NORTE_OBJETIVO_FONTE=/nao/existe bash "$CX/bin/nb-bilhete-objetivo" "$h/b.md")"
  local m="—"; [ -f "$h/.norte-box/bilhete-motivo" ] && m="$(cut -f2 "$h/.norte-box/bilhete-motivo")"
  [ "$m" = "$2" ] && ok "$1 → $m (saída: $s)" || ko "$1 → $m (esperado $2; saída: $s)"
}
SEMPY="$(printf '%s' "$PATH" | tr ':' '\n' | grep -v -i -e python -e conda -e homebrew -e '/usr/bin' -e '/usr/local/bin' | tr '\n' ':'):/usr/bin:/bin"
ST="$(mktemp -d "$T/st.XXXX")"; printf '#!/bin/bash\necho "Python was not found" >&2\nexit 49\n' > "$ST/python3"; chmod +x "$ST/python3"
command -v python3 >/dev/null 2>&1 && PYR="$(command -v python3)"
for c in python py; do cp "$ST/python3" "$ST/$c"; done
BASE="$(mktemp -d "$T/base.XXXX")"; for c in bash env mkdir cut printf cat dirname basename find rm mv cp tr head sed grep jq date; do p="$(command -v "$c" 2>/dev/null)"; [ -n "$p" ] && [ -x "$p" ] && ln -sf "$p" "$BASE/$c"; done
REAL3="$(command -v python3)"
SO_PY="$(mktemp -d "$T/sp.XXXX")"; printf '#!/bin/bash\nexec "%s" "$@"\n' "$REAL3" > "$SO_PY/python"; chmod +x "$SO_PY/python"
STO="$(mktemp -d "$T/sto.XXXX")"; cp "$ST/python3" "$STO/python3"
mot "só atalhos que não rodam (Store)" "motivo=python_nao_roda" "## Objetivo\nvender\n" "PATH=$ST:$BASE"
mot "nenhum python"                    "motivo=sem_python"      "## Objetivo\nvender\n" "PATH=$BASE"
mot "Store no python3 + python ok → acha" "—"                 "## Objetivo\nvender\n" "PATH=$STO:$SO_PY:$BASE"
mot "emoji com tela ascii → não quebra" "—"                     "## 🎯 Objetivo: fechar → enviar\n" "PYTHONIOENCODING=ascii"
mot "bilhete normal não anota"     "—"                       "## Objetivo\nvender\n" "X=1"
mot "bilhete ilegível (bytes ruins)" "motivo=erro_ler"       "## Objetivo\n\xff\xfe\xfa\n" "X=1"
P2="$(mktemp -d "$T/p2.XXXX")"; mkdir -p "$P2/.norte-box"
printf 'compartilhavel\n' > "$P2/.norte-box/modo"; printf '{"versao":"5"}' > "$P2/.norte-box/consent.json"
touch "$P2/.norte-box/telemetry.enabled"; printf '{"invite_id":"teste"}' > "$P2/.norte-box/identity.json"
printf '/x/b.md\tmotivo=python_nao_roda\n' > "$P2/.norte-box/bilhete-motivo"
HOME="$P2" CLAUDE_CODE_SESSION_ID=s2 bash "$CX/bin/nb-passo" obrigado bilhete_com_objetivo --saida "SEM OBJETIVO (erro)"
l="$(tail -1 "$P2/.norte-box/telemetry-queue.jsonl")"
[ "$(printf '%s' "$l" | jq -r '.passo.resultado + " " + .passo.motivo')" = "falhou python_nao_roda" ] && ok "falhou leva o motivo" || ko "motivo não chegou: $l"
printf '/x/b.md\tmotivo=SEGREDO\n' > "$P2/.norte-box/bilhete-motivo"
HOME="$P2" CLAUDE_CODE_SESSION_ID=s2 bash "$CX/bin/nb-passo" obrigado bilhete_com_objetivo --saida "SEM OBJETIVO (erro)"
l="$(tail -1 "$P2/.norte-box/telemetry-queue.jsonl")"
printf '%s' "$l" | grep -qi segredo && ko "motivo fora da lista passou: $l" || ok "motivo fora da lista descartado"

echo
echo "== Resultado: $PASS OK · $FAIL FALHA"
[ "$FAIL" = 0 ]
