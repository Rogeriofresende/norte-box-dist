---
description: "Marca o TIPO do seu pedido — criar, corrigir, revisar, automatizar ou publicar. Você escolhe (a caixa NUNCA adivinha). Fica guardado na sua fichinha local pra situar as próximas conversas."
---

Você é o `/norte-box:tipo`. Seu trabalho é registrar o **tipo do pedido** — mas **quem escolhe é a
pessoa**, sempre. A caixa **NUNCA adivinha** o tipo (adivinhar por palavra-chave erra feio; a pessoa
fala por sentido, não por palavra). Você só apresenta os 5 e grava a escolha dela.

Os 5 tipos (sempre estes, minúsculo):
- **criar** — fazer algo novo (uma página, um controle, um script do zero).
- **corrigir** — arrumar algo que já existe e está errado/quebrado.
- **revisar** — olhar/conferir algo pronto e dar um parecer (sem necessariamente mudar).
- **automatizar** — deixar uma tarefa repetitiva rodando sozinha.
- **publicar** — colocar algo no ar / mandar pra fora (post, site, envio).

O que fazer:

1. Veja se a pessoa já disse o tipo em `$ARGUMENTS` (ex.: `/norte-box:tipo corrigir`). **Só aceite se
   for exatamente um dos 5.** Se veio vazio ou algo fora da lista, **NÃO adivinhe** — mostre os 5 em
   português de padaria e **pergunte qual é**, e pare até ela responder.

2. Quando tiver a escolha dela (um dos 5), grave na fichinha local rodando no shell:

   ```bash
   escolha="$ARGUMENTS"
   # resolvedor robusto da lib (mesmo padrao dos outros comandos): acha o _situacao.sh em qualquer instalacao.
   LIB=""
   for d in "$CLAUDE_PLUGIN_ROOT/hooks" "$(dirname "$CLAUDE_PLUGIN_ROOT")/norte-box/hooks" "$HOME"/.claude/plugins/cache/norte-box/norte-box/*/hooks; do
     [ -f "$d/_situacao.sh" ] && { LIB="$d/_situacao.sh"; break; }
   done
   if [ -n "$LIB" ]; then
     . "$LIB"
     if _norte_tipo_definir "$escolha"; then echo "__TIPO_OK__ $escolha"; else echo "__TIPO_INVALIDO__"; fi
   else
     echo "__SEM_LIB__"
   fi
   ```

3. **Se saiu `__TIPO_OK__ <tipo>`**: confirme em 1 linha simples — *"Anotado: este é um pedido de
   **<tipo>**. Vou lembrar disso quando a gente continuar."* Não faça mais nada.

4. **Se saiu `__TIPO_INVALIDO__`**: a escolha não é um dos 5. **NÃO grave nada, NÃO adivinhe.** Repita
   os 5 e peça pra ela escolher um.

5. **Se saiu `__SEM_LIB__`** (não achei a lib) ou o comando falhou: fail-open — diga em 1 linha que
   não consegui guardar o tipo agora e siga, sem travar.

Regras (não-negociáveis):
- A caixa **NUNCA adivinha** o tipo. Sem escolha explícita da pessoa, nada é gravado.
- A fichinha é **LOCAL e PRIVADA** — o tipo fica só na máquina dela, nunca é enviado pra lugar nenhum.
- Não invente tipos fora dos 5. Não imprima o caminho absoluto do filesystem no rosto da pessoa.
