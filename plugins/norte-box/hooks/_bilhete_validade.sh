#!/usr/bin/env bash
# _bilhete_validade.sh — O AVISO DE BILHETE VENCIDO (o selo com prazo de validade na RETOMADA) do
# Norte-box (NRT-_990474). Sourceado pelo helper bin/nb-bilhete-validade e, via Passo 7.6, pela skill
# /norte-retomar (e o comando retomar) ANTES das 5 perguntas.
#
# O BURACO QUE ESTA PECA FECHA: a pessoa volta a um projeto DIAS depois e a /norte-retomar le o bilhete
# de "onde paramos" como se fosse de agora. So que o codigo pode ter mudado 14 vezes desde que o bilhete
# foi selado — o mapa ja nao bate com o mundo. HOJE nada avisa isso NA CARA, antes de agir. Esta peca
# olha o CARIMBO que a /continuar grava no bilhete (selado-em + selado-em-commit) e, por FATO (idade +
# quantos commits entraram desde), ecoa UMA linha de veredito no TOPO da retomada:
#   🟢 fresco  |  🟡 envelhecido (Nd, Nc)  |  🔴 velho — confira antes de seguir (Nd, Nc)
# em vez de a pessoa seguir cego sobre um recado que talvez ja esteja obsoleto.
#
# MOLDURA HONESTA (o Val pediu — NAO overclaim, esta na copy da linha tambem):
#   - A peca mede so IDADE + NUMERO de mudancas no git. NAO le o conteudo do bilhete nem do codigo.
#   - Commits em OUTRO canto do repo contam (nao sabemos se tocam o assunto do bilhete). Mudanca FORA
#     do git (arquivo salvo sem commit) NAO conta.
#   - E ALERTA pra CONFERIR, NUNCA licenca pra executar. 🟢 quer dizer "recente", NAO "correto".
#
# LEIS (nao-negociaveis, iguais aos outros passos):
#   - LOCAL, ZERO REDE: le so o cabecalho do bilhete (arquivo do PROPRIO projeto do usuario) e o git
#     local (git rev-list). NUNCA sai da maquina, nada de telemetria/rede aqui.
#   - FAIL-OPEN da retomada (NUNCA trava, NUNCA erro): sem carimbo / sem git / commit invalido / carimbo
#     malformado -> ecoa "🟡 nao sei a idade — trate como suposicao" e exit 0. A peca so INFORMA; jamais
#     impede a /norte-retomar de rodar. Um veredito ausente e melhor que uma trava.
#   - DADO E DADO, NUNCA COMANDO: o commit lido do cabecalho vira ARGUMENTO de `git rev-list` /
#     `git cat-file`, NUNCA comando. `set -u`, sem eval, sem expandir o valor como shell. Um payload de
#     shell / caractere estranho no carimbo NAO executa; se nao for um sha plausivel -> desconhecido.
#   - Portabilidade macOS (bash 3.2, SEM arrays associativos/mapfile/${v^^}). SEM jq obrigatorio (a peca
#     so le texto do cabecalho e chama git); date pode ser BSD ou GNU (tratamos os dois).
#
# LIMIARES (ajustaveis por env, imitando NB_PROVAR_TIMEOUT — cada um so numero inteiro, com fallback):
#   🟢 fresco     = idade <= NB_VALIDADE_DIAS_VERDE (2)  E  commits <= NB_VALIDADE_COMMITS_VERDE (3)
#   🔴 velho      = idade  > NB_VALIDADE_DIAS_VERMELHO (7)  OU  commits > NB_VALIDADE_COMMITS_VERMELHO (20)
#   🟡 envelhecido= tudo o que fica no meio (nem fresco, nem velho)
#   (verde e o mais restrito; vermelho ganha do amarelo; commits DESCONHECIDOS nao viram vermelho sozinhos.)
#
# KILL-SWITCH do mecanismo: NORTE_VALIDADE=0 -> a peca fica INERTE (nao emite veredito), fail-open (exit 0,
# nada no stdout). A /norte-retomar segue sem a linha, exatamente como antes desta peca existir.
set -u

# --- kill-switch: NORTE_VALIDADE=0 -> inerte (nao emite veredito). ---
_nbv_desligado() {
  case "${NORTE_VALIDADE:-1}" in
    0|no|nao|off|false) return 0 ;;
    *) return 1 ;;
  esac
}

# --- limiares por env (imita NB_PROVAR_TIMEOUT: so inteiro, senao cai no default). ---
_nbv_int() { # <valor> <default>  -> ecoa o inteiro valido ou o default
  local _v="${1:-}" _d="${2:-}"
  case "$_v" in
    ''|*[!0-9]*) printf '%s' "$_d" ;;
    *) printf '%s' "$_v" ;;
  esac
}

