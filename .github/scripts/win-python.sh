#!/usr/bin/env bash
# Prova Windows do achador único de Python (0.3.58 · NRT-_998309). Roda no Git Bash de uma máquina Windows real.
# Parte A: o achador (bin/nb-python) nos 7 cenários de Python instalado.
# Parte B: cada lugar da caixa que chama Python, ANTES (main) × DEPOIS (esta branch), nos cenários que quebravam.
# Não publica nada, não lê segredo. Sai 1 se algum caso do DEPOIS der errado.
set -u
R="$PWD/plugins/norte-box"
T="$(mktemp -d)"
FALHAS=0
ok()  { printf '  OK    %s\n' "$1"; }
nok() { printf '  FALHA %s\n' "$1"; FALHAS=$((FALHAS+1)); }

# ANTES = a caixa publicada (main), inteira, pra comparar
mkdir -p "$T/antes"; git archive origin/main plugins/norte-box | tar -x -C "$T/antes"
A="$T/antes/plugins/norte-box"

# ---- cenários de PATH (iguais aos do win-objetivo) ----
if [ -n "${NB_TESTE_MAC:-}" ]; then LOJA=/nao; else LOJA="$(cygpath -u "$LOCALAPPDATA")/Microsoft/WindowsApps"; fi
BASE="$(printf '%s' "$PATH" | tr ':' '\n' | grep -vi -e python -e windowsapps | grep -vix '/c/windows' | tr '\n' ':')"
mkdir -p "$T/sopy" "$T/sopyl"
printf '#!/bin/bash\nexec "%s" "$@"\n' "$(command -v python)" > "$T/sopy/python"; chmod +x "$T/sopy/python"
printf '#!/bin/bash\nexec /c/Windows/py "$@"\n' > "$T/sopyl/py"; chmod +x "$T/sopyl/py"
declare -a NOMES=("1 tudo instalado" "2 tela cp1252" "3 so python" "4 site oficial + atalho da Store" "5 so py" "6 so atalho da Store" "7 nenhum Python")
declare -a PATHS=("$PATH" "$PATH" "$T/sopy:$BASE" "$LOJA:$T/sopy:$T/sopyl:$BASE" "$T/sopyl:$BASE" "$LOJA:$BASE" "$BASE")
declare -a TEMPY=(1 1 1 1 1 0 0)
declare -a EXTRA=("X=1" "PYTHONIOENCODING=cp1252" "X=1" "X=1" "X=1" "X=1" "X=1")

echo "== A. achador (bin/nb-python) nos 7 cenários"
for i in 0 1 2 3 4 5 6; do
  P="${PATHS[$i]}"; E="${EXTRA[$i]}"
  env "PATH=$P" "$E" bash "$R/bin/nb-python" --acha; rc=$?
  out="$(env "PATH=$P" "$E" bash "$R/bin/nb-python" -c 'import sys; print("🎯 seta → ok", sys.argv[1])' "ação" 2>/dev/null)"
  onde="$(env "PATH=$P" "$E" bash "$R/bin/nb-python" --onde 2>/dev/null)"
  if [ "${TEMPY[$i]}" = 1 ]; then
    [ "$rc" = 0 ] && [ "$out" = "🎯 seta → ok ação" ] && [ -n "$onde" ] && "$onde" -c 'import sys' 2>/dev/null \
      && ok "${NOMES[$i]}: achou, rodou com emoji, --onde=$onde" || nok "${NOMES[$i]}: rc=$rc out='$out' onde='$onde'"
  else
    [ "$rc" != 0 ] && [ -z "$out" ] && ok "${NOMES[$i]}: diz que não tem (rc=$rc) e não imprime lixo" || nok "${NOMES[$i]}: rc=$rc out='$out'"
  fi
  env "PATH=$P" "$E" bash "$R/bin/nb-python" -c 'import sys; sys.exit(7)' 2>/dev/null; rc7=$?
  [ "${TEMPY[$i]}" = 1 ] && { [ "$rc7" = 7 ] && ok "${NOMES[$i]}: código de saída repassado (7)" || nok "${NOMES[$i]}: código $rc7 ≠ 7"; }
done
env "PATH=${PATHS[3]}" NORTE_ACHA_PYTHON=0 bash "$R/bin/nb-python" --acha; [ $? = 0 ] && ok "desligador: volta ao python3 puro (atalho da Store conta como 'tem', igual antes)" || nok "desligador"

