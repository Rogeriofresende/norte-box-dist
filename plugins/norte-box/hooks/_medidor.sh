#!/usr/bin/env bash
# _medidor.sh — FONTE UNICA do "medidor honesto" do Norte-box (termometro de qualidade LOCAL, NRT-_990212
# passo 8). Sourceado pelo comando /norte-box:diario (mostra o bloco no rodape) e por qualquer superficie
# que queira o termometro. So LE o disco local; nunca escreve; nunca envia nada.
#
# A ideia (padaria): abrir a caixa e ver um termometro do PROPRIO trabalho — "quantas coisas ja pedi,
# quantas ficaram 🟢 provadas vs 🟡 nao-provadas, quantas provas rodaram OK vs falharam, quantas correcoes
# eu ensinei, em quantos dias". So NUMEROS, mostrado PRA PROPRIA PESSOA. NAO e a telemetria de compartilhar
# (essa e outra coisa, opt-in, com consent). Aqui e um espelho local do proprio andamento.
#
# A LEI (o coracao — a armadilha nº1): FAIL-HONEST. Cada numero e CALCULADO contando FATO no disco.
#   - A ARMADILHA nº1: contar "existe artefato em provas/" como verde e MENTIRA — o artefato de prova EXISTE
#     TAMBEM quando a prova FALHOU (o _provar.sh grava a prova com o erro dentro, carimbando "exit: N").
#     Por isso provas_ok/provas_falhas leem o campo `exit:` DE DENTRO de cada artefato (exit 0 = ok; exit
#     !=0 = falhou). A mera existencia do arquivo NUNCA vira verde. Sem isso o termometro seria 100% verde
#     de vaidade.
#   - "retorno espontaneo" e LITERAL "sem dados ainda": mede se a pessoa VOLTOU a usar sozinha, outro dia,
#     sem empurrao — isso exige uso ao longo de dias e nao ha fato no disco pra isso hoje. NUNCA estima.
#   - "% verde" so com denominador honesto (total>0). total 0 -> "sem dados ainda" (nao inventa %).
#   - SO NUMEROS, ZERO conteudo: o bloco de numeros nunca ecoa o texto do que foi pedido/feito — so
#     contagem. O historico visivel (que mostra rotulos) passa CADA texto pelo _redact antes de exibir.
#
# LEIS (nao-negociaveis, iguais aos outros passos):
#   - PRIVADO POR PADRAO: le so os arquivos LOCAIS em $HOME/.norte-box/ (diario.jsonl, correcoes.jsonl,
#     provas/). Nunca sai da maquina. Nao imprime caminho de filesystem.
#   - KILL-SWITCH: NORTE_MEDIDOR=0 desliga (ecoa nada, retorna 1) — fail-open pro comportamento de hoje.
#   - FAIL-OPEN: sem jq / sem arquivo -> sai limpo (numeros 0), sem travar.
#   - Portabilidade macOS (bash 3.2 + BSD). Precisa de jq pros jsonl; sem jq -> tudo 0 honesto.
set -u

# Caminhos unicos (reusa os mesmos que _diario.sh/_correcoes.sh/_provar.sh usam).
_norte_medidor_diario_path()    { printf '%s/.norte-box/diario.jsonl' "${HOME}"; }
_norte_medidor_correcoes_path() { printf '%s/.norte-box/correcoes.jsonl' "${HOME}"; }
_norte_medidor_provas_raiz()    { printf '%s/.norte-box/provas' "${HOME}"; }

