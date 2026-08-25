# Norte-box

O jeito Norte de usar IA, empacotado como plugin de Claude Code. Roda 100% local, na sua
maquina. Nao e um SaaS: e um plugin que voce liga no seu Claude Code.

O que vem dentro:

- **Freios** — `secret-guard` (bloqueia secret colado no chat) + `confirmar-antes`
  (lembra de confirmar a demanda antes de sair construindo).
- **Memoria entre sessoes** — `continuar`/`retomar`: um handoff por-projeto pra proxima
  sessao nascer sabendo onde voce parou (sem voce anexar nada).
- **Metodo de projeto grande** — `projeto`: conduz spec -> plano -> execucao -> verificacao,
  orquestrando o superpowers + as regras anti-perda do jeito Norte.
- **Resposta HTML local** — `resposta`: transforma a entrega num arquivo `.html`
  auto-contido e abre no navegador. Zero servidor, zero rede.
- **MEDIDOR de uso (numeros por padrao)** — com aceite no 1o uso. Por padrao a Norte NAO ve o
  seu trabalho: so recebe os NUMEROS de uso (pedidos, tempo, tamanho) pra cobrar justo. O
  conteudo de uma sessao so sai quando VOCE compartilha (`/norte-box:compartilhar`, com previa
  antes de enviar). Detalhes: `plugins/norte-box/docs/TELEMETRIA.md`.

**Fechado, por convite.** Uso mediante codigo de convite + aceite do termo. Nao e gratis:
voce usa em troca de deixar a Norte analisar o uso (o codigo e revogavel).

---

## Instalar (maquina limpa)

Voce precisa de duas coisas antes de comecar:

1. **O convite do GitHub aceito** — o repositorio e privado; quem te convidou adicionou
   sua conta. Aceite o convite no e-mail do GitHub ou em `https://github.com/notifications`.
   Numa maquina limpa (sem chave SSH), o jeito mais simples de autenticar e `gh auth login`
   (login pelo navegador) — o bootstrap usa isso; um Personal Access Token do git tambem serve.
2. **O codigo de convite** que quem te convidou te mandou (uma string curta, comeca com `nb-`).
   Voce vai digita-lo no 1o uso, em `/norte-box:convite`.

### Instalar (um comando)

Abra o Terminal (nao importa onde) e cole **este unico comando**. Ele garante o `gh`, faz o
login do GitHub (1o "Autorizar" no navegador) e — **so depois de voce estar autenticado** — puxa
o instalador do nosso repo privado via `gh` (sua conta) e o roda. **Sem `curl | bash` de link
publico anonimo; nada baixa antes da sua conta GitHub autenticar.**

```bash
command -v gh >/dev/null 2>&1 || { sudo apt-get update -qq && sudo apt-get install -y gh 2>/dev/null || (type brew >/dev/null 2>&1 && brew install gh); }; gh auth status >/dev/null 2>&1 || gh auth login --hostname github.com --git-protocol https --web; T="$(mktemp)" && gh api repos/Rogeriofresende/norte-box/contents/bootstrap/instalar.sh --jq .content | base64 -d > "$T" && { [ -s "$T" ] && bash "$T" || echo "nao consegui baixar o instalador (sua conta tem acesso ao repo?)"; }; rm -f "$T"
```

O instalador (`bootstrap/instalar.sh`) cuida do resto **na ordem que nao quebra**:
toolchain → login do GitHub → login do Claude (2o "Autorizar") → **clone via `gh` (nunca `git
clone` cru)** → bootstrap → e termina dizendo o proximo passo. O beco que travava (clonar o repo
PRIVADO antes do login → prompt de usuario/senha do GitHub) fica **impossivel por construcao**:
o clone so acontece depois que a autenticacao passa.

Ao final, o instalador diz **"✅ Norte-box instalado"** e pede so o passo humano que falta —
abrir o Claude e colar o convite:

```bash
claude
/norte-box:convite <codigo>  # o codigo nb-... que voce recebeu
/norte-box:consent           # le o termo (numeros por padrao) e responda: sim  -> LIGADO ✅
```

<details><summary>Modo manual (passo a passo, se preferir rodar cada etapa na mao)</summary>

> **Onde rodar:** abra o Terminal numa **pasta limpa** (fora de qualquer projeto). A linha
> `cd ~` do comando abaixo ja faz isso por voce — leva pra sua pasta pessoal antes de baixar,
> **nao importa onde o terminal abriu**. (Se o Norte-box cair dentro de outro projeto, o
> bootstrap PARA e te avisa com o conserto — ele nao segue instalando no lugar errado.)

