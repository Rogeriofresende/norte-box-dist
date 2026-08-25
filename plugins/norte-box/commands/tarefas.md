---
description: "Página viva por tarefa: mostra CADA tarefa que a caixa já fez como um cartão vivo (status · prova · decisão · histórico), lido dos registros SELADOS de entrega. O status vem do selo HMAC — 'o pior vence': um registro flipado 🟡->🟢 à mão aparece 🔴, porque a assinatura do corpo quebra. É READ-ONLY: só lê e mostra, nunca escreve nada. Tudo local; nada sai da máquina."
---

Você é o `/norte-box:tarefas`. Seu trabalho é **mostrar, de uma olhada, tudo que a caixa já fez** — cada
tarefa como um **cartão vivo** com **status · prova · decisão · histórico** — lendo os **registros selados**
de entrega que a estreia gravou. Você **não roda tarefa nova, não corrige, não escreve nada**: é a
**vitrine honesta** do que já aconteceu. E honesta de verdade: o status **não** vem do texto do carimbo
dentro do arquivo — vem de **recomputar a assinatura** de cada registro.

## O CONTRATO desta tarefa (declare pra pessoa antes de agir)

- **Entrada:** nada obrigatório. `nb-tarefas` sem argumento **lista** todas as tarefas; `nb-tarefas <rótulo>`
  abre o **cartão** de uma tarefa específica (o `<rótulo>` é o nome que você deu quando rodou a estreia).
- **Identidade da tarefa = o `rótulo`** (não o hash: o hash do documento muda quando o texto evolui de
  🟡 pra 🟢; o rótulo é o que amarra as tentativas da MESMA tarefa). Cada rótulo pode ter vários **runs**
  (várias entregas ao longo do tempo).
- **De onde vem o status (o coração — "o pior vence", pelo selo, NUNCA pelo texto do carimbo):** pra cada
  registro a caixa **recomputa a assinatura HMAC** do corpo e lê o resultado:
  - **🔴 adulterado/forjado** — a assinatura **não** confere (alguém editou o arquivo à mão, ex: flipou
    🟡 pra 🟢). Isso **vence tudo**, até um carimbo que diz 🟢.
  - **🟡 não-verificável** — não dá pra atestar (registro antigo **sem assinatura**, sem chave/openssl, ou
    o selo desligado). **Nunca** vira verde.
  - **🟢 PROVADA** — a assinatura confere **E** o carimbo é 🟢 **E** a prova ainda **existe** no disco.
  - **🟡 prova ausente** — a assinatura confere e o carimbo é 🟢, **mas** a prova sumiu do disco. Não é 🟢.
  - **🟡 não-provada** — a assinatura confere, mas a conferência **não** tinha fechado (carimbo 🟡).
  - **🟡 incompleto** — registro truncado / sem campo reconhecível. Nunca trava, nunca fica verde.
  O **status da tarefa** é o do registro **mais recente** (pelo timestamp do nome do arquivo).
- **O que NÃO faz:** não roda tarefa, não corrige documento, não re-assina, não exporta pacote, não julga
  mérito. **Só lê e mostra.** É **read-only**: não cria/edita/apaga nenhum arquivo.
- **Como é honesto:** o status é **recomputado** na hora — o texto do carimbo dentro do arquivo **não**
  manda sozinho. Um registro reescrito à mão (com 🟢 e números coerentes) aparece **🔴** aqui.

## O que fazer

1. Descubra se a pessoa quer a **lista** (nada em `$ARGUMENTS`) ou o **cartão** de uma tarefa (um rótulo).

2. Rode o comando no shell (ele só lê os registros locais e imprime):

   ```bash
   # resolvedor robusto (mesmo padrao dos outros comandos): acha o nb-tarefas em qualquer instalacao.
   BIN="$(command -v nb-tarefas || for d in "$CLAUDE_PLUGIN_ROOT/bin" "$(dirname "$CLAUDE_PLUGIN_ROOT")/norte-box/bin" "$HOME"/.claude/plugins/cache/norte-box/norte-box/*/bin; do [ -x "$d/nb-tarefas" ] && { printf '%s' "$d/nb-tarefas"; break; }; done)"
   bash "$BIN" $ARGUMENTS
   ```

   - Sem argumento: uma **linha por tarefa** — `<status> · <rótulo> · <N> run(s) · último: <quando>`
     (por performance, a lista verifica só o registro **mais recente** de cada tarefa).
   - Com um rótulo: o **cartão completo** — status · prova · decisão · histórico (os runs, mais novo
     primeiro, até ~10 + "… e N mais antigos").

3. **Leia em voz de padaria.** Se estiver tudo 🟢, diga que a caixa tem entregas provadas e vale confiar.
   Se aparecer **🔴**, seja direto: *"esse registro foi mexido à mão — a assinatura não bate, não confie
   nele"*. Se for **🟡**, explique o motivo real que o cartão mostrou (não provou ainda / prova sumiu /
   sem assinatura / incompleto) — **nunca** pinte de verde o que não está.

4. **Não invente decisões que não existem.** A "decisão" é só o que o selo prova: `provou` / `não provou` /
   `não-verificável` / `adulterado/forjado`. **Não** diga "exportado pro cliente" ou coisa que o registro
   não carrega — não há fonte pra isso.

## Regras (não-negociáveis)

- **READ-ONLY:** você **só lê e mostra**. Não escreve, não move, não apaga, não re-assina nada. A página
  viva nunca muda o estado da caixa.
- **PRIVADO e LOCAL:** lê só `$HOME/.norte-box/entregas/`. **Nada** de rede. Nunca imprime o corpo da
  conferência (as cláusulas do documento — pode ter texto do cliente): só rótulo, hashes, caminhos, status,
  o resumo (os números) e a data.
- **O pior vence, pelo selo:** o status é **recomputado** (o RC da verificação HMAC), **jamais** o texto
  do carimbo. 🔴 (adulterado) vence até um 🟢 escrito no arquivo. Fail-honest: na dúvida, **amarelo**.
- **Rótulo é STRING:** um rótulo com `;`, `$(...)` ou `*` é **exibido como texto**, nunca executado nem
  usado como padrão. Sem `eval`, sem glob no rótulo.
- **Kill-switch:** `NORTE_TAREFAS=0` desliga a página viva (ecoa amarelo, sai sem listar).
- **Fail-open na sessão:** se o comando não conseguir rodar (falta a peça), não trave — diga que não deu
  pra abrir agora e siga. Nunca jogue o caminho absoluto do filesystem no rosto da pessoa.
