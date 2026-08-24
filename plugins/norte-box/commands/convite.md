---
description: "Norte-box — valida o código de convite contra o servidor e guarda a sua identidade (invite_id)"
---

Você é o `/norte-box:convite`. Papel: pegar o **código de convite** que a pessoa recebeu,
**validar contra o servidor da Norte** e, se válido, guardar a **identidade** local
(`invite_id`) — que é o que marca cada evento de telemetria como sendo dela.

NUNCA escreva fora de `$HOME/.norte-box`. NUNCA imprima o código depois de validar.

## 1. Pré-checagem — o endereço do coletor precisa estar no `.env`

O cliente precisa saber o endereço do servidor. Ele vem de `$HOME/.norte-box/.env`, que leva
**só a URL** (`NORTE_BOX_TELEMETRY_URL`) — o `.env` do convidado **NÃO carrega token de dono**
(seu token nasce quando você valida o convite aqui).

**Esta cópia pública do plugin NÃO embute o endereço do coletor** (de propósito — pra não
publicar infra da Norte no GitHub). Então o `nb-convite.sh` **não cria o `.env` sozinho**: se a
linha `NORTE_BOX_TELEMETRY_URL` não existir, o convite para com
`CONVITE_ERRO: falta o endereco do coletor`. O endereço **NÃO é segredo** (o que autentica é o
token do convite, que nasce agora) — ele só não vive dentro do código público.

**Antes de rodar o `/norte-box:convite`, garanta a linha do coletor:** peça a URL a quem te
convidou e adicione-a ao `.env` (troque `<url-do-coletor>` pelo que te passaram):

```bash
mkdir -p "$HOME/.norte-box"
printf 'NORTE_BOX_TELEMETRY_URL=%s\n' 'https://<url-do-coletor>/ingest' >> "$HOME/.norte-box/.env"
chmod 600 "$HOME/.norte-box/.env"
```

Se o `.env` já tiver a linha, pode ir direto ao passo 2.

## 2. Peça o código

Pergunte em 1 linha: **"Cole o código de convite (começa com `nb-`):"**.

## 3. Valide contra o servidor e grave a identidade (só se válido)

Rode UM comando (o script valida contra o servidor e grava `identity.json`). O `.env` com a URL
do coletor precisa já existir — ver passo 1. Substitua `<CODIGO>` pelo que a pessoa colou:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/bin/nb-convite.sh" "<CODIGO>"
```

> **Por que um script e não bash inline aqui:** o bloco inline antigo tinha aspas aninhadas
> quebradas na leitura do `.env` e dava `syntax error near unexpected token 'fi'` — o convite
> MORRIA na 1ª tentativa (NRT-_1770, visto ao vivo). O `nb-convite.sh` é testável (`bash -n`),
> resolve a raiz do plugin sozinho (mesmo sem `CLAUDE_PLUGIN_ROOT`), e imprime **uma** linha:
> `CONVITE_OK invite_id=<id>` ou `CONVITE_INVALIDO: <reason>` ou `CONVITE_ERRO: <motivo>`.

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
- `CONVITE_ERRO: falta o endereco do coletor ...`: "Falta o endereço do coletor. Peça a URL a
  quem te convidou e adicione a linha `NORTE_BOX_TELEMETRY_URL=https://<url>/ingest` no arquivo
  `~/.norte-box/.env` (ver passo 1), depois rode o convite de novo."
- `CONVITE_ERRO: node ausente` / `jq ausente`: "Falta uma ferramenta local (`node` ou `jq`).
  Instale-a e rode o convite de novo (ou peça ajuda a quem te convidou)."

> A identidade fica em `$HOME/.norte-box/identity.json` (só o `invite_id`, nunca o código).
> O convite é **de uso único** (1 máquina) e tem **validade**. Reinstalar na **mesma máquina**
> dentro da validade funciona (re-bind). Quem convidou pode **revogar** a qualquer momento, e
> **re-emitir** (`reissue`) um código novo se precisar.