```bash
# 0. login do GitHub PRIMEIRO (o repo e privado — SEM isso, o git clone abaixo pediria senha)
gh auth login --hostname github.com --git-protocol https --web

# 1. baixar numa pasta limpa + bootstrap (toolchain + Claude Code CLI + marketplace + plugin + .env)
#    ja autenticado no passo 0, o clone do repo privado nao pede senha.
cd ~ && gh repo clone Rogeriofresende/norte-box && cd norte-box
bash bootstrap/bootstrap.sh

# 2. login (usa o Claude da Norte via convite)
claude /login

# 3. abre o Claude Code e PROVA que a Parte 1 (terminal) deu certo
claude
/norte-box:doctor            # ANCORA da Parte 1 (a casca instalou). ANTES do convite/consent ele
                             #  termina com "DOCTOR: onboarding pendente" — esse e o VERDE esperado
                             #  aqui (casca ok, agora ligue nos passos 4-5). "DOCTOR OK" so aparece
                             #  DEPOIS de convite+consent: o doctor e honesto e nao diz OK enquanto
                             #  o Norte-box nao estiver LIGADO de verdade.

# 4. valida o codigo de convite (guarda sua identidade local)
/norte-box:convite <codigo>  # o <codigo> que voce recebeu (comeca com nb-)

# 5. le o termo (numeros por padrao) e aceita
/norte-box:consent           # mostra o termo; responda sim/nao
/norte-box:doctor            # rode de novo: AGORA sim ele termina com DOCTOR OK (esta LIGADO)
```

</details>

`/norte-box:doctor` no passo 3 e a **linha divisoria da Parte 1**: enquanto ele der `DOCTOR
FALHOU` (item da casca quebrado), a instalacao no terminal nao fechou — conserte pelo que a
tabela aponta antes de avancar. Ja `DOCTOR: onboarding pendente` NAO e falha: e a casca ok
esperando voce ligar (passos 4-5). Depois do passo 5 (aceite), rode o doctor mais uma vez e ele
termina com `DOCTOR OK` — ai o metodo e a telemetria estao liberados.

Se `/norte-box:doctor` terminar com `DOCTOR FALHOU: <itens>`, ele te mostra na propria tabela
qual item falhou + o comando de conserto. Comece o suporte por ai (ver `docs/SUPORTE.md`).

### Instalar na maquina de quem constroi o pacote (HOME real, login que voce ja tem)

Se voce e **quem desenvolve o Norte-box**, sua maquina NAO e limpa: ela ja tem `~/norte-box`
(o repo de DESENVOLVIMENTO — seu trabalho) e o plugin ja instalado no seu `~/.claude`. Mas o
seu `~/.norte-box` **so tem o `.env`** — NAO tem convite nem consent ainda. Ou seja: nao ha
onboarding real a preservar, entao **da pra onboardar no HOME REAL, direto, sem isolar nada.**

> **Por que NAO isolamos o HOME (mudou no NRT-_1429):** a versao antiga rodava num `$HOME` de
> teste separado pra nao tocar o estado real. Mas o `claude /login` e **por HOME** (marcador em
> `~/.claude.json` + keychain por-usuario no macOS): sob um HOME isolado o login **quebra** — voce
> teria que logar de novo naquele canto. Como o `~/.norte-box` real nao tem nada a preservar, o
> caminho certo e o simples: **use o login que voce ja tem, no HOME real.**

O fluxo e o MESMO da "maquina limpa" acima, so que voce ja tem o repo e o login. Faca no
**Terminal** o preparo (opcional, so confirma que e seguro e imprime as linhas):

```bash
cd ~/norte-box
bash bootstrap/teste-do-zero.sh     # confirma login + que ~/.norte-box nao tem convite/consent
                                    #  a sobrescrever (fail-closed) e imprime as 3 linhas reais
```

Depois abra o Claude Code e rode **dentro dele** (o gate libera esses comandos antes do aceite):

```bash
claude                       # usa o login que voce ja tem
/norte-box:doctor            # deve terminar em: DOCTOR: onboarding pendente (casca ok)
/norte-box:convite <codigo>  # o codigo nb-... que voce recebeu
/norte-box:consent           # leia o termo (numeros por padrao), responda: sim
/norte-box:doctor            # AGORA deve terminar em: DOCTOR OK (esta LIGADO)
```

O `teste-do-zero.sh` **para (fail-closed)** se achar `identity.json`/`consent.json` reais — pra
nunca sobrescrever um onboarding por acidente. Se voce QUER refazer do zero de proposito, ele te
diz como mover o estado pra um canto (`mv ~/.norte-box ~/.norte-box.bak-...`) antes.

### 1o uso: convite + aceite (a ordem importa)

Antes de o metodo operar, o Norte-box precisa de duas coisas, **nesta ordem**:

1. **`/norte-box:convite <codigo>`** — valida o codigo contra o servidor da Norte e guarda a
   sua **identidade** local (o `invite_id`). E o que marca o seu uso como sendo seu.
