#!/usr/bin/env bash
# _aplicar.sh — FONTE UNICA dos portoes APLICAR e DESFAZER (NRT-_990212 passo 9 fatia 2).
# Sourceado pelos helpers bin/nb-aplicar e bin/nb-desfazer. Depende da lib irma _sombra.sh (os helpers
# de sha/realpath/raiz sao reusados dali — a caixa tem UMA fonte de verdade por familia).
#
# A ideia (padaria): o ENSAIO (SOMBRA) mostrou "como ficaria" numa copia e provou o real intocado. Agora
# a caixa pode APLICAR de verdade — mas SO se o mundo nao mudou desde o ensaio, e SEMPRE com um backup
# provado antes de escrever. E pode DESFAZER — voltando byte-a-byte pro original, tambem so se o mundo
# nao mudou desde o aplicar. Nada e' cego: cada passo re-mede o disco e recusa em vermelho honesto.
#
# VEREDITO DO PAINEL (Proposta A, SEM HMAC/segredo): o anti-forja e' RE-MEDIR o hash do disco, nao um
# segredo. A ferramenta e' HONESTA: ela nao protege contra quem JA tem escrita no seu $HOME (esse ja
# poderia editar o arquivo direto). O que ela GARANTE: nao aplica se o arquivo mudou desde o ensaio,
# faz backup provado antes de escrever, e desfaz so se o backup estiver integro.
#
# LEIS (herdadas da SOMBRA + as desta fatia):
#   - Le SO o RECIBO do disco. NUNCA aceita alvo/hash por argumento (senao "aplicar" viraria "escreva
#     onde eu mandar"). O unico argumento e' o CAMINHO do recibo, e ele tem que morar dentro de
#     $HOME/.norte-box/sombra/ (realpath-gate). Fora daí -> recusa.
#   - RE-CHECA na hora as leis da SOMBRA sobre o alvo: recusa symlink ([ -L ]), recusa fora do $HOME
#     (realpath gate), o arquivo tem que existir. Fail-CLOSED.
#   - GATE "recusa se mudou desde o ensaio": sha256(alvo agora) == sha_ensaio do recibo. Diferente ->
#     vermelho, NAO escreve NADA.
#   - ANTI-FORJA sem segredo (2 travas): (1) o sombra= do recibo TEM que morar DENTRO da pasta do
#     proprio recibo (co-localizacao — o ensaio grava os dois no mesmo dir); apontar pra fora -> vermelho.
#     (2) sha256(sombra do recibo) == sha_sombra do recibo. Sem a trava (1), a re-medida (2) so provava
#     "a sombra que EU apontei bate com o hash que EU escrevi" (furo #1 do Val).
#   - BACKUP PROVADO antes da 1a escrita: copia o alvo pra .norte-box/aplicado/<slug>/<ts>/antes e
#     confere sha(backup)==sha(alvo). Só então escreve o real.
#   - RE-MEDE depois de escrever: sha256(alvo) == sha_sombra -> 🟢. Senão restaura o backup e 🔴.
#   - DESFAZER honesto: só volta se o alvo AGORA == sha_depois (ninguem editou depois do aplicar) e o
#     backup == sha_antes. Senão vermelho (desfazer cego apagaria trabalho novo).
#   - PRIVADO + LOCAL + ZERO-REDE. set -u. Portabilidade macOS (bash 3.2).
set -u

# --- garante que os helpers da familia SOMBRA existam (sha/realpath/raiz/slug). Se o chamador ja
#     sourceou _sombra.sh, reusa; senao tenta sourcear ao lado. Fail-honest se nao achar. ---
if ! command -v _norte_sombra_sha >/dev/null 2>&1; then
  _apl_self_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)"
  if [ -n "${_apl_self_dir:-}" ] && [ -f "${_apl_self_dir}/_sombra.sh" ]; then
    # shellcheck source=/dev/null
    . "${_apl_self_dir}/_sombra.sh" 2>/dev/null || true
  fi
fi

