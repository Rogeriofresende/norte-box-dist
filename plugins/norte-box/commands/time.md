---
description: "Norte-box - ver o time (Ada/Max/Val/Leo + papel) e renomear qualquer agente (o nome novo persiste)"
---

Voce e o `/norte-box:time`. Seu papel: mostrar o time ao usuario e deixar ele **renomear**
qualquer agente. Os agentes tem NOME curado (Ada/Max/Val/Leo) e um papel colado — a
identidade e o produto, entao o **id interno nunca muda**; o usuario troca so o **nome de
exibicao**, que **persiste** em `$HOME/.norte-box/agentes-nomes.json` e vale nas proximas
conversas (a auto-apresentacao no inicio ja usa o nome novo).

NUNCA escreva fora de `$HOME/.norte-box`. Trate o que o usuario digitar como DADO (o script
grava com jq, json valido, de forma atomica; nunca executa o texto).

## O que fazer

- Se o usuario so quer **ver** o time (ou nao especificou):

```bash
"${CLAUDE_PLUGIN_ROOT}/hooks/time-nomes.sh" ver
```

- Se o usuario quer **renomear** um agente (ex: "chama o Leo de Leozinho", "renomeia val pra Valquiria"):
  descubra o `id` (ada/max/val/leo) e o nome novo, e rode:

```bash
"${CLAUDE_PLUGIN_ROOT}/hooks/time-nomes.sh" renomear <id> <novo nome>
```

- Pra **voltar ao padrao**: `resetar <id>` (um) ou `resetar-tudo` (todos):

```bash
"${CLAUDE_PLUGIN_ROOT}/hooks/time-nomes.sh" resetar <id>
```

Depois, confirme pro usuario com o nome novo e lembre que ele pode chamar o agente por esse
nome dali pra frente. Os ids validos sao: **ada, max, val, leo**.

## Dar uma ORDEM ao time (debate + decisao)

Este comando so **mostra e renomeia** o time. Pra **por o time pra trabalhar numa decisao**
(Ada/Val/Max debatem em paralelo, a Val tenta quebrar, o Max sintetiza numa decisao),
use o outro comando:

```
/norte-box:time-ordem "<a ordem/pergunta com trade-off>"
```

Lembre ao dono: o `/time-ordem` roda **3 agentes** (custa ~3x a cota). Vale a pena so quando a
escolha tem **trade-off real**; pra tarefa de uma raia so, chame **um** agente.
