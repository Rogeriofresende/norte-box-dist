---
description: "Norte-box - ver as 106 regras universais (todas, por tema ou por busca). Lista e conta."
---

Voce e o `/norte-box:regras`. Mostra as **106 regras universais** do Norte-box — o destilado
de como trabalhar bem com uma IA que constroi de verdade. A maioria e conselho macio (voce le,
voce aplica); algumas ja sao freio automatico (marcadas `[HOOK]` — agem na sua sessao mesmo
sem voce lembrar delas). NAO invente regra: mostre so o que esta no arquivo canonico.

O arquivo canonico e `${CLAUDE_PLUGIN_ROOT}/regras/REGRAS.md` — cada regra tem um id estavel
(`R001`..`R106`, cabecalho `### RNNN`). Ele e a FONTE UNICA; nunca reescreva as regras de
memoria.

Argumento em `$ARGUMENTS`:
- **vazio** — resumo: contagem + os temas + como buscar.
- **`todas`** — lista as 106 (id + titulo de cada uma).
- **qualquer outra palavra** — busca (case-insensitive) por id, titulo ou corpo. Ex:
  `seguranca`, `handoff`, `R060`, `secret`, `paralel`.

## Caso 1 — sem argumento: RESUMO

```bash
F="${CLAUDE_PLUGIN_ROOT}/regras/REGRAS.md"
if [ ! -f "$F" ]; then echo "REGRAS.md nao encontrado (instalacao incompleta?)."; exit 0; fi
N="$(grep -cE '^### R[0-9]{3} ' "$F")"
echo "Norte-box: $N regras universais (id estavel R001..R106)."
echo
echo "Temas:"
grep -E '^## Tema ' "$F" | sed 's/^## /  - /'
echo
echo "Como ver:"
echo "  /norte-box:regras todas        (lista as $N)"
echo "  /norte-box:regras seguranca    (busca por tema/palavra)"
echo "  /norte-box:regras R060         (uma regra pelo id)"
echo "  /norte-box:regras HOOK         (quais ja AGEM na sua sessao)"
```

Depois diga, em 1 frase: a maioria e conselho macio; as marcadas `[HOOK]` sao freios que ja
rodam automaticamente (ex: R060 secret nunca no chat = o secret-guard bloqueia de verdade).

## Caso 2 — `todas`: LISTAR id + titulo das 106

```bash
F="${CLAUDE_PLUGIN_ROOT}/regras/REGRAS.md"
grep -E '^### R[0-9]{3} ' "$F" | sed 's/^### //'
echo "---"
echo "Total: $(grep -cE '^### R[0-9]{3} ' "$F") regras."
```

Nao despeje o corpo inteiro sem o usuario pedir — a lista de titulos ja e a visao geral.
Se ele quiser o texto de uma regra, ele busca pelo id (Caso 3).

## Caso 3 — busca por palavra/tema/id

`$ARGUMENTS` = o termo de busca. Mostre cada regra (id + titulo + corpo) cujo id, titulo ou
corpo casem o termo, case-insensitive:

```bash
F="${CLAUDE_PLUGIN_ROOT}/regras/REGRAS.md"
TERM="$ARGUMENTS"
# awk: acumula o bloco de cada regra (### RNNN ... ate o proximo ### ou fim) e imprime os que
# casam o termo em qualquer linha do bloco. Case-insensitive. Sem executar nada do input.
awk -v term="$TERM" '
  BEGIN{ IGNORECASE=1; hit=0; block="" }
  /^### R[0-9][0-9][0-9] /{
    if (block!="" && match_flag) { printf "%s\n", block }
    block=$0"\n"; match_flag=(index(tolower($0), tolower(term))>0); next
  }
  /^## Tema /{
    if (block!="" && match_flag) { printf "%s\n", block }
    block=""; match_flag=0; next
  }
  {
    if (block!="") { block=block $0 "\n"; if (index(tolower($0), tolower(term))>0) match_flag=1 }
  }
  END{ if (block!="" && match_flag) { printf "%s\n", block } }
' "$F"
```

- Se saiu pelo menos 1 bloco — apresente as regras encontradas ao usuario, em linguagem
  simples, sem inventar nada alem do que veio do arquivo.
- Se NAO saiu nada — diga: **"Nenhuma regra casou `<termo>`. Tente `/norte-box:regras todas`
  ou um tema (seguranca, comunicacao, handoff, qualidade, foco, paralel)."** e pare.

> As 106 saem do censo de regras universais da Norte (100 consolidadas + 6 de um gap-check).
> Marcadores no arquivo: `[HOOK]` = ja e um freio que roda · `[FASE4]` = vira comportamento de
> um agente do time · `[KIT]` = ja coberto pelas 6 regras anti-perda. Detalhe: `regras/REGRAS.md`.
