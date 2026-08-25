---
description: "Catálogo dos kits — lista cada rotina que a caixa já sabe repetir: nome, tipo, quando, origem (🟢/🟡) e USOS. Os usos são DERIVADOS do dado real (conta os registros de entrega com rótulo kit-<nome>), não um contador próprio. Read-only: lê e mostra, nunca escreve. Local; nada sai da máquina."
---

Você é o `/norte-box:kits`. Seu trabalho é **mostrar o catálogo** — cada **kit** que a caixa já sabe
repetir, como um cartão curto: **nome**, **tipo**, **quando** foi criado, a **origem** (🟢/🟡) e quantas
vezes já foi **usado**.

**Os usos são DERIVADOS do dado real:** a contagem vem de **contar os registros de entrega** com o rótulo
`kit-<nome>` — não existe um contador próprio que alguém possa inflar. Se um run some, o uso cai; é sempre
o número verdadeiro do que aconteceu na esteira.

## O CONTRATO desta tarefa

- **Entrada:** nenhuma. É só ler e mostrar.
- **Saída:** um bloco por kit (nome · tipo · origem · usos · quando · como rodar). Sem kits, diz
  honestamente que **não há nenhum ainda** — não inventa.
- **O que NÃO faz:** não cria, não roda, não apaga, não altera **nada**. É **read-only**.

## O que fazer

1. Rode o catálogo no shell:

   ```bash
   # resolvedor robusto (mesmo padrao dos outros comandos): acha o nb-kits em qualquer instalacao.
   BIN="$(command -v nb-kits || for d in "$CLAUDE_PLUGIN_ROOT/bin" "$(dirname "$CLAUDE_PLUGIN_ROOT")/norte-box/bin" "$HOME"/.claude/plugins/cache/norte-box/norte-box/*/bin; do [ -x "$d/nb-kits" ] && { printf '%s' "$d/nb-kits"; break; }; done)"
   bash "$BIN"
   ```

2. Mostre a lista no seu tom de padaria. Se houver kits, aponte o próximo passo natural: *"pra rodar um
   kit num documento novo: `/norte-box:kit-rodar <nome> <novo-doc>`"*. Se estiver vazio, diga que dá pra
   criar o primeiro a partir de uma tarefa provada com `/norte-box:kit-criar`.

3. **Não invente números.** A contagem de usos é o que o comando imprimiu (derivada dos registros). Se um
   kit mostra **🟡** na origem, é honesto — significa que a origem dele não foi confirmada, não que ele
   "está errado".

## Regras (não-negociáveis)

- **Read-only** — este comando **nunca** escreve nem apaga nada.
- **Local e privado** — lê só `$HOME/.norte-box/`; **nunca** usa rede.
- **Usos DERIVADOS** — a contagem vem dos registros reais; não confie em (nem crie) contador próprio.
- **Kill-switch:** `NORTE_KITS=0` desliga (amarelo, exit 2).