# _nbv_repo_ok — 0 se o cwd esta num repo git utilizavel (pra contar commits). Fail-open: sem git ou fora
# de repo, os commits viram DESCONHECIDOS (nunca trava, nunca vira vermelho sozinho).
_nbv_repo_ok() {
  command -v git >/dev/null 2>&1 || return 1
  git rev-parse --git-dir >/dev/null 2>&1 || return 1
  return 0
}

# _nbv_e_commit <token> — 0 se o token e um sha de commit plausivel: 7..40 hex puros. So a forma (nao toca
# o git aqui). DADO E DADO: isto e o filtro que impede um valor estranho de virar argumento perigoso.
_nbv_e_commit() {
  local _t="${1:-}" _n
  case "$_t" in
    ''|*[!0-9a-fA-F]*) return 1 ;;   # vazio, ou tem char que nao e hex -> nao e sha
  esac
  _n=${#_t}
  [ "$_n" -ge 7 ] && [ "$_n" -le 40 ]
}

# _nbv_le_campo <arquivo> <chave> — ecoa o VALOR da linha "chave: valor" do CABECALHO do bilhete (antes da
# primeira secao "## "). So le TEXTO local. Le so a primeira ocorrencia. Sem regex perigoso, sem eval.
# Para no primeiro "## " (o cabecalho e o topo do arquivo, antes das secoes) pra nao pegar mencao no corpo.
_nbv_le_campo() {
  local _arq="${1:-}" _chave="${2:-}"
  [ -n "$_arq" ] && [ -f "$_arq" ] || { printf ''; return 0; }
  local _linha _val
  while IFS= read -r _linha || [ -n "$_linha" ]; do
    case "$_linha" in
      "## "*) break ;;                        # entrou nas secoes -> cabecalho acabou
      "${_chave}: "*)
        _val="${_linha#"${_chave}": }"
        # apara espacos das pontas (sem depender de xargs). tr remove \r do CRLF do Windows.
        _val="$(printf '%s' "$_val" | tr -d '\r')"
        printf '%s' "$_val"
        return 0 ;;
    esac
  done < "$_arq"
  printf ''
  return 0
}

# _nbv_epoch_de <iso-utc> — converte um timestamp ISO UTC (ex: 2026-08-26T17:30:00Z) em segundos-epoch.
# Trata date GNU (Linux) e BSD (macOS). Ecoa vazio se nao conseguir parsear (fail-open a montante).
# DADO E DADO: o valor vai como argumento de -d/-j, nunca como comando.
_nbv_epoch_de() {
  local _iso="${1:-}" _e=""
  [ -n "$_iso" ] || { printf ''; return 0; }
  # GNU date: -d <str> (entende ISO com Z direto).
  _e="$(date -u -d "$_iso" +%s 2>/dev/null || true)"
  if [ -z "$_e" ]; then
    # BSD date (macOS): -j -f <fmt>. Tira o Z final e usa o formato sem timezone (ja tratamos como UTC).
    local _s="${_iso%Z}"
    _e="$(date -u -j -f '%Y-%m-%dT%H:%M:%S' "$_s" +%s 2>/dev/null || true)"
    if [ -z "$_e" ]; then
      # alguns carimbos podem vir sem os segundos (2026-08-26T17:30) — tenta esse formato tambem.
      _e="$(date -u -j -f '%Y-%m-%dT%H:%M' "$_s" +%s 2>/dev/null || true)"
    fi
  fi
  case "$_e" in
    ''|*[!0-9]*) printf '' ;;   # nao parseou de forma limpa -> vazio (fail-open)
    *) printf '%s' "$_e" ;;
  esac
  return 0
}

# _nbv_commits_desde <commit> — ecoa o NUMERO de commits de <commit> ate HEAD, por FATO (git rev-list
# --count <commit>..HEAD). Ecoa vazio (DESCONHECIDO) se: sem git, fora de repo, commit vazio/malformado,
# ou o commit nao existe neste repo. NUNCA trava, NUNCA erro. DADO E DADO: <commit> e argumento, so depois
# de passar no filtro de forma (_nbv_e_commit); o range e montado com o sha ja validado.
_nbv_commits_desde() {
  local _c="${1:-}"
  _nbv_repo_ok || { printf ''; return 0; }
  _nbv_e_commit "$_c" || { printf ''; return 0; }
  # o commit existe MESMO neste repo? (senao rev-list erra; tratamos como desconhecido, nao como 0).
  git cat-file -e "${_c}^{commit}" >/dev/null 2>&1 || { printf ''; return 0; }
  local _n
  _n="$(git rev-list --count "${_c}..HEAD" 2>/dev/null || true)"
  case "$_n" in
    ''|*[!0-9]*) printf '' ;;
    *) printf '%s' "$_n" ;;
  esac
  return 0
}

