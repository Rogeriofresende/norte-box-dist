# A barrinha do Norte-box (statusLine)

A barrinha aparece no rodapé do Claude Code e mostra, num relance:

```
▲12 · ctx:11% · Opus
```

- **`▲12`** — a marca Norte (▲) colada no **número da conversa** (`#N`). Esse número é a **âncora fixa** da conversa: fácil de citar ("volta na ▲12"). Sem assunto, sem NRT — só o número.
- **`ctx:11%`** — quanto do **contexto** já foi usado. Muda de cor conforme enche:
  - **< 60%** — neutro (tranquilo).
  - **60–80%** — amarelo (fique de olho).
  - **> 80%** — vermelho (hora de `/continuar` ou `/fechar`).
- **`Opus`** — qual **IA** está rodando (Opus / Sonnet / Haiku).

## Como o número da conversa funciona

Sua máquina **não** tem o registro interno de conversas da Norte. O Norte-box mantém um **contador local próprio**, só seu, em `~/.norte-box/conversas.map`:

- Cada conversa do Claude Code tem um `session_id` (o Claude Code garante que ele é estável e único por sessão).
- Na **primeira vez** que a barra vê um `session_id`, ele ganha o **próximo número** e a linha é gravada.
- Quando você **retoma** a mesma conversa, ela reusa o **mesmo número**.

É só um número estável e fácil de achar — **nunca** um identificador interno da Norte.

## Como ligar

Um plugin do Claude Code **não** liga a `statusLine` sozinho — quem manda na barra é o **seu** `settings.json`.

**Nas instalações novas, a barrinha já vem ligada.** O `bootstrap.sh` roda o instalador automaticamente no final (passo 6b) — você não precisa pedir. É seguro por construção: **só liga a barra se você ainda não tiver nenhuma** (rodando sem terminal, ele **não** sobrescreve uma `statusLine` que já exista) e sempre faz **backup** antes de escrever. Depois, **reinicie/atualize o Claude Code** pra ver a barra.

Se você instalou antes dessa mudança (ou desligou a barra e quer religar), rode o instalador na mão:

```bash
# roda do próprio plugin (o caminho abaixo é ilustrativo — use o binário do seu plugin instalado)
bash "$CLAUDE_PLUGIN_ROOT/bin/instalar-barrinha.sh"
```

O que ele faz, nessa ordem:

1. Acha seu `settings.json` (padrão: `~/.claude/settings.json`).
2. Se **já existe** uma `statusLine` de outra ferramenta → **não sobrescreve calado**: mostra o que tem e só troca se você confirmar (ou passar `--forcar`).
3. Faz **backup com timestamp** antes de qualquer escrita (`settings.json.bak.<epoch>`).
4. Escreve o bloco apontando pra barra do Norte-box, **preservando** o resto do seu `settings.json`.

Depois, **reinicie/atualize o Claude Code** pra ver a barra.

### Se preferir ligar na mão

Basta este bloco no seu `~/.claude/settings.json` (o caminho do `command` é o `norte-statusline` do seu plugin instalado). **Faça backup do arquivo antes** e **preserve as outras chaves** que já existirem:

```json
{
  "statusLine": {
    "type": "command",
    "command": "/caminho/para/o/plugin/norte-box/bin/norte-statusline",
    "padding": 0
  }
}
```

> Aviso: se você **já** tem uma `statusLine`, colar este bloco **substitui** a sua. Por isso o instalador acima é o caminho recomendado — ele detecta e faz backup por você.

## Desfazer

- Se usou o instalador: ele imprime a linha exata de `cp` do backup pra restaurar.
- Na mão: remova o campo `statusLine` do `settings.json` (ou restaure do seu backup).

## Detalhes técnicos (por que é segura)

- **Fail-open total.** A barra é cosmética. Falta de `~/.norte-box`, de `jq`, de um campo no JSON, permissão, disco cheio → a barra **degrada** (ex: `▲ · ctx:--% · —`) e **nunca** derruba a sua sessão. `exit 0` sempre.
- **Burra e rápida.** Só lê o JSON do stdin + um arquivo local. **Zero rede, zero git, zero registry.** Não carrega nada de fora.
- **Lê stdin como dado, jamais executa.** Sem `eval`/`source` de conteúdo externo.
- **Só escreve em `~/.norte-box`.** O binário da barra **não** toca seu `settings.json` (quem faz isso é o instalador, uma vez, com backup e confirmação).
- **Campos nativos do Claude Code:** `model.display_name`, `context_window.used_percentage`, `session_id`.
