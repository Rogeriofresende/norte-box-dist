# Termo de Privacidade e Uso de Dados — MEDIDOR de uso + compartilhar sessao (Modelo A — texto honesto)

Este documento e o detalhamento completo do **Termo de Privacidade e Uso de Dados** do Norte-box
(o mesmo que voce aceita em `/norte-box:consent`, versao 5, Modelo A).

O Norte-box e um pacote FECHADO por convite que usa o Claude da Norte. **Por padrao a Norte NAO
ve o seu trabalho** — so recebe um MEDIDOR de uso (numeros), pra cobrar de forma justa. O
conteudo (o que voce digita, a resposta da IA, seus arquivos) so sai quando **VOCE** compartilha
uma sessao, com previa antes de enviar. Este documento e a verdade sobre o que isso significa.

## DOIS MODOS (o interruptor) — e o que "privado" garante de verdade

O Norte-box tem UM produto com um **interruptor** entre dois modos, gravado em
`~/.norte-box/modo` (uma palavra: `privado` ou `compartilhavel`). Veja/troque com
`/norte-box:modo`. O **selo** no inicio de cada sessao mostra em qual modo voce esta.

- **privado (DEFAULT, fail-closed)** — a Norte **NAO ve** nada, nem os numeros. Nada e coletado,
  enfileirado ou enviado. Nao e "desliguei o envio": no privado o box e **estruturalmente
  incapaz de mandar** — o instalador nao grava endereco de coletor (`NORTE_BOX_TELEMETRY_URL`)
  nem token nem identidade, entao **nao ha pra onde mandar**; e, como 2a trava, um gate de modo
  fail-closed nos hooks recusa emitir mesmo que algum residuo escape pro disco. Se o arquivo
  `modo` some, fica ilegivel ou tem qualquer outro valor, o box trata como **privado** — so o
  valor EXATO `compartilhavel` liga o medidor.
- **compartilhavel** — liga o **MEDIDOR**: SO os NUMEROS de uso sobem automaticamente. **A Norte
  continua NAO vendo o seu trabalho.** So se entra aqui apos **aceitar o termo**
  (`/norte-box:consent`) com um **convite validado** (`/norte-box:convite`).

**Reversibilidade assimetrica:** voltar PARA privado e **imediato** (`/norte-box:modo privado`
apaga o endereco/token/flag do disco na hora); ir PARA compartilhavel **exige o aceite** — sem
consent + convite, o box NAO troca.

## O que o MEDIDOR envia (SO numeros — Modelo A)

No modo compartilhavel, cada acao vira 1 evento **so-numeros** (`kind:"medidor"`):

- `uso: { comandos, tokens, ms, bytes }` — quantos pedidos, tamanho aprox (~= caracteres/4),
  tempo e espaco;
- metadados nao-sensiveis: `event` (TIPO do hook, colapsado por allowlist: UserPromptSubmit /
  PostToolUse / SessionStart / ... — um valor fora da lista vira `outro`), `tool` (rotulo
  GENERICO do TIPO de acao — **nunca** o nome cru: uma ferramenta CORE conhecida passa como
  `Read`/`Edit`/`Bash`/...; **qualquer ferramenta MCP** (`mcp__servidor__funcao`, que poderia
  carregar o nome de um cliente, ex `mcp__clinica-dr-joao__buscar_prontuario`) colapsa pra `mcp`;
  e qualquer ferramenta desconhecida/custom vira `outro` — **nao** e o caminho, nem o conteudo,
  nem o nome do servidor MCP), `ts`, e um `invite_id` opaco (id da pessoa, **nunca** um token/chave).

**O que NUNCA vai no evento automatico:** o texto que voce digita, a resposta da IA, o
conteudo/diff dos arquivos, o **nome ou caminho** dos arquivos, e o **nome de um servidor/ferramenta
MCP** (que num tool nomeado por cliente carregaria o nome dele). Os hooks LEEM o conteudo so pra
**medir o tamanho** (contar bytes/tokens pro custo) e o descartam no mesmo passo, e colapsam o
nome da ferramenta num rotulo generico ANTES de montar o evento — o texto e o nome-por-cliente
nunca entram na linha da fila (`telemetry-queue.jsonl`) nem no POST. Confira por `head` na fila:
so aparece `uso`/`event`/`tool`/`ts`/`invite_id`, nenhum campo de conteudo e nenhum nome cru de MCP.

O `invite_id` e **derivado no servidor do token que autentica o envio** — nao do que o cliente
escreve no corpo — entao ninguem grava evento se passando por outra pessoa.

## Compartilhar UMA sessao (opt-in explicito, com previa)

Quando voce quiser mostrar o conteudo de uma sessao pra Norte (ex: pedir ajuda), rode
**`/norte-box:compartilhar`**. Ele:

1. Le a conversa da sessao atual e monta uma **PREVIA redigida** (o mesmo redator do secret-guard
   tira secret/CPF/CNPJ/nome-de-arquivo que reconhece — fail-closed);
2. **Mostra a previa EXATA** do que sairia + o tamanho, salva num arquivo local
   (`~/.norte-box/share-preview.json`) — sem tocar a rede;
3. So envia **apos o seu "sim"**, e envia exatamente o que voce viu, marcado
   `kind:"sessao-compartilhada"` (separado do medidor).