2. **`/norte-box:consent`** — mostra o **termo (Modelo A: numeros por padrao)** — por padrao a
   Norte NAO ve o seu trabalho, so os NUMEROS de uso — e coleta o seu **aceite** (sim/nao). So
   depois do "sim" o metodo e o medidor ligam. Pra mostrar o conteudo de uma sessao, use
   `/norte-box:compartilhar` (com previa antes de enviar).

Se voce mandar um prompt antes de aceitar, o Norte-box te lembra de rodar `/norte-box:consent`.
Codigo invalido/expirado/ja-usado nao entra — confirme com quem te convidou.

> **Importante:** o **freio de secret continua ativo mesmo antes do aceite.** Seguranca nao
> depende de aceite — se voce colar um secret, ele bloqueia de qualquer jeito.

---

## Comandos (v1)

Todos com namespace `/norte-box:*` (nao colidem com skills que voce ja tenha):

| Comando | O que faz |
|---|---|
| `/norte-box:doctor` | Prova de vida + autodiagnostico. **1a linha do suporte.** |
| `/norte-box:projeto "<ideia>"` | Conduz um projeto grande: spec -> plano em passos -> execucao 1 tarefa por vez -> verificacao por fato. |
| `/norte-box:continuar` | Salva um handoff desta conversa em `./norte-out/handoffs/`. A proxima sessao nasce sabendo onde parou. |
| `/norte-box:retomar` | Numa sessao NOVA, le o handoff mais recente do projeto (com rigor por idade) e reporta objetivo + proximo passo antes de agir. |
| `/norte-box:resposta` | Gera a entrega como um `.html` local auto-contido em `./norte-out/` e abre no navegador. |
| `/norte-box:convite <codigo>` | Valida o codigo de convite contra o servidor e guarda a sua identidade local (`invite_id`). **Passo 1 do 1o uso**, antes do consent. |
| `/norte-box:consent` | Mostra o termo (Modelo A: numeros por padrao) e coleta o **aceite** (sim/nao). **Passo 2 do 1o uso**, depois do convite. |
| `/norte-box:compartilhar` | Compartilha o CONTEUDO de UMA sessao com a Norte — mostra a **previa exata** antes de enviar e so envia com o seu "sim". Opt-in explicito; o padrao continua sendo so os numeros. |
| `/norte-box:telemetry show\|off\|on` | Ve a fila do MEDIDOR antes de enviar (`show`), desliga (`off`) ou religa (`on`). A fila carrega **so numeros**, nunca o seu trabalho. **Desligar nunca desliga os freios de seguranca.** |

### Onde ficam as coisas

- **Estado da maquina** (aceite, codigo validado, identidade, fila de telemetria):
  `$HOME/.norte-box/` — nunca no repositorio do seu projeto.
- **Saida por-projeto** (handoffs, HTML de resposta, spec/plano gerados):
  `./norte-out/` no diretorio do seu projeto. Coloque `norte-out/` no seu `.gitignore`.

O plugin nunca escreve fora desses dois lugares. Nunca toca no seu `settings.json` nem em
`~/.claude/`.

---

## Fluxo tipico

```
/norte-box:projeto "conversor de CSV"   -> gera spec + plano + 1 tarefa verificada em ./norte-out/
... voce trabalha ...
/norte-box:continuar                    -> salva o handoff (contexto enchendo? troca de sessao? use aqui)
... sessao nova ...
/norte-box:retomar                      -> a nova sessao sabe o objetivo e o proximo passo
/norte-box:resposta                     -> a entrega vira HTML local e abre no navegador
```

---

## Documentacao

| Doc | Pra que |
|---|---|
| `docs/SUPORTE.md` | Deu problema? Comeca aqui (`/norte-box:doctor` + becos comuns). |
| `docs/SECURITY.md` | Como os freios sao endurecidos (fail-open, timeout, nao escreve fora do escopo). Como reportar falha de seguranca. |
| `docs/DEPS.md` | A dependencia superpowers (SHA-pinada por nome, nunca vendorizada) e como atualizar. |
| `docs/INSTALL-CLEAN-MACHINE.md` | Roteiro do teste numa maquina LIMPA (nao a de quem construiu) + os gates de negocio antes de distribuir. |
| `plugins/norte-box/docs/TELEMETRIA.md` | O que a telemetria coleta / o que NUNCA / pra onde / como revogar. |

---

## Desinstalar / rollback

O Norte-box e um plugin: liga e desliga sem residuo.

```bash
claude plugin uninstall norte-box@norte-box   # remove o plugin (freios + comandos somem)
rm -rf "$HOME/.norte-box"                       # opcional: apaga o estado local (aceite, fila)
```

Seus projetos e o `./norte-out/` de cada um continuam intactos — sao seus.

---

> Este README cresce ate o **teste do estranho**: uma pessoa que nao e de quem construiu
> consegue instalar so com ele (ver `docs/INSTALL-CLEAN-MACHINE.md`).
