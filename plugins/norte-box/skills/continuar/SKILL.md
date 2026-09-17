---
name: continuar
description: "Salva um handoff por-projeto quando o contexto esta enchendo ou uma etapa terminou, para que a proxima sessao continue exatamente de onde parou. Acionada por /norte:continuar, ou frases como 'salva o estado', 'cria handoff', 'preciso pausar', 'o contexto esta enchendo', 'guarda a memoria'. Escreve ./norte-out/handoffs/<slug>-<AAAAMMDD-HHMM>.md + atualiza ULTIMO.md. Irma de norte-retomar (que LE o handoff de volta)."
---

# continuar

Salva um **bilhete curto e completo** (handoff) desta conversa, **por-projeto**, para que
uma sessao nova nasca sabendo exatamente onde parar e continuar — sem tomar o controle da
maquina e sem o usuario precisar abrir ou anexar nada.

**ONDE SALVAR (regra unica — rode ISTO primeiro e use `$DIR/handoffs/` no lugar de `./norte-out/handoffs/`
em TODOS os comandos abaixo):**

```bash
DIR="$(bash "${CLAUDE_PLUGIN_ROOT}/bin/nb-resolve-outdir")"   # ./norte-out (em projeto) OU ~/.norte-out (fora)
```

- **Dentro de um projeto** (é repo git ou já tem `./norte-out`) -> `$DIR = ./norte-out` — a memoria **viaja
  com o projeto** (outro clone/maquina/colaborador veem o mesmo bilhete). É o caso comum e o melhor.
- **Fora de um projeto** (cwd solto, sem repo) -> `$DIR = ~/.norte-out` (**fallback global**) — assim o
  `/continuar` NUNCA fica sem onde gravar, cobrindo o que o antigo /continuar "do assento" fazia (NRT-_991398).
- Override: `$NORTE_OUT_DIR` manda em tudo, se setado.

## Quando usar

- O usuario disse "pausa", "vou parar", "salva o estado", "cria handoff", "o contexto esta enchendo".
- Uma etapa grande terminou (varios arquivos editados, um bug fechado, uma decisao de arquitetura).
- Proativamente, apos trabalho substancial (5+ edicoes de arquivo, debug complexo): sugira
  "Fizemos bastante progresso. Vale salvar um handoff pra proxima sessao continuar sem ambiguidade.
  Diga `/norte:continuar` quando quiser."

## Passo 1 — Junte o contexto (leitura, nao suposicao)

Rode e leia a saida (o handoff so vale se for baseado em fato):

```bash
pwd
git branch --show-current 2>/dev/null
git log --oneline -10 2>/dev/null
git diff --stat 2>/dev/null
git status --short 2>/dev/null
```

Deriva os campos do handoff:

- **projeto** = `basename "$(pwd)"` (o nome da pasta do projeto).
- **slug** = titulo curto do objetivo, transformado em `[a-z0-9-]` — **ASCII sempre**
  (acento/espaco no nome do arquivo quebra a leitura depois). Ex: "Conversor de CSV" -> `conversor-de-csv`.
- **continues-from** = o handoff anterior deste projeto, se existir:
  `ls -t "$DIR"/handoffs/*.md 2>/dev/null | grep -v ULTIMO | head -1` (ou `-` se for o primeiro).
