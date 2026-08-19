---
description: "Norte-box - login pelo Google via device flow (mostra codigo + URL, autoriza no browser); grava so o sub+email, nunca o token"
---

Voce e o `/norte-box:login`. Seu papel: fazer a pessoa entrar com a conta Google dela
usando o **device flow** (igual `gh auth login`): a gente mostra um CODIGO e uma URL,
a pessoa autoriza no navegador, e o pacote recebe a identidade. Na maquina fica **so o
id opaco (`sub`) + email** em `$HOME/.norte-box/identity.json` - o **token NUNCA e gravado**.

NUNCA peca nem aceite secret colado no chat. O client_id/secret do app OAuth vem de
variavel de ambiente (`NORTE_BOX_GOOGLE_CLIENT_ID` / `NORTE_BOX_GOOGLE_CLIENT_SECRET`),
nunca do chat e nunca hardcoded. NUNCA escreva fora de `$HOME/.norte-box`.

## O que fazer

Rode o script do device flow e mostre a saida pra pessoa (o codigo + a URL aparecem la,
e o script fica esperando ela autorizar no browser):

```bash
"${CLAUDE_PLUGIN_ROOT}/hooks/norte-login.sh"
```

- O script fala com o Google, mostra `user_code` + `verification_url`, faz o polling
  sozinho e, quando a pessoa autoriza, grava `identity.json = {"sub":"...","email":"..."}`.
- **Fail-open sempre:** se `NORTE_BOX_GOOGLE_CLIENT_ID` nao estiver setada, o script
  imprime a instrucao (o Rogerio precisa criar o app OAuth no Google Cloud e setar a env)
  e sai limpo - **nada trava**. O mesmo vale pra qualquer erro de rede/recusa.

## Depois do login

Confirme em 1 linha o que ficou gravado, **sem imprimir o conteudo cru do arquivo**
(nunca exponha o email/sub em detalhe alem do necessario):

```bash
if [ -f "$HOME/.norte-box/identity.json" ]; then
  echo "Identidade presente (so sub+email na maquina; token nunca guardado)."
else
  echo "Sem identidade ainda - rode /norte-box:login pra entrar."
fi
```

> Por que so o `sub` (id opaco) e o email ficam na maquina, e por que o token NUNCA e
> guardado: e o mesmo principio do `identity.json` que a telemetria le pra identificar
> o convite sem nunca tocar credencial. Detalhes: docs/TELEMETRIA.md e docs/SPEC.md.
