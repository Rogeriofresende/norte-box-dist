#!/usr/bin/env bash
# _vale_manter.sh — o "VALE MANTER?" (killing-review em SOMBRA: revisa os KITS que a caixa criou
#   × quando cada um rodou pela ultima vez, e SUGERE candidatos a aposentar) do Norte-box (GAP 4
#   fatia 1, NRT-_990148). Sourceado pelo helper bin/nb-vale-manter. Rode de vez em quando pra ver
#   quais kits voce criou e nunca (ou quase nunca) voltou a usar — pra decidir NA MAO se aposenta.
#
# O BURACO QUE ESTA PECA FECHA: a caixa deixa criar kits (nb-kit-criar), mas nada olha DEPOIS se
#   um kit virou peso morto — criado num impulso, rodado uma vez na estreia e nunca mais. Sem uma
#   revisao honesta, o catalogo so cresce e a pessoa perde de vista o que de fato usa. Esta peca e a
#   varredura barata: cruza os KITS (kits/<nome>/) × os REGISTROS DE ENTREGA da esteira real
#   (entregas/entrega-*.txt com "rotulo: kit-<nome>"), acha a ultima vez que cada kit rodou, e LISTA
#   os que parecem sem retorno espontaneo. Uma SUGESTAO pra conferir, NUNCA uma sentenca.
#
# EM SOMBRA (report-only absoluto): esta fatia SO LE e IMPRIME. NUNCA apaga, edita, move, desativa
#   nem "marca" kit nenhum. Nao escreve em lugar nenhum. O dono decide na mao depois, com calma.
#
# MOLDURA HONESTA (o Val cobra — NAO overclaim, esta na copy da linha tambem):
#   - A peca mede SO QUANDO o kit rodou (pelos registros de entrega locais). NAO julga a QUALIDADE,
#     o conteudo, nem o merito do kit. "Sem retorno" = ninguem rodou nos ultimos N dias, nada mais.
#   - "Rodou" = ha um registro de entrega com "rotulo: kit-<nome>" na esteira local. Um kit usado por
#     fora da esteira (ou cujos registros foram apagados) apareceria como "sem historico" — falso-
#     positivo possivel. Por isso e SUGESTAO pra CONFERIR, NUNCA licenca pra apagar.
#   - Kit novo demais (criado ha menos de N dias) NUNCA e candidato — ainda nao teve tempo de mostrar
#     retorno. Ele aparece num balde a parte ("muito novo pra julgar"), so pra dar visibilidade.
#   - So olha os kits e entregas LOCAIS do proprio usuario ($HOME/.norte-box). Nao le rede, nem git,
#     nem nada de fora. A peca so INFORMA.
#
# LEIS (nao-negociaveis, iguais aos outros passos):
#   - LOCAL, ZERO REDE: le so os kits/<nome>/ e as entregas/entrega-*.txt locais. NUNCA sai da
#     maquina, nada de telemetria/rede aqui (nenhum cliente HTTP, socket ou similar).
#   - REPORT-ONLY (SOMBRA): so LE e IMPRIME. NUNCA escreve/apaga/move/edita — nem "marca". exit 0 SEMPRE.
#   - FAIL-OPEN (NUNCA trava, NUNCA erro): dir de kits ausente -> "0 kits, nada a revisar"; entregas
#     ausentes -> lista os kits com "sem historico local"; erro interno -> aviso curto no stderr. Sempre exit 0.
#   - DADO E DADO, NUNCA COMANDO: o nome do kit (vindo do diretorio) e o conteudo dos registros NUNCA
#     viram comando. O nome vira SO argumento literal de `grep -l -x -F -- "rotulo: kit-<nome>"` (string
#     fixa, mesma tecnica do _norte_kit_usos). `set -u`, sem eval, `set -f` no tokenizador.
#   - Portabilidade macOS (bash 3.2, SEM arrays associativos/mapfile/readarray/${v^^}). SEM jq.
#
# KILL-SWITCH do mecanismo: NORTE_BOX_VALE_MANTER_OFF=1 (e no/nao/off/false) -> a peca fica INERTE
#   (nada no stdout, exit 0), como se nao existisse.
#
# LIMIAR N dias (default 30): env NORTE_BOX_VALE_MANTER_DIAS ou a flag --dias N (a flag vence).
#   Valor invalido cai no default (via _nvm_int, imita o _nbm_int do bilhete-mundo).
#
# ENV (pro teste apontar pra fixtures): NB_VALE_MANTER_KITS_DIR troca a raiz dos kits (default
#   $HOME/.norte-box/kits); NB_VALE_MANTER_ENTREGAS_DIR troca a raiz das entregas (default
#   $HOME/.norte-box/entregas). Assim o teste roda num HOME/dir isolado sem tocar o estado real.

