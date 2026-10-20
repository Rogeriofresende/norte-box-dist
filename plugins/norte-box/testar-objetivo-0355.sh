#!/usr/bin/env bash
# Teste do "achar o objetivo no bilhete" (0.3.55 em preparo · NRT-_997029) — roda SÓ no Mac, num
# HOME de mentira, sem o programa do fio (igual à máquina de um cliente). Nada publicado.
# Compara a 0.3.54 publicada (origin/main 8228683) com a de agora, frase por frase.
set -u
NOVO=~/norte-box-dist-nrt995031/plugins/norte-box
T=/tmp/nb0355/run-$(date +%s)
mkdir -p "$T/old" "$T/b" "$T/home"
git -C ~/norte-box-dist-nrt995031 archive 8228683 plugins/norte-box | tar -x -C "$T/old"
VELHO="$T/old/plugins/norte-box"
PASS=0; FAIL=0; N=0

acha() { # $1 caixa · $2 arquivo → frase achada ou "—"
  local f="$T/b/$N-$(basename "$1" | tr -dc a-z)-$RANDOM.md"; cp "$2" "$f"
  local s; s=$(HOME="$T/home" NORTE_BOX_PASSO=0 NORTE_OBJETIVO_FONTE=/nao/existe bash "$1/bin/nb-bilhete-objetivo" "$f")
  case "$s" in "OBJETIVO: "*) s="${s#OBJETIVO: }"; printf '%s' "${s% (copiado de:*}" ;; *) printf '—' ;; esac
}

caso() { # nome · esperado-antes · esperado-depois · conteúdo do bilhete
  N=$((N+1)); local src="$T/b/src$N.md"; printf -- "$4" > "$src"
  local a d; a=$(acha "$VELHO" "$src"); d=$(acha "$NOVO" "$src")
  local l; l=$(printf '%-40s antes=%-16s depois=%s' "$1" "$a" "$d")
  if [ "$a" = "$2" ] && [ "$d" = "$3" ]; then PASS=$((PASS+1)); echo "  OK    $l"
  else FAIL=$((FAIL+1)); echo "  FALHA $l   (esperado antes=$2 depois=$3)"; fi
}

H='---\nx: 1\n---\n'
echo "== O que o conserto pede"
caso "mesma linha: ## Objetivo: vender mais"   "—" "vender mais"  "$H## Objetivo: vender mais\n\n## Onde estamos\n- [x] a\n"
caso "molde com frase na linha: (1 frase): ..." "—" "vender mais"  "$H## Objetivo (1 frase): vender mais\n\n## Onde estamos\n"
caso "negrito: **Objetivo:** vender mais"      "—" "vender mais"  "$H**Objetivo:** vender mais\n\n## Onde estamos\n"
caso "negrito com a frase dentro"              "—" "vender mais"  "$H**Objetivo: vender mais**\n\n## Onde estamos\n"
caso "negrito e frase embaixo"                 "—" "vender mais"  "$H**Objetivo**\nvender mais\n\n## Onde estamos\n"
caso "emoji: ## 🎯 Objetivo + frase embaixo"    "—" "vender mais"  "$H## 🎯 Objetivo\nvender mais\n"
caso "emoji e mesma linha"                     "—" "vender mais"  "$H## 🎯 Objetivo — vender mais\n"
echo "== O que já funcionava (não pode piorar)"
caso "molde oficial, frase embaixo"            "vender mais" "vender mais" "$H## Objetivo (1 frase)\nvender mais\n\n## Onde estamos\n"
caso "linha em branco antes da frase"          "vender mais" "vender mais" "$H## Objetivo\n\nvender mais\n"
caso "frase em lista"                          "vender mais" "vender mais" "$H## Objetivo\n- vender mais\n"
caso "título longo: Objetivo da sessão"         "vender mais" "vender mais" "$H## Objetivo da sessão\nvender mais\n"
caso "plural: ## Objetivos"                    "vender mais" "vender mais" "$H## Objetivos\nvender mais\n"
caso "### Objetivo"                            "vender mais" "vender mais" "$H### Objetivo\nvender mais\n"
caso "objetivo: já no cabeçalho"               "vender mais" "vender mais" '---\nobjetivo: vender mais\n---\n# x\n'
caso "sem cabeçalho"                           "vender mais" "vender mais" "## Objetivo\nvender mais\n"
echo "== O que NÃO pode virar objetivo (não inventar)"
caso "seção vazia"                             "—" "—" "$H## Objetivo (1 frase)\n\n## Onde estamos\n- [x] a\n"
caso "molde vazio não vira '(1 frase)'"         "—" "—" "$H## Objetivo (1 frase)\n## Onde estamos\n"
caso "emoji com seção vazia"                   "—" "—" "$H## 🎯 Objetivo\n\n## Onde estamos\n"
caso "negrito vazio"                           "—" "—" "$H**Objetivo:**\n\n## Onde estamos\n"
caso "sem seção nenhuma"                       "—" "—" "$H# Bilhete\n## Onde estamos\n- [x] a\n"
caso "'objetivo' no meio do texto corrido"      "—" "—" "$H# Bilhete\nO objetivo do teste: medir.\n"
caso "'Meu objetivo' (fora do pedido)"          "—" "—" "$H## Meu objetivo\nvender mais\n"
caso "negrito vazio seguido de outro campo"     "—" "—" "$H**Objetivo:**\n**Responsável:** Ana\n"
caso "título dentro de exemplo de código"       "—" "—" "$H# Bilhete\n\`\`\`\n## Objetivo: exemplo\n\`\`\`\n"
caso "dois objetivos: vale o primeiro"          "—" "vender mais" "$H## Objetivo: vender mais\n## Objetivo: outro\n"
echo
echo "== Resultado: $PASS OK · $FAIL FALHA"
[ "$FAIL" = 0 ]
