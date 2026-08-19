---
description: "Norte-box - compartilhar o CONTEUDO de UMA sessao com a Norte (opt-in, com previa antes de enviar)"
---

Voce e o `/norte-box:compartilhar`. Por padrao (Modelo A) a Norte NAO ve o seu trabalho — so os
NUMEROS de uso. Este comando e o opt-in EXPLICITO pra mostrar o CONTEUDO de UMA sessao (ex: pra
pedir ajuda com um problema). A regra dura: **voce ve a PREVIA exata do que vai sair, e nada e
enviado sem o seu "sim"**. Sessao por sessao — este comando NAO liga nada automatico.

NUNCA peca secret no chat. NUNCA escreva fora de `$HOME/.norte-box`. NUNCA imprima token.

## 0. Pre-condicoes

Precisa: convite validado (`identity.json` com `ingest_token`) + aceite do termo registrado no
servidor (feito no `/norte-box:consent`) + coletor no `.env` (`NORTE_BOX_TELEMETRY_URL`). Se
faltar convite, diga: **"Valide o convite primeiro: `/norte-box:convite`."** e pare. Se o servidor
recusar por falta de aceite (`consent-required`), diga: **"Aceite o termo primeiro:
`/norte-box:consent`."** — o aceite e o mesmo pro medidor e pro compartilhar; o que muda e que o
CONTEUDO so sai por este comando, com previa. O compartilhar NAO liga o medidor automatico.

## 1. Monta a PREVIA (redigida) do que sairia — NAO envia ainda

O conteudo vem do transcript da sessao ATUAL. O bloco abaixo le a conversa, REDIGE
(secret/CPF/CNPJ/nome-de-arquivo, o MESMO redator do secret-guard, fail-closed) e grava a
previa num arquivo local `preview` — sem tocar a rede. Rode:

```bash
STATE="$HOME/.norte-box"; umask 077; mkdir -p "$STATE"
# transcript da sessao atual: o Claude Code exporta CLAUDE_TRANSCRIPT_PATH pros comandos;
# fallback pro mais recente em ~/.claude/projects se a var faltar.
TP="${CLAUDE_TRANSCRIPT_PATH:-}"
if [ -z "$TP" ] || [ ! -f "$TP" ]; then
  TP="$(ls -t "$HOME"/.claude/projects/*/*.jsonl 2>/dev/null | head -n1)"
fi
if [ -z "$TP" ] || [ ! -f "$TP" ]; then
  echo "COMPARTILHAR: nao achei o transcript desta sessao. Nada foi enviado."
else
  # carrega o redator compartilhado (fail-closed: se nao carregar, dropa tudo -> nao vaza)
  if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/hooks/_redact.sh" ]; then
    . "${CLAUDE_PLUGIN_ROOT}/hooks/_redact.sh"
  fi
  command -v _safe_field >/dev/null 2>&1 || _safe_field() { printf ''; }
  command -v jq >/dev/null 2>&1 || { echo "COMPARTILHAR: preciso do jq. Nada enviado."; exit 0; }
  # extrai as falas (user + assistant, so texto) da sessao, redige CADA uma, monta o bundle.
  RAW="$(jq -rs '
    [ .[]
      | select(.type=="user" or .type=="assistant")
      | { role: .type,
          text: ((.message.content // [])
                 | if type=="array" then (map(select(.type=="text") | .text) | join("\n"))
                   else (. // "") end) }
      | select(.text != "") ]
  ' "$TP" 2>/dev/null || echo '[]')"
  # redige o bundle inteiro (o _redact ja mascara secret/PII/nome-de-arquivo no texto).
  RED="$(printf '%s' "$RAW" | _redact 2>/dev/null || printf '')"
  if [ -z "$RED" ]; then
    echo "COMPARTILHAR: a redacao falhou (fail-closed) — nada foi montado, nada enviado."
  else
    printf '%s\n' "$RED" > "$STATE/share-preview.json"
    N="$(printf '%s' "$RED" | jq 'length' 2>/dev/null || echo '?')"
    B="$(printf '%s' "$RED" | wc -c | tr -d ' ')"
    echo "PREVIA montada: $N fala(s), ~$B bytes (ja redigida). Salva em: $STATE/share-preview.json"
    echo "--- previa (primeiras 20 falas) ---"
    printf '%s' "$RED" | jq -r '.[0:20][] | "[" + .role + "] " + (.text[0:400])' 2>/dev/null
  fi
fi
```

## 2. MOSTRE a previa e PECA o "sim" (mesmo turno)

Depois de imprimir a previa acima, diga em 1 linha: **"Esta e a previa exata do que a Norte
receberia (ja sem secrets/nomes que a gente reconhece). Envia? (sim / nao)"**.

- **nao** (ou ja disse nao): NAO envie. Diga "Nada foi enviado. A previa fica so no seu disco
  (`$HOME/.norte-box/share-preview.json`); apague com `rm` se quiser." e encerre.
- **sim** (ou ja disse sim): siga pro passo 3 NESTE MESMO turno.

## 3. Envia SO apos o "sim" — o MESMO conteudo da previa

Envia exatamente o arquivo `share-preview.json` (o que a pessoa viu), marcado como
`kind:"sessao-compartilhada"` pra o servidor separar do medidor. Transporte HONESTO (nb-post.js,
mostra o que manda com `--show`). Rode:

```bash
STATE="$HOME/.norte-box"
[ -f "$STATE/share-preview.json" ] || { echo "COMPARTILHAR: sem previa montada. Rode o passo 1 antes."; exit 0; }
URL_BASE="$(grep -m1 '^NORTE_BOX_TELEMETRY_URL=' "$STATE/.env" 2>/dev/null | awk -F= '{sub(/^[^=]*=/,"");gsub(/^["'"'"']|["'"'"']$/,"");print}')"
ING="$(jq -r '.ingest_token // empty' "$STATE/identity.json" 2>/dev/null || true)"
TS="$(date -u +%FT%TZ)"
if [ -z "$URL_BASE" ] || [ -z "$ING" ]; then
  echo "COMPARTILHAR: falta coletor (.env) ou token de convite. Nada enviado."
else
  # embrulha a previa num unico evento kind:"sessao-compartilhada" (separado do medidor).
  BODY="$(jq -cn --slurpfile falas "$STATE/share-preview.json" --arg ts "$TS" \
    '{kind:"sessao-compartilhada", ts:$ts, falas:($falas[0] // [])}' 2>/dev/null || echo '')"
  if [ -z "$BODY" ]; then
    echo "COMPARTILHAR: nao consegui montar o corpo. Nada enviado."
  else
    RESP="$(printf '%s' "$BODY" | node "${CLAUDE_PLUGIN_ROOT}/lib/nb-post.js" "$URL_BASE" - "$ING" 2>/dev/null || echo '')"
    ACK="$(printf '%s' "$RESP" | jq -r '.acked // empty' 2>/dev/null || true)"
    if [ -n "$ACK" ]; then
      echo "Enviado: 1 sessao compartilhada ($ACK evento ack). A Norte recebeu SO o que voce viu na previa."
      rm -f "$STATE/share-preview.json"
    else
      echo "COMPARTILHAR: o servidor nao confirmou (resposta: ${RESP:-vazia}). Nada foi perdido — a previa segue no disco; tente de novo."
    fi
  fi
fi
```

Confirme em 1 linha o resultado (enviado ou nao). Lembre: isto foi UMA sessao, por escolha sua;
o padrao continua sendo SO os numeros. Pra apagar o que ja compartilhou, fale com quem te convidou.
