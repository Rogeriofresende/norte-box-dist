#!/usr/bin/env bash
# _bilhete_mundo.sh — O AVISO DE MUNDO MUDADO (quais arquivos CITADOS no bilhete mudaram no git desde o
# selo) do Norte-box (NRT-_990148). Sourceado pelo helper bin/nb-bilhete-mundo e, via a retomada, pela
# skill /norte-retomar ANTES das 5 perguntas — logo depois do aviso de idade (_bilhete_validade.sh).
#
# O BURACO QUE ESTA PECA FECHA: o _bilhete_validade.sh ja avisa a IDADE do bilhete e QUANTOS commits
# entraram desde o selo — mas isso e GENERICO: "20 commits entraram" nao diz se algum tocou o que o
# bilhete manda mexer. A pessoa volta, ve "🟡 envelhecido (5d, 8c)" e ainda nao sabe se o `monitor.py`
# que o recado cita e um dos 8 que mudaram. Esta peca e o alerta FINO que complementa: cruza os
# ARQUIVOS que o bilhete CITA no corpo × o `git diff --name-only <ancora>..HEAD`, e ecoa UMA linha POR
# arquivo citado que MUDOU desde o selo. Se NENHUM citado mudou -> SILENCIO (nao incomoda; so um resumo
# curto no stderr). O objetivo e nao afogar: so fala do que o bilhete realmente cita E que realmente andou.
#
# MOLDURA HONESTA (o Val cobra — NAO overclaim, esta na copy da linha tambem):
#   - A peca so cruza "caminho CITADO como texto no corpo" × "git diff de NOMES de arquivo". NAO le o
#     conteudo do arquivo nem entende se a mudanca e RELEVANTE pro que o bilhete pede.
#   - Um arquivo citado POR ACASO (mencionado de passagem) que por coincidencia mudou tambem gera aviso —
#     falso-positivo possivel. Por isso e ALERTA pra CONFERIR, NUNCA licenca pra executar.
#   - "Mudou" = apareceu no `git diff --name-only <ancora>..HEAD`. Mudanca FORA do git (arquivo salvo sem
#     commit) NAO conta. Um arquivo renomeado pode aparecer como o nome novo, nao o citado.
#
# LEIS (nao-negociaveis, iguais aos outros passos):
#   - LOCAL, ZERO REDE: le so o cabecalho+corpo do bilhete (arquivo do PROPRIO projeto do usuario) e o git
#     local (git diff --name-only). NUNCA sai da maquina, nada de telemetria/rede aqui.
#   - FAIL-OPEN da retomada (NUNCA trava, NUNCA erro): sem ancora legivel / sha inexistente no repo / sem
#     git / fora de repo -> silencio no stdout + 1 linha honesta no stderr ("nao sei o mundo deste
#     bilhete") e exit 0. A peca so INFORMA; jamais impede a /norte-retomar de rodar.
#   - DADO E DADO, NUNCA COMANDO: o commit lido do cabecalho, DEPOIS de validado pela forma (_e_commit) e
#     confirmado existir no repo (git cat-file -e), vira ARGUMENTO de `git diff --name-only <sha>..HEAD`,
#     NUNCA comando. Os caminhos citados no corpo sao so COMPARADOS como texto (nunca `test`/`eval`/glob).
#     `set -u`, sem eval, `set -f` no tokenizador (o "*" do dado nao expande).
#   - Portabilidade macOS (bash 3.2, SEM arrays associativos/mapfile/${v^^}). SEM jq (so texto + git).
#
# KILL-SWITCH do mecanismo: NORTE_MUNDO=0 -> a peca fica INERTE (nada no stdout, exit 0). A /norte-retomar
# segue sem a linha, exatamente como antes desta peca existir.
set -u

# --- kill-switch: NORTE_MUNDO=0 -> inerte (nao emite aviso). ---
_nbm_desligado() {
  case "${NORTE_MUNDO:-1}" in
    0|no|nao|off|false) return 0 ;;
    *) return 1 ;;
  esac
}

# _nbm_int <valor> <default> — ecoa o inteiro valido ou o default (imita _nbv_int do validade). Usado pro
# teto de linhas do corpo (NB_MUNDO_MAX_LINHAS), a defesa contra bilhete patologico (Val R1).
_nbm_int() {
  case "${1:-}" in
    ''|*[!0-9]*) printf '%s' "${2:-}" ;;
    *) printf '%s' "$1" ;;
  esac
}

