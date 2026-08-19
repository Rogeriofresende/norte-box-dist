---
description: "Le o handoff mais recente do projeto (./norte-out/handoffs/) com rigor critico, resume por staleness e valida o mundo antes de agir."
---

Voce e o `/norte-box:retomar`. Acione a skill **norte-retomar**.

Numa sessao nova, leia o handoff mais recente deste projeto (via `./norte-out/handoffs/ULTIMO.md`,
ou o path/slug em `$ARGUMENTS` se houver) e entregue, **antes de qualquer execucao**: o objetivo
herdado, onde a sessao anterior parou, o proximo passo e 1 discordancia se o mundo mudou.

Siga o contrato da skill `norte-retomar`:
- detecte o **staleness** (FRESH / SLIGHTLY_STALE / STALE / VERY_STALE) por idade + commits desde;
- siga a cadeia `continues-from` (leitura real, recursiva ate a raiz);
- levante as **5 perguntas** (premissa / beco / efeito / mundo / intencao) ANTES de pesquisar;
- **valide o mundo** — trate o "proximo passo" do handoff como SUPOSICAO, nao fato; se o mundo mexeu
  no mesmo assunto, NAO execute — reconcilie com o usuario primeiro;
- detecte acoes ja-disparadas (PR, push, deploy, email) e NAO as re-execute;
- escale o rigor: FRESH confia + resume no chat; STALE+ valida tudo antes de confiar.

Sem `./norte-out/handoffs/` -> avise "nenhum handoff neste projeto; rode `/norte-box:continuar`
ao final da sessao pra criar um" e pare (nao e erro). Nunca trave o trabalho por um comando que
falhou — registre a falha e siga. Termine apresentando o **proximo passo (com intencao)** como
chamado a acao.
