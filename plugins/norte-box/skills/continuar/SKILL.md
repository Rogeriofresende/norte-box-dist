---
name: continuar
description: "Salva um handoff por-projeto quando o contexto esta enchendo ou uma etapa terminou, para que a proxima sessao continue exatamente de onde parou. Acionada por /norte:continuar, ou frases como 'salva o estado', 'cria handoff', 'preciso pausar', 'o contexto esta enchendo', 'guarda a memoria'. Escreve ./norte-out/handoffs/<slug>-<AAAAMMDD-HHMM>.md + atualiza ULTIMO.md. Quando roda no assento local da Norte, tambem TROCA a conversa no mesmo lugar (fora do assento, so salva o bilhete). Irma de norte-retomar (que LE o handoff de volta)."
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
- Em repo git, `$DIR` e a pasta **PRINCIPAL** do projeto (nunca a copia temporaria/worktree da conversa) —
  assim a proxima conversa acha o bilhete (0.3.41).

**UM BILHETE SO (0.3.41 — rode ISTO logo depois do `DIR`):** cada `/continuar` grava **um** bilhete. Qual:

```bash
if [ "${NORTE_BILHETE_UNICO:-1}" != "0" ] && [ -f "${NORTE_HANDOFF_SKILL:-$HOME/.claude/skills/session-handoff/SKILL.md}" ]; then echo "BILHETE-RICO"; else echo "BILHETE-SIMPLES"; fi
```

- **BILHETE-RICO** (maquina que tem a skill de handoff completo — ex.: a do dono da Norte): o bilhete UNICO e
  o completo. **Pule os Passos 2, 2.5 e 3** (NAO escreva o bilhete de 6 secoes) e faca so isto, no lugar deles:
  1. Invoque a skill **`session-handoff`** (ferramenta Skill) pra criar o handoff COMPLETO desta conversa.
     Avise a ela: **pule os Steps 4.6 e 4.7** (quem cuida da troca e o `/continuar`, no Passo 5) e **inclua a
     secao "Pedidos do CEO nesta conversa" cobrindo a conversa INTEIRA**.
  2. Guarde-o na pasta certa do projeto (move o arquivo de verdade pro `$DIR/handoffs/`, deixa um atalho no
     lugar antigo e atualiza o `ULTIMO.md`):
     ```bash
     SID="${CLAUDE_CODE_SESSION_ID:-nosid}"; H="$(cat "$HOME/.claude/handoffs/.last-handoff-$SID" 2>/dev/null)"
     [ -e "$H" ] && NOVO="$(bash "${CLAUDE_PLUGIN_ROOT}/bin/nb-bilhete-unificar" "$H" "$DIR")" && echo "BILHETE: $NOVO" || echo "SEM BILHETE"
     ```
     `SEM BILHETE` = a skill de handoff nao deixou o ponteiro desta conversa → **PARE** e diga *"nao consegui
     salvar o bilhete desta conversa — nao vou trocar pra nao continuar o assunto errado. Tento de novo?"*.
     NUNCA pegue "o bilhete mais recente da pasta" no lugar: pode ser de OUTRA janela.
  3. Siga pro **Passo 4** (confirme) → 4.5 → 5.
- **BILHETE-SIMPLES** (quem recebe a caixa): siga os Passos 1 a 5 normalmente (bilhete de 6 secoes).

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
`./norte-out/handoffs/<slug>-<AAAAMMDD-HHMM>.md`). Use exatamente estas secoes:

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

## Pedidos do usuario nesta conversa (todos, com status)
- [feito|pendente|descartado] "<palavras dele, curtas>" — <prova ou o que falta>

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
- **Pedidos do usuario:** releia a conversa INTEIRA (nao so o fim) e liste CADA pedido, na ordem, com status.
  Pedido feito horas antes conta igual ao ultimo — esquecer um pedido e o furo que mais faz a proxima
  conversa "nascer perdida".
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

