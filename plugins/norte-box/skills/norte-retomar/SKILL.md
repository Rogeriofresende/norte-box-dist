---
name: norte-retomar
description: "Numa sessao NOVA, le o handoff mais recente do projeto (./norte-out/handoffs/) com rigor critico ANTES de qualquer execucao: escala por idade (FRESH/SLIGHTLY_STALE/STALE/VERY_STALE), valida o mundo (o que mudou desde o handoff), detecta acoes ja-disparadas e entrega objetivo + onde parou + proximo passo. Acionada por /norte-box:retomar, ou frases como 'retoma', 'continua de onde parei', 'carrega o handoff', 'onde a gente estava'. Irma de continuar (que CRIA o handoff)."
---

# norte-retomar

Recebe um handoff de outra sessao (ou de voce mesmo, ontem) **com rigor critico** — para que a
sessao que retoma alcance paridade de contexto com a que salvou, **antes de executar qualquer coisa**.

Evita o anti-padrao central: *"le o handoff por cima -> acha que entendeu -> executa errado."*

O "projeto" e o **cwd** (a pasta onde voce esta). A fonte e **`./norte-out/handoffs/`** — portatil,
viaja com o repo. Sem diretorio global, sem estado escondido na maquina.

## Acionamento

- **Comando:** `/norte-box:retomar` (sem argumento = handoff mais recente do projeto, via `ULTIMO.md`;
  com slug ou path = handoff especifico).
- **Linguagem natural:** "retoma", "continua de onde parei", "carrega o handoff", "onde a gente estava".

## Pre-condicoes

- **`./norte-out/handoffs/` nao existe** -> "Nenhum handoff neste projeto. Ao terminar uma sessao,
  rode `/norte-box:continuar` pra criar um." E pare (nao e erro — e o estado normal de projeto novo).
- **Path passado como argumento nao existe** -> "Handoff nao encontrado em `<path>`" e liste os
  disponiveis (`ls -t ./norte-out/handoffs/*.md`).
- **Varios handoffs recentes e nenhum argumento** -> use o `ULTIMO.md`; se nao houver ponteiro,
  liste os 5 mais recentes com data e peca pro usuario escolher.

## Passo 1 — Localize o handoff

```bash
# Sem argumento: o ponteiro ULTIMO.md aponta pro mais recente
cat ./norte-out/handoffs/ULTIMO.md 2>/dev/null | head -1   # confere que tem conteudo
# Fallback (sem ponteiro): o mais recente por mtime
ls -t ./norte-out/handoffs/*.md 2>/dev/null | grep -v ULTIMO.md | head -1
# Com argumento (slug parcial):
ls ./norte-out/handoffs/*<slug>*.md 2>/dev/null
```

Fixe `HANDOFF_PATH` para os proximos passos. Leia o arquivo **inteiro** com o tool `Read` (nao `cat`).

## Passo 2 — Detecte o staleness (idade + commits desde)

```bash
HANDOFF_MTIME=$(python3 -c "import os,sys; print(int(os.path.getmtime(sys.argv[1])))" "$HANDOFF_PATH")
HANDOFF_DATE=$(python3 -c "import time,sys; print(time.strftime('%Y-%m-%d', time.localtime(int(sys.argv[1]))))" "$HANDOFF_MTIME")
DAYS_SINCE=$(( ($(date +%s) - HANDOFF_MTIME) / 86400 ))
COMMITS_SINCE=$(git log --oneline --since="$HANDOFF_DATE" 2>/dev/null | wc -l | tr -d ' ')
```

> `python3 os.path.getmtime` funciona igual em macOS e Linux — `stat -f` (BSD) falha calado no Linux
> e classificaria tudo como FRESH por engano.

Classifique:

| Nivel | Definicao | Rigor |
|---|---|---|
| **FRESH** | `< 1 dia` E `< 5 commits` | Confia + apresenta no chat |
| **SLIGHTLY_STALE** | `1 a 3 dias` | + pre-mortem + deteccao de efeito ja-disparado |
| **STALE** | `3 a 7 dias` | valida o mundo antes de confiar em fatos do bilhete |
| **VERY_STALE** | `> 7 dias` | valida TUDO + avisa "o mundo provavelmente divergiu" |

Reporte: "Staleness do handoff: <NIVEL> (N dias, M commits desde)."
Se VERY_STALE, adicione: "O handoff tem mais de 7 dias — o estado do mundo provavelmente mudou bastante.
Considere salvar um handoff novo depois desta analise."

## Passo 3 — Siga a cadeia (chain-aware)

Se o handoff tem `continues-from: <arquivo>` (diferente de `-`), **leia esse arquivo tambem** com o
tool `Read` — recursivamente ate o handoff-raiz (sem `continues-from` ou com `-`). Mencionar o
predecessor no chat NAO basta: tem que ser uma leitura real, senao perde dependencias e decisoes das
sessoes anteriores.