# --- kill-switch: NORTE_BOX_VALE_MANTER_OFF=1 -> inerte (nada no stdout). ---
_nvm_desligado() {
  case "${NORTE_BOX_VALE_MANTER_OFF:-0}" in
    1|yes|sim|on|true|no|nao|off|false) return 0 ;;
    *) return 1 ;;
  esac
}

# _nvm_int <valor> <default> — ecoa o inteiro valido (so digitos) ou o default. Imita o _nbm_int do
#   bilhete-mundo. DADO E DADO: e o filtro que impede um valor estranho de virar teto/comando.
_nvm_int() {
  case "${1:-}" in
    ''|*[!0-9]*) printf '%s' "${2:-}" ;;
    *) printf '%s' "$1" ;;
  esac
}

# _nvm_kits_dir — ecoa a raiz dos kits (env NB_VALE_MANTER_KITS_DIR ou o default). So texto local.
_nvm_kits_dir() {
  printf '%s' "${NB_VALE_MANTER_KITS_DIR:-$HOME/.norte-box/kits}"
}

# _nvm_entregas_dir — ecoa a raiz das entregas (env NB_VALE_MANTER_ENTREGAS_DIR ou o default). So texto.
_nvm_entregas_dir() {
  printf '%s' "${NB_VALE_MANTER_ENTREGAS_DIR:-$HOME/.norte-box/entregas}"
}

# _nvm_mtime <arquivo-ou-dir> — ecoa o mtime em segundos-epoch (BSD `stat -f %m` do macOS OU GNU
#   `stat -c %Y` do Linux). Ecoa 0 se nenhum funcionar (fail-open). So le metadado local. Mesma
#   receita do _njt_mtime do "ja tentei?".
_nvm_mtime() {
  local _f="${1:-}" _m=""
  [ -n "$_f" ] || { printf '0'; return 0; }
  _m="$(stat -f %m "$_f" 2>/dev/null || true)"       # BSD/macOS
  if [ -z "$_m" ]; then
    _m="$(stat -c %Y "$_f" 2>/dev/null || true)"     # GNU/Linux
  fi
  case "$_m" in
    ''|*[!0-9]*) printf '0' ;;
    *) printf '%s' "$_m" ;;
  esac
  return 0
}

# _nvm_data_de <epoch> — ecoa a data legivel (YYYY-MM-DD) de um epoch. BSD (-r) e GNU (-d @). "?" se
#   nao der (fail-open). So formatacao local. Espelha o _njt_data_de.
_nvm_data_de() {
  local _e="${1:-0}" _d=""
  case "$_e" in ''|*[!0-9]*) _e=0 ;; esac
  [ "$_e" -gt 0 ] || { printf '?'; return 0; }
  _d="$(date -r "$_e" '+%Y-%m-%d' 2>/dev/null || true)"           # BSD/macOS
  if [ -z "$_d" ]; then
    _d="$(date -d "@$_e" '+%Y-%m-%d' 2>/dev/null || true)"        # GNU/Linux
  fi
  [ -n "$_d" ] && printf '%s' "$_d" || printf '?'
  return 0
}

