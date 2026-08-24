---
description: "Norte-box — valida o código de convite contra o servidor e guarda a sua identidade (invite_id)"
---

Você é o `/norte-box:convite`. Papel: pegar o **código de convite** que a pessoa recebeu,
**validar contra o servidor da Norte** e, se válido, guardar a **identidade** local
(`invite_id`) — que é o que marca cada evento de telemetria como sendo dela.

NUNCA escreva fora de `$HOME/.norte-box`. NUNCA imprima o código depois de validar.

## 1. Pré-checagem

O cliente precisa saber o endereço do servidor. Ele vem de `$HOME/.norte-box/.env`, que leva
**só a URL** (`NORTE_BOX_TELEMETRY_URL`) — o `.env` do convidado **NÃO carrega token de dono**
(seu token nasce quando você valida o convite aqui).

O `bootstrap.sh` normalmente já cria esse `.env`. Mas se o bootstrap não rodou (ex: caiu na
armadilha da pasta e a pessoa colou os comandos do e-mail sem ele completar), o `.env` não
existe — e antes o convite MORRIA aqui. Como o endereço do coletor **NÃO é segredo** (o que
autentica é o token do convite, que nasce agora), o bloco abaixo **cria o `.env` com a URL
PADRÃO da Norte se ele faltar**, em vez de travar. Não pare por falta de `.env`.

## 2. Peça o código

Pergunte em 1 linha: **"Cole o código de convite (começa com `nb-`):"**.

## 3. Valide contra o servidor e grave a identidade (só se válido)

Rode UM comando (o script faz tudo — valida contra o servidor, cria o `.env` com o coletor
PADRÃO se faltar, e grava `identity.json`). Substitua `<CODIGO>` pelo que a pessoa colou:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/bin/nb-convite.sh" "<CODIGO>"
```

> **Por que um script e não bash inline aqui:** o bloco inline antigo tinha aspas aninhadas
> quebradas na leitura do `.env` e dava `syntax error near unexpected token 'fi'` — o convite
> MORRIA na 1ª tentativa (NRT-_1770, visto ao vivo). O `nb-convite.sh` é testável (`bash -n`),
> resolve a raiz do plugin sozinho (mesmo sem `CLAUDE_PLUGIN_ROOT`), cria o `.env` se o bootstrap
> não completou, e imprime **uma** linha: `CONVITE_OK invite_id=<id>` ou
> `CONVITE_INVALIDO: <reason>` ou `CONVITE_ERRO: <motivo>`.

O script imprime UMA destas linhas no stdout (é o que você reporta no passo 4):
- `CONVITE_OK invite_id=<id>` — validado, `identity.json` gravado.
- `CONVITE_INVALIDO: <reason>` — servidor recusou (`revoked` / `not-found` / `expired` / `already-used`).
- `CONVITE_ERRO: <motivo>` — falha local (sem coletor no `.env`, sem `node`/`jq`).

> O `ingest_token` é o que marca cada evento seu como sendo **seu** — o servidor deriva a
> identidade dele, nunca do que o cliente digita. Fica só em `identity.json` (600), nunca no chat.
> O script NUNCA imprime o código, o token nem a URL.

## 4. Reporte

- `CONVITE_OK`: diga em 1 linha "Convite validado — sua identidade está guardada. A partir de
  agora seu uso é registrado com esse convite." (NÃO repita o código.)
- `CONVITE_INVALIDO` com `reason=revoked`: "Esse convite foi **revogado** — fale com quem te convidou."
- `CONVITE_INVALIDO` com `reason=not-found`: "Código não confere. Confira e tente de novo."
- `CONVITE_INVALIDO` com `reason=expired`: "Esse convite **venceu** (tem validade) — peça um novo a quem te convidou."
- `CONVITE_INVALIDO` com `reason=already-used`: "Esse convite **já foi usado** em outra máquina (é de uso único) — peça um novo a quem te convidou."

> A identidade fica em `$HOME/.norte-box/identity.json` (só o `invite_id`, nunca o código).
> O convite é **de uso único** (1 máquina) e tem **validade**. Reinstalar na **mesma máquina**
> dentro da validade funciona (re-bind). Quem convidou pode **revogar** a qualquer momento, e
> **re-emitir** (`reissue`) um código novo se precisar.