# _norte_bilhete_validade <arquivo-handoff> — o CORACAO da peca. Le o carimbo do cabecalho, calcula idade
# (agora - selado-em) e commits desde (selado-em-commit..HEAD), e ecoa UMA linha de veredito no stdout.
# SEMPRE exit 0 (fail-open: informa, nunca trava a retomada).
#   - kill-switch NORTE_VALIDADE=0 -> inerte: nada no stdout, exit 0.
#   - sem carimbo (selado-em ausente/nao-parseavel) -> "🟡 nao sei a idade — trate como suposicao".
#   - com idade mas commits DESCONHECIDOS (sem git/commit invalido) -> classifica so pela idade, e a linha
#     diz "(commits: nao sei)". Commits desconhecidos NUNCA viram 🔴 sozinhos (fail-honest do alarme).
#   - com idade E commits -> aplica os limiares e monta "(Nd, Nc)".
_norte_bilhete_validade() {
  local _arq="${1:-}"

  if _nbv_desligado; then
    return 0   # inerte: nada no stdout (a /norte-retomar segue sem a linha, como antes).
  fi

  if [ -z "$_arq" ] || [ ! -f "$_arq" ]; then
    printf '🟡 nao sei a idade deste bilhete — trate como suposicao (nao achei o arquivo). (mede so idade+commits; alerta pra conferir, nunca licenca pra executar)\n'
    return 0
  fi

  # limiares (env com fallback).
  local _dv _dr _cv _cr
  _dv="$(_nbv_int "${NB_VALIDADE_DIAS_VERDE:-}" 2)"
  _dr="$(_nbv_int "${NB_VALIDADE_DIAS_VERMELHO:-}" 7)"
  _cv="$(_nbv_int "${NB_VALIDADE_COMMITS_VERDE:-}" 3)"
  _cr="$(_nbv_int "${NB_VALIDADE_COMMITS_VERMELHO:-}" 20)"

  # 1) idade (agora - selado-em).
  local _selo_em _epoch_selo _agora _dias
  _selo_em="$(_nbv_le_campo "$_arq" 'selado-em')"
  _epoch_selo="$(_nbv_epoch_de "$_selo_em")"
  if [ -z "$_epoch_selo" ]; then
    # sem carimbo de tempo (bilhete velho pre-peca, ou carimbo malformado) -> fail-open honesto.
    printf '🟡 nao sei a idade deste bilhete — trate como suposicao (sem carimbo "selado-em" que eu consiga ler). (mede so idade+commits; alerta pra conferir, nunca licenca pra executar)\n'
    return 0
  fi
  _agora="$(date -u +%s 2>/dev/null || echo 0)"
  case "$_agora" in ''|*[!0-9]*) _agora=0 ;; esac
  if [ "$_agora" -le 0 ] || [ "$_epoch_selo" -gt "$_agora" ]; then
    # relogio esquisito ou carimbo no futuro -> nao invento idade negativa; trato como desconhecido.
    printf '🟡 nao sei a idade deste bilhete — trate como suposicao (o carimbo de data nao bate com o relogio). (mede so idade+commits; alerta pra conferir, nunca licenca pra executar)\n'
    return 0
  fi
  _dias=$(( (_agora - _epoch_selo) / 86400 ))

  # 2) commits desde (selado-em-commit..HEAD) — pode ser DESCONHECIDO (sem git / sem/invalido commit).
  local _selo_commit _commits _commits_txt
  _selo_commit="$(_nbv_le_campo "$_arq" 'selado-em-commit')"
  _commits="$(_nbv_commits_desde "$_selo_commit")"
  if [ -n "$_commits" ]; then
    _commits_txt="${_commits}c"
  else
    _commits_txt="commits: nao sei"
  fi

  # 3) veredito. VERMELHO ganha do amarelo; VERDE e o mais restrito. Commits DESCONHECIDOS nunca disparam
  #    vermelho sozinhos (so a idade pode, nesse caso).
  local _estado="amarelo"   # default = envelhecido (o meio)
  # vermelho?
  if [ "$_dias" -gt "$_dr" ]; then
    _estado="vermelho"
  elif [ -n "$_commits" ] && [ "$_commits" -gt "$_cr" ]; then
    _estado="vermelho"
  # verde? (precisa idade <= verde E commits <= verde; commits desconhecidos NAO deixam ficar verde —
  #         na duvida da mudanca do mundo, o piso e amarelo, nunca verde).
  elif [ "$_dias" -le "$_dv" ] && [ -n "$_commits" ] && [ "$_commits" -le "$_cv" ]; then
    _estado="verde"
  fi

  local _nota='(mede so idade+commits, nao le o conteudo; alerta pra conferir, nunca licenca pra executar)'
  case "$_estado" in
    verde)
      printf '🟢 fresco (%sd, %s) — recente; ainda assim confira. %s\n' "$_dias" "$_commits_txt" "$_nota" ;;
    vermelho)
      printf '🔴 velho — confira antes de seguir (%sd, %s). %s\n' "$_dias" "$_commits_txt" "$_nota" ;;
    amarelo|*)
      printf '🟡 envelhecido (%sd, %s) — confira antes de confiar. %s\n' "$_dias" "$_commits_txt" "$_nota" ;;
  esac
  return 0
}
