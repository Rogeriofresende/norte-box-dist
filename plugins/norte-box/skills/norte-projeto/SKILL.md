---
name: norte-projeto
description: "O metodo Norte de projeto grande. Use quando o trabalho e maior que escrever uma funcao — um produto, sistema, feature multi-parte, ou o usuario disser 'projeto grande', 'construir do zero', 'me ajuda a planejar isso', '/norte-box:projeto'. Conduz brainstorm -> spec -> plano -> tarefas provadas por fato, orquestrando o superpowers por NOME e aplicando as 6 regras anti-perda. Degrada com aviso claro se o superpowers nao estiver instalado."
---

# Norte-projeto — o metodo de projeto grande (o coracao)

Voce conduz um projeto grande no jeito Norte: **brainstorm -> spec -> plano -> tarefas
provadas**, sem pular etapa. Voce e um **wrapper por NOME sobre o superpowers** — voce
NAO reimplementa o que o superpowers ja faz, voce o **aciona pelo nome das skills** e
garante que o objetivo, o mapa e as provas nao se percam entre as etapas.

A explicacao em prosa do metodo esta em `${CLAUDE_PLUGIN_ROOT}/METODO.md`. As regras que
seguram tudo estao em `${CLAUDE_PLUGIN_ROOT}/docs/seis-regras-anti-perda.md`. Mantenha
ambas em mente; nao precisa recitar, precisa cumprir.

## Passo 0 — checar a dependencia (superpowers)

Antes de conduzir, verifique se o superpowers esta disponivel:

```
claude plugin list 2>/dev/null | grep -i superpowers
```

- **Presente:** siga o fluxo normal abaixo, invocando as skills do superpowers **por nome**.
- **Ausente:** entre em **modo degradado com aviso claro** (nao quebre). Diga ao usuario,
  em uma linha honesta:
  > "O superpowers nao esta instalado — vou conduzir o metodo manualmente (spec + plano +
  > 1a tarefa). Pra o fluxo completo com as ferramentas de engenharia, instale:
  > `claude plugin marketplace add obra/superpowers-marketplace && claude plugin install superpowers@superpowers-marketplace`"

  E entao conduza as 4 fases voce mesmo (a mecanica esta descrita em cada fase abaixo).
  O metodo funciona degradado — so perde as ferramentas afiadas do superpowers.

## Fase 1 — Brainstorm (entender antes de construir)

Esclareca o que o usuario realmente quer: intencao, requisitos, o que fica de fora. Uma
pergunta de cada vez ate o desenho ficar claro e ser aprovado.

- Com superpowers: invoque **`superpowers:brainstorming`**.
- Degradado: faca voce as perguntas de esclarecimento, uma de cada vez, e apresente o
  desenho pra aprovacao antes de seguir.

O objetivo que sai daqui e a **frase imutavel** (regra 1): registre-a e nao a reescreva.

## Fase 2 — Spec (o contrato antes do codigo)

Do desenho aprovado, escreva a spec: o que cada peca faz, como se prova pronta, o que
fica de fora (regra 3). Grave em **`./norte-out/SPEC.md`** (dentro do repo do usuario,
para viajar com o projeto — nunca no plugin). Slug/paths de saida em ASCII.

## Fase 3 — Plano (passos verificaveis)

Da spec, escreva o plano em passos, cada passo com um criterio de "pronto" provavel por
fato. Este e o mapa vivo (regra 2): `[x]` feito / `[ ]` pendente, com o passo atual
marcado.

- Com superpowers: invoque **`superpowers:writing-plans`**.
- Degradado: escreva o plano voce mesmo, em passos numerados com criterio de prova.

Grave em **`./norte-out/PLANO.md`**.

## Fase 4 — Tarefas provadas (uma de cada vez)

Execute o plano **uma tarefa por vez**. Cada tarefa so fecha com **evidencia externa
reproduzivel** (regra 4): a saida de um teste que rodou, o resultado de um comando, a
tela abrindo. Cole a saida literal — "acho que funciona" nao conta.

- Com superpowers: invoque **`superpowers:executing-plans`** (com pontos de revisao) ou
  **`superpowers:subagent-driven-development`** (tarefas independentes na mesma sessao).
  Ao concluir, invoque **`superpowers:verification-before-completion`** pra confirmar que
  o "pronto" e real, nao auto-declarado.
- Degradado: execute a **1a tarefa** voce mesmo e prove-a por fato antes de anunciar
  pronto. Marque `[x]` no `./norte-out/PLANO.md` so depois da prova no disco.

## As 6 regras que seguram tudo (nao negociaveis)

Correndo por cima das 4 fases (detalhe em `${CLAUDE_PLUGIN_ROOT}/docs/seis-regras-anti-perda.md`):

1. **Objetivo imutavel, sempre visivel** — a frase da Fase 1 nao se reescreve.
2. **Caminho e estado sempre a vista** — `./norte-out/PLANO.md` e a fonte unica de "onde estamos".
3. **Spec antes de codar** — Fase 2 antes de qualquer codigo.
4. **Provar cada passo por fato** — evidencia externa, nunca criterio interno de quem construiu.
5. **Esqueleto vivo antes de conteudo** — o minimo que roda primeiro, riqueza depois.
6. **Checkpoint/handoff a cada troca de sessao** — ao trocar de sessao, `/norte-box:continuar`
   salva o handoff e `/norte-box:retomar` continua no mesmo lugar. Um `[x]` so vale com prova no disco.

## Estado que grava

Tudo do **projeto do usuario** vai em **`./norte-out/`** (cwd): `SPEC.md`, `PLANO.md` e o
que a execucao produzir. **Nunca** grave no diretorio do plugin. Nunca escreva fora de
`./norte-out/` (saida por-projeto) e `$HOME/.norte-box/` (estado da maquina).

## Prova (o que "pronto" significa aqui)

Num repo-brinquedo, `/norte-box:projeto "conversor de CSV"` produz no disco: uma spec
(`./norte-out/SPEC.md`) + um plano em passos (`./norte-out/PLANO.md`) + **1 tarefa
verificada** (com a saida do teste dela colada). Verificavel por `ls ./norte-out/` e
abrindo os arquivos.
