# METODO — o jeito Norte de projeto grande

> O coracao do Norte-box. Quando o trabalho e maior que "escrever uma funcao" — um
> produto, um sistema, uma feature com varias partes — este e o metodo pra construir
> sem se perder. Ele nao inventa um processo novo: ele **orquestra o superpowers**
> (a caixa de ferramentas de engenharia disciplinada) e adiciona por cima as
> **6 regras anti-perda** (`docs/seis-regras-anti-perda.md`), que sao a memoria de
> como projetos grandes evaporam.

## O metodo em uma frase

**Brainstorm -> spec -> plano -> tarefas provadas.** Nao se pula etapa. Cada etapa
tem um dono no superpowers; o Norte-box so as encadeia na ordem certa e garante que
o objetivo, o mapa e as provas nao se percam entre elas.

## As 4 fases

### 1. Brainstorm — entender antes de construir

Antes de qualquer codigo, esclarecer o que estamos realmente tentando fazer: intencao,
requisitos, o que fica de fora. Uma pergunta de cada vez, ate o desenho ficar claro e
ser aprovado. Isto e a skill **`superpowers:brainstorming`** — o metodo a invoca por
nome. O objetivo que sai daqui vira a "frase imutavel" da regra 1: ele nao se reescreve
depois.

### 2. Spec — o contrato antes do codigo

Do desenho aprovado nasce a spec: o que cada peca faz, como se prova que esta pronta,
o que esta fora de escopo. A spec e curta se o projeto e simples, mas existe sempre —
e a regra 3 ("spec antes de codar"). No jeito Norte a spec do projeto do usuario e
gravada em `./norte-out/` (ex: `./norte-out/SPEC.md`), dentro do repo dele, pra viajar
com o projeto.

### 3. Plano — passos verificaveis

Da spec sai um plano em passos, cada passo com um criterio de "pronto" que se possa
provar por fato. Isto e a skill **`superpowers:writing-plans`**. O plano vira o mapa
vivo da regra 2 (`[x]` feito / `[ ]` pendente) — a fonte unica de "onde estamos",
gravado em `./norte-out/` (ex: `./norte-out/PLANO.md`).

### 4. Tarefas provadas — uma de cada vez

Executar o plano **uma tarefa por vez**, e cada tarefa so fecha com **evidencia
externa reproduzivel** (regra 4): a saida de um teste, o resultado de um comando, a
tela abrindo. Isto e a skill **`superpowers:executing-plans`** (com pontos de revisao)
ou **`superpowers:subagent-driven-development`** (quando as tarefas sao independentes e
cabem na mesma sessao). No fim, **`superpowers:verification-before-completion`** confere
que o "pronto" e real, nao auto-declarado.

## Wrapper por NOME, nunca copia

O Norte-box **nao vendoriza** o superpowers. Ele o aciona **pelo nome das skills**
(`superpowers:brainstorming`, `superpowers:writing-plans`, `superpowers:executing-plans`,
`superpowers:subagent-driven-development`, `superpowers:verification-before-completion`),
que sao instaladas como dependencia separada. Vantagem: o superpowers evolui por conta
propria e voce nao carrega uma copia velha dentro do pacote.

**Se o superpowers nao estiver instalado**, o metodo nao quebra: ele avisa claramente
e degrada, conduzindo spec + plano + a 1a tarefa manualmente, e mostra o conserto:

```
claude plugin marketplace add obra/superpowers-marketplace
claude plugin install superpowers@superpowers-marketplace
```

## O que segura tudo: as 6 regras

Por cima das 4 fases correm as **6 regras anti-perda** (`docs/seis-regras-anti-perda.md`):
objetivo imutavel a vista · caminho/estado sempre visivel · spec antes de codar · provar
cada passo por fato · esqueleto vivo antes de conteudo · handoff a cada troca de sessao.
Sao a diferenca entre "quase pronto e perdido" e "pronto e provado".

## Como usar

Rode **`/norte-box:projeto "<descricao do que voce quer construir>"`**. O comando
conduz as 4 fases na ordem, gravando spec e plano em `./norte-out/` e provando a 1a
tarefa por fato. Ao trocar de sessao, `/norte-box:continuar` salva o handoff e
`/norte-box:retomar` continua no mesmo lugar.
