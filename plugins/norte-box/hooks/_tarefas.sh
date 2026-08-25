#!/usr/bin/env bash
# _tarefas.sh — a PAGINA VIVA POR TAREFA do Norte-box (NRT-_990380, ultima peca do passo 10).
#
# A ideia (padaria): a caixa ja tem UM lugar por sessao ("a fichinha") e um selo por entrega ("o registro
# de entrega"). Faltava o OUTRO lado: um lugar onde a pessoa VE, de uma so olhada, CADA tarefa que a caixa
# ja fez — como um cartao vivo (status / prova / decisao / historico), lendo os REGISTROS SELADOS. Isto e
# esse lugar. E READ-ONLY: le os registros de entrega e MOSTRA. NUNCA escreve nada.
#
# DE ONDE VEM O STATUS (o coracao — "o pior vence", pelo RC do verificar, NUNCA pelo texto do carimbo):
# a cada registro roda-se _norte_estreia_verificar (o motor da Ponta B, que recomputa o HMAC do corpo) e
# le-se o RC (0/1/2). O texto "carimbo: 🟢/🟡" dentro do arquivo NAO decide sozinho — quem manda e o RC:
#   RC=1 (adulterado/forjado)  -> 🔴 SEMPRE (vence ate um carimbo 🟢 flipado a mao). E o coracao: um flip
#                                 🟡->🟢 na mao aparece 🔴 aqui, porque o HMAC do corpo quebra.
#   RC=2 (nao-verificavel)     -> 🟡 SEMPRE (sem assinatura / sem chave / kill-switch do HMAC). Nunca verde.
#   RC=0 (confere) + carimbo 🟢 + a prova EXISTE no disco -> 🟢 PROVADA.
#   RC=0 + carimbo 🟢 mas a prova SUMIU do disco          -> 🟡 (prova ausente) — nunca 🟢.
#   RC=0 + carimbo 🟡                                       -> 🟡 NAO-PROVADA.
#   registro malformado / campo faltando / ilegivel        -> 🟡 INCOMPLETO (NUNCA trava, NUNCA verde).
#
# IDENTIDADE DA TAREFA = o campo 'rotulo' (NAO o hash: o doc_hash muda quando o doc evolui 🟡->🟢). Agrupa
# por rotulo. ORDEM dos registros = pelo TIMESTAMP DO NOME do arquivo (entrega-<ts>.txt, UTC sortavel),
# NAO pelo campo 'quando:' (conteudo editavel). Status da TAREFA = o status do registro MAIS RECENTE.
#
# LEIS (nao-negociaveis, iguais aos outros passos):
#   - PRIVADO POR PADRAO: le so $HOME/.norte-box/entregas/. NUNCA usa rede. So LE o disco local.
#   - READ-ONLY: nao cria/edita/apaga NENHUM arquivo. Nao muda a fichinha, nao re-assina, nada.
#   - FAIL-HONEST: na duvida, amarelo. Malformado nunca trava e nunca vira verde.
#   - NAO ECOA O CORPO DA CONFERENCIA (pode ter texto do cliente): so rotulo / hashes / caminhos / status /
#     resumo (numeros) / quando. O grosso do arquivo (as clausulas conferidas) NAO e impresso.
#   - Portabilidade macOS (bash 3.2): sem array associativo, sem mapfile, sem eval; o rotulo e tratado
#     como STRING (grep -F, printf '%s'), nunca como comando/pattern.
#   - KILL-SWITCH: NORTE_TAREFAS=0 -> ecoa amarelo e recusa (exit 2), sem listar nada.
set -u

# raiz PRIVADA dos registros de entrega (a mesma que a estreia grava).
_norte_tarefas_raiz() { printf '%s/.norte-box/entregas' "${HOME}"; }

# _norte_tarefas_campo <registro> <chave> — ecoa o VALOR string da 1a linha "^<chave>: " do registro.
# Vazio se ausente. grep -F na chave (a chave e literal). NUNCA executa o dado.
_norte_tarefas_campo() {
  local _reg="${1:-}" _k="${2:-}"
  [ -n "$_reg" ] && [ -f "$_reg" ] && [ -n "$_k" ] || return 1
  grep -m1 "^${_k}: " "$_reg" 2>/dev/null | sed "s/^${_k}: //"
}