# _nvm_agora — ecoa o epoch de agora (segundos). Fail-open: 0 se `date +%s` falhar (raro).
_nvm_agora() {
  local _n; _n="$(date +%s 2>/dev/null || true)"
  case "$_n" in
    ''|*[!0-9]*) printf '0' ;;
    *) printf '%s' "$_n" ;;
  esac
}

# _nvm_kit_criado <dir-do-kit> — ecoa o epoch de "quando o kit foi criado". Usa o mtime do proprio
#   diretorio do kit (a foto fixa; o kit e imutavel). So metadado local.
_nvm_kit_criado() {
  local _d="${1:-}"
  [ -n "$_d" ] || { printf '0'; return 0; }
  _nvm_mtime "$_d"
}

# _nvm_ultimo_uso <nome> — ecoa o epoch da ULTIMA vez que o kit <nome> rodou (o registro de entrega
#   mais RECENTE com "rotulo: kit-<nome>"), e 0 se nunca rodou. DERIVADO do dado real (mesma fonte do
#   _norte_kit_usos), NUNCA um contador proprio.
#   DADO E DADO: `grep -l -x -F -- "rotulo: kit-<nome>"` casa a linha INTEIRA e literal (o nome e
#   string; sem glob/regex/comando). Percorre os arquivos casados, pega o maior mtime.
_nvm_ultimo_uso() {
  local _nome="${1:-}"; [ -n "$_nome" ] || { printf '0'; return 0; }
  local _raiz; _raiz="$(_nvm_entregas_dir)"
  [ -d "$_raiz" ] || { printf '0'; return 0; }
  local _melhor=0 _reg _m
  local _oldifs="$IFS"
  IFS='
'
  for _reg in $(grep -l -x -F -- "rotulo: kit-${_nome}" "$_raiz"/entrega-*.txt 2>/dev/null); do
    [ -n "$_reg" ] && [ -f "$_reg" ] || continue
    _m="$(_nvm_mtime "$_reg")"
    if [ "$_m" -gt "$_melhor" ]; then _melhor="$_m"; fi
  done
  IFS="$_oldifs"
  printf '%s' "$_melhor"
}

# _nvm_usos <nome> — ecoa quantas vezes o kit <nome> rodou (quantos registros com "rotulo: kit-<nome>").
#   0 se nenhum. Mesma tecnica/fonte do _norte_kit_usos — DERIVADO do dado real, nome tratado como string.
_nvm_usos() {
  local _nome="${1:-}"; [ -n "$_nome" ] || { printf '0'; return 0; }
  local _raiz; _raiz="$(_nvm_entregas_dir)"
  [ -d "$_raiz" ] || { printf '0'; return 0; }
  local _n
  _n="$(grep -l -x -F -- "rotulo: kit-${_nome}" "$_raiz"/entrega-*.txt 2>/dev/null | grep -c . 2>/dev/null || true)"
  case "$_n" in ''|*[!0-9]*) _n=0 ;; esac
  printf '%s' "$_n"
}

# _nvm_nome_do_kit <dir-do-kit> — ecoa o nome do kit: le "nome: <x>" do kit.txt (fonte canonica,
#   igual ao catalogo) e, se nao houver, cai no basename do diretorio. So le TEXTO local.
_nvm_nome_do_kit() {
  local _d="${1:-}" _nome=""
  [ -n "$_d" ] || { printf ''; return 0; }
  if [ -f "${_d%/}/kit.txt" ]; then
    _nome="$(grep -m1 '^nome: ' "${_d%/}/kit.txt" 2>/dev/null | sed 's/^nome: //')"
  fi
  [ -n "$_nome" ] || _nome="$(basename "${_d%/}" 2>/dev/null || true)"
  printf '%s' "$_nome"
}