Liste a cadeia lida em ordem (raiz -> mais recente): "Li N handoffs na cadeia: [paths]."

## Passo 4 — Levante as 5 perguntas (escreva ANTES de pesquisar)

Escreva as 5 perguntas **explicitamente** no chat ANTES de rodar qualquer comando do Passo 5. Elas sao
o coracao do rigor — pular isso colapsa a skill em "despejo de pesquisa". Adapte cada template aos
fatos REAIS deste handoff (arquivos, comandos, servicos citados nele):

| # | Pilar | Pergunta |
|---|---|---|
| 1 | **Atacar a premissa** | Qual afirmacao do handoff eu consigo REFUTAR agora com evidencia (ler o codigo real, git log, rodar o teste)? Pegue a suposicao mais estruturante e tente quebra-la. |
| 2 | **Evitar beco sem saida** | O que a sessao anterior TENTOU e nao conseguiu? Por que eu nao deveria simplesmente repetir o mesmo caminho? |
| 3 | **Detectar efeito ja-disparado** | Quais acoes com efeito externo (PR criado, push, deploy, email enviado, comando destrutivo) JA foram disparadas? Quais NAO podem ser re-executadas? |
| 4 | **Validar o estado do mundo** | Qual fato do handoff pode ter mudado nesses N dias? Como eu verifico (git fetch, ls do path, curl da URL, checar o servico)? |
| 5 | **Extrair a intencao** | Qual era o PORQUE original? Se o contexto mudou, essa intencao ainda vale ou o plano ficou obsoleto? |

## Passo 5 — Responda + valide o mundo

Para cada pergunta, ache resposta CONCRETA, nesta ordem de fonte:

1. **Ler o repo** — abra os arquivos citados no handoff; compare o que o handoff diz vs o que o codigo
   mostra AGORA.
2. **Git log** — `git fetch --all 2>/dev/null && git log --all --since="$HANDOFF_DATE" --oneline` pra ver
   o que mudou desde.
3. **Comandos smoke** — rode as validacoes reais (checklist abaixo).
4. **Busca externa** — so se a pergunta exige info de fora (doc de API, boa pratica). No maximo 3 fontes
   por pergunta pra nao entrar em toca de coelho; cite cada fonte.
5. **Marque PRE-CONDICAO BLOQUEANTE** se a resposta exige info privada (decisao do usuario, credencial,
   intencao que nao esta no handoff). NAO execute o proximo passo ate resolver; deixe a pergunta explicita.

### Checklist de validacao do mundo (rode e marque OK/FALHA por item)

```bash
# Commits desde o handoff (cross-branch)
git fetch --all 2>/dev/null && git log --all --since="$HANDOFF_DATE" --oneline

# Cada path citado no handoff ainda existe?
ls "<path>"

# Cada URL https citada no handoff responde?
curl -sI -o /dev/null -w "%{http_code}\n" "<url>"

# Sessoes paralelas (se o projeto usa .wip/active.md)
cat .wip/active.md 2>/dev/null
```

> **CONFERIDA OBRIGATORIA — trate o "proximo passo" do handoff como SUPOSICAO, nao fato.** So o concreto
> (arquivo existe, PR, teste que passa) e confiavel sem re-checar. Se o Passo 5 mostrar que o mundo mexeu
> no MESMO assunto do proximo passo, **NAO execute** — mostre "isto ja mudou: X" no cartao de chegada e
> reconcilie com o usuario ANTES de agir. A troca automatica que confia cega no recado velho e a causa
> numero 1 de retomada errada.

## Passo 6 — Pre-mortem (SLIGHTLY_STALE ou pior)

Pule se FRESH. Caso contrario:

> "Imagine que eu executei o 'Proximo passo' do handoff e quebrou. Liste as 3 causas-raiz mais provaveis.
> Para cada uma, cite a evidencia concreta (arquivo, commit, linha de log) que deveria ter previsto."

Minimo 3 causas, cada uma com artefato concreto — ou marque explicitamente "evidencia ausente = risco escondido".

## Passo 7 — Detecte acoes ja-disparadas

Varra o corpo do handoff (e a cadeia) por verbos de acao com efeito externo — em especial a secao
**"Cuidados / ja-disparado"**. Padroes: `PR #\d+`, `merge(ei|ado)?`, `push(ei|ado)?`, `deploy(ei|ado)?`,
`git commit`, `envie?i email`, `criei <arquivo>`. Para cada match:

1. Cite a linha do handoff.
2. Verifique o estado atual (ex: `git log` pro commit, checar se o arquivo existe, `gh pr view <N>` se houver `gh`).
3. **Regra padrao: NAO re-executar.** So refaca se o handoff documentar uma chave de idempotencia OU a
   verificacao confirmar que a acao falhou de forma recuperavel. Na duvida, pergunte ao usuario.