# _norte_tarefas_status <registro> — ecoa uma LINHA "<emoji>\t<frase>\t<decisao>" com o status derivado
# pela LEI acima. Campos separados por TAB (facil de cortar com cut -f). O chamador decide como exibir.
# Colunas: 1=emoji (🟢/🟡/🔴)  2=frase de status  3=palavra da DECISAO (provou/nao provou/nao-verificavel/
# adulterado/forjado/incompleto/prova ausente). NUNCA trava; malformado -> 🟡 INCOMPLETO.
_norte_tarefas_status() {
  local _reg="${1:-}"
  [ -n "$_reg" ] && [ -f "$_reg" ] || { printf '🟡\tINCOMPLETO (registro ilegivel)\tincompleto\n'; return 0; }

  # RC do verificador (o coracao). Silencia o texto dele; so o RC importa aqui.
  _norte_estreia_verificar "$_reg" >/dev/null 2>&1; local _rc=$?

  # RC=1 -> adulterado/forjado, o pior, vence ate um carimbo 🟢.
  if [ "$_rc" -eq 1 ]; then
    printf '🔴\tADULTERADO/FORJADO (a assinatura nao confere — registro editado a mao)\tadulterado/forjado\n'
    return 0
  fi
  # RC=2 -> nao-verificavel: sem assinatura / sem chave / kill-switch. Nunca verde.
  if [ "$_rc" -eq 2 ]; then
    # distingue "antigo sem assinatura" pra dar o motivo honesto.
    if ! grep -qE '^assinatura_hmac:' "$_reg" 2>/dev/null; then
      printf '🟡\tNAO-VERIFICAVEL (registro anterior a assinatura)\tnao-verificavel\n'
    else
      printf '🟡\tNAO-VERIFICAVEL (sem chave/openssl ou assinatura desligada)\tnao-verificavel\n'
    fi
    return 0
  fi

  # RC=0 -> a assinatura confere. Agora o carimbo + a prova decidem verde vs amarelo.
  local _carimbo; _carimbo="$(_norte_tarefas_campo "$_reg" carimbo)"
  # malformado: sem carimbo reconhecivel -> INCOMPLETO (nunca verde, nunca trava).
  case "$_carimbo" in
    '🟢 ENTREGA PROVADA'*)
      # carimbo verde legitimo: exige que a prova EXISTA no disco.
      local _prova; _prova="$(_norte_tarefas_campo "$_reg" prova)"
      if [ -n "$_prova" ] && [ -f "$_prova" ]; then
        printf '🟢\tPROVADA (rodou ponta a ponta e a conferencia fechou)\tprovou\n'
      else
        printf '🟡\tPROVA AUSENTE (o registro diz provada, mas a prova sumiu do disco)\tprova ausente\n'
      fi
      return 0
      ;;
    '🟡 ENTREGA NAO-PROVADA'*)
      printf '🟡\tNAO-PROVADA (rodou, mas a conferencia nao fechou)\tnao provou\n'
      return 0
      ;;
    *)
      printf '🟡\tINCOMPLETO (registro sem carimbo reconhecivel)\tincompleto\n'
      return 0
      ;;
  esac
}

# _norte_tarefas_regs_do_rotulo <rotulo> — ecoa os caminhos dos registros daquele rotulo, MAIS NOVO
# PRIMEIRO (ordenado pelo ts do NOME do arquivo). grep -F -x casa a linha "rotulo: <r>" INTEIRA e literal
# (o rotulo e string; sem glob/regex). Vazio se nenhum.
_norte_tarefas_regs_do_rotulo() {
  local _r="${1:-}"; [ -n "$_r" ] || return 1
  local _raiz; _raiz="$(_norte_tarefas_raiz)"
  [ -d "$_raiz" ] || return 1
  # ls -1r = ordem reversa por nome = mais novo primeiro (o ts UTC no nome e sortavel).
  local _f
  for _f in $(ls -1r "$_raiz"/entrega-*.txt 2>/dev/null); do
    [ -f "$_f" ] || continue
    grep -qxF "rotulo: $_r" "$_f" 2>/dev/null && printf '%s\n' "$_f"
  done
}