**Antes, garanta o objetivo no bilhete (0.3.42 — vale pros dois tipos de bilhete):** a conversa nova le a
linha `objetivo:` pra saber o PORQUE do assunto. Em 30/09 4 de 5 bilhetes sairam sem ela. Rode:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/bin/nb-bilhete-objetivo" "$NOVO"
```

- `OBJETIVO: <frase>` → use essa frase no item 1 abaixo.
- `SEM OBJETIVO` → **nao invente**. Avise em 1 linha: *"⚠ Este assunto nao tem objetivo guardado — a
  proxima conversa vai te perguntar qual e."* e siga (nao trava a troca).

Reporte ao usuario, nesta ordem:
1. **Handoff salvo:** o path do `.md` + o objetivo em 1 frase.
2. **Ponteiro:** `ULTIMO.md` -> aponta pro novo.
3. **Primeiro passo pra proxima sessao:** o "Proximo passo" que voce gravou.
4. **Como retomar:** "na proxima sessao, rode `/norte:retomar` — ele le este handoff,
   confere o mundo e diz onde continuar."

## Passo 4.5 — Carimba QUAL conversa a retomar (aba de projeto) — fail-open

Marca no bilhete recem-salvo qual conversa a proxima sessao deve retomar (`fio` + `authored_by` +
`adota_conversa:true`), pra a `norte-retomar` SENTAR na mesma conversa em vez de nascer com numero novo.
SO carimba DENTRO da Norte (conversa resolvivel por session_id no registro); FORA da Norte NAO faz nada
(bilhete igual a hoje). Idempotente, nao-fatal — nunca trava o `/continuar`.

```bash
# $NOVO = o bilhete salvo no Passo 2. Kill-switch NORTE_HANDON_ADOTA_CONVERSA=0 pula (a norte-retomar respeita igual).
[ "${NORTE_HANDON_ADOTA_CONVERSA:-1}" != "0" ] && [ -x "${CLAUDE_PLUGIN_ROOT}/bin/nb-mark-adota" ] \
  && bash "${CLAUDE_PLUGIN_ROOT}/bin/nb-mark-adota" "$NOVO" || true
```

## Passo 5 — Trocar a conversa no lugar (o "assento") — SO quando local

> **Auto-detecta o ambiente.** Este passo SO roda quando a sessao esta no "assento" da Norte
> (a tela que troca a conversa no mesmo lugar) E as pecas locais da troca existem. Fora disso
> (quem recebe a caixa, outra maquina, terminal comum) ele e PULADO — o bilhete dos Passos 1-4
> ja e a entrega completa. Nunca trava, nunca abre janela pra quem nao tem o assento.

> **REGRA UNICA DO /continuar (0.3.44 · conselho autouso01, GO do dono):** **no assento** troca na 1a
> vez; **fora do assento** salva o bilhete e AVISA na tela que nao trocou e como continuar. Nunca abre
> aba/janela por conta propria, nunca termina calado. `/continuar`, `/▲-continuar` e `/norte:continuar`
> sao o MESMO fluxo (este arquivo e a fonte unica).

**Passo 5.1 — so siga se (a) o Passo 4 confirmou o bilhete salvo E (b) ISTO imprimir `PODE-TROCAR`.
Senao PARE: o `/continuar` termina aqui (o bilhete ja esta salvo).**

```bash
# kill-switch desliga a troca  E  esta no assento  E  as pecas locais da troca existem?
if [ "${NORTE_CONTINUAR_TROCA:-1}" != "0" ] \
   && { [ -n "${NORTE_SEAT_AUTO:-}" ] || [ -n "${NORTE_SEAT:-}" ]; } \
   && [ -x "${NORTE_SEAT_SCRIPTS:-$HOME/.claude/scripts}/norte-mark-relay.sh" ]; then echo "PODE-TROCAR"; else echo "SO-BILHETE"; fi
