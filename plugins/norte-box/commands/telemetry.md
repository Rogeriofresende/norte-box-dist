---
description: "Norte-box - ver a fila do MEDIDOR antes de enviar (show), desligar (off) ou religar (on)"
---

Voce e o `/norte-box:telemetry`. Da transparencia e CONTROLE sobre o MEDIDOR (Modelo A:
numeros por padrao): mostrar a fila local antes de qualquer envio, e ligar/desligar a emissao.
A fila carrega SO os NUMEROS de uso — nenhum conteudo do seu trabalho (o que a Norte ve por
padrao e so a conta). Desligar o medidor NUNCA desliga os freios de seguranca (o secret-guard
segue valendo). Pra MOSTRAR o conteudo de uma sessao especifica, use `/norte-box:compartilhar`.

A fila ja e so-numeros na origem; ainda assim, nao adicione conteudo cru aqui.

Argumento em `$ARGUMENTS` (default: `show`):

## `show` - ver a fila antes de enviar

Mostre o buffer local que ainda nao foi enviado:

```bash
Q="$HOME/.norte-box/telemetry-queue.jsonl"
if [ -f "$Q" ]; then
  echo "Fila do medidor (buffer local, SO numeros): $(wc -l < "$Q" | tr -d ' ') evento(s)"
  echo "--- ultimos 10 ---"
  tail -n 10 "$Q"
else
  echo "Fila vazia (nenhum evento no buffer)."
fi
if [ -f "$HOME/.norte-box/telemetry.enabled" ]; then
  echo "Estado: LIGADO (medindo)."
else
  echo "Estado: DESLIGADO (nao mede). Religue com: /norte-box:telemetry on"
fi
```

Explique em 1 linha: cada linha = 1 evento do MEDIDOR (`kind:"medidor"`), SO numeros de uso
(`uso:{comandos,tokens,ms,bytes}` + tipo do evento + nome da ferramenta) — NENHUM texto do seu
trabalho. O envio pro servidor so acontece se `NORTE_BOX_TELEMETRY_URL` estiver setada e o modo
for compartilhavel com aceite.

## `off` - desligar (e funciona de verdade)

```bash
rm -f "$HOME/.norte-box/telemetry.enabled"
echo "Medidor DESLIGADO. Os proximos comandos NAO geram evento novo."
echo "Os freios de seguranca (secret-guard) continuam valendo."
```

## `on` - religar

```bash
mkdir -p "$HOME/.norte-box"
touch "$HOME/.norte-box/telemetry.enabled"
echo "Medidor LIGADO. Volta a registrar SO os numeros de uso no buffer local."
```

> Detalhes do que e coletado (so numeros), do que NUNCA sobe (seu trabalho), da retencao 90d e
> de como compartilhar uma sessao por opt-in: docs/TELEMETRIA.md.
