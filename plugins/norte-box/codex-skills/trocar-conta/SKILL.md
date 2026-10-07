---
name: "trocar-conta"
description: "Pra quem tem 2 contas Claude: mostra quanto cada uma já usou e troca a conta DESTA conversa (ela fecha e reabre sozinha na outra conta, com o histórico). Ex.: /trocar-conta · /trocar-conta B · /trocar-conta configurar (comando /norte:trocar-conta)"
---

> **No Codex:** onde este texto disser `/norte:<nome>`, a pessoa digita `$norte:<nome>` (ou pede em português).
> Os comandos de terminal abaixo já acham a pasta da caixa sozinhos — rode-os como estão.

> `<ARGUMENTOS>` = o que a pessoa escreveu junto com o pedido (pode ser vazio).

Você é o `/norte:trocar-conta`. Papel: pra quem tem **2 contas Claude** (A e B), mostrar quanto cada uma
já usou e trocar a conta **desta conversa**. A troca fecha a conversa quando ela para e o `nb-claude` reabre
a MESMA conversa na outra conta, no mesmo terminal, com o histórico.

**Regras que não se quebram:** NUNCA peça, leia, imprima ou mostre uma chave (nem `cat` do `.env`, nem em
erro). Chave só entra pelo formulário do `/norte:salvar-seguro`. NUNCA faça `/login` pela pessoa.
Só troca quem ela pediu com a letra (A ou B) — sem letra, só mostra.

Ache os programas (o resolvedor funciona em qualquer instalação):

```bash
NBD="$(for d in "${CLAUDE_PLUGIN_ROOT:-$(ls -d "${CODEX_HOME:-$HOME/.codex}"/plugins/cache/norte-box/norte/*/ 2>/dev/null | sort -V | tail -1)}/bin" "$HOME"/.claude/plugins/cache/norte-box/*/*/bin; do [ -f "$d/nb-trocar-conta" ] && { printf '%s' "$d"; break; }; done)"
```

Leia `<ARGUMENTOS>`:

## Vazio → mostrar

```bash
node "$NBD/nb-trocar-conta" estado
```

Mostre as linhas como vieram (as 2 contas + em qual conta está esta conversa). Se aparecer "sem chave
guardada" ou "não foi aberta pelo nb-claude", ofereça em 1 linha o `/norte:trocar-conta configurar`.

## `A` ou `B` → trocar esta conversa

```bash
node "$NBD/nb-trocar-conta" esta <A|B>
```

- `OK|...` → diga só a frase, e acrescente: *"O que estiver digitado e não enviado se perde."* **Termine a
  resposta logo** — a troca só acontece quando a conversa para.
- `NAO|...` → diga o motivo em 1 linha. É recusa honesta (conta quase cheia, já está nela, conversa fora do
  nb-claude, Windows). Não tente contornar.

## `configurar` → preparar (uma vez por computador)

1. **As chaves.** Pra cada conta, a pessoa gera uma chave longa no Terminal DELA (não aqui):
   `claude setup-token` — o navegador abre, ela entra **na conta certa** e o Terminal mostra a chave.
   Guarde cada uma pelo formulário seguro (pasta pessoal, não o projeto):

   ```bash
   NB="$NBD/nb-salvar-seguro.js"; P="$HOME/.norte-box/contas"; mkdir -p "$P" && chmod 700 "$P"
   node "$NB" --projeto "$P" --cadastrar CLAUDE_CONTA_A_TOKEN --rotulo "chave da conta Claude A"
   node "$NB" --projeto "$P" --cadastrar CLAUDE_CONTA_B_TOKEN --rotulo "chave da conta Claude B"
   ```

   Depois abra o formulário de UMA conta por vez (siga o passo 2 do `/norte:salvar-seguro`, com
   `--projeto "$P" --nome CLAUDE_CONTA_A_TOKEN`, e depois o da B). A conta A pode ficar sem chave: aí ela
   usa o login normal do Claude (só não aparece o % dela).

2. **O lançador.** A troca só funciona em conversa aberta pelo `nb-claude`. **Pergunte antes** (mexe no
   arquivo de início do Terminal dela): *"Posso instalar o comando `nb-claude` no seu Terminal?"* Só com o
   "pode":

   ```bash
   mkdir -p "$HOME/.norte-box/bin" && cp "$NBD/nb-claude" "$HOME/.norte-box/bin/nb-claude" && chmod +x "$HOME/.norte-box/bin/nb-claude"
   for rc in "$HOME/.zshrc" "$HOME/.bashrc"; do [ -f "$rc" ] && ! grep -q 'norte-box/bin' "$rc" && printf '\n# norte-box: nb-claude (troca de conta)\nexport PATH="$HOME/.norte-box/bin:$PATH"\n' >> "$rc"; done
   ```

   Diga: *"Pronto. Abra um Terminal novo e use `nb-claude` no lugar de `claude` (ou `nb-claude B` pra
   começar na B). Dali, `/norte:trocar-conta B` troca a conversa."*

3. Confira com `node "$NBD/nb-trocar-conta" estado`.

## O que não funciona (diga se perguntarem)

- Windows: ainda não.
- Conversa aberta com `claude` puro (sem `nb-claude`): mostra o uso, mas não troca.
- Conversa trabalhando: espera até 30 min ela parar; depois desiste sem trocar.