Nada e compartilhado sem esse ok, **sessao por sessao**. Se disser "nao", a previa fica so no seu
disco (apague com `rm` se quiser) e nada sobe. Isto **NAO** liga o medidor automatico nem muda o
padrao — o padrao continua sendo so os numeros.

## O que o REDATOR tira ANTES de compartilhar (secret + PII) — e o que NAO garante

Mesmo no compartilhar explicito, o conteudo passa por um **redator portatil** (**fonte unica** em
`hooks/_redact.sh`) que mascara os formatos que **reconhece**:

- **secrets/chaves**: OpenAI `sk-`/`sk-proj-`/`sk-ant-`, Google OAuth `ya29.`, GitHub `ghp_`/
  `gho_`/`github_pat_`, GitLab `glpat-`, HuggingFace `hf_`, AWS `AKIA`, Asaas `aact_`, Slack
  `xox`, Google API `AIza`, **JWT** (`eyJ.eyJ.sig`), **strings de conexao** com senha embutida
  (`postgres://user:senha@...`), chaves privadas PEM, e atribuicoes nomeadas
  (`...API_KEY = valor`, `...SECRET = valor`, `...TOKEN = valor`, `...PASSWORD = valor`);
- **cartao/app-password** (16 digitos, 4x4) e **PII**: CPF e CNPJ;
- **NOME/CAMINHO de arquivos** (unix `/laudos/paciente.pdf`, Windows `C:\...`, relativo `../`,
  `~/`, no meio da prosa, URL que termina em nome-de-arquivo) — vira `[arquivo:.ext]` (so a
  extensao) ou `[REDACTED-PATH]`.

O redator e **fail-closed**: se falhar num campo, o campo **nao vai** (preferimos perder o dado a
vazar). **MAS seja honesto: um redator baseado em LISTA de formatos SEMPRE pode deixar passar um
formato novo** — ele reduz o vazamento conhecido, **nao garante zero**. Como voce ve a previa
antes de enviar, a decisao final e sua: na duvida, nao compartilhe a sessao.

## Onde fica, acesso, retencao e cifra (o que VALE HOJE)

- **Escondido**: o coletor fica preso ao proprio servidor (bind loopback) e so e alcancavel
  pela rede privada da Norte (Tailscale), nao pela internet aberta.
- **Cifra SELADA (assimetrica)**: cada evento (numeros OU sessao compartilhada) e guardado com
  sealed-box (X25519 + AES-256-GCM). O coletor guarda **so a chave PUBLICA** -> so consegue
  CIFRAR, **nunca decifrar**. A chave PRIVADA mora **FORA do servidor** (na maquina do dono). Um
  root que invada o coletor le so ciphertext. Sem cifra configurada, o servidor **recusa** guardar
  (503 `encryption-required`) em vez de gravar em claro.
- **Retencao com apagamento automatico**: o servidor apaga sozinho os eventos mais velhos que a
  retencao (default **90 dias**). Voce pode pedir pra APAGAR o que ja foi guardado.
- **Aceite verificado NO SERVIDOR**: o `/ingest` do convidado so e aceito depois que o proprio
  servidor registrou o aceite (POST `/consent` com o token do convite). Um arquivo local de
  consent nao libera nada sozinho (furo #3).
- **Identidade pelo token**: cada convite tem um token proprio; o servidor deriva o `invite_id`
  dele, ignorando o que o corpo diz -> ninguem se passa por outro (furo #1). Revogar mata o token.
- **`.env` lido como DADO**: o cliente le `~/.norte-box/.env` sem `source`/eval — um `$(comando)`
  la dentro NUNCA executa (furo #2).
- **Offline corta em 7 dias**: o buffer local tem TTL - o que nao subiu em 7 dias e descartado.
- **NUNCA trava o seu trabalho** (fail-open): se a telemetria falhar, o Claude segue normal.
- Voce pode **ver a fila antes de enviar** (`/norte-box:telemetry show`) e **desligar o medidor**
  (`/norte-box:telemetry off`) — desligar funciona de verdade e nao afeta o secret-guard.

O painel/relatorio pro dono sai do `server/report.js`, que roda ONDE a chave privada mora (a
maquina do dono), NUNCA no coletor.

## O TRANSPORTE (honesto, a mostra)

O envio (medidor, aceite e compartilhar) usa `lib/nb-post.js` — um cliente HTTP comum do stdlib
do node, do tamanho de um exemplo de manual. **Se voce quiser ver EXATAMENTE o que ele manda**,
rode com `--show` (ou `NB_POST_SHOW=1`): ele imprime o metodo, a URL, os headers (token
mascarado) e o corpo ANTES de enviar; `--dry-run` mostra o mesmo e NAO envia. Nada e escondido —
um transporte honesto mostra o que faz quando perguntado.

## O MEDIDOR de custo (uso REAL, nao estimativa)

O Claude da Norte e assinatura fixa. O custo de cada pessoa = a **fatia do uso dela sobre o
total**: pedidos + tokens aprox + tempo + espaco, por `invite_id`. A 1a baseline e o uso do
proprio CEO (unico usuario hoje). Os campos vivem nos eventos so-numeros do buffer
(`telemetry-queue.jsonl`) — da pra conferir por `head` na fila.
