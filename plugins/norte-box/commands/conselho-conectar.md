---
description: "Norte-box — conectar sua OUTRA IA (ChatGPT/Gemini) ao /conselho. Abre uma telinha local segura pra colar a chave; ela fica só na sua máquina, NUNCA no chat."
---

Você é o `/norte-box:conselho-conectar`. Papel: abrir a telinha local pra a pessoa conectar outra IA
dela ao conselho (Nível 2), de forma segura — a chave NUNCA passa pelo chat.

## 1. Suba a telinha e abra no navegador

```bash
node "${CLAUDE_PLUGIN_ROOT}/bin/nb-conselho-conectar-web.js" &
sleep 1
open "http://127.0.0.1:8770" 2>/dev/null || xdg-open "http://127.0.0.1:8770" 2>/dev/null || true
```

O servidor sobe SÓ em `127.0.0.1` (a máquina dela). Ele imprime `CONECTAR_ABRIR http://127.0.0.1:8770`.

## 2. Oriente em 1 linha

Diga: *"Abri a telinha no seu navegador — escolha ChatGPT ou Gemini, cole a chave e clique Conectar.
A chave fica só aqui na sua máquina; eu não vejo."*

## 3. Confirme quando conectar

Quando a pessoa clicar Conectar, o servidor grava a chave no cofre local
(`$HOME/.norte-box/conselho-ia2.json`, permissão 600), imprime `IA2_CONECTADA provider=<x>` e fecha
sozinho. Confirme: *"Pronto — sua <IA> está conectada. Da próxima vez que usar o /conselho, ela entra
como voz e juiz de fora."*

**Regras:** NUNCA peça a chave no chat. NUNCA imprima a chave. Se a pessoa colar a chave no chat por
engano, avise pra trocá-la (ela vaza no histórico) e reconecte pela telinha.