# _norte_medidor_numeros — ecoa o BLOCO de numeros do termometro, uma "chave: valor" por linha (formato
# estavel, machine-parseable, mesmo espirito do arquivo de prova). SO NUMEROS + rotulos fixos; ZERO
# conteudo do que foi pedido/feito. Cada valor conta FATO no disco (ver LEIS acima).
#
# Chaves emitidas:
#   total            = nº de linhas jq-validas do diario.jsonl (itens registrados).
#   verde            = nº dessas linhas cujo campo .selo comeca com 🟢 (PROVADO).
#   amarelo          = nº dessas linhas cujo campo .selo comeca com 🟡 (NAO-PROVADO).
#   provas_ok        = nº de artefatos de prova (provas/*/prova-*.txt) com "exit: 0" DENTRO.
#   provas_falhas    = nº de artefatos de prova com "exit:" != 0 DENTRO (LE o exit — a ARMADILHA).
#   correcoes        = nº de linhas jq-validas do correcoes.jsonl (regras que a pessoa ensinou).
#   dias             = nº de datas DISTINTAS (YYYY-MM-DD de .quando) no diario — em quantos dias mexeu.
#   pct_verde        = round(100*verde/total)% SO se total>0; senao "sem dados ainda".
#   retorno_espontaneo = SEMPRE "sem dados ainda" (literal — nao ha fato no disco pra isso; nunca estima).
# Retorna 0 se ecoou; 1 se desligado (kill-switch).
_norte_medidor_numeros() {
  # kill-switch: default LIGADO; NORTE_MEDIDOR=0 desliga.
  case "${NORTE_MEDIDOR:-1}" in 0|no|nao|off|false) return 1 ;; esac

  local _total=0 _verde=0 _amarelo=0 _provas_ok=0 _provas_falhas=0 _correcoes=0 _dias=0
  local _tem_jq=1
  command -v jq >/dev/null 2>&1 && _tem_jq=0

  # --- diario: total / verde / amarelo / dias (so linhas jq-validas; lixo e ignorado) ---
  # NOTA (a armadilha da robustez): jq em modo normal ABORTA o stream inteiro na 1a linha corrompida
  # (so conta ate o lixo). Por isso lemos com `-R` (cada linha vira uma STRING crua) + `fromjson?` (o `?`
  # engole o erro de parse por linha -> a linha corrompida simplesmente nao produz nada, e as validas
  # seguem sendo contadas). Assim uma linha jsonl quebrada NAO derruba a contagem nem trava.
  local _dia; _dia="$(_norte_medidor_diario_path)"
  if [ "$_tem_jq" -eq 0 ] && [ -f "$_dia" ]; then
    _total="$(jq -rR 'fromjson? | select(type=="object") | 1' "$_dia" 2>/dev/null | grep -c 1 2>/dev/null)"
    _verde="$(jq -rR 'fromjson? | select(type=="object") | .selo // "" | select(startswith("🟢")) | 1' "$_dia" 2>/dev/null | grep -c 1 2>/dev/null)"
    _amarelo="$(jq -rR 'fromjson? | select(type=="object") | .selo // "" | select(startswith("🟡")) | 1' "$_dia" 2>/dev/null | grep -c 1 2>/dev/null)"
    # dias distintos: pega YYYY-MM-DD de .quando, dedup.
    _dias="$(jq -rR 'fromjson? | select(type=="object") | (.quando // "") | .[0:10] | select(length>0)' "$_dia" 2>/dev/null | sort -u 2>/dev/null | grep -c . 2>/dev/null)"
  fi

  # --- correcoes: nº de linhas jq-validas (regras ensinadas; linha corrompida ignorada, idem acima) ---
  local _cor; _cor="$(_norte_medidor_correcoes_path)"
  if [ "$_tem_jq" -eq 0 ] && [ -f "$_cor" ]; then
    _correcoes="$(jq -rR 'fromjson? | select(type=="object") | select(.texto_cru != null) | 1' "$_cor" 2>/dev/null | grep -c 1 2>/dev/null)"
  fi

  # --- provas: LE o exit DE DENTRO de cada artefato (a ARMADILHA nº1) ---
  # NAO conta "existe arquivo em provas/". Le a linha "exit: N" de cada prova-*.txt:
  #   exit: 0  -> ok ; exit: !=0 -> falha ; sem linha exit -> nem conta (fail-honest: na duvida nao vira ok).
  local _raiz; _raiz="$(_norte_medidor_provas_raiz)"
  if [ -d "$_raiz" ]; then
    local _p _ex
    # -type f + nome prova-*.txt: so os artefatos que o motor escreve. Sandbox (.sbx.*) e limpo pelo motor;
    # se por acaso sobrar, o nome nao casa prova-*.txt e nao entra. Symlink nao e seguido ([ -f ] no read).
    while IFS= read -r _p; do
      [ -n "$_p" ] || continue
      # recusa symlink DURO (defesa: um symlink em provas/ apontando pra fora nao vira contagem).
      [ -L "$_p" ] && continue
      [ -f "$_p" ] || continue
      # le a PRIMEIRA linha "exit: N" do arquivo. Sem essa linha -> nao conta (nem ok nem falha).
      _ex="$(grep -m1 '^exit: ' "$_p" 2>/dev/null | sed 's/^exit: //' | tr -d '[:space:]')"
      [ -n "$_ex" ] || continue
      if [ "$_ex" = "0" ]; then
        _provas_ok=$((_provas_ok+1))
      else
        _provas_falhas=$((_provas_falhas+1))
      fi
    done <<EOF
$(find "$_raiz" -type f -name 'prova-*.txt' 2>/dev/null)
EOF
  fi

  # normaliza vazios (grep -c pode ecoar vazio se o pipe falhar) -> 0.
  case "$_total" in ''|*[!0-9]*) _total=0 ;; esac
  case "$_verde" in ''|*[!0-9]*) _verde=0 ;; esac
  case "$_amarelo" in ''|*[!0-9]*) _amarelo=0 ;; esac
  case "$_correcoes" in ''|*[!0-9]*) _correcoes=0 ;; esac
  case "$_dias" in ''|*[!0-9]*) _dias=0 ;; esac

  # --- % verde: SO com denominador honesto (total>0). Senao "sem dados ainda" (nao inventa). ---
  # Arredonda pra BAIXO (floor) de proposito: 2 de 3 = 66,67% -> mostra 66% (nao infla o proprio placar).
  # O termometro e local e honesto — na duvida, o numero menor. Divisao inteira do shell ja faz floor.
  local _pct
  if [ "$_total" -gt 0 ]; then
    _pct="$(( (100*_verde) / _total ))%"
  else
    _pct="sem dados ainda"
  fi

  printf 'total: %s\n' "$_total"
  printf 'verde: %s\n' "$_verde"
  printf 'amarelo: %s\n' "$_amarelo"
  printf 'provas_ok: %s\n' "$_provas_ok"
  printf 'provas_falhas: %s\n' "$_provas_falhas"
  printf 'correcoes: %s\n' "$_correcoes"
  printf 'dias: %s\n' "$_dias"
  printf 'pct_verde: %s\n' "$_pct"
  # retorno espontaneo: LITERAL "sem dados ainda" — nunca ha fato no disco pra isso; nunca estima.
  printf 'retorno_espontaneo: %s\n' "sem dados ainda"
  return 0
}

