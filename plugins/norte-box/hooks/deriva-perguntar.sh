#!/usr/bin/env bash
# deriva-perguntar.sh — UserPromptSubmit hook do norte-box: a "pergunta da deriva".
#
# A ideia (padaria): a caixa guarda, numa fichinha LOCAL, o objetivo que a pessoa declarou
# (situacao.json — o passo 1, ABRIR SITUANDO). Quando o NOVO pedido dela parece PUXAR pra outro
# assunto (deriva do objetivo guardado), a caixa NAO reescreve o objetivo sozinha e NAO segue calada:
# ela APONTA em 1 linha o que percebeu e PERGUNTA, com duas saidas claras,
#   "isso muda seu objetivo?  [continuar no objetivo]  [mudar de rumo]"
# A ULTIMA palavra e sempre da pessoa (soberania do objetivo). A caixa so PERGUNTA — nunca decide.
#
# MECANICO (testavel): este hook LE a fichinha + o prompt novo e decide, por uma heuristica simples
# de sobreposicao de palavras, se ha deriva. Se ha -> injeta a pergunta (additionalContext). Se o
# pedido esta ALINHADO com o objetivo -> silencio (nao pergunta nada). Sem fichinha -> silencio
# (fail-open: quem nunca declarou objetivo nao tem de onde derivar).
#
# LEIS (iguais aos outros hooks do box):
#   - FAIL-OPEN: exit 0 SEMPRE. Nunca trava/atrasa o Claude. Sem jq / sem fichinha -> sai limpo.
#   - PRIVADO: le SO o disco local ($HOME/.norte-box/situacao.json). Nao envia nada, nao escreve nada.
#   - Consome stdin (JSON do UserPromptSubmit) como DADO, nunca executa/eval o prompt.
#   - NAO reescreve o objetivo. So injeta uma PERGUNTA com as duas saidas; a pessoa decide.
#   - Kill-switch: NORTE_DERIVA=0 desliga (o Val compara com/sem no clean-room). Vazio/1 = ligado.
#
# VIES FORTE PARA O SILENCIO (correcao NRT-_990212, Val re-run):
#   Perguntar errado (falso+) e o erro CARO (o CEO odeia atrito a toa). Deixar passar uma divergencia
#   leve (falso-) e BARATO (a caixa ainda tem o cartao de situacao + a voz Norte cobrindo). Entao o
#   mecanico so grita quando ha EVIDENCIA FORTE de TROCA DE DOMINIO real. A antiga heuristica de
#   "zero overlap de palavra literal" era fraca demais e gritava em 7/10 follow-ups legitimos
#   ("adiciona uma pagina", "quero um carrinho de compras", "muda a fonte"...). Nova regra:
#     1) qualquer VERBO DE EDICAO/continuacao no pedido -> SILENCIO garantido (e o mesmo trabalho).
#     2) so DISPARA quando o pedido cita um MARCADOR DE OUTRO DOMINIO (lista curada, sinal muito mais
#        forte que overlap) — ex.: imposto/declaracao/estoque/contabilidade/curriculo/viagem.
#   Escopo reduzido de proposito: o mecanico so cobre a troca de dominio CLIMATICAMENTE OBVIA; o resto
#   (deriva sutil) fica pra a regra de voz Norte (guidance, o LLM julga). Melhor calar que gritar a toa.
set -u

# Kill-switch explicito. Vazio/1 = ligado; 0 = desligado (consome stdin e sai).
if [ "${NORTE_DERIVA:-1}" = "0" ]; then
  cat >/dev/null 2>&1 || true
  exit 0
fi

# Sem jq nao da pra parsear com seguranca -> fail-open silencioso (consome stdin pra evitar SIGPIPE).
if ! command -v jq >/dev/null 2>&1; then
  cat >/dev/null 2>&1 || true
  exit 0
fi

_stdin="$(cat 2>/dev/null || true)"

# Carrega a lib da fichinha (fonte unica de leitura). Se nao carregar, fail-open.
_self_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)"
# shellcheck source=/dev/null
[ -f "$_self_dir/_situacao.sh" ] && . "$_self_dir/_situacao.sh" 2>/dev/null
command -v _norte_situacao_tem >/dev/null 2>&1 || exit 0

# Sem fichinha (ninguem declarou objetivo ainda) -> nada de que derivar. Silencio.
_norte_situacao_tem || exit 0
# MEMORIA DO OBJETIVO (NRT-_990419): le pelo leitor unico (declarado tem prioridade; herda o
# kill-switch NORTE_OBJETIVO=0). Fallback pro leitor antigo se a lib nova nao estiver carregada.
if command -v _norte_objetivo_atual >/dev/null 2>&1; then
  _obj="$(_norte_objetivo_atual 2>/dev/null)"
else
  _obj="$(_norte_situacao_campo objetivo 2>/dev/null)"
fi
[ -n "$_obj" ] || exit 0

# O prompt novo da pessoa (dado NAO-confiavel; so comparamos texto, nunca executamos).
_prompt="$(printf '%s' "$_stdin" | jq -r '.prompt // .user_prompt // .message // "" | if type=="string" then . else "" end' 2>/dev/null)"
[ -n "$_prompt" ] || exit 0

