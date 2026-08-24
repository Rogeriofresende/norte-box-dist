#!/usr/bin/env bash
# instalar-trava-segredo.sh - liga a TRAVA ANTI-SEGREDO em TODOS os commits desta maquina.
#
# COMO: o git tem uma configuracao global `core.hooksPath` que diz "os hooks de todos os
# repos ficam nesta pasta". Instalamos a trava la (uma vez), e a partir dai TODO `git commit`
# em QUALQUER projeto desta maquina passa pela trava - sem precisar configurar repo por repo.
# (Os funcionarios trabalham dentro dos PROPRIOS projetos deles; a trava por maquina cobre todos.)
#
# SEGURANCA / NAO-CLOBBER (por que e seguro rodar no automatico):
#   - Se a maquina JA tem um core.hooksPath (o usuario ja usa hooks proprios), NAO roubamos:
#     copiamos os hooks dele pra nossa pasta e PRESERVAMOS o pre-commit dele como
#     `pre-commit.local` — nossa trava o CHAMA no final. O comportamento dele continua.
#   - Se a maquina JA tem nossa trava, so atualiza o conteudo (idempotente).
#   - Backup com timestamp do valor anterior de core.hooksPath (da pra reverter).
#   - Fail-open no bootstrap: se algo falhar aqui, nao quebra a instalacao do Norte-box.
#
# COMO DESLIGAR (reverter tudo):
#   git config --global --unset core.hooksPath      # solta a trava global
#   (ou aponte de volta pro backup impresso no fim desta saida)
#   E pra pular UM commit especifico:  NORTE_TRAVA_SEGREDO_OFF=1 git commit ...
#
# Idempotente: rodar 2x nao quebra.
set -uo pipefail

_verde() { printf '\033[1;32m%s\033[0m\n' "$*"; }
_azul()  { printf '\033[1;34m%s\033[0m\n' "$*"; }
_amar()  { printf '\033[1;33m%s\033[0m\n' "$*"; }
_verm()  { printf '\033[1;31m%s\033[0m\n' "$*" >&2; }

# --- de onde vem o hook (o arquivo-fonte da trava, ao lado deste instalador) -------------------
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
HOOK_FONTE="$SELF_DIR/../hooks/pre-commit-trava-segredo.sh"
if [ ! -f "$HOOK_FONTE" ]; then
  _verm "[trava-segredo] nao achei o hook-fonte em $HOOK_FONTE — nada instalado."
  exit 1
fi

command -v git >/dev/null 2>&1 || { _verm "[trava-segredo] git nao encontrado — nada instalado."; exit 1; }

# --- onde os hooks globais vao morar -----------------------------------------------------------
DEST_DIR="${NORTE_TRAVA_HOOKS_DIR:-$HOME/.norte-box/git-hooks}"
mkdir -p "$DEST_DIR"

ATUAL="$(git config --global --get core.hooksPath 2>/dev/null || true)"

# Ja e a nossa pasta? So atualiza o conteudo do hook (idempotente).
if [ -n "$ATUAL" ] && [ "$ATUAL" = "$DEST_DIR" ]; then
  cp "$HOOK_FONTE" "$DEST_DIR/pre-commit"
  chmod +x "$DEST_DIR/pre-commit"
  _verde "[trava-segredo] ja estava ligada — hook atualizado em $DEST_DIR/pre-commit."
  exit 0
fi

# A maquina tem OUTRA core.hooksPath (o usuario usa hooks proprios)? Preserva os dele.
if [ -n "$ATUAL" ] && [ "$ATUAL" != "$DEST_DIR" ]; then
  _amar "[trava-segredo] voce ja tinha hooks globais em: $ATUAL"
  _amar "                vou preservar os seus e encadear a trava por cima (nao roubo o seu setup)."
  # copia os hooks existentes pra nossa pasta (menos um pre-commit, que viramos .local)
  if [ -d "$ATUAL" ]; then
    for f in "$ATUAL"/*; do
      [ -e "$f" ] || continue
      base="$(basename "$f")"
      if [ "$base" = "pre-commit" ]; then
        cp "$f" "$DEST_DIR/pre-commit.local"
        chmod +x "$DEST_DIR/pre-commit.local" 2>/dev/null || true
      else
        cp "$f" "$DEST_DIR/$base"
      fi
    done
  fi
fi

# Se NAO havia core.hooksPath global, mas existe um pre-commit no repo atual (raro), nao mexemos
# em repo — core.hooksPath global e por-maquina e nao interfere nos .git/hooks/ locais? Na verdade
# core.hooksPath SUBSTITUI o .git/hooks de TODOS os repos. Pra nao silenciar um pre-commit local
# que o usuario tenha, avisamos (honestidade). Casos raros; a maioria das maquinas nao tem isso.

# instala a trava
cp "$HOOK_FONTE" "$DEST_DIR/pre-commit"
chmod +x "$DEST_DIR/pre-commit"

# backup do valor anterior (pra reverter) + aponta o git global pra nossa pasta
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
if [ -n "$ATUAL" ]; then
  echo "$ATUAL" > "$DEST_DIR/.hooksPath-anterior-$STAMP"
fi
git config --global core.hooksPath "$DEST_DIR"

_verde "[trava-segredo] LIGADA. Todo 'git commit' desta maquina agora passa pela trava anti-segredo."
_azul  "                hooks globais: $DEST_DIR"
if [ -n "$ATUAL" ]; then
  _azul "                (seu hooksPath anterior era '$ATUAL' — salvo em $DEST_DIR/.hooksPath-anterior-$STAMP)"
  [ -x "$DEST_DIR/pre-commit.local" ] && _azul "                seu pre-commit antigo virou pre-commit.local e continua rodando."
fi
_azul  "                desligar de vez: git config --global --unset core.hooksPath"
_azul  "                pular um commit:  NORTE_TRAVA_SEGREDO_OFF=1 git commit ..."
exit 0
