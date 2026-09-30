# norte-box (distribuição pública)

Cópia pública **somente do plugin** norte-box, para instalar no Claude Code **sem precisar de acesso a repositório privado**.

A norte-box é a "caixa" que roda em cima do Claude: memória entre sessões, freios de segurança, método de projeto grande, resposta em página e um medidor de uso opcional (só liga com convite + consentimento explícito).

---

## Jeito mais fácil: a página de instalação

Abra **https://norte-box-install.vercel.app** — ela detecta se você está no Windows ou no Mac e mostra só os passos certos, com botão de copiar. O passo a passo abaixo é o mesmo, por escrito.

---

## Instalar no Windows 11 — passo a passo (não precisa saber programar)

Você vai fazer isso **uma vez** (10-15 minutos). Se algum comando pedir para reiniciar, feche e abra o programa de novo.

### 1) Preparar o computador

Abra o **Prompt de Comando** (menu Iniciar → digite `cmd` → Enter) e cole, um de cada vez:

```
winget install --id Git.Git --exact --silent --accept-source-agreements --accept-package-agreements
winget install --id OpenJS.NodeJS.LTS --exact --silent --accept-source-agreements --accept-package-agreements
winget install --id jqlang.jq --exact --silent --accept-source-agreements --accept-package-agreements
winget install --id Anthropic.ClaudeCode --exact --silent --accept-source-agreements --accept-package-agreements
```

> Se o último disser que não encontrou o pacote, **feche o Prompt de Comando, abra de novo** e cole: `npm install -g @anthropic-ai/claude-code`

**Feche o Prompt de Comando e abra de novo** (pra ele enxergar o que você acabou de instalar). Depois siga em **"Abrir o Claude e entrar"**, mais abaixo.

---

## Instalar no Mac — passo a passo

Abra o **Terminal** (Cmd+Espaço → digite `Terminal` → Enter) e cole esta linha (ela instala tudo de uma vez):

```
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"; eval "$(/opt/homebrew/bin/brew shellenv 2>/dev/null || /usr/local/bin/brew shellenv)"; brew install node jq; npm install -g @anthropic-ai/claude-code
```

No meio ele pede a **senha do seu Mac** (ela não aparece enquanto você digita — é normal) e um **Enter** pra confirmar.

---

## Abrir o Claude e entrar (Windows e Mac)

Digite `claude` e tecle Enter. Na **primeira vez** aparecem 3 telas (em inglês):

1. **Cores do texto** — só tecle **Enter**.
2. **"Select login method"** — escolha **1** (*Claude account with subscription*) e tecle Enter. Abre o navegador: você entra na sua conta Claude e autoriza.
3. **"Is this a project you trust?"** — ⚠ ela já vem marcada em **"No, exit"**. Se você só apertar Enter, o Claude **fecha**. Aperte a **seta pra baixo** até **"Yes, I trust this folder"** e aí Enter.

## Instalar a norte-box (4 comandos, dentro do Claude)

Com o Claude aberto, cole **um de cada vez** (espere cada um terminar):

```
/plugin marketplace add Rogeriofresende/norte-box-dist
/plugin install norte@norte-box
/plugin marketplace add obra/superpowers-marketplace
/plugin install superpowers@superpowers-marketplace
```

**Feche o Claude e abra de novo** (`claude`) pra ligar a caixa.

## Ligar com o seu convite

Dentro do Claude, cole um de cada vez (troque `<seu-código>` pelo código que você recebeu — começa com `nb-`):

```
/norte:convite <seu-código>
/norte:consent
```

No `consent`, leia o termo e responda **sim**. Depois confira:

```
/norte:doctor
```

Tem que terminar com **DOCTOR OK**. Pronto — a norte-box está ligada. ✅

> Deu erro em algum passo? Tire um print da tela e mande pra quem te convidou.

### Deixar a caixa se atualizar sozinha (recomendado — 1 vez só)

Dentro do Claude, abra `/plugin`, vá em **Marketplaces → norte-box** e ligue o **auto-update**. Daí em diante, quando sair uma versão nova, a caixa se atualiza sozinha pouco depois de você abrir o Claude. Quem liga é você — a caixa **nunca** se atualiza escondida.

---

## Já tinha instalado uma versão antiga? (2º encontro)

Se você já instalou antes, **não precisa desinstalar nada**. Só atualize, dentro do Claude:

```
/plugin marketplace update norte-box
/plugin update norte@norte-box
```

Feche o Claude e abra de novo. Depois rode o seu convite normalmente. Se o seu convite já estava validado nesta mesma máquina, ele continua valendo.

---

## Privacidade (o medidor de uso)

O medidor de uso **só envia números de uso** (quantas vezes você usou cada coisa), e **só depois** que você valida um convite e responde **sim** no `/norte:consent`. Sem isso, **nada sai da sua máquina**. O conteúdo do seu trabalho **não** é enviado. Você pode ver e desligar isso a qualquer momento com `/norte:telemetry`.

O endereço do servidor de números **não é segredo** e é preenchido automaticamente pelo convite — você **não** precisa digitar nada de configuração.

---

## O que tem nesta cópia

Apenas o plugin: `plugins/norte-box/` + `.claude-plugin/marketplace.json`. Sem código de servidor, sem chaves, sem infraestrutura.