# --- garante o FREIO (a trava-mestra das acoes) — mesmo padrao robusto do _sombra.sh. Se nao carregar,
#     degrade FAIL-OPEN pra a sessao (stub que passa): a ausencia da peca do freio nunca trava a caixa. ---
if ! command -v _norte_freio_checa >/dev/null 2>&1; then
  _apl_freio_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)"
  if [ -n "${_apl_freio_dir:-}" ] && [ -f "${_apl_freio_dir}/_freio.sh" ]; then
    # shellcheck source=/dev/null
    . "${_apl_freio_dir}/_freio.sh" 2>/dev/null || true
  fi
  command -v _norte_freio_checa >/dev/null 2>&1 || _norte_freio_checa() { return 0; }
fi

# _norte_aplicar_le <recibo> <chave> — le o valor de "chave=valor" do recibo (1a ocorrencia). Vazio se
# nao achar. Le so o texto do disco; nao faz eval (o recibo e' dado, nao codigo).
_norte_aplicar_le() {
  local _rec="${1:-}" _k="${2:-}"
  [ -n "$_rec" ] && [ -n "$_k" ] && [ -f "$_rec" ] || return 1
  local _l
  while IFS= read -r _l || [ -n "$_l" ]; do
    case "$_l" in
      "${_k}="*) printf '%s' "${_l#${_k}=}"; return 0 ;;
    esac
  done < "$_rec"
  return 1
}

# _norte_aplicar_red <caminho> — versao redigida pro rosto (usa _redact se disponivel; senao [arquivo]).
_norte_aplicar_red() {
  local _c="${1:-}"
  if command -v _redact >/dev/null 2>&1; then
    local _r; _r="$(printf '%s' "$_c" | _redact 2>/dev/null)" || _r="[arquivo]"
    [ -n "$_r" ] && { printf '%s' "$_r"; return 0; }
    printf '[arquivo]'; return 0
  fi
  printf '[arquivo]'
}