echo; echo "== B. cada lugar da caixa · ANTES × DEPOIS (cenários 3, 4, 5 = quebravam · 7 = sem Python)"
# fixtures
fx() { # pasta nova com 2 bilhetes do mesmo assunto + ULTIMO copia antiga
  local d="$1"; mkdir -p "$d/handoffs"
  printf -- '---\nobjetivo: vender mais\n---\n# a\n' > "$d/handoffs/assunto-20261022-1000.md"
  printf -- '---\nobjetivo: vender mais\n---\n# b\n' > "$d/handoffs/assunto-20261022-1100.md"
  touch -d '2026-10-22T10:00:00' "$d/handoffs/assunto-20261022-1000.md"; touch -d '2026-10-22T11:00:00' "$d/handoffs/assunto-20261022-1100.md"
  cp "$d/handoffs/assunto-20261022-1000.md" "$d/handoffs/ULTIMO.md"
}
caso() { # rotulo · versão(raiz) · índice cenário  → imprime o resultado curto do lugar
  local rot="$1" V="$2" i="$3" P="${PATHS[$3]}" d="$T/w-$1-$(basename "$(dirname "$V")")-$3" s=""
  rm -rf "$d"; fx "$d"; local H="$d/home"; mkdir -p "$H"
  case "$rot" in
    retomar-alvo)  s="$(env "PATH=$P" HOME="$H" NORTE_BOX_PASSO=0 bash "$V/bin/nb-retomar-alvo" "$d" 999999999 2>/dev/null | head -1)"; s="${s%% /*}${s:+ $(basename "${s#* }")}" ;;
    unificar)      cp "$d/handoffs/assunto-20261022-1100.md" "$d/solto.md"; mkdir -p "$d/proj"
                   s="$(env "PATH=$P" HOME="$H" bash "$V/bin/nb-bilhete-unificar" "$d/solto.md" "$d/proj" 2>/dev/null)"; [ -f "$d/proj/handoffs/solto.md" ] && s="moveu pro projeto" || s="não moveu ($s)" ;;
    ponteiro)      env "PATH=$P" HOME="$H" bash "$V/bin/nb-ponteiro-reaponta" "$d/handoffs/assunto-20261022-1100.md"
                   grep -q '# b' "$d/handoffs/ULTIMO.md" && s="ULTIMO aponta pro novo" || s="ULTIMO ficou no velho" ;;
    mark-adota)    s="$(env "PATH=$P" HOME="$H" NRT_REGISTRY_PATH=/nao/existe bash "$V/bin/nb-mark-adota" "$d/handoffs/assunto-20261022-1100.md" 2>&1 | head -1 | cut -c1-60)" ;;
    passo)         env "PATH=$P" HOME="$H" bash "$V/bin/nb-passo" continuar ponteiro --confere "$d/handoffs/ULTIMO.md" "$d/handoffs/assunto-20261022-1000.md" >/dev/null 2>&1; s="saiu $?" ;;
    desinstalar)   mkdir -p "$H/.claude"; printf '{"enabledPlugins":{"norte@norte-box":true,"outro@x":true}}\n' > "$H/.claude/settings.json"
                   s="$(env "PATH=$P" HOME="$H" bash "$V/bin/nb-desinstalar.sh" --home "$H" --dry-run 2>&1 | grep -m1 -iE 'sem python3 nem node|removeria|REMOVERIA|ja-limpo|desligaria|tiraria' | cut -c1-60)"; [ -n "$s" ] || s="(sem linha reconhecida)" ;;
    provar)        s="$(env "PATH=$P" bash -c '. "$1/hooks/_provar.sh" 2>/dev/null; r="$(_norte_provar_runner py)"; [ -n "$r" ] && "$r" -c "print(1)" 2>/dev/null || echo "não roda ($r)"' _ "$V")" ;;
    prova-negativa) s="$(env "PATH=$P" bash -c '. "$1/hooks/_prova-negativa.sh" 2>/dev/null; r="$(_npn_runner py)"; [ -n "$r" ] && "$r" -c "print(1)" 2>/dev/null || echo "não roda ($r)"' _ "$V")" ;;
    objetivo)      s="$(env "PATH=$P" HOME="$H" NORTE_BOX_PASSO=0 NORTE_OBJETIVO_FONTE=/nao/existe bash "$V/bin/nb-bilhete-objetivo" "$d/handoffs/assunto-20261022-1100.md" 2>/dev/null)"; s="${s% (copiado de:*}" ;;
  esac
  printf '%s' "$s"
}
# o que o DEPOIS tem que dar, por lugar, quando HÁ Python (cenários 3/4/5) — e quando NÃO há (7)
espera_com() { case "$1" in
  retomar-alvo) echo "ALVO assunto-20261022-1100.md" ;; unificar) echo "moveu pro projeto" ;; ponteiro) echo "ULTIMO aponta pro novo" ;;
  mark-adota) echo "▲ conserto-continuar v2 · nao-carimbei" ;; passo) echo "saiu 0" ;; provar|prova-negativa) echo "1" ;;
  objetivo) echo "OBJETIVO: vender mais" ;; desinstalar) echo "*" ;; esac; }
espera_sem() { case "$1" in
  retomar-alvo) echo "ALVO assunto-20261022-1100.md" ;; unificar) echo "*" ;; ponteiro) echo "*" ;; mark-adota) echo "*" ;;
  passo) echo "saiu 0" ;; provar|prova-negativa) echo "não roda" ;; objetivo) echo "SEM OBJETIVO (sem python3)" ;; desinstalar) echo "*" ;; esac; }
confere() { # obtido · esperado (prefixo; * = qualquer coisa que não trave)
  [ "$2" = "*" ] && return 0; case "$1" in "$2"*) return 0 ;; esac; return 1; }

for lugar in retomar-alvo objetivo unificar ponteiro mark-adota passo desinstalar provar prova-negativa; do
  echo "-- $lugar"
  for i in 0 2 3 4 6; do
    a="$(caso "$lugar" "$A" "$i")"; b="$(caso "$lugar" "$R" "$i")"
    if [ "${TEMPY[$i]}" = 1 ]; then e="$(espera_com "$lugar")"; else e="$(espera_sem "$lugar")"; fi
    if confere "$b" "$e"; then st="OK   "; else st="FALHA"; FALHAS=$((FALHAS+1)); fi
    printf '  %s %-34s antes: %-40s depois: %s\n' "$st" "${NOMES[$i]}" "$(printf '%s' "$a" | cut -c1-40)" "$b"
  done
done

echo; [ "$FALHAS" = 0 ] && echo "RESULTADO: tudo OK no Windows" || echo "RESULTADO: $FALHAS falha(s)"
[ "$FALHAS" = 0 ]