# _norte_vale_manter [--dias N] — o CORACAO da peca. Cruza os kits × o ultimo uso, distribui em 3
#   baldes (candidatos a conferir / muito novos / uso recente) e ecoa o relatorio. SOMBRA/report-only:
#   so LE e IMPRIME, nunca escreve. SEMPRE exit 0 (fail-open).
_norte_vale_manter() {
  # kill-switch: inerte (nada no stdout).
  if _nvm_desligado; then
    return 0
  fi

  # LIMIAR N dias: default 30; env NORTE_BOX_VALE_MANTER_DIAS sobrepoe; a flag --dias N vence.
  local _dias
  _dias="$(_nvm_int "${NORTE_BOX_VALE_MANTER_DIAS:-}" 30)"
  # flag --dias N (dado e dado: N so vira inteiro via _nvm_int; nunca comando).
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --dias) shift; _dias="$(_nvm_int "${1:-}" "$_dias")" ;;
      --dias=*) _dias="$(_nvm_int "${1#--dias=}" "$_dias")" ;;
      *) ;;   # ignora o resto (report-only; nao ha outros argumentos)
    esac
    shift 2>/dev/null || break
  done
  # blindagem final: garante inteiro (nunca fica vazio).
  _dias="$(_nvm_int "$_dias" 30)"
  # guard Val: limiar 0 (ou negativo impossivel) nao faz sentido pratico (tornaria TODO kit candidato) ->
  # cai no default 30. --dias >=1 e respeitado normalmente.
  [ "$_dias" -lt 1 ] && _dias=30

  local _kdir; _kdir="$(_nvm_kits_dir)"
  local _agora; _agora="$(_nvm_agora)"
  local _seg=$(( _dias * 86400 ))

  # cabecalho SEMPRE (a moldura em sombra vem primeiro).
  printf '▲ vale-manter — revisao em SOMBRA (so relatorio; NADA sera removido, editado ou desativado). Mede so quando rodou; nao julga qualidade nem conteudo. Sugestao pra conferir, nao sentenca.\n'
  printf '(limiar: %s dias sem rodar · so os SEUS kits e entregas locais)\n\n' "$_dias"

  # FONTE: dir de kits ausente/vazio -> nada a revisar (fail-open honesto).
  if [ -z "$_kdir" ] || [ ! -d "$_kdir" ]; then
    printf '0 kits, nada a revisar (nenhum kit criado ainda).\n'
    return 0
  fi
  local _tem=0 _d
  for _d in "$_kdir"/*/; do
    if [ -d "$_d" ]; then _tem=1; break; fi
  done
  if [ "$_tem" -eq 0 ]; then
    printf '0 kits, nada a revisar (nenhum kit criado ainda).\n'
    return 0
  fi

  # aviso honesto se nao ha historico de entregas nenhum (fail-open): sem base pra sugerir aposentar.
  # FIX Val: NAO basta o dir existir. Dir VAZIO ou registros APAGADOS (limpeza de log / reinstalacao) =
  # MESMO caso "sem base pra sugerir" — a peca nao consegue distinguir "abandonado" de "usado mas o
  # registro sumiu". _tem_hist=1 SO com >=1 registro entrega-*.txt REAL (senao mentiria "nunca voltou").
  local _edir; _edir="$(_nvm_entregas_dir)"
  local _tem_hist=0 _ef
  if [ -n "$_edir" ] && [ -d "$_edir" ]; then
    for _ef in "$_edir"/entrega-*.txt; do
      if [ -e "$_ef" ]; then _tem_hist=1; break; fi
    done
  fi

  # 3 baldes (bash 3.2: strings, uma linha por item, sem array associativo).
  local _cand="" _novos="" _recentes="" _n_recentes=0

  for _d in "$_kdir"/*/; do
    [ -d "$_d" ] || continue
    local _nome; _nome="$(_nvm_nome_do_kit "$_d")"
    [ -n "$_nome" ] || continue

    local _criado; _criado="$(_nvm_kit_criado "$_d")"
    local _idade_s=0
    if [ "$_agora" -gt 0 ] && [ "$_criado" -gt 0 ] && [ "$_agora" -gt "$_criado" ]; then
      _idade_s=$(( _agora - _criado ))
    fi
    local _idade_d=$(( _idade_s / 86400 ))
    local _dcriado; _dcriado="$(_nvm_data_de "$_criado")"

    local _usos; _usos="$(_nvm_usos "$_nome")"
    local _ult; _ult="$(_nvm_ultimo_uso "$_nome")"
    local _dult="nunca"
    if [ "$_ult" -gt 0 ]; then _dult="$(_nvm_data_de "$_ult")"; fi

    # rodou nos ultimos N dias? (uso recente = nao incomoda)
    local _rodou_recente=0
    if [ "$_ult" -gt 0 ] && [ "$_agora" -gt 0 ] && [ $(( _agora - _ult )) -lt "$_seg" ]; then
      _rodou_recente=1
    fi

    if [ "$_rodou_recente" -eq 1 ]; then
      # BALDE 3: uso recente -> nao sinalizado.
      _recentes="${_recentes}  • ${_nome} (rodou ${_usos}x · ultimo uso ${_dult})
