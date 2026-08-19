---
name: projeto
description: "Conduz um projeto grande no jeito Norte: brainstorm -> spec -> plano -> tarefas provadas por fato. Orquestra o superpowers por nome e aplica as 6 regras anti-perda."
argument-hint: "<descricao do que voce quer construir>"
---

Voce e o comando `/norte-box:projeto`. Acione a skill **norte-projeto** (o coracao do
metodo) pra conduzir um projeto grande no jeito Norte.

O usuario descreveu: **$ARGUMENTS**

Conduza o metodo **brainstorm -> spec -> plano -> tarefas provadas**, orquestrando o
superpowers **por nome** e aplicando as 6 regras anti-perda:

1. **Passo 0 — checar dependencia:** rode `claude plugin list 2>/dev/null | grep -i superpowers`.
   Ausente = **modo degradado com aviso claro** (nao quebre) + o conserto copiavel:
   `claude plugin marketplace add obra/superpowers-marketplace && claude plugin install superpowers@superpowers-marketplace`.

2. **Brainstorm** — esclarecer intencao/requisitos/fora-de-escopo, uma pergunta por vez,
   ate o desenho ser aprovado. Com superpowers: invoque **`superpowers:brainstorming`**.
   O objetivo que sair daqui e a frase imutavel (regra 1) — nao a reescreva.

3. **Spec** — escreva o contrato de cada peca (o que faz, como se prova, o que fica fora)
   em `./norte-out/SPEC.md`. Spec antes de codar (regra 3).

4. **Plano** — passos verificaveis com criterio de prova, gravado em `./norte-out/PLANO.md`
   (o mapa vivo `[x]`/`[ ]`, regra 2). Com superpowers: invoque **`superpowers:writing-plans`**.

5. **Tarefas provadas** — uma tarefa por vez, cada uma fechada por evidencia externa
   reproduzivel (regra 4). Com superpowers: **`superpowers:executing-plans`** ou
   **`superpowers:subagent-driven-development`**, e ao fim **`superpowers:verification-before-completion`**.
   Um `[x]` no plano so vale com prova no disco.

Grave sempre em `./norte-out/` (o projeto do usuario), nunca no diretorio do plugin.
Detalhe do metodo em prosa: `${CLAUDE_PLUGIN_ROOT}/METODO.md`. As 6 regras:
`${CLAUDE_PLUGIN_ROOT}/docs/seis-regras-anti-perda.md`.

Ao trocar de sessao, lembre o usuario de rodar `/norte-box:continuar` (salva o handoff)
e `/norte-box:retomar` (continua no mesmo lugar).
