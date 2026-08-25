#!/usr/bin/env bash
# situacao-abrir.sh — SessionStart hook do norte-box: ABRIR SITUANDO.
#
# O QUE FAZ: quando a pessoa abre a caixa, a 1a coisa que ela ve e um CARTAO DE SITUACAO:
#   "Seu objetivo: '<as palavras dela>'. Da ultima vez: entreguei <X> — [🟢 PROVADO / 🟡 NAO PROVEI
#    AINDA]. Hoje: continuar  |  mudar de rumo?"
# Assim ela NUNCA fica no branco. Le a fichinha LOCAL ($HOME/.norte-box/situacao.json) que o Stop
# hook (situacao-gravar.sh) escreveu no fim da sessao anterior.
#
# 1a VEZ (sem fichinha ainda): mensagem GENTIL de boas-vindas — NAO e erro, e o estado normal de
# quem abre a caixa pela primeira vez.
#
# SELO HONESTO: o cartao carrega o selo real do disco. Default 🟡 NAO-PROVADO (so vira 🟢 PROVADO com
# artefato de prova real, que ainda nao existe). Honesto por padrao, sempre.
#
# LEIS (mesmas dos outros hooks do box):
#   - FAIL-OPEN: exit 0 SEMPRE. Nunca trava a sessao.
#   - Emite hookSpecificOutput.additionalContext (o Claude injeta e apresenta o cartao ao usuario).
#   - So LE o disco local ($HOME/.norte-box). Nao escreve nada. Nao imprime caminho de filesystem.
#   - Consome stdin (JSON do SessionStart) como DADO, nunca executa.
set -u

# Carrega a lib da fichinha (fonte unica de leitura).
_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)"
if [ -n "${_SELF_DIR:-}" ] && [ -f "${_SELF_DIR}/_situacao.sh" ]; then
  . "${_SELF_DIR}/_situacao.sh"
