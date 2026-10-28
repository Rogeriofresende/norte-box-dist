---
name: fios-soltos
description: "Lista o que ficou ABERTO nos bilhetes da pessoa (./norte-out/handoffs/): por assunto, so o bilhete mais novo conta; mostra itens [ ] pendentes, pedidos pendentes, itens que o selo nao achou no disco e o proximo passo, cada um com arquivo:linha, e sugere o /norte:retomar daquele assunto. SO LE — nunca grava, fecha ou apaga. Acionada por /norte:fios-soltos ou frases como 'o que ficou aberto', 'o que deixei pra tras', 'pontas soltas', 'fios soltos'."
---

> **No Codex:** onde este texto disser `/norte:<nome>`, a pessoa digita `$norte:<nome>` (ou pede em português).
> Os comandos de terminal abaixo já acham a pasta da caixa sozinhos — rode-os como estão.

# fios-soltos

Mostra o que a pessoa comecou e nao fechou, lendo os bilhetes que o `/obrigado` e o `/continuar` ja
salvaram. **So le.** Quem decide o que fazer com cada item e a pessoa.

## Passo 1 — Rode o programa (ele le, confere e marca os passos sozinho)

```bash
DIR="$(bash "${CLAUDE_PLUGIN_ROOT:-$(ls -d "${CODEX_HOME:-$HOME/.codex}"/plugins/cache/norte-box/norte/*/ 2>/dev/null | sort -V | tail -1)}/bin/nb-resolve-outdir")"     # a mesma pasta que o /continuar usa
bash "${CLAUDE_PLUGIN_ROOT:-$(ls -d "${CODEX_HOME:-$HOME/.codex}"/plugins/cache/norte-box/norte/*/ 2>/dev/null | sort -V | tail -1)}/bin/nb-fios-soltos" "$DIR" ${DIAS:-30}
```

Contrato da saida (separado por TAB):
- `VAZIO` -> nenhum bilhete. Diga: "Ainda nao tem bilhete neste projeto. Ao terminar uma conversa, use
  `/norte:obrigado` — ai esta lista passa a funcionar." E pare.
- `FIO <assunto> <dias> <n_abertos> <retomado:sim|nao> <arquivo>` -> um assunto com coisa aberta.
- `ITEM <arquivo:linha> <tipo> <texto>` -> o item; `tipo` = `pendente` | `pedido` | `conferir` | `proximo`.
- `ANTIGOS <n>` -> assuntos com coisa aberta parados ha mais que a janela (so conte, nao liste).
- `RESUMO <bilhetes> <assuntos> <com_aberto> <itens> <sem_molde>`.
- `GRAVOU nada` -> o programa conferiu que a pasta ficou igual. Se vier `GRAVOU mudou`, diga que a
  pasta mudou durante a leitura (outra conversa salvou um bilhete) e sugira rodar de novo.
- `FALHOU ...` -> diga o motivo em 1 linha e pare. Nunca invente a lista.

## Passo 2 — Mostre a lista (curta, mais novo primeiro)

- No maximo **10 assuntos**; se houver mais, diga "e mais N assuntos — peca 'mostra todos' pra ver".
- Por assunto: nome (troque `-` por espaco), ha quantos dias, e os itens, um por linha:
  - `pendente` -> "falta: <texto>"
  - `pedido` -> "voce pediu: <texto>"
  - `conferir` -> "o bilhete dizia feito, mas o arquivo nao esta no disco: <texto>"
  - `proximo` -> "proximo passo anotado: <texto>"
- Depois de cada item, a fonte entre parenteses, so o nome do arquivo e a linha (ex.: `(site-loja-20261025-1000.md:9)`).
- `retomado:nao` -> marque "nunca retomado".
- Use o texto do bilhete como esta: nao resuma, nao junte itens, nao invente item que nao veio na saida.

## Passo 3 — Ofereca o proximo gesto (sem fazer)

Termine com UMA recomendacao: o assunto mais novo que tem item `pendente` ou `pedido`, e o comando
`/norte:retomar <assunto>`. Se a pessoa disser que um assunto ja acabou, sugira fechar com
`/norte:obrigado` na conversa daquele assunto — **voce nao edita o bilhete**.

## Regras

- **Nunca grava** em `norte-out/`, nunca apaga bilhete, nunca marca `.ja-visto` (isso e do `/retomar`).
- Mede so os passos que o PROGRAMA marca (`achou_bilhetes`, `leu_molde`, `listou`, `nao_gravou`), sem
  nenhum texto do bilhete. Desligar: `NORTE_BOX_PASSO=0`.
- So a pasta deste projeto (ou a global, fora de projeto). Nao varre o resto do computador.
