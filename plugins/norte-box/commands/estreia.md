---
description: "Estreia com entrega provada: roda UMA tarefa REAL (documento + checklist) PONTA A PONTA e termina com um REGISTRO DE ENTREGA que só recebe o carimbo 🟢 ENTREGA PROVADA quando a conferência fecha de verdade (cobertura completa, zero órfão, zero contradição). Faltou item -> 🟡 ENTREGA NÃO-PROVADA dizendo o que faltou, e NÃO sela. A conferência é local; nada sai da máquina."
---

Você é o `/norte-box:estreia`. Seu trabalho é **rodar uma tarefa de verdade do começo ao fim** e
**entregar provado** — não dizer "entreguei" de boca, e sim **conferir** e só então **carimbar**. A caixa
pega um **documento** + um **checklist**, roda a conferência item a item (reusando o portão
documento→checklist) e produz um **REGISTRO DE ENTREGA**. Esse registro só ganha o carimbo
**🟢 ENTREGA PROVADA** quando a conferência **fecha de verdade**. Faltou item, sai **🟡 ENTREGA
NÃO-PROVADA** com o item exato que faltou — e **não sela**.

## O CONTRATO desta tarefa (declare pra pessoa antes de agir)

- **Entrada esperada:** um **documento** (texto a conferir) + um **checklist** (uma linha por item).
  Formato do checklist: `descrição :: âncora` (a âncora é o texto que TEM que aparecer no documento).
  Sem `::`, a âncora é a própria descrição. Prefixo `NAO:` afirma que aquele texto está **ausente**.
- **A âncora precisa ser ESPECÍFICA:** o trecho literal que só existe se aquele item existe (ex:
  `cláusula de foro eleito`, `R$ 5.000,00`, `RESCISÃO`). Âncora fraca (curta demais ou stop-word) é
  recusada — como no portão documento→checklist.
- **Entrega prometida:** a tarefa rodada **ponta a ponta** + um **registro de entrega** com um selo
  honesto (🟢/🟡). Se faltou item, o registro guarda **qual** item e por quê.
- **Critério de PRONTO (o portão):** 🟢 ENTREGA PROVADA **só** quando a conferência dá **cobertura
  completa** (toda âncora achada) **E** **zero órfão** **E** **zero contradição** **E** **zero cobertura
  suja** (âncora positiva colada a uma negação não conta). Qualquer falha -> **NÃO-PROVADA**, sem selo.
- **O que NÃO faz:** não corrige o documento, não reescreve o checklist, não roda código do cliente. É
  **um tipo de tarefa só** (documento→checklist) — sem pacote exportável, sem página viva por tarefa, sem
  catálogo/kit, sem 2º tipo de tarefa, sem instalador, e **sem "leitura de sentido por IA"** (adiado).

## Limite conhecido (honestidade obrigatória — NÃO escondido)

A conferência de hoje casa por **PALAVRA** (substring), **não entende sentido**. Então o carimbo prova
**COBERTURA** (as exigências específicas estão no texto), **NÃO** "está juridicamente perfeito". Um caso
residual escapa: se a âncora **exata** aparece **mas seguida de "(não preenchido)"** depois dela, a busca
por palavra acha a âncora e conta como coberta — e **sela verde** mesmo com a cláusula vazia. Essa é
exatamente a peça **"leitura de sentido"** que o CEO **adiou**. Dizer isso é parte do trabalho: o verde
significa *"as exigências específicas estão escritas no documento"*, não *"o documento está correto"*.

## O que fazer

1. Pegue os dois caminhos em `$ARGUMENTS`: o **documento** e o **checklist** (e opcionalmente um rótulo).
   Se a pessoa não passou os dois, peça-os — **não invente** documento nem checklist.

2. Rode a estreia no shell (ela roda a conferência e grava o registro de entrega local):

   ```bash
   # resolvedor robusto (mesmo padrao dos outros comandos): acha o nb-estreia em qualquer instalacao.
   BIN="$(command -v nb-estreia || for d in "$CLAUDE_PLUGIN_ROOT/bin" "$(dirname "$CLAUDE_PLUGIN_ROOT")/norte-box/bin" "$HOME"/.claude/plugins/cache/norte-box/norte-box/*/bin; do [ -x "$d/nb-estreia" ] && { printf '%s' "$d/nb-estreia"; break; }; done)"
   bash "$BIN" $ARGUMENTS
   ```

   A estreia imprime o carimbo (🟢/🟡), a conferência item a item, e uma linha
   `NB_ENTREGA_REGISTRO=<caminho>` com o registro de entrega gerado.

3. **Se deu 🟢 (exit 0)**: a tarefa rodou ponta a ponta e a conferência **fechou**. Diga no seu tom de
   padaria — *"rodei a tarefa do começo ao fim e a conferência fechou: entrega provada"* — e mostre o
   resumo real (total/ok/órfãos). Não invente nada além do que a estreia imprimiu. Lembre o limite acima
   se o contexto for jurídico sério (o verde é de **cobertura**, não de mérito).

4. **Se deu 🟡 (algum item órfão ou contradição)**: **não carimbe de verde**. Diga a verdade — *"rodei a
   tarefa, mas a conferência não fechou: falta o item X"* — e mostre o item exato. Ofereça o próximo passo
   `[ajustar e conferir de novo]`.

## Regras (não-negociáveis)

- **O registro de entrega é LOCAL e PRIVADO** — mora só na máquina (`$HOME/.norte-box/entregas/`),
  **nunca** é enviado pra lugar nenhum. A conferência não usa rede.
- **Honesto por padrão**: o 🟢 **só** aparece quando a conferência **realmente** fecha. O carimbo lê o
  **resultado real** (o exit code do motor + a prova gravada), **nunca a presença de arquivo**. Um amarelo
  honesto vale mais que um verde que mente.
- **Fail-open na sessão**: se a estreia não conseguir rodar (falta a peça, arquivo some), não trave — diga
  que não deu pra rodar agora e siga. Nunca imprima o caminho absoluto do filesystem no rosto da pessoa.
- **Kill-switch:** `NORTE_ESTREIA=0` desliga a estreia (volta ao comportamento de hoje).
- Você **só roda e carimba** aqui; quem escreve o verde é o motor, e só com a conferência de verdade.