## Passo 7.5 — Levante as linhas REBAIXADAS pelo selo do bilhete (mostrar em 🔴 no topo)

O bilhete pode ter sido gravado pela `continuar` **com o selo do bilhete** (Passo 2.5 de la): cada `[x]`
da secao `## Onde estamos` que citou um arquivo/commit que **nao existia no disco** foi REBAIXADO pra:

```
- [ ] ⚠ nao achei no disco: <ref> (o bilhete marcava feito, mas o disco nao mostra) — era: ...
```

Varra o corpo do handoff (e a cadeia) por essas linhas: padrao `⚠ nao achei no disco` (ou `nao-verificavel`).
Se houver **qualquer** uma, mostre-a **em 🔴 NO TOPO** do cartao de chegada, ANTES de tudo:

```
🔴 O bilhete jurava isto, mas o disco nao mostra — CONFIRME antes de confiar:
   - <ref> (o bilhete marcava feito; nao achei no projeto)
```

Isto e o oposto do relato fabricado: em vez de a proxima sessao herdar um "feito" falso, ela ve, logo de
cara, o que o disco desmente. **Nao execute** o proximo passo que dependa de uma linha rebaixada sem antes
reconciliar com o usuario. (Se o handoff nao tiver linhas rebaixadas, pule este passo — bilhete limpo.)

## Passo 8 — Entregue (o cartao de chegada)

Formato pelo staleness:
- **FRESH / SLIGHTLY_STALE** -> apresente a analise no chat.
- **STALE / VERY_STALE** -> escreva a mesma analise em `<basename-do-handoff>-RECEIVED.md` ao lado do
  handoff (idempotente — sobrescreve; nao encadeie RECEIVED).

**Se houver linhas rebaixadas pelo selo (Passo 7.5), a PRIMEIRISSIMA coisa do output e o bloco 🔴 delas**
(antes ate da ancora "De onde viemos") — o alerta de "isto o disco desmente" ganha de tudo.

**A primeira coisa do output e SEMPRE a ancora** (nunca comprima nem pule, mesmo em FRESH):

```
De onde viemos: <objetivo herdado LITERAL do handoff>
Conversa anterior: <o que a ultima sessao fez, em palavras — via continues-from, ou "- (primeiro handoff)">
Agora: <o que esta sessao vai continuar>
```

Depois, o cartao:

```markdown
# Retomada: <nome do handoff>

Staleness: <NIVEL> · <N> dias · <M> commits desde · cadeia: <N> handoffs

## 5 perguntas + respostas
1..5 (premissa / beco / efeito / mundo / intencao)
Pergunta: ... · Resposta: ... (evidencia: leu X / git log Y / [fonte: url])

## Validacao do mundo
- [OK/FALHA] item verificado (saida do comando)

## Acoes JA DISPARADAS (nao re-executar)
- <acao> — estado verificado

## Riscos (pre-mortem, se SLIGHTLY_STALE+)
1. Causa-raiz: ... | Evidencia: ...

## Proximo passo (com intencao)
Acao proposta: ... · Intencao original: ... · Ainda vale? SIM/NAO/PARCIAL (+ ajuste se NAO/PARCIAL)

## Pre-condicoes bloqueantes (se houver)
- [ ] pergunta unica ao usuario: ...
```

Termine apresentando o **Proximo passo (com intencao)** como ultima mensagem — e o chamado a acao.

### Orcamento de saida (por staleness)

- **FRESH** — chat, curto (a ancora vem primeiro e NAO conta no limite). Resuma as 5 perguntas + 1 linha
  de resposta + 1 proximo passo. Pule a lista de validacao (mencione so os itens que FALHARAM) e o pre-mortem.
- **SLIGHTLY_STALE** — chat, um pouco mais longo. Inclua validacao so se algum item falhou; mencione o risco
  numero 1 do pre-mortem.
- **STALE / VERY_STALE** — arquivo `<original>-RECEIVED.md`, sem limite de tamanho, mas seja conciso:
  cite evidencia (arquivo + linha), nao despeje verbatim.

## Degradacao (nunca trava o trabalho)

- **Sem `./norte-out/handoffs/`** -> mensagem da pre-condicao e para (nao e erro).
- **Sem git** -> `COMMITS_SINCE=0`; classifique so pela idade; pule os checks de git no Passo 5.
- **Sem `python3`** pro mtime -> aproxime pela data no corpo do handoff (`data:`); se nem isso, trate como
  SLIGHTLY_STALE por seguranca (mais rigor, nao menos).
- **Erro em qualquer smoke** -> registre como FALHA no item e siga; nunca aborte a retomada por um comando.

## Prova (teste real)

Com o handoff criado por `continuar` no disco, uma sessao nova roda `/norte-box:retomar` e reporta o
**mesmo objetivo** e o **mesmo proximo passo** que o handoff gravou — provando que a memoria viajou entre
sessoes.
