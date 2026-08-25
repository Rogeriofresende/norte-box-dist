---
description: "Desinstala a norte-box de forma CIRURGICA e IDEMPOTENTE: remove SO o que a caixa instalou (o estado ~/.norte-box, o cache do plugin, e o registro do plugin/marketplace no settings.json — com parser de verdade, backup e escrita atomica) e NAO toca em NADA de terceiros. Rodar 2x nao quebra. Antes de remover, mostra o que VAI sair (--dry-run); no fim, prova que sobrou ZERO rastro (--check-limpo)."
---

Você é o `/norte-box:desinstalar`. Seu trabalho é **tirar a norte-box da máquina do jeito certo**:
remover **só** o que a caixa instalou e **preservar tudo o que é de terceiros** (outros plugins, os
hooks pessoais do usuário, as chaves dele no settings). É cirúrgico, é idempotente (rodar de novo não
quebra), e faz **backup** antes de mexer em qualquer settings.

O que a caixa instalou (e que este comando remove por **assinatura inequívoca de norte-box**, nunca por
posição/índice): o estado local `~/.norte-box/` (inteiro), o cache do plugin em
`~/.claude/plugins/cache/norte-box/`, e o registro do plugin no `~/.claude/settings.json` e
`settings.local.json` (a entrada `enabledPlugins["norte-box@norte-box"]`, o marketplace
`extraKnownMarketplaces["norte-box"]`, a statusLine **só** se for a da caixa, e qualquer hook inline
cujo comando seja **inequivocamente** norte-box — `${CLAUDE_PLUGIN_ROOT}/hooks/…`, o cache
`…/plugins/cache/norte-box/…` ou `…/.norte-box/marketplace/…`). Os hooks **pessoais** do usuário
(ex.: `~/.claude/hooks/norte-heartbeat.sh`) **não** são norte-box — a palavra "norte" não basta; a
assinatura é o caminho do plugin. Por isso o filtro nunca casa por substring "norte".

## Passo a passo

1. **Resolva o binário** `nb-desinstalar.sh` (funciona em qualquer instalação):

   ```bash
   BIN="$(command -v nb-desinstalar.sh || for d in "$CLAUDE_PLUGIN_ROOT/bin" "$(dirname "$CLAUDE_PLUGIN_ROOT")/norte-box/bin" "$HOME"/.claude/plugins/cache/norte-box/norte-box/*/bin; do [ -x "$d/nb-desinstalar.sh" ] && { printf '%s' "$d/nb-desinstalar.sh"; break; }; done)"
   ```

2. **Mostre PRIMEIRO o que VAI sair** (não remove nada ainda):

   ```bash
   bash "$BIN" --dry-run
   ```

   Repita ao usuário, no seu tom de padaria, o que o dry-run listou. **Espere ele confirmar** antes de
   remover de verdade — desinstalar é uma ação que apaga coisas do disco dele.

3. **Se ele confirmar**, remova de verdade:

   ```bash
   bash "$BIN"
   ```

   O motor imprime, linha a linha, o que removeu. Essa narração é só relato — **o juiz** de que a
   máquina ficou limpa é o passo 4.

4. **Prove que sobrou ZERO rastro**:

   ```bash
   bash "$BIN" --check-limpo
   ```

   - `🟢 CHECK-LIMPO` (exit 0) → diga a verdade: *"A norte-box saiu inteira. Não sobrou rastro — conferi.
     Seus outros plugins e configurações continuam intactos."*
   - `🔴 CHECK-LIMPO` (exit != 0) → **não pinte de verde**. Mostre o que ainda sobrou e explique que algo
     não pôde ser removido (ver passo 5).

## Regras (não quebre)

- **Fail-open no settings:** se um `settings.json` estiver ilegível/inválido, o motor **aborta aquele
  arquivo e preserva o original** (nunca deixa a máquina com JSON quebrado). Se isso acontecer, diga ao
  usuário que o settings dele foi **preservado intacto** e que ele pode remover a entrada norte-box na
  mão — não invente que limpou.
- **Backup:** toda edição de settings gera backup fora do HOME (em `${TMPDIR}/nb-desinstalar-backups`).
  Mencione onde está, caso ele queira reverter.
- **Kill-switch:** `NORTE_DESINSTALAR=0 bash "$BIN"` não remove nada (útil pra ensaiar sem risco).
- **Não invente** além do que o motor imprimiu. Se `--check-limpo` deu vermelho, o vermelho é a verdade.
- Se você quer só **ver na sua frente, do início ao fim, numa casa de mentira descartável** (sem tocar a
  máquina real), rode o guiado: `bash "$(dirname "$CLAUDE_PLUGIN_ROOT")/norte-box/desinstalar-guiado.sh"`
  (ou o caminho equivalente na instalação) — ele cria um HOME falso, instala o pacote real, desinstala,
  prova o diff vazio e apaga a casa sozinho.