# _norte_medidor_termometro — ecoa o bloco de numeros JA em portugues de padaria (pra o rodape do
# comando /norte-box:diario). Reusa _norte_medidor_numeros (a fonte honesta) e so traduz as chaves pra
# frases. SO NUMEROS. Nao imprime caminho. Retorna 0 se ecoou; 1 se desligado (kill-switch).
_norte_medidor_termometro() {
  case "${NORTE_MEDIDOR:-1}" in 0|no|nao|off|false) return 1 ;; esac
  local _n; _n="$(_norte_medidor_numeros)" || return 1
  [ -n "$_n" ] || return 1
  local _get; _get() { printf '%s\n' "$_n" | grep -m1 "^$1: " | sed "s/^$1: //"; }
  local _total _verde _amarelo _pok _pfalha _cor _dias _pct
  _total="$(_get total)"; _verde="$(_get verde)"; _amarelo="$(_get amarelo)"
  _pok="$(_get provas_ok)"; _pfalha="$(_get provas_falhas)"; _cor="$(_get correcoes)"
  _dias="$(_get dias)"; _pct="$(_get pct_verde)"
  printf '🌡️  TERMOMETRO (só números, contados do seu disco — nada é inventado):\n'
  printf '  • itens no diário: %s  (🟢 provados: %s · 🟡 não provados: %s)\n' "$_total" "$_verde" "$_amarelo"
  printf '  • %% provados: %s\n' "$_pct"
  printf '  • provas que rodaram: %s OK · %s falharam (li o resultado de cada uma, não só se existe)\n' "$_pok" "$_pfalha"
  printf '  • correções que você me ensinou: %s\n' "$_cor"
  printf '  • dias em que você mexeu: %s\n' "$_dias"
  printf '  • você voltou sozinho outro dia?: sem dados ainda (isso só o tempo mostra)\n'
  return 0
}

# _norte_medidor_historico <N> — ecoa as ULTIMAS N linhas do diario formatadas pra leitura humana, com o
# ROTULO (o que pediu) passado pelo _redact ANTES de exibir. Um item cujo _redact falhe/vaze e OMITIDO
# (fail-CLOSED na redacao: melhor nao mostrar do que vazar cru). Formato: "quando · pediu(redigido) · selo".
# SO LE. Nao imprime caminho de filesystem. Vazio + return 1 se nao ha diario / jq / kill-switch.
_norte_medidor_historico() {
  case "${NORTE_MEDIDOR:-1}" in 0|no|nao|off|false) return 1 ;; esac
  command -v jq >/dev/null 2>&1 || return 1
  local _n="${1:-10}"; case "$_n" in ''|*[!0-9]*) _n=10 ;; esac
  local _f; _f="$(_norte_medidor_diario_path)"
  [ -f "$_f" ] || return 1
  # extrai por linha os 3 campos SEPARADOS por TAB (o rotulo pode ter espacos; TAB nao). Redige SO o rotulo.
  local _linhas _out=''
  _linhas="$(tail -n "$_n" "$_f" 2>/dev/null | jq -r '
    select(type=="object")
    | ((.quando // "") | .[0:10]) + "\t" + (.pediu // "?") + "\t" + (.selo // "🟡 NAO-PROVADO")
  ' 2>/dev/null)"
  [ -n "$_linhas" ] || return 1
  local _quando _pediu _selo _pediu_red
  while IFS="$(printf '\t')" read -r _quando _pediu _selo; do
    [ -n "${_pediu:-}" ] || continue
    # REDACTION OBRIGATORIA no rotulo (fail-CLOSED): sem _redact / redacao vazia -> OMITE o item.
    if command -v _redact >/dev/null 2>&1; then
      _pediu_red="$(printf '%s' "$_pediu" | _redact 2>/dev/null)"
    else
      _pediu_red=""
    fi
    [ -n "$_pediu_red" ] || continue
    _out="${_out}  • ${_quando:-?} · ${_pediu_red} · ${_selo:-🟡 NAO-PROVADO}"$'\n'
  done <<EOF
$_linhas
EOF
  [ -n "$_out" ] || return 1
  printf '%s' "$_out"
  return 0
}