- **timestamp** = `date +"%Y-%m-%d %H:%M"` e o sufixo do arquivo `date +"%Y%m%d-%H%M"`.
- **carimbo de validade** (o "prazo do bilhete" — a `norte-retomar` usa isto pra avisar se o
  bilhete envelheceu). Deriva de COMANDO, nao de opiniao:
  - **selado-em-commit** = `git rev-parse --short HEAD 2>/dev/null || echo sem-git` — o commit do
    projeto NESTE instante (a ancora pra contar "quantas mudancas entraram desde").
  - **selado-em** = `date -u +%Y-%m-%dT%H:%M:%SZ` — o agora em ISO UTC (a ancora pra contar "ha
    quantos dias").
  Escreva os dois no CABECALHO do handoff (ver Passo 2). Se nao for repo git, `selado-em-commit`
  vira `sem-git` — sem problema: a `norte-retomar` trata como "commits: nao sei" e segue.

## Passo 2 — Escreva o handoff

**Nome do arquivo (À PROVA DE PERDA — rode ISTO; NUNCA monte o nome na mao):** o nome com precisao
de minuto COLIDE se dois salvamentos caem no mesmo minuto com o mesmo assunto — o segundo sobrescreve
o primeiro e um bilhete SOME (furo provado NRT-_991398, 16/09). O helper devolve um caminho
**garantidamente novo** (segundos + nunca sobrescreve; se colidir, cria `-2`, `-3`…) e ja cria a pasta:

```bash
NOVO="$(bash "${CLAUDE_PLUGIN_ROOT}/bin/nb-bilhete-path" "$DIR" "$slug")"
```

Escreva o handoff em **`$NOVO`** (use `$NOVO` em TODOS os comandos abaixo, no lugar de
`./norte-out/handoffs/<slug>-<AAAAMMDD-HHMM>.md`). Use exatamente estas 6 secoes:

```markdown
# Handoff — <titulo curto>
data: <AAAA-MM-DD HH:MM>
projeto: <basename do cwd>
continues-from: <arquivo do handoff anterior deste projeto | "-">
selado-em-commit: <sha curto do HEAD do projeto AGORA | "sem-git">
selado-em: <timestamp ISO UTC de agora>

## Objetivo (1 frase)
<o que estamos tentando fazer — em portugues de padaria, sem sigla>

## Onde estamos (mapa: [x] feito / [ ] pendente)
- [x] <passo feito, com prova no disco (arquivo/commit/teste)>
- [ ] <proximo passo>

## Fatos verificados (nao suposicao)
- <fato + como foi provado (comando que rodou, arquivo que existe, teste que passou)>

## Proximo passo (1, concreto)
<a PRIMEIRA coisa que a proxima sessao faz — especifico e acionavel>

## Cuidados / ja-disparado (nao repetir)
- <PR aberto / arquivo criado / comando ja rodado / deploy feito — o que NAO re-executar>
```

### Regras de preenchimento (o que separa um handoff util de um inutil)

- **Objetivo em 1 frase de padaria** — quem le em 30 segundos entende o que fazer. Sem sigla.
- **Passo `[x]` so com prova no disco.** Marcou feito? Cite o arquivo/commit/teste que prova.
  Sem prova, e `[ ]` (nao "provavelmente feito").
- **Fatos verificados = so o que voce checou** rodando um comando ou lendo um arquivo. O que
  voce "acha" nao entra aqui.
- **Cuidados / ja-disparado** e a secao anti-retrabalho: liste toda acao com efeito externo
  (PR, push, deploy, email, comando destrutivo) pra a proxima sessao NAO refazer.
- **Nao invente.** Se uma secao nao tem substancia real, escreva menos — mas nunca deixe vazio
  quando houve trabalho de verdade.

## Passo 2.5 — Sele o bilhete (OBRIGATORIO, antes de gravar)

O "so marque `[x]` com prova" do Passo 2 e um pedido ao modelo — sozinho, **nada verifica**. Um bilhete
pode jurar `[x] feito: PR #42` ou `[x] pronto: soma.py` sem NENHUM commit/arquivo no disco, e a proxima
sessao (`norte-retomar`) le como verdade. Esse e o furo do **relato fabricado**. Feche-o **antes de gravar**:

Depois de rascunhar o bilhete e **ANTES** de escrever o `.md`, rode o **selo do bilhete** no rascunho e
grave a **versao conferida** (nunca o rascunho cru):

```bash
# rode do CWD do projeto (onde os arquivos/commits do bilhete moram)
# $NOVO foi definido no Passo 2 (caminho garantidamente unico — nunca sobrescreve outro bilhete)
printf '%s' "$RASCUNHO" | "${CLAUDE_PLUGIN_ROOT}/bin/nb-bilhete-selo" - > "$NOVO"
# (ou, se ja escreveu um rascunho em arquivo:)
#   "${CLAUDE_PLUGIN_ROOT}/bin/nb-bilhete-selo" rascunho.md > "$NOVO"
```

O que o selo faz, linha a linha, na secao **`## Onde estamos`** (so ali):
- **`[x]` que cita arquivo/commit que EXISTE** -> mantem `[x]` + `✓ conferido: existe`.
- **`[x]` que cita arquivo/commit que NAO existe** -> **REBAIXA** pra `[ ] ⚠ nao achei no disco: <ref>`
  (a mentira obvia morre aqui — nao grave um "feito" que o disco desmente).
- **`[x]` que cita `PR #N`** ou coisa que nao da pra checar local -> `🟡 nao-verificavel` (nao rebaixa,
  mas tambem nao abencoa).
- **`[x]` sem artefato conferivel** (vago) -> mantem `[x]` + `(sem prova no disco pra conferir)`.

**Moldura honesta (nao mais que isso):** o selo so atesta que **o arquivo/commit citado existe e o bilhete
o cita** — NAO que o trabalho foi feito **certo** (um arquivo real, mas vazio/errado, passa). E LOCAL, nao
usa rede. Se o selo nao estiver instalado ou quebrar, ele **devolve o rascunho como esta** (fail-open) —
nunca trava o `/continuar`. Kill-switch: `NORTE_BILHETE=0` grava o rascunho intacto, como antes.

> **O carimbo de validade passa intacto pelo selo.** O selo do bilhete so mexe nas linhas `- [x] ...` da
> secao `## Onde estamos` — o CABECALHO (incluindo `selado-em` e `selado-em-commit` do Passo 1) atravessa
> sem ser tocado. Sao **duas pecas somadas, nao concorrentes**: o selo confere o que o bilhete jura ter
> feito; o carimbo permite, na retomada, avisar se o bilhete envelheceu. Nao remova nem duplique o carimbo.

## Passo 3 — Atualize o ponteiro `ULTIMO.md`

Aponte `./norte-out/handoffs/ULTIMO.md` pro handoff recem-criado (e o que `norte-retomar` le
primeiro). Symlink de preferencia, com fallback pra copia (nem todo filesystem faz symlink):

```bash
mkdir -p "$DIR/handoffs"
# $NOVO ja foi definido no Passo 2 (caminho garantidamente unico) — NAO remonte o nome aqui
ln -sf "$(basename "$NOVO")" "$DIR/handoffs/ULTIMO.md" 2>/dev/null \
  || cp "$NOVO" "$DIR/handoffs/ULTIMO.md"
```

> **Nota (2 sessoes na mesma pasta):** o `ULTIMO.md` e um ponteiro unico — se outra sessao salvar depois,
> ele passa a apontar pro bilhete DELA. Nenhum arquivo se perde (cada bilhete tem nome unico, Passo 2),
> mas por isso a `norte-retomar` NAO confia cega no `ULTIMO.md`: ela usa o `nb-retomar-alvo`, que
> desambigua quando ha 2+ assuntos recentes na mesma pasta.

## Passo 4 — Confirme

Reporte ao usuario, nesta ordem:
1. **Handoff salvo:** o path do `.md` + o objetivo em 1 frase.
2. **Ponteiro:** `ULTIMO.md` -> aponta pro novo.
3. **Primeiro passo pra proxima sessao:** o "Proximo passo" que voce gravou.
4. **Como retomar:** "na proxima sessao, rode `/norte:retomar` — ele le este handoff,
   confere o mundo e diz onde continuar."

## Degradacao (nunca trava o trabalho)

- **`./norte-out/` nao e gravavel** (permissao, disco cheio): avise em 1 linha e imprima o
  handoff completo **no chat** pra o usuario copiar. Nunca trave por isso.
- **Sem git** (nao e repo): pule o Passo 1 de git; o projeto ainda e o `basename` do cwd e o
  handoff ainda vale (so sem a lista de commits).
- **Erro em qualquer comando** -> siga com o que der; o handoff no chat sempre e possivel.

## Prova (teste real)

Num repo-brinquedo, rodar a skill cria `./norte-out/handoffs/<slug>-*.md` com as 6 secoes
preenchidas + `ULTIMO.md` apontando pra ele. Verificavel por `ls ./norte-out/handoffs/` e
abrindo o `.md`.
