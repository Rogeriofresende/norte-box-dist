---
name: obrigado
description: "Encerra a conversa quando voce TERMINOU: salva o bilhete (handoff) completo do projeto, igual ao /norte:continuar, e fecha. Acionada por /norte:obrigado, ou frases como 'terminei', 'obrigado, pode fechar', 'encerra a conversa'. Escreve ./norte-out/handoffs/<slug>-<AAAAMMDD-HHMMSS>.md + atualiza ULTIMO.md. Na tela da Norte (maquina com as pecas internas), tambem marca a conversa como fechada no registro junto com o bilhete e encerra a sessao; em qualquer outra maquina so salva o bilhete. Par do /norte:continuar (que salva e SEGUE)."
---

# obrigado

Voce vai **ENCERRAR** esta conversa: salvar o bilhete de tudo que fizemos e fechar. E a metade
"terminei" do par `/norte:obrigado` ↔ `/norte:continuar` — o `/continuar` salva e SEGUE; o
`/obrigado` salva e FECHA. Nunca abre conversa nova.

## Passo 1 — Salve o bilhete do projeto (o MESMO do /continuar)

O bilhete e exatamente o do `/norte:continuar` — um formato so, sem duplicar regra. Leia a skill
irma e execute **os Passos 1, 2, 2.5 e 3 dela, sem pular nada** (onde salvar, nome a prova de
perda, as 6 secoes, o selo, o ponteiro `ULTIMO.md`):

```bash
cat "${CLAUDE_PLUGIN_ROOT}/skills/continuar/SKILL.md"
```

Regras extras do bilhete de ENCERRAMENTO:
- Na secao `## Proximo passo`, se nao sobrou nada, escreva `nada pendente — conversa encerrada`
  (nao invente trabalho).
- Guarde o caminho do bilhete salvo em `$NOVO` (o Passo 2 da irma ja define).
- **NAO** rode os Passos 4.5 e 5 da irma (carimbar retomada / trocar a conversa) — quem encerra
  nao troca de conversa.
- **Garanta o objetivo no bilhete (0.3.43 — o mesmo conferente do Passo 4 da irma):**

  ```bash
  bash "${CLAUDE_PLUGIN_ROOT}/bin/nb-bilhete-objetivo" "$NOVO"
  ```

  `OBJETIVO: <frase>` → use essa frase na confirmacao. `SEM OBJETIVO` → **nao invente**; avise em 1
  linha *"⚠ Este assunto nao tem objetivo guardado — quem retomar vai te perguntar qual e."* e siga
  (nunca trava o encerramento).

Se o bilhete nao salvou (pasta sem permissao etc.), imprima o bilhete completo **no chat** e diga
em 1 linha que nao consegui gravar — e **PARE aqui** (sem bilhete, nao fecho nada).

## Passo 2 — Onde estou? (auto-detecta; nunca trava)

```bash
if [ "${NORTE_OBRIGADO_INTERNO:-1}" != "0" ] && [ -x "$HOME/.claude/scripts/norte-concluir-conversa.sh" ]; then echo "INTERNO"; else echo "SO-BILHETE"; fi
```

- **SO-BILHETE** (qualquer maquina sem as pecas internas da Norte — e o caso de quem recebe a caixa):
  va direto pro Passo 4. **Nada de rede, nada de servidor.** O bilhete salvo ja e a entrega completa.
- **INTERNO** (a tela da Norte): siga o Passo 3.

## Passo 3 — So no INTERNO: fecha no registro COM o bilhete e encerra

**3.1 — bilhete da tela da Norte.** Invoque a skill **`session-handoff`** (ferramenta Skill) pra
criar o handoff COMPLETO desta conversa (a tela da Norte le os bilhetes de `~/.claude/handoffs/`).
Anote o caminho exato:

```bash
SID="${CLAUDE_CODE_SESSION_ID:-nosid}"; H="$(cat "$HOME/.claude/handoffs/.last-handoff-$SID" 2>/dev/null)"; [ -f "$H" ] || H="$(ls -1t "$HOME"/.claude/handoffs/*.md 2>/dev/null | head -1)"; test -f "$H" && echo "BILHETE: $H" || echo "SEM BILHETE"
```

Se imprimiu `SEM BILHETE`, use o `$NOVO` do Passo 1 como `H`.

Se `H` for outro arquivo (o bilhete grande), passe ele tambem pelo conferente — mesma regra do Passo 1
(`SEM OBJETIVO` = avisa em 1 linha, nao trava):

```bash
[ "$H" != "$NOVO" ] && bash "${CLAUDE_PLUGIN_ROOT}/bin/nb-bilhete-objetivo" "$H"
```

**3.2 — manda pra "Concluida" + registro fechado + bilhete.** Rode UMA vez, quieto:

```bash
"$HOME/.claude/scripts/norte-concluir-conversa.sh" --bilhete "$H"
```

Se falhar, **NAO trave** — o bilhete ja esta salvo; diga em 1 linha que a conversa nao moveu pra
Concluida e siga.

**3.3 — confirme** do jeito que esta tela confirma (cartao curto): *"Fechei — bilhete salvo em
<arquivo>, conversa em Concluida. Pra retomar depois, e so /norte:continuar."*

**3.4 — encerre (SEMPRE o ultimo)**, se a peca existir:

```bash
[ -x "$HOME/.claude/scripts/norte-fechar-encerrar.sh" ] && "$HOME/.claude/scripts/norte-fechar-encerrar.sh" || echo "SEM-ENCERRAR"
```

Se ele encerrar, a saida dele e a palavra final. Se NAO encerrar (ou `SEM-ENCERRAR`), a conversa
fica aberta: diga em 1 linha honesta o porque. **NUNCA diga "fechei" se nao encerrou.**

## Passo 4 — So no SO-BILHETE: confirme e pronto

Reporte, nesta ordem:
1. **Bilhete salvo:** o caminho do `.md` + o objetivo em 1 frase.
2. **Ponteiro:** `ULTIMO.md` aponta pro novo.
3. **Como retomar:** "quando quiser voltar, rode `/norte:retomar` — ele le este bilhete e diz onde
   continuar."
4. **Pode fechar:** "pode fechar esta janela quando quiser." (Nesta maquina a caixa NAO encerra a
   sessao sozinha.)

Abra com **"Bilhete salvo — pode fechar esta janela."** e **NUNCA** com "Fechei"/"encerrei": aqui a
conversa nao foi encerrada por nos, so o bilhete foi salvo.

## Ordem sagrada (nao inverta)

Bilhete salvo (Passo 1) → [so INTERNO: Concluida + registro com bilhete → confirmacao] → encerrar
por ultimo. Sem bilhete, nada fecha. Desligar a parte interna: `NORTE_OBRIGADO_INTERNO=0` (vira
so-bilhete em qualquer maquina).

## Prova (teste real)

Numa maquina limpa (sem `~/.claude/scripts/`), num repo-brinquedo: o Passo 2 imprime `SO-BILHETE`,
nasce `./norte-out/handoffs/<slug>-*.md` com as 6 secoes + `ULTIMO.md`, e nenhuma chamada de rede
acontece.
