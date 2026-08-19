---
description: "Norte-box - ver e trocar o MODO (privado | compartilhavel). Default privado; ->compartilhavel exige o aceite."
---

Voce e o `/norte-box:modo`. O Norte-box e UM produto com um INTERRUPTOR entre dois modos:

- **privado** (default) — a Norte **NAO ve** este trabalho. Nada e enviado (nem os numeros): no
  privado o box e ESTRUTURALMENTE incapaz de mandar telemetria (nao tem endereco nem token
  gravados, e um gate de modo fail-closed recusa mesmo que algo escape).
- **compartilhavel** — liga o **MEDIDOR**: SO os NUMEROS de uso sobem (pedidos, tempo, tamanho),
  pra cobrar justo. **Modelo A: a Norte continua NAO vendo o seu trabalho** — o conteudo so sai
  quando VOCE compartilha uma sessao (`/norte-box:compartilhar`, com previa). Exige aceite; ver
  `docs/TELEMETRIA.md`.

**Reversibilidade assimetrica (regra dura):** trocar PARA **privado** e IMEDIATO (so apaga o
endereco/token e grava o modo). Trocar PARA **compartilhavel** EXIGE o aceite do termo
(`/norte-box:consent`) e um convite validado — sem isso, NAO vira compartilhavel.

Argumento em `$ARGUMENTS` (vazio = so mostrar; `privado` ou `compartilhavel` = trocar).
NUNCA escreva fora de `$HOME/.norte-box`. NUNCA imprima token/segredo.

## Caso 1 — sem argumento: MOSTRAR o modo atual

Rode:

```bash
STATE="$HOME/.norte-box"; mkdir -p "$STATE"
# FONTE UNICA: reusa _norte_modo do _modo.sh (mesma leitura que o GATE usa) pra o DISPLAY
# nunca divergir do gate. Se der pra sourcear, usa a funcao; senao, o MESMO trim de pontas.
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/hooks/_modo.sh" ]; then
  . "${CLAUDE_PLUGIN_ROOT}/hooks/_modo.sh"
fi
if command -v _norte_modo >/dev/null 2>&1; then
  M="$(_norte_modo)"
else
  # Fallback (sem o _modo.sh a mao): MESMO trim de PONTAS do _modo.sh — NUNCA `tr -d` global.
  # `tr -d ' \t\r\n'` (global) colapsava "compart ilhavel" (espaco interno) em "compartilhavel"
  # e o DISPLAY mentiria "compartilhavel" enquanto o GATE (trim de pontas) trata como privado.
  M="privado"
  if [ -r "$STATE/modo" ]; then
    V="$(head -n1 "$STATE/modo" 2>/dev/null | tr -d '\r\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    [ "$V" = "compartilhavel" ] && M="compartilhavel"   # fail-closed: so o valor exato abre
  fi
fi
if [ "$M" = "compartilhavel" ]; then
  echo "MODO ATUAL: compartilhavel — o MEDIDOR (SO numeros de uso) esta ligado. A Norte NAO ve o seu trabalho; pra mostrar uma sessao use /norte-box:compartilhar."
  echo "Trocar pra privado (imediato): /norte-box:modo privado"
else
  echo "MODO ATUAL: privado — a Norte NAO ve este trabalho (nada e enviado)."
  echo "Trocar pra compartilhavel (exige aceite): /norte-box:modo compartilhavel"
fi
```

## Caso 2 — `$ARGUMENTS` = `privado`: TROCAR pra privado (imediato)

Trocar pra privado e SEMPRE permitido e IMEDIATO. Alem de gravar `modo=privado`, a gente
**apaga o endereco e o token do disco** — pra o box ficar sem "pra onde mandar" (nao basta
declarar privado; a gente remove a capacidade). Rode:

