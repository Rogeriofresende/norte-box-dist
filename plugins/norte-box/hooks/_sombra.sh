#!/usr/bin/env bash
# _sombra.sh — FONTE UNICA do PORTAO SOMBRA (NRT-_990212 passo 9, "portoes de acao").
# Sourceado pelo helper bin/nb-sombra (e futuramente pelo comando /norte-box:sombra).
#
# A ideia (padaria): a caixa passa a poder AGIR — editar um arquivo que JA existe. MAS nesta fatia
# fina ela SO ENSAIA numa COPIA (a "sombra"). O arquivo REAL nunca e' tocado. E' o "ver o antes"
# seguro: mostra como ficaria a mudanca, prova que o real continua igualzinho, e so entao da o selo.
#
# FATIA FINA — 1 EDICAO SO: substituicao de string (de -> para) num UNICO arquivo real existente.
# (Botao "Aplicar" real, undo, multi-arquivo, patch complexo, detectar drift-na-hora-de-aplicar:
#  TUDO fora de escopo aqui. Uma coisa que ENSAIA de verdade > tudo pela metade.)
#
# LEIS (nao-negociaveis):
#   - NENHUM caminho de codigo escreve no arquivo REAL. So a SOMBRA e' escrita. FAIL-CLOSED no caminho
#     de escrita: na duvida, NAO escreve — nem na sombra (recusa o alvo e sai vermelho honesto).
#   - PRIVADO + LOCAL + ZERO-REDE: a sombra e a prova moram em $HOME/.norte-box/sombra/<sessao>/. Nada
#     sai da maquina. Esta lib so le/escreve o disco local — nao ha chamada de rede em lugar nenhum.
#   - COPIA POR CONTEUDO, NUNCA POR LINK: a sombra e' um `cp` do conteudo. Se o alvo for symlink/hardlink
#     pro real, RECUSA (vermelho) — nao seguimos o link (senao "editar a sombra" tocaria o real).
#   - REALPATH GATE: o CANONICO do alvo (resolve ../ e symlinks) tem que existir; recusamos alvo cujo
#     realpath escape pra fora do permitido na hora de copiar (nao copiamos /etc/hosts como "sombra").
#   - REAL INTOCADO PROVADO POR HASH: mede sha256 do REAL ANTES de tudo e DEPOIS de tudo. So da 🟢 se
#     forem IDENTICOS. Se o real mudou 1 byte no meio -> ensaio invalido, vermelho.
#   - ANTI-DIFF-FABRICADO: o diff que a caixa MOSTRA tem que bater com o diff RECALCULADO da propria
#     sombra na hora do selo. Divergiu -> vermelho (ninguem forja um "antes->depois" bonito).
#   - KILL-SWITCH: NORTE_SOMBRA=0 -> inerte (nao faz nada, exit 2).
#   - Portabilidade macOS (bash 3.2). Precisa de diff; sem diff, degrada honesto (nao mente verde).
#   - FREIO (NRT-_990212): a trava-mestra do leigo. Se o freio esta puxado, esta acao nem comeca. O guard
#     (_norte_freio_checa) e' a PRIMEIRA coisa da funcao, ANTES dos checks de env (precedencia freio > env).
set -u

# --- garante o FREIO (a trava-mestra das acoes). Sourceia o irmao hooks/_freio.sh de forma robusta. Se
#     nao carregar, degrada FAIL-OPEN pra a SESSAO (define um stub que deixa passar) — nao quebramos a
#     acao por falta do freio; o resto (32/60/26/45 testes) segue verde. (Fail-CLOSED e' da ACAO quando o
#     freio ESTA la e diz "puxado"; a AUSENCIA da peca do freio nao pode travar a caixa toda.) ---
if ! command -v _norte_freio_checa >/dev/null 2>&1; then
  _sombra_self_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)"
  if [ -n "${_sombra_self_dir:-}" ] && [ -f "${_sombra_self_dir}/_freio.sh" ]; then
    # shellcheck source=/dev/null
    . "${_sombra_self_dir}/_freio.sh" 2>/dev/null || true
  fi
  # degrade fail-open pra a sessao se o freio nao carregou (nunca quebra a acao por falta da peca).
  command -v _norte_freio_checa >/dev/null 2>&1 || _norte_freio_checa() { return 0; }