```

- **SO-BILHETE** → a troca NAO vai acontecer nesta maquina. **Nunca termine calado:** encerre o
  `/continuar` dizendo ao usuario, com estas palavras (pode ajustar o assunto, nunca o sentido):
  *"✅ Bilhete salvo. Aqui a conversa **nao troca sozinha** — abra uma conversa nova (ou digite
  `/clear`) e rode `/norte:retomar`: ela le este bilhete e continua de onde paramos."*
  NUNCA diga "troquei", "a nova nasce sozinha" ou "fechando" neste ramo (e o caso de quem recebe a caixa).
- **PODE-TROCAR** → siga 5.2 a 5.4 (a troca no assento).

**Passo 5.2 — marque o bilhete como "pronto pra troca"** (a troca so acontece com o bilhete marcado):

- **BILHETE-RICO:** o bilhete UNICO ja existe (feito no inicio) — NAO crie outro.
- **BILHETE-SIMPLES** (so se alguem desligou o bilhete unico com `NORTE_BILHETE_UNICO=0` dentro do assento):
  invoque a skill **`session-handoff`** agora (pulando os Steps 4.6 e 4.7), como era antes.

Depois marque — SO o bilhete DESTA conversa (sem "plano B": o antigo "pega o mais recente da pasta"
chegou a armar o bilhete de OUTRA janela):

```bash
SID="${CLAUDE_CODE_SESSION_ID:-nosid}"; H="$(cat "$HOME/.claude/handoffs/.last-handoff-$SID" 2>/dev/null)"; test -e "$H" && "${NORTE_SEAT_SCRIPTS:-$HOME/.claude/scripts}/norte-mark-relay.sh" "$H" && echo "OK: $H" || echo "SEM BILHETE"
```

Confira: imprimiu `OK: ...` E o nome bate com ESTE assunto. Se nao, **PARE** e diga:
*"nao consegui salvar o bilhete da troca; nao vou trocar pra nao continuar o assunto errado — tento de novo?"*.

**Passo 5.3 — modo do assento + a troca no lugar:**

```bash
if [ -n "${NORTE_SEAT_INTERACTIVE:-}" ]; then echo "SEATED_INTERATIVO"; elif [ -n "${NORTE_SEAT_AUTO:-}" ]; then echo "SEATED_AUTO"; elif [ -n "${NORTE_SEAT:-}" ]; then echo "SEATED"; else echo "NAO-SEATED"; fi
```

- **SEATED_INTERATIVO** (o assento de uma pessoa, `--stay` — e o caso NORMAL de quem usa o assento)
  **ou SEATED:** a conversa **NAO se fecha sozinha** — quem fecha e voce, agora. Avise em 1 linha
  (*"Bilhete salvo — troco a conversa aqui mesmo agora, a nova entra no lugar em ~20s"*) e rode, nesta
  ordem, SO DEPOIS do 5.2 dar `OK:` (sem isto a troca NUNCA acontece — regressao da 0.3.37, consertada na 0.3.41):
  ```bash
  [ -x "${NORTE_SEAT_SCRIPTS:-$HOME/.claude/scripts}/norte-troca-log.sh" ] && zsh "${NORTE_SEAT_SCRIPTS:-$HOME/.claude/scripts}/norte-troca-log.sh" --evento pediu --sid "${CLAUDE_CODE_SESSION_ID:-}" --handoff "$H" 2>/dev/null || true
  "${NORTE_SEAT_SCRIPTS:-$HOME/.claude/scripts}/norte-seat-exit.sh"
  ```
- **SEATED_AUTO** (robo autonomo sem pessoa, `--allow-handon`): nao faca nada — a sessao sem pessoa
  termina sozinha ao fim da resposta e a nova nasce no lugar com `/handon`.
- **NAO-SEATED:** nao acontece aqui (o 5.1 so deixa chegar quem esta no assento). Se cair aqui por engano, NAO abra aba nem janela: diga *"✅ Bilhete salvo. Aqui a conversa nao troca sozinha — abra uma conversa nova e rode `/norte:retomar`."* e pare (regra unica do /continuar, 0.3.44).

**Passo 5.4 — cartao de chegada:** quando a nova nascer (via `/handon`), a PRIMEIRA coisa dela e entregar
na Vitrine um cartao de chegada curto ("De onde viemos" + pontos-chave). O chat recebe so o ponteiro.

> **ORDEM E SEGURANCA:** o Passo 5 (troca) so comeca DEPOIS do bilhete confirmado (Passos 1-4). Se o
> bilhete nao salvou, NAO troque — o bilhete que viaja e a rede de seguranca da troca. Kill: `NORTE_CONTINUAR_TROCA=0`
> forca `SO-BILHETE` (nunca troca), util pra quem quer so o handoff mesmo no assento.

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