# _norte_tarefas_rotulos — ecoa os rotulos UNICOS de todos os registros, um por linha (ordenado). Trata o
# rotulo como STRING (nunca como comando). Vazio se nenhum registro.
_norte_tarefas_rotulos() {
  local _raiz; _raiz="$(_norte_tarefas_raiz)"
  [ -d "$_raiz" ] || return 1
  # grep -h '^rotulo: ' pega a linha em TODOS os arquivos; sed tira o prefixo; sort -u dedup.
  grep -h '^rotulo: ' "$_raiz"/entrega-*.txt 2>/dev/null | sed 's/^rotulo: //' | sort -u
}

# _norte_tarefas_lista — a LISTA (sem argumento): 1 linha por tarefa, verificando SO o registro mais
# recente de cada (por PERF). Formato: "<emoji> · <rotulo> · <N> run(s) · ultimo: <quando>".
_norte_tarefas_lista() {
  local _raiz; _raiz="$(_norte_tarefas_raiz)"
  # diretorio vazio/inexistente -> mensagem honesta, exit 0.
  if [ ! -d "$_raiz" ] || [ -z "$(ls -1 "$_raiz"/entrega-*.txt 2>/dev/null)" ]; then
    printf 'nenhuma entrega registrada ainda. Rode uma tarefa (/norte-box:estreia) e ela aparece aqui.\n'
    return 0
  fi

  printf '📋 TAREFAS QUE A CAIXA JA FEZ (cada uma um cartao vivo — read-only, lido dos registros selados)\n'
  printf '   detalhe de uma: nb-tarefas <rotulo>\n\n'

  local _r
  # loop reabrindo por rotulo (bash 3.2: sem array associativo).
  _norte_tarefas_rotulos | while IFS= read -r _r; do
    [ -n "$_r" ] || continue
    # o registro MAIS NOVO desse rotulo (1o da lista) — so ele e verificado, por PERF.
    local _novo _n _linha_status _emoji _quando
    _novo="$(_norte_tarefas_regs_do_rotulo "$_r" | head -1)"
    [ -n "$_novo" ] || continue
    # conta quantos runs (linhas) esse rotulo tem.
    _n="$(_norte_tarefas_regs_do_rotulo "$_r" | grep -c . )"; [ -n "$_n" ] || _n=0
    _linha_status="$(_norte_tarefas_status "$_novo")"
    _emoji="$(printf '%s' "$_linha_status" | cut -f1)"
    _quando="$(_norte_tarefas_campo "$_novo" quando)"; [ -n "$_quando" ] || _quando='(sem data)'
    # rotulo como STRING (printf %s); nunca interpretado.
    printf '%s · ' "$_emoji"
    printf '%s' "$_r"
    printf ' · %s run(s) · ultimo: %s\n' "$_n" "$_quando"
  done
  return 0
}