# --- Deteccao de TROCA DE DOMINIO (vies forte para o silencio, deterministica, bash 3.2) -----------
# Duas camadas, nesta ordem, e o DEFAULT e sempre SILENCIO:
#   Camada 1 (silencio garantido): o pedido contem um VERBO DE EDICAO/continuacao (muda, adiciona,
#     coloca, tira, ajusta, troca a cor/fonte/pagina...) -> e o MESMO trabalho, nunca pergunta.
#   Camada 2 (unico caminho pro DISPARO): o pedido cita um MARCADOR DE OUTRO DOMINIO da lista curada
#     (imposto, declaracao, estoque, contabilidade, curriculo, viagem, dieta...). So esse sinal FORTE
#     dispara. Sem marcador -> silencio (a deriva sutil fica pra a voz Norte julgar).
# Por que assim: overlap de palavra literal e fraco demais pra "dominio" (gritava em 7/10 follow-ups
# legitimos). Marcador curado + verbo-de-edicao elimina o falso+ mantendo o disparo na troca obvia.

_norm() {
  # minuscula + troca tudo que nao for letra/numero por espaco. tr do macOS: classes POSIX.
  printf '%s' "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | tr -c '[:alnum:]' ' '
}

_prompt_norm=" $(_norm "$_prompt") "   # espacos nas bordas p/ casar palavra inteira com *" x "*

# Camada 1 — VERBOS DE EDICAO / continuacao do mesmo trabalho -> SILENCIO garantido.
# Se o pedido tem qualquer um destes, e ajuste/edicao do trabalho corrente, nunca troca de dominio.
_edit_verbs="muda mude mudar adiciona adicione adicionar acrescenta acrescente acrescentar \
inclui inclua incluir poe poem coloca coloque colocar bota bote botar tira tire tirar \
remove remova remover ajusta ajuste ajustar troca troque trocar altera altere alterar aumenta \
aumente aumentar diminui diminua diminuir reduz reduza reduzir deixa deixe deixar renomeia renomeie \
reordena reordene corrige corrija corrigir aplica aplique aplicar move mova mover sobe suba subir \
desce desca descer centraliza centralize alinha alinhe alinhar destaca destaque escreve escreva \
reescreve reescreva encurta encurte maior menor melhora melhore"
for _v in $_edit_verbs; do
  case "$_prompt_norm" in *" $_v "*) exit 0 ;; esac
done

# Camada 2 — MARCADORES DE OUTRO DOMINIO (lista curada). Sinal FORTE de troca de assunto.
# So palavras que praticamente nunca aparecem num follow-up do mesmo trabalho. Casa palavra inteira.
_dominio_markers="imposto impostos irpf declaracao declarar tributaria tributario receita fiscal \
contabilidade contabil estoque inventario planilha calculo curriculo emprego vaga entrevista \
viagem passagem hotel roteiro turismo dieta treino academia musculacao remedio medico consulta \
processo peticao juridico advogado contrato divorcio inventario financiamento emprestimo \
investimento acoes bolsa cripto bitcoin casamento festa mudanca aluguel condominio veterinario"
_hit=""
for _m in $_dominio_markers; do
  case "$_prompt_norm" in *" $_m "*) _hit="$_m"; break ;; esac
done

# Sem marcador de outro dominio -> silencio (vies forte pro silencio; a deriva sutil fica pra a voz).
[ -n "$_hit" ] || exit 0

# --- Deriva detectada: injeta a PERGUNTA (nunca reescreve o objetivo). -----------------------------
# Passa o objetivo LITERAL de volta (as palavras dela) pra a caixa apontar sem inventar.
_ctx="$(cat <<EOF
=== PERGUNTA DA DERIVA (o novo pedido parece puxar pra outro assunto) ===
O objetivo que a pessoa guardou foi: "${_obj}"
O pedido de agora parece ser sobre outra coisa (nao encostou nesse objetivo).

ANTES de mergulhar no pedido novo, APONTE isso em 1 linha gentil e PERGUNTE — com estas duas saidas,
como se fossem botoes, exatamente assim:

  "Percebi que isso parece um rumo diferente do seu objetivo ('${_obj}'). Isso muda seu objetivo?
   [continuar no objetivo]   [mudar de rumo]"

Regras (nao-negociaveis):
- NUNCA reescreva/atualize o objetivo por conta propria. A ultima palavra e da pessoa (e o objetivo dela).
- Repita o objetivo COM AS PALAVRAS DELA (o texto acima), sem parafrasear.
- Se ela escolher "continuar no objetivo": traga o pedido novo de volta pro rumo, ou registre como
  nota lateral — mas o objetivo guardado NAO muda.
- Se ela escolher "mudar de rumo": ok, siga o novo pedido (o objetivo so muda porque ELA disse). E,
  se ela quiser CRAVAR o novo objetivo com as palavras dela, convide numa linha: use /norte-box:objetivo.
- Uma linha, tom de padaria, sem jargao. NAO trave o trabalho — e uma pergunta, nao um bloqueio.
=== fim ===
EOF
)"

jq -n --arg ctx "$_ctx" '{
  "hookSpecificOutput": {
    "hookEventName": "UserPromptSubmit",
    "additionalContext": $ctx
  }
}' 2>/dev/null || exit 0

exit 0