# _norte_aplicar_gate_alvo <alvo> — RE-CHECA as leis da SOMBRA sobre o alvo NA HORA. Ecoa o canonico
# no stdout se OK; caso contrario ecoa a mensagem 🔴 e devolve !=0. Nao escreve nada.
#   1 -> vermelho deliberado (symlink / fora do HOME / nao existe / nao resolve)
_norte_aplicar_gate_alvo() {
  local _alvo="${1:-}"
  # RECUSA symlink DURO antes de [ -f ] (que seguiria o link).
  if [ -L "$_alvo" ]; then
    printf '🔴 alvo recusado: o caminho virou um atalho (symlink) — aplicar por atalho tocaria outro arquivo.\n'
    return 1
  fi
  if [ ! -f "$_alvo" ]; then
    printf '🔴 alvo recusado: o arquivo do recibo nao existe mais.\n'
    return 1
  fi
  local _canon _homec
  _canon="$(_norte_sombra_realpath "$_alvo")" || { printf '🔴 alvo recusado: nao consegui resolver o caminho do arquivo.\n'; return 1; }
  [ -n "$_canon" ] || { printf '🔴 alvo recusado: caminho vazio.\n'; return 1; }
  _homec="$(_norte_sombra_realpath "${HOME}")" || { printf '🔴 alvo recusado: nao consegui resolver o HOME.\n'; return 1; }
  [ -n "$_homec" ] || { printf '🔴 alvo recusado: HOME vazio.\n'; return 1; }
  case "$_canon" in
    "$_homec"/*) : ;;
    *) printf '🔴 alvo recusado: o arquivo esta fora do seu espaco de usuario. Por seguranca, so aplico dentro da sua pasta.\n'; return 1 ;;
  esac
  printf '%s' "$_canon"
  return 0
}

# =====================================================================================================
# nb-aplicar: aplica de verdade a sombra do recibo no arquivo real, com backup provado e re-medida.
#   0 -> ✅ APLIQUEI (arquivo ficou com o conteudo do recibo, sem mudar desde a medida; NAO e "revisado
#        por humano" — so prova conteudo+integridade)   1 -> 🔴 vermelho honesto   2 -> 🟡 inerte (kill)
# =====================================================================================================
_norte_aplicar() {
  local _rec="${1:-}"

  # FREIO (precedencia freio > env): se a trava-mestra esta puxada, aborta AQUI, sem agir.
  _norte_freio_checa || return 1

  # kill-switch: NORTE_APLICAR=0 (ou NORTE_SOMBRA=0) -> inerte.
  case "${NORTE_APLICAR:-1}" in
    0|no|nao|off|false) printf '🟡 o portao "aplicar" nao esta ligado nesta maquina (NORTE_APLICAR=0).\n'; return 2 ;;
  esac
  case "${NORTE_SOMBRA:-1}" in
    0|no|nao|off|false) printf '🟡 o portao "sombra/aplicar" nao esta ligado nesta maquina (NORTE_SOMBRA=0).\n'; return 2 ;;
  esac

  command -v _norte_sombra_sha >/dev/null 2>&1 || { printf '🟡 nao consegui aplicar: portao incompleto (falta a lib da sombra).\n'; return 2; }

  # --- 1) recibo tem que existir e morar DENTRO de $HOME/.norte-box/sombra/ (realpath-gate) ---
  if [ -z "$_rec" ]; then printf '🟡 diga qual recibo eu aplico (o .recibo que o ensaio gerou).\n'; return 2; fi
  if [ -L "$_rec" ]; then printf '🔴 recibo recusado: o caminho e um atalho (symlink).\n'; return 1; fi
  if [ ! -f "$_rec" ]; then printf '🟡 nao achei esse recibo — ensaie de novo e me passe o .recibo que ele gera.\n'; return 2; fi
  local _rec_c _raiz_c
  _rec_c="$(_norte_sombra_realpath "$_rec")" || { printf '🔴 recibo recusado: nao consegui resolver o caminho.\n'; return 1; }
  _raiz_c="$(_norte_sombra_realpath "$(_norte_sombra_raiz)")" || { printf '🔴 recibo recusado: nao consegui resolver a pasta das sombras.\n'; return 1; }
  case "$_rec_c" in
    "$_raiz_c"/*) : ;;
    *) printf '🔴 recibo recusado: so aplico recibos que moram na pasta das sombras (%s/...).\n' "$(_norte_aplicar_red "$_raiz_c")"; return 1 ;;
  esac

  # --- 2) le os 3 fatos do recibo (NUNCA por argumento) ---
  local _alvo _sha_ensaio _sha_sombra _sombra
  _alvo="$(_norte_aplicar_le "$_rec" alvo)"       || { printf '🔴 recibo invalido: falta o campo alvo=.\n'; return 1; }
  _sha_ensaio="$(_norte_aplicar_le "$_rec" sha_ensaio)" || { printf '🔴 recibo invalido: falta o campo sha_ensaio=.\n'; return 1; }
  _sha_sombra="$(_norte_aplicar_le "$_rec" sha_sombra)" || { printf '🔴 recibo invalido: falta o campo sha_sombra=.\n'; return 1; }
  _sombra="$(_norte_aplicar_le "$_rec" sombra)"   || _sombra=""
  [ -n "$_alvo" ] && [ -n "$_sha_ensaio" ] && [ -n "$_sha_sombra" ] || { printf '🔴 recibo invalido: campos vazios.\n'; return 1; }

  # --- 3) re-checa as leis da SOMBRA sobre o alvo NA HORA (symlink/fora-do-HOME/existe) ---
  local _canon _gate
  _gate="$(_norte_aplicar_gate_alvo "$_alvo")"; local _grc=$?
  if [ "$_grc" != "0" ]; then printf '%s\n' "$_gate"; return 1; fi
  _canon="$_gate"

  # --- 4) GATE "mudou desde o ensaio?": sha(alvo agora) == sha_ensaio? Diferente -> 🔴, NAO escreve. ---
  local _sha_agora
  _sha_agora="$(_norte_sombra_sha "$_canon")" || { printf '🔴 nao consegui medir o arquivo agora — abortado (nada aplicado).\n'; return 1; }
  if [ "$_sha_agora" != "$_sha_ensaio" ]; then
    printf '🔴 o arquivo mudou desde o ensaio; ensaie de novo.\n'
    printf '   (por seguranca eu NAO apliquei nada — o que voce ensaiou ja nao vale pro arquivo de agora.)\n'
    return 1
  fi

  # --- 5) ANTI-FORJA (sem segredo): sha(sombra do recibo) == sha_sombra? Adulterado -> 🔴. ---
  if [ -z "$_sombra" ] || [ ! -f "$_sombra" ]; then
    printf '🔴 nao achei a copia (sombra) que o recibo aponta — abortado (nada aplicado).\n'; return 1
  fi
  if [ -L "$_sombra" ]; then printf '🔴 a sombra do recibo virou atalho (symlink) — recusado.\n'; return 1; fi

  # --- 5a) GATE DE CO-LOCALIZACAO (furo #1 do Val, NRT-_990212): o sombra= do recibo TEM que resolver
  #        (realpath) pra DENTRO da pasta do PROPRIO recibo. O ensaio grava o recibo e a sombra no MESMO
  #        dir (._sombra_final + ._sombra_final.recibo). Se sombra= aponta pra FORA -> recusa. Isso mata
  #        o vetor "editar sombra= do recibo pra um arquivo qualquer que o atacante criou + sha_sombra=
  #        pro hash dele" (a re-medida sozinha nao pega: ambos os lados seriam do atacante).
  #        Sem isso, a "prova por hash" so provava "a sombra que EU apontei bate com o hash que EU escrevi".
  local _rec_dir _somb_canon
  _rec_dir="$(dirname "$_rec_c")"
  _somb_canon="$(_norte_sombra_realpath "$_sombra")" || { printf '🔴 nao consegui resolver o caminho da copia (sombra) — abortado (nada aplicado).\n'; return 1; }
  [ -n "$_somb_canon" ] || { printf '🔴 caminho da copia (sombra) vazio — abortado.\n'; return 1; }
  case "$_somb_canon" in
    "$_rec_dir"/*) : ;;
    *) printf '🔴 esse recibo aponta a sombra pra fora da pasta dele — recusei (nada aplicado).\n'; return 1 ;;
  esac
  local _sha_sombra_agora
  _sha_sombra_agora="$(_norte_sombra_sha "$_sombra")" || { printf '🔴 nao consegui medir a copia (sombra) — abortado.\n'; return 1; }
  if [ "$_sha_sombra_agora" != "$_sha_sombra" ]; then
    printf '🔴 o recibo/copia nao batem (parecem adulterados) — recusado, nada aplicado.\n'; return 1
  fi

  # --- 6) BACKUP PROVADO antes da 1a escrita ---
  local _slug _ts _apldir _backup _recaplic
  # aplicado mora ao lado de sombra, sob $HOME/.norte-box/aplicado (a mesma raiz LOCAL da familia).
  _apldir="${HOME}/.norte-box/aplicado"
  _slug="$(_norte_sombra_slug "$(basename "$_canon")")"; [ -n "$_slug" ] || _slug="alvo"
  _ts="$(date -u +%Y%m%dT%H%M%SZ 2>/dev/null || echo t)"
  local _dstdir="${_apldir}/${_slug}/${_ts}"
  mkdir -p "$_dstdir" 2>/dev/null || { printf '🔴 nao consegui preparar o backup (disco nao gravavel) — abortado.\n'; return 1; }
  _backup="${_dstdir}/antes"
  cp -- "$_canon" "$_backup" 2>/dev/null || { printf '🔴 nao consegui fazer o backup do arquivo — abortado (nada aplicado).\n'; return 1; }
  # confere: sha(backup) == sha(alvo agora)? Se nao bater, o backup nao serve -> NAO escreve o real.
  local _sha_backup
  _sha_backup="$(_norte_sombra_sha "$_backup")" || { printf '🔴 nao consegui medir o backup — abortado (nada aplicado).\n'; return 1; }
  if [ "$_sha_backup" != "$_sha_agora" ]; then
    printf '🔴 o backup nao confere com o arquivo — abortado por seguranca (nada aplicado).\n'; return 1
  fi
  # grava o recibo-de-aplicacao (a testemunha pro DESFAZER).
  _recaplic="${_dstdir}/recibo.recibo-aplic"
  {
    printf 'alvo=%s\n' "$_canon"
    printf 'sha_antes=%s\n' "$_sha_ensaio"
    printf 'sha_depois=%s\n' "$_sha_sombra"
    printf 'backup=%s\n' "$_backup"
  } > "$_recaplic" 2>/dev/null || { printf '🔴 nao consegui gravar o recibo de aplicacao — abortado (nada aplicado).\n'; return 1; }

  # --- 7) grava o CONTEUDO da sombra no alvo real (cp por conteudo) ---
  cp -- "$_sombra" "$_canon" 2>/dev/null || {
    # falhou a escrita: tenta restaurar do backup (defesa) e vermelho.
    cp -- "$_backup" "$_canon" 2>/dev/null || true
    printf '🔴 nao consegui escrever no arquivo — restaurei do backup, nada foi perdido.\n'; return 1
  }

  # --- 8) RE-MEDE: sha(alvo) == sha_sombra? ---
  local _sha_final
  _sha_final="$(_norte_sombra_sha "$_canon")" || _sha_final=""
  if [ "$_sha_final" = "$_sha_sombra" ]; then
    printf '✅ APLIQUEI a troca do ensaio. Conferi que o arquivo ficou com esse conteudo e que ele NAO tinha mudado desde a medicao do recibo. Guardei um backup do antes — da pra desfazer.\n'
    printf '   alvo: %s   (%s -> %s)\n' "$(_norte_aplicar_red "$_canon")" "$(printf '%s' "$_sha_ensaio" | cut -c1-12)" "$(printf '%s' "$_sha_sombra" | cut -c1-12)"
    printf 'NB_APLICAR_RECIBO=%s\n' "$_recaplic"
    return 0
  fi
  # nao bateu: restaura o backup na hora e vermelho.
  cp -- "$_backup" "$_canon" 2>/dev/null || true
  printf '🔴 a escrita nao ficou como o ensaio (hash nao bateu) — restaurei o original do backup.\n'
  return 1
}

# =====================================================================================================
# nb-desfazer: restaura o backup no alvo real, so se o mundo nao mudou desde o aplicar.
#   0 -> 🟢 DESFEITO   1 -> 🔴 vermelho honesto   2 -> 🟡 inerte (kill-switch)
# =====================================================================================================
_norte_desfazer() {
  local _rec="${1:-}"

  # FREIO (precedencia freio > env): se a trava-mestra esta puxada, aborta AQUI, sem agir.
  _norte_freio_checa || return 1

  case "${NORTE_APLICAR:-1}" in
    0|no|nao|off|false) printf '🟡 o portao "desfazer" nao esta ligado nesta maquina (NORTE_APLICAR=0).\n'; return 2 ;;
  esac
  case "${NORTE_SOMBRA:-1}" in
    0|no|nao|off|false) printf '🟡 o portao "sombra/desfazer" nao esta ligado nesta maquina (NORTE_SOMBRA=0).\n'; return 2 ;;
  esac

  command -v _norte_sombra_sha >/dev/null 2>&1 || { printf '🟡 nao consegui desfazer: portao incompleto.\n'; return 2; }

  # --- 1) recibo-aplic tem que existir e morar sob $HOME/.norte-box/aplicado/ ---
  if [ -z "$_rec" ]; then printf '🟡 diga qual recibo-de-aplicacao eu desfaco (o .recibo-aplic que o aplicar gerou).\n'; return 2; fi
  if [ -L "$_rec" ]; then printf '🔴 recibo recusado: o caminho e um atalho (symlink).\n'; return 1; fi
  if [ ! -f "$_rec" ]; then printf '🟡 nao achei esse recibo de aplicacao.\n'; return 2; fi
  local _rec_c _apl_c
  _rec_c="$(_norte_sombra_realpath "$_rec")" || { printf '🔴 recibo recusado: nao consegui resolver o caminho.\n'; return 1; }
  _apl_c="$(_norte_sombra_realpath "${HOME}/.norte-box/aplicado")" || _apl_c=""
  if [ -n "$_apl_c" ]; then
    case "$_rec_c" in
      "$_apl_c"/*) : ;;
      *) printf '🔴 recibo recusado: so desfaco a partir de recibos na pasta de aplicacao.\n'; return 1 ;;
    esac
  fi

  # --- 2) le os fatos ---
  local _alvo _sha_antes _sha_depois _backup
  _alvo="$(_norte_aplicar_le "$_rec" alvo)"        || { printf '🔴 recibo invalido: falta alvo=.\n'; return 1; }
  _sha_antes="$(_norte_aplicar_le "$_rec" sha_antes)"   || { printf '🔴 recibo invalido: falta sha_antes=.\n'; return 1; }
  _sha_depois="$(_norte_aplicar_le "$_rec" sha_depois)" || { printf '🔴 recibo invalido: falta sha_depois=.\n'; return 1; }
  _backup="$(_norte_aplicar_le "$_rec" backup)"    || { printf '🔴 recibo invalido: falta backup=.\n'; return 1; }
  [ -n "$_alvo" ] && [ -n "$_sha_antes" ] && [ -n "$_sha_depois" ] && [ -n "$_backup" ] || { printf '🔴 recibo invalido: campos vazios.\n'; return 1; }

  # --- 3) re-checa as leis da SOMBRA sobre o alvo ---
  local _canon _gate
  _gate="$(_norte_aplicar_gate_alvo "$_alvo")"; local _grc=$?
  if [ "$_grc" != "0" ]; then printf '%s\n' "$_gate"; return 1; fi
  _canon="$_gate"

  # --- 4) o alvo AGORA tem que estar como o aplicar deixou (== sha_depois). Se mudou depois, NAO
  #        desfaz cego (apagaria trabalho novo). ---
  local _sha_agora
  _sha_agora="$(_norte_sombra_sha "$_canon")" || { printf '🔴 nao consegui medir o arquivo agora — abortado.\n'; return 1; }
  if [ "$_sha_agora" != "$_sha_depois" ]; then
    printf '🔴 o arquivo mudou DEPOIS do aplicar; desfazer cego apagaria trabalho novo.\n'
    printf '   (por seguranca eu NAO desfiz nada.)\n'
    return 1
  fi

  # --- 5) o backup tem que estar integro (== sha_antes) ---
  if [ -L "$_backup" ]; then printf '🔴 o backup virou atalho (symlink) — recusado.\n'; return 1; fi
  if [ ! -f "$_backup" ]; then printf '🔴 nao achei o backup do original — nao da pra desfazer com seguranca.\n'; return 1; fi
  local _sha_backup
  _sha_backup="$(_norte_sombra_sha "$_backup")" || { printf '🔴 nao consegui medir o backup — abortado.\n'; return 1; }
  if [ "$_sha_backup" != "$_sha_antes" ]; then
    printf '🔴 o backup do original parece corrompido (hash nao bate) — nao desfaco as cegas.\n'; return 1
  fi

  # --- 6) restaura o backup no alvo (cp por conteudo) e re-mede ---
  cp -- "$_backup" "$_canon" 2>/dev/null || { printf '🔴 nao consegui restaurar o backup — abortado.\n'; return 1; }
  local _sha_final
  _sha_final="$(_norte_sombra_sha "$_canon")" || _sha_final=""
  if [ "$_sha_final" = "$_sha_antes" ]; then
    printf '✅ DESFIZ — o arquivo voltou ao conteudo de antes (conferido).\n'
    printf '   alvo: %s   (%s)\n' "$(_norte_aplicar_red "$_canon")" "$(printf '%s' "$_sha_antes" | cut -c1-12)"
    return 0
  fi
  printf '🔴 a restauracao nao ficou como o original (hash nao bateu) — algo errado, nao confie.\n'
  return 1
}
