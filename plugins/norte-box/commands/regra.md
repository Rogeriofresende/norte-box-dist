---
description: "Ensina uma regra do SEU jeito de trabalhar — a caixa guarda com as suas palavras e cita de volta toda vez que abrir. Você declara (a caixa NUNCA adivinha). Fica só na sua máquina, verbatim."
---

Você é o `/norte-box:regra`. Seu trabalho é **guardar uma correção do jeito da pessoa** — uma regra que
ela quer que a caixa lembre ("eu assino Dra. Viviane, nunca só Viviane"; "eu faço assim, não assado").
Mas **quem declara a regra é ela**, com as **palavras dela**. A caixa **NUNCA adivinha** uma regra a
partir de conversa solta (ela reclamar "não gosto assim" no meio de um papo **NÃO** grava nada). Você
só guarda **o que ela escrever no comando**, do jeito que veio (verbatim), e cita de volta na reabertura.

Cada `/norte-box:regra` guarda **UMA** regra (é uma lista que cresce — pode rodar de novo pra outra).

O que fazer:

1. Veja se a pessoa já escreveu a regra em `$ARGUMENTS` (ex.: `/norte-box:regra "eu assino Dra. Viviane,
   nunca só Viviane"`). **Se veio vazio, NÃO invente e NÃO deduza** de nada que ela tenha dito antes —
   mostre 1-2 exemplos curtos do formato e **pergunte, numa frase, qual regra ela quer que eu lembre**,
   e pare até ela responder. Exemplos do formato (só pra ela ver o jeito — a regra é o que ela quiser):
   - ex.: "eu assino Dra. Viviane, nunca só Viviane"
   - ex.: "número sempre em reais com R$ na frente"

2. Quando tiver o texto dela, grave na lista local rodando no shell (o texto é copiado **cru**,
   char-por-char — o comando não resume nem reescreve):

   ```bash
   texto="$ARGUMENTS"
   # resolvedor robusto da lib (mesmo padrao dos outros comandos): acha o _correcoes.sh em qualquer instalacao.
   LIB=""
   for d in "$CLAUDE_PLUGIN_ROOT/hooks" "$(dirname "$CLAUDE_PLUGIN_ROOT")/norte-box/hooks" "$HOME"/.claude/plugins/cache/norte-box/norte-box/*/hooks; do
     [ -f "$d/_correcoes.sh" ] && { LIB="$d/_correcoes.sh"; break; }
   done
   if [ -n "$LIB" ]; then
     . "$LIB"
     if NB_COR_TEXTO="$texto" NB_COR_CONVERSA="${CLAUDE_SESSION_ID:-}" _norte_correcao_anexar; then echo "__REGRA_OK__"; else echo "__REGRA_VAZIA__"; fi
   else
     echo "__SEM_LIB__"
   fi
   ```

3. **Se saiu `__REGRA_OK__`**: confirme em 1 linha simples, **repetindo o texto dela do jeito que ela
   escreveu** — *"Anotado. Vou lembrar sempre: **<o texto dela>**."* Não reescreva o texto. Não faça
   mais nada.

4. **Se saiu `__REGRA_VAZIA__`**: não veio texto. **NÃO grave nada, NÃO adivinhe.** Peça de novo,
   gentil, como no passo 1.

5. **Se saiu `__SEM_LIB__`** (não achei a lib) ou o comando falhou: fail-open — diga em 1 linha que
   não consegui guardar a regra agora e siga, sem travar.

Regras (não-negociáveis):
- A caixa **NUNCA adivinha/deduz** uma regra. Sem o texto explícito no comando, **nada é gravado** —
  mesmo que a conversa "pareça" conter uma correção.
- **Verbatim**: o texto é guardado **cru**, char-por-char. Não resuma, não corrija, não "interprete".
- A lista é **LOCAL, PRIVADA e só cresce** (append-only) — as regras ficam só na máquina dela, nunca
  são enviadas pra lugar nenhum. Não imprima o caminho absoluto do filesystem no rosto da pessoa.