```bash
STATE="$HOME/.norte-box"; mkdir -p "$STATE"
# 1. grava o modo
printf 'privado\n' > "$STATE/modo"; chmod 600 "$STATE/modo" 2>/dev/null || true
# 2. desliga a coleta (remove a flag)
rm -f "$STATE/telemetry.enabled"
# 3. remove o ENDERECO do coletor do .env (sem sed -i; portavel macOS).
#    ATENCAO: `grep -v` sai com codigo 1 quando NAO sobra nenhuma linha (ex: o .env so tinha a
#    URL). Isso NAO e erro — o .env.tmp foi criado (vazio) corretamente. Por isso NAO amarramos
#    o mv ao exit do grep (um `&&` faria a purga FALHAR silenciosa nesse caso — furo real do teste).
if [ -f "$STATE/.env" ]; then
  grep -v '^NORTE_BOX_TELEMETRY_URL=' "$STATE/.env" > "$STATE/.env.tmp" 2>/dev/null
  if [ -f "$STATE/.env.tmp" ]; then mv "$STATE/.env.tmp" "$STATE/.env" 2>/dev/null || rm -f "$STATE/.env.tmp"; fi
fi
# 4. remove o TOKEN de ingestao do identity.json (mantem invite_id/label; so tira o token).
if [ -f "$STATE/identity.json" ] && command -v jq >/dev/null 2>&1; then
  jq 'del(.ingest_token)' "$STATE/identity.json" > "$STATE/identity.json.tmp" 2>/dev/null && mv "$STATE/identity.json.tmp" "$STATE/identity.json" 2>/dev/null || rm -f "$STATE/identity.json.tmp"
fi
# 5. PURGA a fila local e o cursor do dreno (residuo do periodo compartilhavel). Sem isto, a fila
#    ficava no disco so bloqueada pelo gate — se reabrisse compartilhavel, subiria evento antigo.
#    "Reverti pra privado" tem que significar "a Norte nao ve mais NADA", inclusive o que ja estava
#    na fila. (Nao ha vazamento de trabalho PRIVADO aqui — trabalho privado nunca entra na fila —
#    e sim limpeza do residuo compartilhavel.)
rm -f "$STATE/telemetry-queue.jsonl" "$STATE/telemetry-queue.cursor"
echo "MODO: privado. Coleta DESLIGADA, endereco/token APAGADOS do disco e a fila local PURGADA."
echo "A partir de agora a Norte nao ve este trabalho — o box nem tem pra onde mandar."
```

Confirme em 1 linha: "Pronto — modo privado. A Norte nao ve mais este trabalho."

> A fila local `telemetry-queue.jsonl` foi APAGADA na reversao (junto com endereco/token/flag).
> Nao sobra residuo pra subir se voce reabrir compartilhavel depois. Pra ver/limpar a fila a
> qualquer momento use `/norte-box:telemetry show`.

## Caso 3 — `$ARGUMENTS` = `compartilhavel`: TROCAR pra compartilhavel (exige aceite)

So vira compartilhavel quem **ja aceitou o termo** (`consent.json` na versao vigente) **e tem um
convite validado** (`identity.json` com `ingest_token`). Sem isso, NAO troca — manda a pessoa
fazer o onboarding primeiro. Rode:

```bash
STATE="$HOME/.norte-box"; mkdir -p "$STATE"
HAS_CONSENT=0
if [ -f "$STATE/consent.json" ] && command -v jq >/dev/null 2>&1; then
  V="$(jq -r '.versao // empty' "$STATE/consent.json" 2>/dev/null)"
  [ "$V" = "5" ] && HAS_CONSENT=1
fi
HAS_TOKEN=0
if [ -f "$STATE/identity.json" ] && command -v jq >/dev/null 2>&1; then
  T="$(jq -r 'if (.ingest_token // "") != "" then "1" else "0" end' "$STATE/identity.json" 2>/dev/null)"
  [ "$T" = "1" ] && HAS_TOKEN=1
fi
if [ "$HAS_CONSENT" = 1 ] && [ "$HAS_TOKEN" = 1 ]; then
  printf 'compartilhavel\n' > "$STATE/modo"; chmod 600 "$STATE/modo" 2>/dev/null || true
  echo "MODO: compartilhavel. O MEDIDOR (SO numeros de uso) esta ligado — a Norte NAO ve o seu trabalho. Pra mostrar uma sessao, use /norte-box:compartilhar."
elif [ "$HAS_TOKEN" != 1 ]; then
  echo "NAO troquei: falta um convite validado. Rode /norte-box:convite (e depois /norte-box:consent)."
else
  echo "NAO troquei: falta aceitar o termo. Rode /norte-box:consent — dai eu troco pra compartilhavel."
fi
```

- Se saiu `MODO: compartilhavel` — confirme em 1 linha e lembre que dá pra voltar pra privado a
  qualquer momento com `/norte-box:modo privado`.
- Se saiu `NAO troquei:` — repita a instrucao ao usuario (rodar convite/consent) e pare.

## Caso 4 — `$ARGUMENTS` e qualquer outra coisa

Diga: **"Modo invalido. Use `/norte-box:modo` (ver), `/norte-box:modo privado` ou `/norte-box:modo compartilhavel`."**
