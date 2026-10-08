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

## Antes de rodar qualquer coisa: dá pra trocar aqui?

A troca **não funciona** em 3 lugares. Confira primeiro (só lê variáveis, não mexe em nada):

```bash
case "$(uname -s 2>/dev/null)" in MINGW*|MSYS*|CYGWIN*) echo LUGAR=windows;; *) [ "${OS:-}" = Windows_NT ] && echo LUGAR=windows;; esac
[ -z "${CLAUDE_CODE_SESSION_ID:-}" ] && echo LUGAR=fora-do-claude-code
[ -n "${CLAUDE_CODE_ENTRYPOINT:-}" ] && [ "$CLAUDE_CODE_ENTRYPOINT" != cli ] && echo "LUGAR=painel ($CLAUDE_CODE_ENTRYPOINT)"
```

- **Windows** (`LUGAR=windows`) → *"No Windows a troca de conta ainda não funciona."*
- **Codex** (você é o Codex, não o Claude Code — ou saiu `LUGAR=fora-do-claude-code`) → *"No Codex a troca de
  conta não funciona — ela é só pro Claude Code."*
- **Painel lateral do VS Code / extensão** (`LUGAR=painel ...`) → *"No painel lateral do VS Code a troca não
  funciona — abra a conversa num Terminal com `nb-claude`."*

Nesses casos diga a frase em 1 linha e **pare** — não rode o `esta A|B`. Mostrar o uso (sem letra) ainda
pode. Não saiu nada (ou ficou na dúvida) → siga; o `nb-trocar-conta` decide e recusa com motivo se precisar.

Ache os programas (o resolvedor funciona em qualquer instalação):

```bash
NBD="$([ -f "${CLAUDE_PLUGIN_ROOT:-$(ls -d "${CODEX_HOME:-$HOME/.codex}"/plugins/cache/norte-box/norte/*/ 2>/dev/null | sort -V | tail -1)}/bin/nb-trocar-conta" ] && printf '%s' "${CLAUDE_PLUGIN_ROOT:-$(ls -d "${CODEX_HOME:-$HOME/.codex}"/plugins/cache/norte-box/norte/*/ 2>/dev/null | sort -V | tail -1)}/bin" || for d in "$HOME"/.claude/plugins/cache/norte-box/*/*/bin; do [ -f "$d/nb-trocar-conta" ] && printf '%s\t%s\n' "$(basename "$(dirname "$d")")" "$d"; done | grep -E '^[0-9]+\.[0-9]+\.[0-9]+'"$(printf '\t')" | sort -t. -k1,1n -k2,2n -k3,3n | tail -1 | cut -f2-)"
```

(Sem `CLAUDE_PLUGIN_ROOT`, pega a versão **mais nova** instalada — 0.3.10 vem depois de 0.3.9.)

Leia `<ARGUMENTOS>`:

## Vazio → mostrar

```bash
node "$NBD/nb-trocar-conta" estado
```

Mostre as linhas como vieram (as 2 contas + em qual conta está esta conversa). Se aparecer "sem chave
guardada" ou "não foi aberta pelo nb-claude", ofereça em 1 linha o `/norte:trocar-conta configurar`.

**A letra na barrinha:** em conversa aberta pelo `nb-claude`, a barrinha de baixo mostra 🄰 ou 🄱 no fim — é a
conta em que **esta conversa foi aberta**. Conversa aberta com `claude` puro não mostra letra nenhuma. Com o
complemento do VS Code (passo 3 do `configurar`), Cmd+clique na letra troca a conta por ali mesmo. A letra
não quer dizer "troca feita": depois de trocar, a conversa reabre e a letra nova aparece nela.

## `A` ou `B` → trocar esta conversa

```bash
node "$NBD/nb-trocar-conta" esta <A|B>
```

- `OK|...` → diga só a frase, e acrescente: *"O que estiver digitado e não enviado se perde."* **Termine a
  resposta logo** — a troca só acontece quando a conversa para.
- `NAO|...` → diga o motivo em 1 linha. É recusa honesta (conta quase cheia, já está nela, conversa fora do
  nb-claude, Windows). Não tente contornar.
- Se o `NAO|...` trouxer um comando `nb-claude <A|B> --resume <número>` (conversa aberta com `claude` puro),
  mostre esse comando **exato**, num bloco de código, e diga: *"Saia desta conversa com `/exit` e cole isso
  no Terminal — ela volta igualzinha, já na outra conta."* Não rode o comando você mesmo.

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
   mkdir -p "$HOME/.norte-box/bin" && cp "$NBD/nb-claude-ponteiro" "$HOME/.norte-box/bin/nb-claude" && chmod +x "$HOME/.norte-box/bin/nb-claude"
   for rc in "$HOME/.zshrc" "$HOME/.bashrc"; do [ -f "$rc" ] && ! grep -q 'norte-box/bin' "$rc" && printf '\n# norte-box: nb-claude (troca de conta)\nexport PATH="$HOME/.norte-box/bin:$PATH"\n' >> "$rc"; done
   ```

   O que fica instalado é um **ponteiro**: a cada uso ele roda o `nb-claude` da versão mais nova da caixa.
   **Atualizar a caixa não exige reinstalar.** (Quem tem a cópia antiga: rodar este passo de novo troca pelo
   ponteiro; o `/norte:doctor` avisa "nb-claude antigo".)

   Diga: *"Pronto. Abra um Terminal novo e use `nb-claude` no lugar de `claude` (ou `nb-claude B` pra
   começar na B). Dali, `/norte:trocar-conta B` troca a conversa. Quando a caixa atualizar, não precisa
   refazer nada."*

3. **A letra clicável (opcional, só no VS Code).** Com um complemento do VS Code, o Cmd+clique (Ctrl+clique no
   Linux) na letra 🄰/🄱 da barrinha abre a lista das 2 contas → escolhe → confirma → a conversa troca sozinha.
   **Pergunte antes** (instala um complemento no VS Code dela): *"Quer que eu instale no seu VS Code o
   complemento que deixa a letra clicável?"* Só com o "pode":

   ```bash
   node "$NBD/nb-troca-vscode" instalar
   ```

   - `OK|...` → diga: *"Pronto. Nas conversas abertas com `nb-claude` no Terminal do VS Code, dê Cmd+clique na
     letra do fim da barrinha. Se não clicar de primeira, feche e abra o Terminal."* NÃO reinicie o VS Code.
   - `NAO|...` → diga o motivo em 1 linha (sem VS Code, Windows). A troca pelo `/norte:trocar-conta B` segue.
   - Tirar depois: `node "$NBD/nb-troca-vscode" remover`.

4. Confira com `node "$NBD/nb-trocar-conta" estado` e com o `/norte:doctor` (3 linhas "Troca de conta").

## O que não funciona (diga se perguntarem)

- **Windows:** ainda não. Avisa antes de tentar.
- **Codex:** não — a troca é só do Claude Code. Avisa antes de tentar.
- **Painel lateral do VS Code (extensão):** não troca — use um Terminal (pode ser o Terminal de dentro do VS
  Code) com `nb-claude`. Avisa antes de tentar.
- **Conversa aberta com `claude` puro** (sem `nb-claude`): mostra o uso e a barrinha fica sem letra; não troca
  no lugar, mas dá o comando `nb-claude <conta> --resume ...` pra reabrir a mesma conversa na outra conta.
- **Conversa trabalhando:** espera até 30 min ela parar; depois desiste sem trocar.