# _nbm_repo_ok — 0 se o cwd esta num repo git utilizavel (pra rodar git diff). Fail-open: sem git ou fora
# de repo, a peca cai no fail-open honesto (silencio + stderr), nunca trava.
_nbm_repo_ok() {
  command -v git >/dev/null 2>&1 || return 1
  git rev-parse --git-dir >/dev/null 2>&1 || return 1
  return 0
}

# _nbm_e_commit <token> — 0 se o token e um sha de commit plausivel: 7..40 hex puros. So a forma (nao toca
# o git aqui). DADO E DADO: isto e o filtro que impede um valor estranho de virar argumento perigoso.
_nbm_e_commit() {
  local _t="${1:-}" _n
  case "$_t" in
    ''|*[!0-9a-fA-F]*) return 1 ;;   # vazio, ou tem char que nao e hex -> nao e sha
  esac
  _n=${#_t}
  [ "$_n" -ge 7 ] && [ "$_n" -le 40 ]
}

# _nbm_e_traversal <ref> — 0 (SIM, escapa o projeto) se a ref e caminho absoluto OU contem ".." de subida.
# Igual ao _nbs_e_traversal do selo: um caminho fora da arvore do projeto nao entra no cruzamento (nao
# temos como comparar de forma util com o git diff local; fica fora de escopo). Nao executamos nada aqui.
_nbm_e_traversal() {
  local _r="${1:-}"
  case "$_r" in
    /*) return 0 ;;                 # caminho absoluto = fora do escopo do projeto
    *../*|*/..|..) return 0 ;;      # sobe de nivel = pode escapar o projeto
    *) return 1 ;;
  esac
}

# _nbm_parece_caminho <token> — 0 se o token PARECE um caminho de arquivo: tem "/" OU termina numa
# extensao conhecida de artefato. So a forma do token (nao toca o disco/git aqui). Reusa a mesma regra
# do _nbs_parece_caminho do selo (fonte da mesma verdade sobre "o que parece arquivo").
_nbm_parece_caminho() {
  local _t="${1:-}"
  case "$_t" in
    */*) return 0 ;;
    *.py|*.js|*.ts|*.tsx|*.jsx|*.mjs|*.cjs|*.sh|*.bash|*.md|*.json|*.html|*.htm|*.css|*.csv|*.txt|*.yml|*.yaml|*.toml|*.sql|*.go|*.rs|*.rb|*.java|*.c|*.h|*.cpp|*.php) return 0 ;;
    *) return 1 ;;
  esac
}

# _nbm_le_ancora <arquivo> — ecoa o SHA da ancora (o selo) lida do CABECALHO do bilhete, aceitando OS DOIS
# formatos, na ordem em que aparecerem (o PRIMEIRO que der um valor vence):
#   (A) formato /continuar:        "selado-em-commit: <sha>"  (linha "chave: valor" no cabecalho)
#   (B) formato session-handoff:   "world_anchor:" e, logo abaixo, uma linha INDENTADA "commit: <sha>"
# So le TEXTO local. Le so o CABECALHO (antes da primeira secao "## ") pra nao pegar mencao no corpo.
# Sem regex perigoso, sem eval. Ecoa vazio se nao achar nada legivel (fail-open a montante decide).
_nbm_le_ancora() {
  local _arq="${1:-}"
  [ -n "$_arq" ] && [ -f "$_arq" ] || { printf ''; return 0; }
  local _linha _val _dentro_wa=0
  while IFS= read -r _linha || [ -n "$_linha" ]; do
    case "$_linha" in
      "## "*) break ;;   # entrou nas secoes -> cabecalho acabou
    esac
    # (A) selado-em-commit: <sha>  — o formato /continuar.
    case "$_linha" in
      "selado-em-commit: "*)
        _val="${_linha#selado-em-commit: }"
        _val="$(printf '%s' "$_val" | tr -d '\r' | tr -d ' ')"
        [ -n "$_val" ] && { printf '%s' "$_val"; return 0; }
        ;;
    esac
    # (B) world_anchor: (abre o bloco) e, logo abaixo, uma linha "commit: <sha>" (pode vir indentada).
    case "$_linha" in
      "world_anchor:"*|"world_anchor: "*) _dentro_wa=1; continue ;;
    esac
    if [ "$_dentro_wa" -eq 1 ]; then
      # dentro do bloco world_anchor: aceita a linha "commit:" com qualquer indentacao (apara espacos/tab
      # do inicio antes de casar). Uma linha nao-indentada "chave: valor" (nova chave de topo) encerra o bloco.
      local _t
      _t="$(printf '%s' "$_linha" | sed 's/^[[:space:]]*//')"
      case "$_t" in
        "commit: "*)
          _val="${_t#commit: }"
          _val="$(printf '%s' "$_val" | tr -d '\r' | tr -d ' ')"
          [ -n "$_val" ] && { printf '%s' "$_val"; return 0; }
          ;;
        "commit:"*)
          # "commit:" sem valor na mesma linha -> nada; segue procurando.
          ;;
        '') ;;   # linha em branco dentro do bloco -> ignora, continua
        *:\ *|*:) _dentro_wa=0 ;;   # outra chave de topo (nao-indentada) fecha o bloco
      esac
    fi
  done < "$_arq"
  printf ''
  return 0
}

