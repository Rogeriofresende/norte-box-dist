# norte-box (distribuição pública)

Cópia pública **somente do plugin** norte-box, para instalar no Claude Code **sem precisar de acesso a repositório privado**.

A norte-box é a "caixa" que roda em cima do Claude: memória entre sessões, freios de segurança, método de projeto grande, resposta em página e um medidor de uso opcional (só liga com convite + consentimento explícito).

---

## Instalar no Windows 11 — passo a passo (não precisa saber programar)

Você vai fazer isso **uma vez**. Se algum comando pedir para reiniciar, feche e abra o programa de novo.

### 1) Instalar o Git (traz o "Git Bash", que os freios de segurança usam)

Abra o **Prompt de Comando** (menu Iniciar → digite `cmd` → Enter) e cole:

```
winget install --id Git.Git --exact --silent --accept-source-agreements --accept-package-agreements
```

### 2) Instalar o Node e o jq (o convite precisa dos dois)

Ainda no Prompt de Comando, cole os dois:

```
winget install --id OpenJS.NodeJS.LTS --exact --silent --accept-source-agreements --accept-package-agreements
winget install --id jqlang.jq --exact --silent --accept-source-agreements --accept-package-agreements
```

### 3) Instalar o Claude Code

```
winget install --id Anthropic.ClaudeCode --exact --silent --accept-source-agreements --accept-package-agreements
```

> Se o `winget install --id Anthropic.ClaudeCode` disser que não encontrou o pacote, instale pelo Node: `npm install -g @anthropic-ai/claude-code` (o Node do passo 2 já traz o `npm`).

**Feche o Prompt de Comando e abra de novo** (pra ele enxergar o que você acabou de instalar).

### 4) Abrir o Claude e fazer login

No Prompt de Comando, digite:

```
claude
```

Na primeira vez ele pede login — siga o que aparecer na tela (abre o navegador, você entra e autoriza).

### 5) Instalar a norte-box (dois comandos, **dentro do Claude**)

Com o Claude aberto, cole um de cada vez:

```
/plugin marketplace add Rogeriofresende/norte-box-dist
/plugin install norte-box@norte-box
```

**Feche o Claude e abra de novo** (`claude`) pra ligar a caixa.

### 6) Ligar com o seu convite

Dentro do Claude, cole (troque `<seu-código>` pelo código que você recebeu — começa com `nb-`):

```
/norte-box:convite <seu-código>
/norte-box:consent
```

No `consent`, leia o termo e responda **sim**. Pronto — a norte-box está ligada.

Pra conferir a qualquer momento:

```
/norte-box:doctor
```

Verde = tudo certo.

---

## Já tinha instalado uma versão antiga? (2º encontro)

Se você já instalou antes, **não precisa desinstalar nada**. Só atualize, dentro do Claude:

```
/plugin marketplace update norte-box
/plugin update norte-box@norte-box
```

Feche o Claude e abra de novo. Depois rode o seu convite normalmente (passo 6). Se o seu convite já estava validado nesta mesma máquina, ele continua valendo.

---

## Privacidade (o medidor de uso)

O medidor de uso **só envia números de uso** (quantas vezes você usou cada coisa), e **só depois** que você valida um convite e responde **sim** no `/norte-box:consent`. Sem isso, **nada sai da sua máquina**. O conteúdo do seu trabalho **não** é enviado. Você pode ver e desligar isso a qualquer momento com `/norte-box:telemetry`.

O endereço do servidor de números **não é segredo** e é preenchido automaticamente pelo convite — você **não** precisa digitar nada de configuração.

---

## O que tem nesta cópia

Apenas o plugin: `plugins/norte-box/` + `.claude-plugin/marketplace.json`. Sem código de servidor, sem chaves, sem infraestrutura.
