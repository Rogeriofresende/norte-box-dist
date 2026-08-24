---
description: "Norte-box - VER (so rotulos) e APAGAR o pacote de atrito que a Norte captou de voce"
---

Voce e o `/norte-box:atrito`. Da a VOCE transparencia e controle TOTAL sobre o "pacote de
atrito" — o que a Norte captou pra te AJUDAR (consertar travas/erros antes de a advocacia usar).

O pacote carrega SO RÓTULOS e BITS, nunca o seu trabalho:
- **comando**: só o VERBO de um `/norte-box:...` (ex `projeto`), NUNCA o que voce digitou depois.
- **trava**: só o NOME do freio que barrou (ex `secret-guard`), NUNCA a mensagem.
- **erro**: só SIM/NÃO (deu-erro), NUNCA o texto do erro.

Voce pode VER tudo isso e APAGAR quando quiser. Se voce nao pudesse ver/apagar, seria vigilancia
— por isso este comando existe.

Argumento em `$ARGUMENTS` (default: `ver`):

## `ver` - o que foi captado (so rotulos)

```bash
Q="$HOME/.norte-box/atrito-queue.jsonl"
if [ -f "$Q" ] && command -v jq >/dev/null 2>&1; then
  echo "Pacote de atrito (SO rotulos): $(wc -l < "$Q" | tr -d ' ') evento(s)."
  echo "--- so os campos de rotulo (cmd / travas / erro / ts) ---"
  jq -c '{cmd:.atrito.cmd, travas:.atrito.travas, erro:.atrito.erro, ts:.ts}' "$Q" | tail -n 30
  echo
  echo "-- resumo comandos --"; jq -r 'select(.atrito.cmd!=null)|.atrito.cmd' "$Q" | sort | uniq -c
  echo "-- resumo travas --";   jq -r 'select(.atrito.travas!=null)|.atrito.travas[]' "$Q" | sort | uniq -c
  echo "-- erros (sim) --";     jq -r 'select(.atrito.erro==true)|"erro"' "$Q" | wc -l | tr -d ' '
else
  echo "Nada captado ainda (pacote de atrito vazio)."
fi
```

Explique em 1 linha: cada evento é SÓ o rótulo (verbo do comando, nome do freio, bit de erro) —
nenhum texto do seu trabalho, nenhum argumento, nenhuma mensagem. É o que a Norte usa pra
consertar o atrito ANTES da estreia da advocacia.

## `apagar` - limpa tudo (é seu)

```bash
rm -f "$HOME/.norte-box/atrito-queue.jsonl" \
      "$HOME/.norte-box/atrito-breadcrumbs.jsonl" \
      "$HOME/.norte-box/atrito-breadcrumbs.cursor"
echo "Pacote de atrito APAGADO. A Norte nao tem mais nenhum rotulo captado de voce."
echo "A captura continua ligada; pra DESLIGAR de vez: exporte NORTE_ATRITO_OFF=1 no seu shell."
```

## `off` / `on` - desligar / religar a captura de atrito

```bash
case "$ARGUMENTS" in
  off*) echo "Pra desligar a captura de atrito nesta sessao e nas proximas, adicione ao seu shell:";
        echo "  export NORTE_ATRITO_OFF=1";
        echo "Com isso, nenhum rotulo novo é captado (fail-open: sua caixa segue igual).";;
  on*)  echo "Pra religar, remova NORTE_ATRITO_OFF do seu shell (unset NORTE_ATRITO_OFF).";;
esac
```

> O pacote de atrito é local (na sua maquina). A Norte só o recebe se voce estiver em modo
> compartilhavel com o termo aceito — igual ao medidor. Detalhes: docs/TELEMETRIA.md.