# _nbm_mudados_desde <ancora> — ecoa, UM POR LINHA, os nomes de arquivo que MUDARAM de <ancora> ate HEAD
# (git diff --name-only <ancora>..HEAD). Ecoa vazio se: sem git, fora de repo, ancora malformada, ou a
# ancora nao existe neste repo. NUNCA trava. DADO E DADO: <ancora> vira argumento SO depois de passar no
# filtro de forma (_nbm_e_commit) e de o commit existir MESMO (git cat-file -e); o range e montado com o
# sha ja validado.
_nbm_mudados_desde() {
  local _c="${1:-}"
  _nbm_repo_ok || { printf ''; return 1; }
  _nbm_e_commit "$_c" || { printf ''; return 1; }
  git cat-file -e "${_c}^{commit}" >/dev/null 2>&1 || { printf ''; return 1; }
  git diff --name-only "${_c}..HEAD" 2>/dev/null || true
  return 0
}

# _nbm_extrai_citados <arquivo> — ecoa, UM POR LINHA, os caminhos que o CORPO do bilhete CITA (parecem
# caminho de arquivo), DEDUPADOS e SEM traversal/absoluto (fora do escopo do projeto). Le so TEXTO local.
# Tokeniza o corpo inteiro por espaco/pontuacao comum (mesmo tokenizador seguro do selo: set -f desliga o
# glob, o "*" do dado NAO expande). O cabecalho (antes da 1a "## ") e pulado — a ancora ja saiu de la e o
# selado-em-commit do cabecalho NAO deve virar "arquivo citado".
_nbm_extrai_citados() {
  local _arq="${1:-}"
  [ -n "$_arq" ] && [ -f "$_arq" ] || { printf ''; return 0; }
  # TETO DE LINHAS DO CORPO (Val R1): o tokenizador forka um subshell+tr por LINHA; um bilhete patologico
  # (milhares de linhas) penduraria a retomada minutos. Handoff real e <=~600 linhas, entao 3000 folga muito.
  # Ajustavel por NB_MUNDO_MAX_LINHAS. Estourou -> confere so as primeiras N (best-effort, honesto no stderr).
  local _cap; _cap="$(_nbm_int "${NB_MUNDO_MAX_LINHAS:-}" 3000)"
  local _linha _dentro_corpo=0 _w _vistos="" _nlin=0
  while IFS= read -r _linha || [ -n "$_linha" ]; do
    # o corpo comeca na primeira secao "## " (o cabecalho e o topo, antes das secoes).
    case "$_linha" in
      "## "*) _dentro_corpo=1 ;;
    esac
    [ "$_dentro_corpo" -eq 1 ] || continue

    _nlin=$((_nlin+1))
    if [ "$_nlin" -gt "$_cap" ]; then
      printf 'mundo do bilhete: corpo grande demais (>%s linhas) — conferi so as primeiras %s (ajuste NB_MUNDO_MAX_LINHAS).\n' "$_cap" "$_cap" >&2
      break
    fi

    # normaliza separadores comuns em espaco pra tokenizar. set -f desliga glob (o "*" do dado nao expande).
    set -f
    # shellcheck disable=SC2086
    set -- $(printf '%s' "$_linha" | tr ',();:[]"'"'"'`<>{}|' '                ')
    set +f
    for _w in "$@"; do
      # apara pontuacao de borda comum (crase/parenteses ja viraram espaco; tira ponto/virgula final).
      case "$_w" in
        *.|*,) _w="${_w%?}" ;;
      esac
      # NORMALIZA prefixo "./" (Val R2): o bilhete cita "./monitor.py", o git diff --name-only usa "monitor.py"
      # (sem "./"). Sem isto, um arquivo citado com "./" MUDADO passava batido (falso-negativo no coracao).
      _w="${_w#./}"
      [ -n "$_w" ] || continue
      _nbm_parece_caminho "$_w" || continue
      _nbm_e_traversal "$_w" && continue     # absoluto / ".." -> fora de escopo, descarta
      # dedupe: guarda em _vistos cercado por " | " pra casar o token inteiro (nao substring).
      case " $_vistos " in
        *" $_w "*) ;;                        # ja visto -> pula
        *) _vistos="$_vistos $_w"; printf '%s\n' "$_w" ;;
      esac
    done
  done < "$_arq"
  return 0
}