fi

# --- raiz controlada das sombras (a caixa-de-areia descartavel, LOCAL) ---
_norte_sombra_raiz() { printf '%s/.norte-box/sombra' "${HOME}"; }

# _norte_sombra_slug <str> — sanitiza pra nome de dir seguro (so [A-Za-z0-9._-]).
_norte_sombra_slug() {
  printf '%s' "${1:-}" | tr -c 'A-Za-z0-9._-' '_' | cut -c1-64
}

# _norte_sombra_sha <arquivo> — sha256 ESTAVEL do CONTEUDO (a testemunha do "real intocado"). Igual
# ao _norte_prova_hash_arquivo do _situacao.sh mas independente (a lib e' auto-contida). Vazio se falha.
_norte_sombra_sha() {
  local _p="${1:-}"; [ -n "$_p" ] || return 1; [ -f "$_p" ] || return 1
  if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$_p" 2>/dev/null | cut -d' ' -f1; return 0; fi
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$_p" 2>/dev/null | cut -d' ' -f1; return 0; fi
  cksum "$_p" 2>/dev/null | tr -d ' '
}

# _norte_sombra_realpath <caminho> — canonico (resolve .., ., symlinks). realpath/grealpath -> fallback
# bash 3.2 (canoniza o DIRETORIO via pwd -P + basename). Vazio se nao resolve. Fecha ../ traversal.
_norte_sombra_realpath() {
  local _p="${1:-}"; [ -n "$_p" ] || return 1
  if command -v realpath >/dev/null 2>&1; then realpath "$_p" 2>/dev/null && return 0; fi
  if command -v grealpath >/dev/null 2>&1; then grealpath "$_p" 2>/dev/null && return 0; fi
  local _d _b
  _d="$(dirname "$_p" 2>/dev/null)"; _b="$(basename "$_p" 2>/dev/null)"
  _d="$(cd "$_d" 2>/dev/null && pwd -P 2>/dev/null)" || return 1
  [ -n "$_d" ] || return 1
  printf '%s/%s' "$_d" "$_b"
}

