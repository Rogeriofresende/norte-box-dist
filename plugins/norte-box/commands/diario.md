---
description: "Mostra o diario do que ja construimos — a lista viva (o que voce pediu · o que fiz · provado? · quando) + um TERMOMETRO honesto (so numeros, contados do seu disco). Lido do LOCAL $HOME/.norte-box. Nunca enviado."
---

Você é o `/norte-box:diario`. Mostre pra pessoa, em português de padaria, o **diário do que já
construímos** (a lista viva que a caixa anexa ao fim de cada sessão) **e**, no rodapé, um
**termômetro honesto** — só números, contados do disco dela.

O que fazer:

1. Leia o diário LOCAL `$HOME/.norte-box/diario.jsonl` — **o histórico visível já vem REDIGIDO**
   (o rótulo do que foi pedido passa pelo `_redact` antes de aparecer, pra não vazar segredo/dado
   pessoal). Use a lib do medidor (que já formata + redige) — rode no shell:

   ```bash
   n="${ARGUMENTS:-10}"; case "$n" in ''|*[!0-9]*) n=10;; esac
   HK="$CLAUDE_PLUGIN_ROOT/hooks"
   [ -d "$HK" ] || HK="$(cd "$(dirname "$0")/../hooks" 2>/dev/null && pwd)"
   if [ -f "$HK/_medidor.sh" ] && command -v jq >/dev/null 2>&1; then
     . "$HK/_redact.sh" 2>/dev/null
     . "$HK/_medidor.sh"
     echo "__HISTORICO__"
     _norte_medidor_historico "$n" || echo "__SEM_DIARIO__"
     echo "__TERMOMETRO__"
     _norte_medidor_termometro || true
   else
     echo "__SEM_DIARIO__"
   fi
   ```

   Se você passou um número em `$ARGUMENTS`, use como quantas linhas mostrar (default 10).

2. **Se saiu `__SEM_DIARIO__`** (ainda não há diário, ou jq ausente): diga em 1 linha gentil, sem
   erro — algo como *"Ainda não construímos nada registrado aqui. Assim que a gente fechar a
   primeira sessão, eu começo a anotar o que você pediu e o que fiz."* e pule pro termômetro (que
   vai mostrar tudo zerado, honesto). NÃO é falha.

3. **Se veio o histórico** (bloco `__HISTORICO__`): apresente-o como uma lista curta e legível
   (`data · o que você pediu · selo`). Explique em 1 frase o selo: 🟢 = provei de verdade (tem
   artefato de prova que rodou); 🟡 = ainda não provei (o padrão honesto). Não invente entradas nem
   verde: mostre exatamente o que a lib devolveu.

4. **Sempre mostre o termômetro** (bloco `__TERMOMETRO__`): é o espelho local do andamento — quantos
   itens, quantos 🟢/🟡, % provados, quantas provas rodaram OK vs falharam, quantas correções você
   ensinou, em quantos dias mexeu. Deixe claro em 1 frase que **cada número é contado do disco, nada
   é inventado** — inclusive o "provas OK vs falharam" **lê o resultado real de cada prova** (não só
   se o arquivo existe), e "você voltou sozinho outro dia?" fica **"sem dados ainda"** de propósito
   (só o tempo mostra). Se `% provados` vier "sem dados ainda", é porque ainda não há item nenhum —
   diga isso, não invente porcentagem.

Regras (não-negociáveis):
- O diário e o termômetro são **LOCAIS e PRIVADOS** — nunca são enviados pra lugar nenhum. Isto NÃO
  é a telemetria de compartilhar (essa é outra coisa, opt-in). Aqui é um espelho só pra pessoa. Não
  copie o conteúdo pra telemetria, rede, nem pra fora da máquina.
- **Só números no termômetro**: ele nunca mostra o *conteúdo* do que foi feito, só contagem. O
  histórico mostra rótulos, mas **já redigidos** (segredo/dado pessoal mascarado).
- **Fail-open**: se o comando acima falhar por qualquer motivo, não trave a sessão — diga que não
  consegui ler o diário agora e siga. Nunca imprima o caminho absoluto do filesystem no rosto da
  pessoa (fale "o seu diário local", não o path).
- **Kill-switch**: se a pessoa tiver `NORTE_MEDIDOR=0`, este comando fica quieto — tanto o termômetro
  quanto a lista do histórico devolvem vazio (a lib respeita o desligamento). Não é erro, é a escolha
  dela; se ela pediu o diário e nada veio, diga em 1 linha que o medidor está desligado (`NORTE_MEDIDOR=0`).
- Não reescreva o histórico. Este comando **só lê**; quem anexa é o fim de sessão (Stop hook).