# _norte_bilhete_mundo <arquivo-handoff> — o CORACAO da peca. Le a ancora do cabecalho (2 formatos),
# calcula os arquivos mudados desde ela, extrai os caminhos citados no corpo, e ecoa UMA linha POR
# caminho citado que TAMBEM mudou. Se nenhum citado mudou -> SILENCIO no stdout (so resumo no stderr).
# SEMPRE exit 0 (fail-open: informa, nunca trava a retomada).
#   - kill-switch NORTE_MUNDO=0 -> inerte: nada no stdout, exit 0.
#   - sem ancora legivel / sha inexistente / sem git -> silencio no stdout + 1 linha honesta no stderr.
_norte_bilhete_mundo() {
  local _arq="${1:-}"

  if _nbm_desligado; then
    return 0   # inerte: nada no stdout (a /norte-retomar segue sem a linha, como antes).
  fi

  if [ -z "$_arq" ] || [ ! -f "$_arq" ]; then
    printf '🟡 nao sei o mundo deste bilhete (nao achei o arquivo) — trate o recado como suposicao.\n' >&2
    return 0
  fi

  # 1) ancora (o selo). Aceita selado-em-commit (/continuar) OU world_anchor:/commit: (session-handoff).
  local _ancora
  _ancora="$(_nbm_le_ancora "$_arq")"
  if ! _nbm_e_commit "$_ancora"; then
    # sem ancora legivel (bilhete pre-peca, "sem-git", ou sha malformado) -> fail-open honesto.
    printf '🟡 nao sei o mundo deste bilhete (sem commit-ancora legivel) — trate o recado como suposicao.\n' >&2
    return 0
  fi

  # 2) arquivos mudados desde a ancora. _nbm_mudados_desde falha (rc!=0) se sem git / ancora inexistente.
  local _mudados
  if ! _mudados="$(_nbm_mudados_desde "$_ancora")"; then
    printf '🟡 nao sei o mundo deste bilhete (sem git, ou o commit-ancora nao existe neste repo) — trate o recado como suposicao.\n' >&2
    return 0
  fi

  # 3) caminhos citados no corpo (dedupados, sem traversal).
  local _citados
  _citados="$(_nbm_extrai_citados "$_arq")"

  # 4) cruzamento: pra cada citado que ESTA no conjunto de mudados -> uma linha de aviso no stdout.
  #    Comparacao de NOME inteiro (linha == linha), nunca substring, nunca glob. DADO E DADO.
  local _nota='(so cruza nome citado x git diff; nao le o conteudo; alerta pra conferir, nunca licenca pra executar)'
  local _cit _mud _n_avisos=0 _n_citados=0
  local _oldifs="$IFS"
  IFS='
'
  for _cit in $_citados; do
    [ -n "$_cit" ] || continue
    _n_citados=$((_n_citados+1))
    for _mud in $_mudados; do
      if [ "$_cit" = "$_mud" ]; then
        printf '⚠ mudou desde o bilhete: %s — confira se o recado ainda vale (o bilhete cita esse arquivo e ele mudou no git desde o selo). %s\n' "$_cit" "$_nota"
        _n_avisos=$((_n_avisos+1))
        break
      fi
    done
  done
  IFS="$_oldifs"

  if [ "$_n_avisos" -eq 0 ]; then
    # NENHUM citado mudou -> SILENCIO no stdout (nao incomoda). So um resumo curto no stderr.
    printf 'mundo do bilhete: 0 citados mudaram desde o selo (%s arquivos citados conferidos).\n' "$_n_citados" >&2
  fi
  return 0
}
