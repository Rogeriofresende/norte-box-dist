#!/usr/bin/env bash
# testar-sombra.sh — teste "na mao" do PORTAO SOMBRA, pra uma pessoa NAO-tecnica (o CEO) sentir na mao
# que a caixa pode ENSAIAR uma edicao SEM tocar o arquivo real — e que a trava de seguranca e' REAL.
#
# POR QUE ESTE CAMINHO (leve, sem Docker):
#   A Sombra e' BASH PURO, ZERO-REDE e NUNCA chama `claude` -> nao gasta cota e nao precisa de container
#   pra isolar cota. O unico isolamento que ela pede e' um $HOME proprio (a guarda recusa alvo fora do
#   $HOME). Entao o teste mais robusto e leve e': um $HOME DESCARTAVEL sob /tmp + a arvore LIMPA do plugin
#   (git archive HEAD, nunca a arvore suja) + os arquivos de exemplo JA semeados. Some ao fim, nao toca o
#   ~/.claude de trabalho, nao escreve nada permanente fora de /tmp.
#
# USO:  bash testar-sombra.sh
#   (roda do worktree da branch feat/nrt990212-portoes-sombra — usa o HEAD dela via git archive)
#
# O que ele monta e IMPRIME pro CEO:
#   1) um $HOME de mentira em /tmp, com  meu-arquivo.txt  (conteudo: "saudacao: ola mundo") JA la;
#   2) um  atalho-perigoso.txt  (symlink pro original) JA la — pro caso VERMELHO (a caixa deve BARRAR);
#   3) um atalho de comando  nb-sombra  no PATH, pra ele digitar CURTO;
#   4) o passo-a-passo EXATO (<=4 linhas de padaria) na tela, ja pronto pra copiar.
set -euo pipefail

# --- 0) localiza a arvore LIMPA do plugin (git archive HEAD; NUNCA a arvore suja) ---
_here="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"     # .../plugins/norte-box
_repo="$(cd "$_here" && git rev-parse --show-toplevel 2>/dev/null || true)"
if [ -z "${_repo:-}" ]; then
  echo "ERRO: rode este script de dentro do worktree git da branch da Sombra." >&2; exit 1
fi

# --- 1) $HOME descartavel + caixa do plugin (tudo sob /tmp, some ao fim) ---
LAB="$(mktemp -d "${TMPDIR:-/tmp}/sombra-teste.XXXXXX")"
FAKEHOME="$LAB/casa"
PLUGTREE="$LAB/plugin"
BINDIR="$LAB/bin"
mkdir -p "$FAKEHOME" "$PLUGTREE" "$BINDIR"

# arvore LIMPA (HEAD) — nao a suja. So o subdir do plugin.
( cd "$_repo" && git archive HEAD plugins/norte-box ) | tar -x -C "$PLUGTREE"
_nb_real="$PLUGTREE/plugins/norte-box/bin/nb-sombra"
[ -x "$_nb_real" ] || chmod +x "$_nb_real" 2>/dev/null || true
[ -f "$_nb_real" ] || { echo "ERRO: nb-sombra nao veio na arvore limpa (HEAD)." >&2; exit 1; }

# --- 2) PRE-SEMEIA os arquivos de exemplo DENTRO do $HOME de mentira (o CEO nao cria nada) ---
printf 'saudacao: ola mundo\n' > "$FAKEHOME/meu-arquivo.txt"
# o atalho perigoso: um symlink apontando pro original — a caixa deve RECUSAR (nao seguir o link).
ln -sf "$FAKEHOME/meu-arquivo.txt" "$FAKEHOME/atalho-perigoso.txt"

# --- 3) atalho de comando `nb-sombra` no PATH, com o HOME de mentira embutido, pro CEO digitar CURTO ---
#     (o shim fixa HOME=$FAKEHOME e chama o nb-sombra da arvore limpa; assim o comando dele e' 1 linha.)
#     ACABAMENTO PRO CEO NAO-TECNICO: o nb-sombra REAL imprime, alem das linhas -/+ de conteudo, ruido
#     de diagnostico — as 2 linhas de cabecalho do diff (--- /tmp/..., +++ /tmp/...), a linha @@ -1 +1 @@,
#     e a linha NB_SOMBRA_ARQUIVO=/var/folders/... (caminho da sombra) — gibberish pra quem nao le diff.
#     O shim RODA o nb-sombra real, FILTRA so esse ruido (nunca as linhas -/+ de conteudo, que sao o
#     valor) e PRESERVA o exit code do real (o PASSO 3 vermelho depende de exit 1). NAO tocamos
#     bin/nb-sombra nem hooks/_sombra.sh (as LEIs red-teamadas) — o motor segue emitindo tudo.
cat > "$BINDIR/nb-sombra" <<SHIM
#!/usr/bin/env bash
export HOME="$FAKEHOME"
# roda o nb-sombra REAL capturando a saida; guarda o exit code ANTES de qualquer pipe (\$? seria perdido).
_out="\$(bash "$_nb_real" "\$@")"
_rc=\$?
# filtra SO o ruido de diagnostico, nunca as linhas -/+ de conteudo (que sao o valor):
#   '   --- /...' , '   +++ /...' , '   @@ ...@@' (recuo de 3 espacos que o portao aplica) e
#   'NB_SOMBRA_ARQUIVO=/var/folders/...' (caminho da sombra, em coluna 0) — gibberish pro CEO.
printf '%s\n' "\$_out" | grep -v -E '^   (--- /|\+\+\+ /|@@ )|^NB_SOMBRA_ARQUIVO='
exit \$_rc
SHIM
chmod +x "$BINDIR/nb-sombra"

# --- 4) imprime o passo-a-passo EXATO (<=4 passos, 1 linha cada) ---
cat <<EOF

======================================================================
  TESTE DA SOMBRA — voce vai VER a caixa ensaiar uma edicao SEM
  tocar o seu arquivo real. Tudo numa casa de mentira em /tmp que
  some ao fim. Nao toca nada do seu computador de trabalho.
======================================================================

Antes: dentro da casa de mentira ja existe  meu-arquivo.txt  com o texto
"saudacao: ola mundo". Voce NAO precisa criar nada.

Copie e cole ESTA linha uma vez (liga o atalho 'nb-sombra' nesta janela):

    export PATH="$BINDIR:\$PATH"; cd "$FAKEHOME"

--- PASSO 1 (VERDE) — ensaiar a troca ------------------------------------
    nb-sombra meu-arquivo.txt "ola mundo" "bom dia"

  Voce deve VER: um selo 🟢, e o "antes -> depois":
     -saudacao: ola mundo
     +saudacao: bom dia

--- PASSO 2 — provar que o ORIGINAL nao mudou ----------------------------
    cat meu-arquivo.txt

  Deve mostrar AINDA:  saudacao: ola mundo   (nada mudou — foi so ensaio)

--- PASSO 3 (VERMELHO) — sentir a trava de seguranca ---------------------
    nb-sombra atalho-perigoso.txt "ola mundo" "bom dia"

  Voce deve VER um cartao 🔴 recusando: a caixa percebeu que
  'atalho-perigoso.txt' e' um ATALHO pro seu arquivo real e se RECUSA
  a mexer por atalho. A trava e' de verdade, nao promessa.

--- PASSO 4 — fechar (apaga a casa de mentira, sem rastro) ---------------
    rm -rf "$LAB"

======================================================================
EOF
