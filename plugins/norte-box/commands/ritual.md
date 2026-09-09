---
description: "Norte-box - VER, APAGAR, LIGAR/DESLIGAR o observador em sombra do ritual (so contagem, 100% local, nada sai da maquina)"
---

Voce e o `/norte-box:ritual`. Da a VOCE transparencia e controle TOTAL sobre o "observador em
sombra" — a caixa apenas CONTA quantas vezes voce completou um ritual repetido de trabalho
(mandato -> teste/review -> abrir PR). Nada mais.

O observador guarda SO CONTAGEM e RÓTULOS de um vocabulario fechado — NUNCA o seu trabalho:
- **marco**: só o RÓTULO da forma (ex `mandato`, `teste`, `review`, `pr`), NUNCA o arquivo, o
  comando ou o texto.
- **contagem**: quantos rituais `mandato_pr_v1` voce completou / deixou pela metade.

Nada sai da sua maquina (esta fatia NAO envia nada — nem contagem). Se voce nao pudesse ver/
apagar/desligar, seria vigilancia — por isso este comando existe.

Limitacao honesta: a v1 confere o ESQUELETO do ritual (mandato -> teste/review -> pr), NAO a
qualidade do mandato (o "DoD" nao e detectavel sem ler o conteudo, e a caixa nunca le conteudo).

Argumento em `$ARGUMENTS` (default: `ver`):

## `ver` - o placar (so contagem + rotulos)

```bash
C="$HOME/.norte-box/ritual-contagem.json"
FLAG="$HOME/.norte-box/ritual-observador.enabled"
if [ -f "$FLAG" ]; then echo "Observador: LIGADO"; else echo "Observador: DESLIGADO (ligue com: /norte-box:ritual on)"; fi
if [ -f "$C" ] && command -v jq >/dev/null 2>&1; then
  echo "--- placar do ritual mandato_pr_v1 ---"
  jq -r '
    .rituais.mandato_pr_v1 as $r
    | "completos: \(($r.completos)//0)",
      "parciais:  \(($r.parciais)//0)",
      "ultimo completo: \(($r.ultimo_completo_ts)//"nenhum ainda")"
  ' "$C" 2>/dev/null
  echo "-- de quando deixou pela metade, o que faltou (so rotulos) --"
  jq -r '(.rituais.mandato_pr_v1.parciais_faltou // {}) | to_entries[]? | "\(.value)x faltou: \(.key)"' "$C" 2>/dev/null
  echo "-- atualizado --"; jq -r '.atualizado // "?"' "$C" 2>/dev/null
else
  echo "Nenhum ritual contado ainda (placar vazio)."
fi
```

Explique em 1 linha: o placar é SÓ contagem + rótulos da forma do ritual — nenhum arquivo,
nenhum comando, nenhum texto do seu trabalho, e nada sai da sua máquina.

## `apagar` - zera o placar e o estado (é seu)

```bash
rm -f "$HOME/.norte-box/ritual-contagem.json"
rm -rf "$HOME/.norte-box/ritual-state"
echo "Observador em sombra ZERADO. A caixa nao guarda mais nenhuma contagem de voce."
echo "A observacao continua no estado atual (ligada/desligada); pra DESLIGAR: /norte-box:ritual off"
```

## `on` - liga o observador (opt-in explicito, fail-closed)

```bash
mkdir -p "$HOME/.norte-box" 2>/dev/null
: > "$HOME/.norte-box/ritual-observador.enabled"
echo "Observador em sombra LIGADO. A caixa vai CONTAR seus rituais (mandato -> teste/review -> pr)."
echo "So contagem, 100% local, nada sai da maquina. Pra ver: /norte-box:ritual ver"
```

## `off` - desliga o observador (para de contar na hora)

```bash
rm -f "$HOME/.norte-box/ritual-observador.enabled"
echo "Observador em sombra DESLIGADO. Nenhuma contagem nova (fail-closed: sem a flag, nao observa)."
echo "Kill-switch imediato pra qualquer sessao: exporte NORTE_RITUAL_OFF=1 no seu shell."
echo "O placar ja contado continua ate voce mandar: /norte-box:ritual apagar"
```

> O observador é local (na sua maquina). Nesta fatia ele SÓ conta e mostra pra voce — não
> envia nada (nem a contagem). É modo SOMBRA puro: provar que a caixa enxerga o ritual.