# _norte_tarefas_cartao <rotulo> — o CARTAO completo de UMA tarefa: status · prova · decisao · historico.
# Verifica CADA registro do historico (cap 10, mais novo primeiro). O status da TAREFA = o do mais novo.
_norte_tarefas_cartao() {
  local _r="${1:-}"; [ -n "$_r" ] || { printf '🟡 diga qual tarefa (o rotulo). Veja a lista com: nb-tarefas\n'; return 0; }
  local _raiz; _raiz="$(_norte_tarefas_raiz)"
  if [ ! -d "$_raiz" ]; then
    printf 'nenhuma entrega registrada ainda.\n'; return 0
  fi
  # todos os registros desse rotulo (mais novo primeiro). Vazio -> honesto.
  local _todos; _todos="$(_norte_tarefas_regs_do_rotulo "$_r")"
  if [ -z "$_todos" ]; then
    printf '🟡 nao achei nenhuma entrega com esse rotulo: '; printf '%s' "$_r"; printf '\n'
    printf '   veja os rotulos existentes com: nb-tarefas\n'
    return 0
  fi

  # o registro MAIS NOVO manda no status da TAREFA.
  local _novo; _novo="$(printf '%s\n' "$_todos" | head -1)"
  local _st _emoji _frase _decisao
  _st="$(_norte_tarefas_status "$_novo")"
  _emoji="$(printf '%s' "$_st" | cut -f1)"
  _frase="$(printf '%s' "$_st" | cut -f2)"
  _decisao="$(printf '%s' "$_st" | cut -f3)"

  # --- cabecalho + STATUS ---
  printf '📋 TAREFA: '; printf '%s' "$_r"; printf '\n'
  printf '   (cartao vivo, read-only — lido do registro selado; nada sai da maquina)\n\n'
  printf '  status: %s %s\n' "$_emoji" "$_frase"

  # --- PROVA (ecoa o caminho do campo prova do registro mais novo; avisa se sumiu) ---
  local _prova; _prova="$(_norte_tarefas_campo "$_novo" prova)"
  if [ -z "$_prova" ]; then
    printf '  prova: (nenhuma prova registrada neste registro)\n'
  elif [ -f "$_prova" ]; then
    printf '  prova: %s\n' "$_prova"
  else
    printf '  prova: 🟡 prova registrada mas sumiu do disco (%s)\n' "$_prova"
  fi

  # --- DECISAO (mapeamento honesto; nao inventa "exportado pro cliente") ---
  case "$_decisao" in
    provou)              printf '  decisao: 🟢 provou (a conferencia fechou e a assinatura confere)\n' ;;
    'nao provou')        printf '  decisao: 🟡 nao provou (a conferencia nao fechou — carimbo amarelo)\n' ;;
    'nao-verificavel')   printf '  decisao: 🟡 nao-verificavel (sem assinatura/sem chave — nao da pra atestar)\n' ;;
    'adulterado/forjado')printf '  decisao: 🔴 adulterado/forjado (a assinatura NAO confere — nao confie)\n' ;;
    'prova ausente')     printf '  decisao: 🟡 prova ausente (o registro diz provada, mas a evidencia sumiu do disco)\n' ;;
    *)                   printf '  decisao: 🟡 incompleto (registro sem carimbo/campo reconhecivel)\n' ;;
  esac

  # --- HISTORICO (mais novo primeiro, cap 10) ---
  printf '  historico (mais novo primeiro):\n'
  local _n_total _i _f _hst _hemoji _hquando _hresumo _linha
  _n_total="$(printf '%s\n' "$_todos" | grep -c .)"; [ -n "$_n_total" ] || _n_total=0
  _i=0
  # itera os primeiros 10 (mais novos). read line a line.
  printf '%s\n' "$_todos" | head -10 | while IFS= read -r _f; do
    [ -n "$_f" ] || continue
    _hst="$(_norte_tarefas_status "$_f")"
    _hemoji="$(printf '%s' "$_hst" | cut -f1)"
    _hquando="$(_norte_tarefas_campo "$_f" quando)"; [ -n "$_hquando" ] || _hquando='(sem data)'
    # resumo = os NUMEROS (total/ok/orfaos), nunca o corpo. Se faltar, honesto.
    _hresumo="$(_norte_tarefas_campo "$_f" resumo)"; [ -n "$_hresumo" ] || _hresumo='(sem resumo)'
    printf '  • %s — %s (%s)\n' "$_hquando" "$_hemoji" "$_hresumo"
  done
  # "... e N mais antigos" se passou de 10.
  if [ "$_n_total" -gt 10 ]; then
    printf '  … e %s mais antigos\n' "$((_n_total - 10))"
  fi
  return 0
}

# _norte_tarefas <rotulo?> — o ponto de entrada. Sem argumento -> lista; com rotulo -> cartao.
# KILL-SWITCH: NORTE_TAREFAS=0 -> amarelo + exit 2.
_norte_tarefas() {
  case "${NORTE_TAREFAS:-1}" in
    0|no|nao|off|false)
      printf '🟡 a pagina viva por tarefa nao esta ligada nesta maquina (NORTE_TAREFAS=0).\n'
      return 2 ;;
  esac
  # precisa do verificador (o coracao do status). Sem ele, nao da pra atestar nada -> amarelo honesto.
  command -v _norte_estreia_verificar >/dev/null 2>&1 || {
    printf '🟡 nao consegui ler as tarefas: o verificador de selo nao esta disponivel nesta instalacao.\n'
    return 2
  }
  local _r="${1:-}"
  if [ -z "$_r" ]; then
    _norte_tarefas_lista
  else
    _norte_tarefas_cartao "$_r"
  fi
  return 0
}