"
      _n_recentes=$(( _n_recentes + 1 ))
    elif [ "$_idade_d" -lt "$_dias" ]; then
      # BALDE 2 (enxerto do painel): muito novo pra julgar — jovem demais pra ter mostrado retorno.
      _novos="${_novos}  • ${_nome} (criado ha ${_idade_d}d · rodou ${_usos}x · ainda cedo pra saber)
"
    else
      # BALDE 1: candidato a conferir — velho o bastante E sem retorno nos ultimos N dias.
      local _porque
      if [ "$_tem_hist" -eq 0 ]; then
        # SEM historico de entregas NENHUM na maquina: a peca nao consegue distinguir "abandonado" de
        # "usado mas os registros nao foram gravados/foram apagados". Fica HONESTA: sem base pra sugerir.
        _porque="criado ha ${_idade_d}d · sem historico local (nenhum registro de entrega na maquina) — sem base pra sugerir aposentar"
      elif [ "$_usos" -eq 0 ]; then
        _porque="criado ha ${_idade_d}d, rodou 0x (nunca voltou depois da criacao) — sem retorno"
      elif [ "$_usos" -eq 1 ]; then
        _porque="criado ha ${_idade_d}d, rodou so 1x (so na criacao/estreia · ultimo uso ${_dult}) — usou e dormiu, sem retorno"
      else
        _porque="criado ha ${_idade_d}d, rodou ${_usos}x mas nada nos ultimos ${_dias}d (ultimo uso ${_dult}) — usou e dormiu, sem retorno"
      fi
      _cand="${_cand}  • ${_nome} — ${_porque}
"
    fi
  done

  # BALDE 1 — CANDIDATOS A CONFERIR (report-only).
  printf 'CANDIDATOS A CONFERIR (>= %s dias de vida, sem rodar nos ultimos %s dias):\n' "$_dias" "$_dias"
  if [ -n "$_cand" ]; then
    printf '%s' "$_cand"
  elif [ "$_tem_hist" -eq 0 ]; then
    printf '  nenhum candidato pelos logs locais disponiveis (sem historico de entregas — sem base pra sugerir).\n'
  else
    printf '  nenhum candidato pelos logs locais disponiveis.\n'
  fi
  printf '\n'

  # BALDE 2 — MUITO NOVOS PRA JULGAR (enxerto do painel).
  printf 'MUITO NOVOS PRA JULGAR (< %s dias de vida — nunca sao candidatos):\n' "$_dias"
  if [ -n "$_novos" ]; then
    printf '%s' "$_novos"
  else
    printf '  (nenhum)\n'
  fi
  printf '\n'

  # BALDE 3 — NAO SINALIZADOS (uso recente).
  printf 'NAO SINALIZADOS (uso recente, nos ultimos %s dias) — %s:\n' "$_dias" "$_n_recentes"
  if [ -n "$_recentes" ]; then
    printf '%s' "$_recentes"
  else
    printf '  (nenhum)\n'
  fi

  return 0
}