elif [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/hooks/_situacao.sh" ]; then
  . "${CLAUDE_PLUGIN_ROOT}/hooks/_situacao.sh"
fi

# Carrega tambem a lib do diario (mostrar as ultimas 3 entradas no cartao). Opcional: se nao carregar,
# o cartao segue sem a lista (fail-open) — a lista e um extra, nao o coracao do situar.
if [ -n "${_SELF_DIR:-}" ] && [ -f "${_SELF_DIR}/_diario.sh" ]; then
  . "${_SELF_DIR}/_diario.sh" 2>/dev/null
elif [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/hooks/_diario.sh" ]; then
  . "${CLAUDE_PLUGIN_ROOT}/hooks/_diario.sh" 2>/dev/null
fi

# Carrega a lib das CORRECOES (memoria funda, NRT-_990212 passo 7) — as regras do jeito da pessoa que a
# reabertura cita verbatim. Opcional: sem ela, o bloco 🧠 MEMORIA FUNDA ainda mostra o perfil (fail-open).
if [ -n "${_SELF_DIR:-}" ] && [ -f "${_SELF_DIR}/_correcoes.sh" ]; then
  . "${_SELF_DIR}/_correcoes.sh" 2>/dev/null
elif [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/hooks/_correcoes.sh" ]; then
  . "${CLAUDE_PLUGIN_ROOT}/hooks/_correcoes.sh" 2>/dev/null
fi

# Carrega o REDATOR compartilhado (fonte unica _redact.sh). O bloco "▶ Ver rodar" passa a saida da
# entrega do cliente por ele ANTES de mostrar (pode conter secret). Se nao carregar, _norte_situacao_ver_rodar
# falha fechado (nao mostra o bloco) — a saida nunca sai crua. Opcional pro resto do cartao (fail-open).
if [ -n "${_SELF_DIR:-}" ] && [ -f "${_SELF_DIR}/_redact.sh" ]; then
  . "${_SELF_DIR}/_redact.sh" 2>/dev/null
elif [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/hooks/_redact.sh" ]; then
  . "${CLAUDE_PLUGIN_ROOT}/hooks/_redact.sh" 2>/dev/null
fi

# Consome o JSON do SessionStart como DADO (evita SIGPIPE) e sai limpo se algo faltar.
cat >/dev/null 2>&1 || true

command -v _norte_situacao_tem >/dev/null 2>&1 || exit 0
command -v jq >/dev/null 2>&1 || exit 0

if _norte_situacao_tem; then
  # MEMORIA DO OBJETIVO (NRT-_990419): le pelo leitor unico (declarado tem prioridade; herda o
  # kill-switch NORTE_OBJETIVO=0). Fallback pro leitor antigo se a lib nova nao estiver carregada.
  if command -v _norte_objetivo_atual >/dev/null 2>&1; then
    _obj="$(_norte_objetivo_atual 2>/dev/null)"
  else
    _obj="$(_norte_situacao_campo objetivo)"
  fi
  _ent="$(_norte_situacao_campo entregou)"
  _selo="$(_norte_situacao_selo)"

  # Sem objetivo legivel na fichinha -> trata como 1a vez (fail-honest: nao inventa cartao vazio).
  if [ -z "$_obj" ]; then
    _ctx="$(cat <<'EOF'
=== ABRIR SITUANDO (primeira vez) ===
Diga, no seu tom e em portugues simples, ALGO como: "Esta e a sua caixa Norte. Ainda nao guardei
um objetivo aqui. Me conte, numa frase, o que voce quer fazer — no fim da conversa eu guardo, e na
proxima vez que voce abrir eu ja te situo de onde a gente parou." Uma linha, acolhedor, sem jargao.

ENSINAR A PEDIR: logo depois, mostre 2-3 EXEMPLOS curtos de um bom pedido, pra ela ver o jeito de
pedir (nao precisa ser tecnico). Algo como:
  ex.: "monta um controle de estoque simples"
  ex.: "faz uma pagina de contato pro meu negocio"
  ex.: "me ajuda a organizar minhas tarefas da semana"
Deixe claro que e so um exemplo do formato — o pedido dela pode ser qualquer coisa, com as palavras dela.
=== fim ===
EOF
)"
  else
    # Monta a linha "entreguei X" so se houver algo gravado; senao, fala pelo objetivo (honesto).
    if [ -n "$_ent" ]; then
      _linha_entrega="Da ultima vez, entreguei: ${_ent} — ${_selo}."
    else
      _linha_entrega="Da ultima vez, o rumo era esse (ainda nao registrei uma entrega fechada) — ${_selo}."
    fi
    _ctx="$(cat <<EOF
=== ABRIR SITUANDO ===
Antes de tudo, SITUE a pessoa com um cartao curto (portugues de padaria, sem jargao), mais ou menos assim:

  Seu objetivo: "${_obj}"
  ${_linha_entrega}
  Hoje voce quer: continuar de onde paramos  ou  mudar de rumo?

Regras do cartao:
- Repita o objetivo COM AS PALAVRAS DELA (o texto acima), sem reescrever.
- O selo "${_selo}" e honesto: 🟡 NAO-PROVADO quer dizer "ainda nao provei que ficou bom" (e o padrao — o
  motor de prova ainda nao existe); 🟢 PROVADO so apareceria se houvesse um artefato de prova real. Explique
  o amarelo em 1 linha simples se ela perguntar; nunca finja verde.
- Ofereca as duas saidas (continuar | mudar de rumo) e espere ela escolher antes de seguir.
=== fim ===
EOF
)"

    # ▶ VER RODAR (NRT-_990212): quando ha prova VALIDA, o cartao mostra "a coisa rodando" — a SAIDA
    # REAL capturada pela prova, nao so o selo. So aparece com prova legitima (mesma validacao do selo),
    # a saida ja vem CORTADA (ultimas ~15 linhas) e REDIGIDA (secrets mascarados). Sem prova valida OU
    # com o kill-switch NORTE_VER_RODAR=0, _norte_situacao_ver_rodar nao ecoa nada -> nenhum bloco
    # (fail-honest + fail-open). Extra do cartao — nunca o coracao do situar.
    if command -v _norte_situacao_ver_rodar >/dev/null 2>&1; then
      _saida_rodar="$(_norte_situacao_ver_rodar 2>/dev/null || true)"
      if [ -n "$_saida_rodar" ]; then
        _ctx="$(printf '%s\n\n=== ▶ VER RODAR (a saida REAL da sua entrega, ja provada) ===\nMOSTRE ao usuario este bloco depois do cartao, com um titulo simples tipo "▶ Ver rodar — foi isso que rodou:" e a\nsaida abaixo NUM BLOCO DE CODIGO (crase tripla), sem reescrever nem resumir (e a saida de verdade, ja cortada nas\nultimas linhas e com qualquer segredo mascarado). Uma linha de moldura, sem jargao:\n%s\n=== fim ===' "$_ctx" "$_saida_rodar")"
      fi
    fi

    # Extra opcional: as ULTIMAS 3 entradas do diario do que construimos (lista viva, LOCAL). So se
    # houver diario legivel. E um lembrete de "o que ja fizemos", nao o coracao do cartao (fail-open).
    if command -v _norte_diario_ultimas >/dev/null 2>&1; then
      _ult3="$(_norte_diario_ultimas 3 2>/dev/null || true)"
      if [ -n "$_ult3" ]; then
        _ctx="$(printf '%s\n\n=== DIARIO — ultimas 3 do que ja construimos (lista viva, LOCAL) ===\nMOSTRE ao usuario, no inicio da resposta, estas ultimas entregas (uma por linha, do jeito que estao):\n%s\n(Se ela quiser ver a lista inteira, ha o comando /norte-box:diario. O selo de cada linha e honesto:\n 🟢 = provei; 🟡 = ainda nao provei — o padrao.)\n=== fim ===' "$_ctx" "$_ult3")"
      fi
    fi

    # ✍️ ASSINATURA (NRT-_990212 passo 6): o rodape do cartao ganha 3 carimbos AMARRADOS EM FATO
    # (nunca texto do agente): Construí (arquivo real no disco), Provei (veredito MECANICO do motor —
    # 🟢 impossivel sem provado:true; o texto do corpo nao muda o carimbo), Expliquei (o cartao existe).
    # Kill-switch NORTE_ASSINATURA=0 -> volta ao cartao de hoje (a funcao ecoa nada). Extra do cartao,
    # nunca o coracao do situar (fail-open).
    if command -v _norte_situacao_assinatura >/dev/null 2>&1; then
      _assin="$(_norte_situacao_assinatura 2>/dev/null || true)"
      if [ -n "$_assin" ]; then
        _ctx="$(printf '%s\n\n=== ✍️ ASSINATURA (mostre no RODAPE do cartao, os 3 carimbos abaixo, do jeito que estao) ===\nMOSTRE ao usuario estes 3 carimbos exatamente como estao (nao reescreva os selos 🟢/🟡). Uma linha de\nmoldura simples, tipo "Antes de eu te entregar, esta e a minha assinatura honesta:". O selo "Provei" e\nlido DIRETO do motor — se estiver 🟡 e porque o motor ainda nao provou; nunca finja 🟢:\n%s\n=== fim ===' "$_ctx" "$_assin")"
      fi
    fi
  fi
else
  # 1a vez de todas: sem fichinha ainda. Mensagem gentil, NAO erro.
  _ctx="$(cat <<'EOF'
=== ABRIR SITUANDO (primeira vez) ===
Diga, no seu tom e em portugues simples, ALGO como: "Esta e a sua caixa Norte. Ainda nao guardei
um objetivo aqui. Me conte, numa frase, o que voce quer fazer — no fim da conversa eu guardo, e na
proxima vez que voce abrir eu ja te situo de onde a gente parou." Uma linha, acolhedor, sem jargao.

ENSINAR A PEDIR: logo depois, mostre 2-3 EXEMPLOS curtos de um bom pedido, pra ela ver o jeito de
pedir (nao precisa ser tecnico). Algo como:
  ex.: "monta um controle de estoque simples"
  ex.: "faz uma pagina de contato pro meu negocio"
  ex.: "me ajuda a organizar minhas tarefas da semana"
Deixe claro que e so um exemplo do formato — o pedido dela pode ser qualquer coisa, com as palavras dela.
=== fim ===
EOF
)"
fi

# 🧠 MEMORIA FUNDA (NRT-_990212 passo 7): a caixa passa a CITAR, na reabertura, o PERFIL do negocio + as
# CORRECOES do jeito da pessoa — VERBATIM (o texto CRU que ela declarou por ATO EXPLICITO), com a data.
# Fica FORA do if/else de objetivo DE PROPOSITO: a pessoa pode ensinar perfil/regra (via /norte-box:perfil
# e /norte-box:regra) ANTES de fechar um objetivo — a memoria funda precisa aparecer em qualquer cartao
# (1a vez, sem objetivo, ou com objetivo). So aparece quando HA memoria de que falar (_norte_memoria_funda
# retorna vazio se nao ha perfil nem regra — nao inventa/nao polui o 1o uso). Cada texto passa pelo _redact
# ANTES de exibir (pode conter secret). Kill-switch NORTE_MEMORIA=0 -> a funcao ecoa nada. Extra do cartao,
# nunca o coracao do situar (fail-open).
if command -v _norte_memoria_funda >/dev/null 2>&1; then
  _mem="$(_norte_memoria_funda 2>/dev/null || true)"
  if [ -n "${_mem:-}" ]; then
    _ctx="$(printf '%s\n\n=== 🧠 MEMORIA FUNDA (mostre ao usuario, do jeito que esta) ===\nMOSTRE ao usuario este bloco: o PERFIL do negocio dele e AS REGRAS que ele ja te ensinou, CITADOS\nVERBATIM (do jeito que ele escreveu, sem reescrever/resumir). Se disser "nenhuma regra gravada" ou que\nvoce ainda nao sabe o negocio, e a verdade honesta — NAO invente perfil/regra que ele nao declarou. Uma\nlinha de moldura simples, tipo "O que voce ja me ensinou, do seu jeito:":\n%s\n=== fim ===' "$_ctx" "$_mem")"
  fi
fi

jq -n --arg ctx "$_ctx" '{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": $ctx
  }
}' 2>/dev/null || exit 0

exit 0