# _norte_sombra_ensaiar <arquivo-real> <de> <para> [sessao]
#   ENSAIA a substituicao <de> -> <para> numa COPIA do <arquivo-real>. NUNCA toca o real.
#   Ecoa no stdout um bloco humano (o antes->depois + o selo) e devolve:
#     0  -> 🟢 ENSAIO OK: real intocado (sha antes==depois) E o diff mostrado bate com o recalculado.
#     1  -> 🔴 vermelho honesto: real mudou / diff fabricado / nao consegui ensaiar / alvo recusado.
#     2  -> inerte (kill-switch NORTE_SOMBRA=0) ou pre-condicao ausente (sem diff, sem arquivo, etc).
#   O caminho da sombra e' ecoado numa linha NB_SOMBRA_ARQUIVO=... pra o chamador citar sem inventar.
_norte_sombra_ensaiar() {
  local _real="${1:-}" _de="${2:-}" _para="${3:-}" _sess="${4:-}"

  # FREIO (precedencia freio > env): se a trava-mestra esta puxada, aborta AQUI, sem agir.
  _norte_freio_checa || return 1

  # kill-switch: NORTE_SOMBRA=0 -> inerte (nao faz NADA).
  case "${NORTE_SOMBRA:-1}" in
    0|no|nao|off|false)
      printf '🟡 o portao "sombra" nao esta ligado nesta maquina (NORTE_SOMBRA=0).\n'
      return 2 ;;
  esac

  # --- pre-condicoes (fail-honest: sem ensaiar de verdade, nao mente verde) ---
  if [ -z "$_real" ]; then
    printf '🟡 nao consegui ensaiar: diga qual arquivo real eu ensaio.\n'; return 2
  fi
  # RECUSA symlink DURO antes de qualquer [ -f ] (que seguiria o link e "editaria" o real por tras).
  if [ -L "$_real" ]; then
    printf '🔴 alvo recusado: o caminho e um atalho (symlink) — copiar por atalho tocaria o arquivo real.\n'
    return 1
  fi
  if [ ! -f "$_real" ]; then
    printf '🟡 nao consegui ensaiar: o arquivo real indicado nao existe.\n'; return 2
  fi
  if [ -z "$_de" ]; then
    printf '🟡 nao consegui ensaiar: diga o trecho a trocar (de -> para).\n'; return 2
  fi
  command -v diff >/dev/null 2>&1 || { printf '🟡 nao consegui ensaiar: falta o programa diff nesta maquina.\n'; return 2; }

  # --- GATE de escopo: o CANONICO do real tem que resolver DENTRO do HOME (a arvore permitida pra
  #     esta fatia). Isso recusa /etc/hosts, /System/..., e qualquer alvo fora do espaco do usuario —
  #     o ensaio COPIA o alvo; nao vamos copiar arquivo de sistema pra "sombra". FAIL-CLOSED. ---
  local _canon _homec
  _canon="$(_norte_sombra_realpath "$_real")" || { printf '🔴 alvo recusado: nao consegui resolver o caminho do arquivo.\n'; return 1; }
  [ -n "$_canon" ] || { printf '🔴 alvo recusado: caminho vazio.\n'; return 1; }
  _homec="$(_norte_sombra_realpath "${HOME}")" || { printf '🔴 alvo recusado: nao consegui resolver o HOME.\n'; return 1; }
  [ -n "$_homec" ] || { printf '🔴 alvo recusado: HOME vazio.\n'; return 1; }
  case "$_canon" in
    "$_homec"/*) : ;;
    *) printf '🔴 alvo recusado: o arquivo esta fora do seu espaco de usuario (%s...). Por seguranca, so ensaio arquivos dentro da sua pasta.\n' "$(printf '%s' "$_canon" | cut -c1-1)"; return 1 ;;
  esac

  # --- 1) sha256 do REAL ANTES (a testemunha) ---
  local _sha_antes
  _sha_antes="$(_norte_sombra_sha "$_real")" || { printf '🟡 nao consegui ensaiar: nao consegui medir o arquivo.\n'; return 2; }
  [ -n "$_sha_antes" ] || { printf '🟡 nao consegui ensaiar: medida vazia.\n'; return 2; }

  # --- caixa-de-areia descartavel (LOCAL, sob $HOME/.norte-box/sombra/<sessao>/) ---
  local _raiz _sslug _dir _ts _sbx
  _raiz="$(_norte_sombra_raiz)"
  _sslug="$(_norte_sombra_slug "${_sess:-sessao}")"; [ -n "$_sslug" ] || _sslug="sessao"
  _ts="$(date -u +%Y%m%dT%H%M%SZ 2>/dev/null || echo t)"
  _dir="${_raiz}/${_sslug}"
  mkdir -p "$_dir" 2>/dev/null || { printf '🟡 nao consegui ensaiar (disco nao gravavel).\n'; return 2; }
  _sbx="${_dir}/.sbx.$$.${_ts}"
  mkdir -p "$_sbx" 2>/dev/null || { printf '🟡 nao consegui preparar a caixa-de-areia (disco nao gravavel).\n'; return 2; }

  # --- 2) COPIA POR CONTEUDO pra sombra (cp -- ; NUNCA symlink/hardlink). A sombra e' a UNICA coisa
  #        que escrevemos. O real fica de fora do caminho de escrita, por construcao. ---
  local _sombra="${_sbx}/sombra"
  # 'cp' de conteudo (arquivo regular ja garantido por [ -f ] + nao-symlink pelo [ -L ] acima).
  cp -- "$_real" "$_sombra" 2>/dev/null || { rm -rf "$_sbx" 2>/dev/null; printf '🔴 nao consegui copiar pra sombra — ensaio abortado (nada foi aplicado).\n'; return 1; }
  # defesa em profundidade: a copia NAO pode ter virado link nem apontar pro real.
  if [ -L "$_sombra" ]; then rm -rf "$_sbx" 2>/dev/null; printf '🔴 a sombra virou atalho — abortado.\n'; return 1; fi

  # --- 3) aplica a edicao SO na sombra (troca <de> por <para>, literal, primeira ocorrencia por linha).
  #        Usa um filtro que NAO interpreta o dado como regex/comando: le linha a linha e substitui a
  #        substring literal via replace de shell (bash 3.2: ${var//busca/troca} e literal). ---
  #        FIDELIDADE bash 3.2: o BUSCA ($_de) fica ENTRE ASPAS (senao vira glob/regex e reabre injection);
  #        o TROCA ($_para) fica SEM ASPAS — em bash 3.2 aspar o lado direito vaza aspas LITERAIS no
  #        resultado (a troca gravaria "para" com aspas; a delecao gravaria ""). Como $_para so expande pra
  #        texto (nunca e reavaliado), tira-las e' seguro E fiel. (Bug isolado pelo Val, NRT-_990212.)
  local _sombra_edit="${_sbx}/sombra.edit" _l _linha
  : > "$_sombra_edit" 2>/dev/null || { rm -rf "$_sbx" 2>/dev/null; printf '🔴 nao consegui gravar a sombra editada — abortado.\n'; return 1; }
  while IFS= read -r _linha || [ -n "$_linha" ]; do
    _l="${_linha//"$_de"/$_para}"
    printf '%s\n' "$_l" >> "$_sombra_edit"
  done < "$_sombra"

  # --- calcula o diff da sombra (antes -> depois), o que sera MOSTRADO ---
  local _diff_mostrado
  _diff_mostrado="$(diff -u "$_sombra" "$_sombra_edit" 2>/dev/null)"
  # HOOK DE TESTE (so em teste): NB_SOMBRA_TEST_DIFF_FALSO=1 injeta um diff que NAO corresponde a sombra
  # -> o selo (recalculo abaixo) tem que pegar a divergencia e sair VERMELHO. Nao muda producao.
  if [ "${NB_SOMBRA_TEST_DIFF_FALSO:-0}" = "1" ]; then
    _diff_mostrado="$(printf -- '--- a\n+++ b\n@@ -1 +1 @@\n-ISTO E UMA MENTIRA\n+ISTO NAO SAIU DA SOMBRA\n')"
  fi

  # HOOK DE TESTE (so em teste): NB_SOMBRA_TEST_MUTA=<arquivo> muta 1 byte do REAL DEPOIS de copiar a
  # sombra e ANTES de fechar o selo — simula "o real mudou no meio". Em producao NUNCA escrevemos o real;
  # este gancho existe so pra o teste provar que a checagem sha-antes==sha-depois PEGA a mudanca.
  if [ -n "${NB_SOMBRA_TEST_MUTA:-}" ] && [ -f "${NB_SOMBRA_TEST_MUTA}" ]; then
    printf 'X' >> "${NB_SOMBRA_TEST_MUTA}" 2>/dev/null || true
  fi

  # --- 4) sha256 do REAL DEPOIS de tudo (tem que bater com o de antes) ---
  local _sha_depois
  _sha_depois="$(_norte_sombra_sha "$_real")"

  # --- 6a) SELO — condicao (a): o real esta intocado? ---
  if [ "$_sha_antes" != "$_sha_depois" ]; then
    rm -rf "$_sbx" 2>/dev/null
    printf '🔴 o arquivo real MUDOU durante o ensaio — ensaio invalido, nada foi aplicado.\n'
    printf '   (o hash de antes e o de depois nao batem; por seguranca eu descartei o ensaio.)\n'
    return 1
  fi

  # --- 6b) SELO — condicao (b): ANTI-DIFF-FABRICADO. Recalcula o diff da sombra AGORA e exige que bata
  #        com o que sera mostrado. Se divergir (ex.: alguem forjou um diff bonito), vermelho. ---
  local _diff_recalc
  _diff_recalc="$(diff -u "$_sombra" "$_sombra_edit" 2>/dev/null)"
  if [ "$_diff_mostrado" != "$_diff_recalc" ]; then
    rm -rf "$_sbx" 2>/dev/null
    printf '🔴 o diff mostrado NAO bate com a mudanca real da sombra — recusado (nada foi aplicado).\n'
    return 1
  fi

  # --- caso a edicao nao mudou nada (o <de> nao aparece): honesto, nao "ensaiou" mudanca alguma ---
  if [ -z "$_diff_recalc" ]; then
    rm -rf "$_sbx" 2>/dev/null
    printf '🟡 nada a ensaiar: o trecho "%s" nao aparece no arquivo, entao a edicao nao muda nada.\n' "$_de"
    return 2
  fi

  # --- persiste a sombra editada num lugar estavel (fora do .sbx.$$ que sera limpo), pra o chamador
  #     citar/inspecionar. Continua LOCAL, dentro da caixa-de-areia da sessao. ---
  local _sombra_final="${_dir}/sombra-${_ts}"
  cp -- "$_sombra_edit" "$_sombra_final" 2>/dev/null || _sombra_final="$_sombra_edit"

  # --- RECIBO (NRT-_990212 passo 9 fatia 2, PURAMENTE ADITIVO) — grava 3 fatos ao lado da sombra pra
  #     o portao APLICAR poder, DEPOIS, re-medir e recusar se algo mudou. NAO altera o stdout nem o exit
  #     code deste ensaio (os 32+26 testes seguem verdes). Best-effort: se o disco recusar, o ensaio
  #     continua 🟢 igual — o recibo e' um EXTRA, nao muda a garantia do ensaio.
  #       alvo=       o canonico do arquivo real
  #       sha_ensaio= o sha256 do real NO MOMENTO do ensaio (o "_sha_antes" que ja provamos == depois)
  #       sha_sombra= o sha256 da sombra editada final
  #       sombra=     o caminho da sombra editada (pra o aplicar achar o conteudo) ---
  local _sha_sombra
  _sha_sombra="$(_norte_sombra_sha "$_sombra_final" 2>/dev/null)" || _sha_sombra=""
  if [ -n "$_sha_sombra" ]; then
    {
      printf 'alvo=%s\n' "$_canon"
      printf 'sha_ensaio=%s\n' "$_sha_antes"
      printf 'sha_sombra=%s\n' "$_sha_sombra"
      printf 'sombra=%s\n' "$_sombra_final"
    } > "${_sombra_final}.recibo" 2>/dev/null || true
  fi

  # --- 5) MOSTRA o antes->depois + nomeia o alvo (redigido) e o caminho da sombra ---
  local _alvo_red="$_canon"
  if command -v _redact >/dev/null 2>&1; then
    _alvo_red="$(printf '%s' "$_canon" | _redact 2>/dev/null)" || _alvo_red="[arquivo]"
    [ -n "$_alvo_red" ] || _alvo_red="[arquivo]"
  fi
  printf '🟢 ENSAIO OK — arquivo real intocado (hash conferido, identico antes e depois).\n'
  printf '   alvo real: %s\n' "$_alvo_red"
  printf '   ensaiei numa copia (sombra); o arquivo original NAO foi modificado.\n'
  printf '   veja como ficaria a troca "%s" -> "%s":\n' "$_de" "$_para"
  printf '%s\n' "$_diff_mostrado" | sed 's/^/   /' | head -40
  printf 'NB_SOMBRA_ARQUIVO=%s\n' "$_sombra_final"

  # limpa o dir temporario de trabalho (a sombra_final ja foi persistida fora dele).
  rm -rf "$_sbx" 2>/dev/null
  return 0
}
