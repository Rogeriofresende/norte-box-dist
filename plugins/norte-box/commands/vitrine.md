---
description: "A Vitrine: gera a entrega como um arquivo HTML local auto-contido (CSS inline, zero rede) em ./norte-out/ e abre no navegador. Apelido: /norte-box:resposta"
---

Você é o `/norte-box:vitrine` (apelido: `/norte-box:resposta`). Acione a skill **vitrine** pra
transformar uma entrega em markdown num único arquivo `.html` **auto-contido** (CSS inline, sem
servidor, sem rede) dentro de `./norte-out/`, e abrir no navegador (`open` no macOS, `xdg-open`
no Linux, `start` no Windows/Git Bash). É o lugar onde você **vê** a entrega.

Entrada:
- Se o usuário passou um caminho de arquivo `.md` como argumento, use esse arquivo.
- Se não passou nada, use a entrega/resposta que você acabou de produzir nesta conversa (o
  markdown corrente).

Regras que a skill enforça (não invente atalho):
- **Slug ASCII sempre** — o nome do arquivo é `[a-z0-9-]` derivado do título; acento/espaço no
  nome quebra a abertura no navegador (some calado).
- **Zero rede** — o HTML final não tem `<script src>`, `<link href>` externo, `fetch` nem CDN;
  todo o CSS mora inline no próprio arquivo (via `templates/resposta.html`).
- **Não sobrescreve calado** — se `<slug>.html` já existe, gera `<slug>-2.html`, etc.
- **Fail-open** — `./norte-out/` não gravável → imprime o HTML no chat; sem `open`/`xdg-open`
  → grava e mostra o path absoluto pra abrir manualmente. Nunca trava a sessão do usuário.

Ao final, reporte em 1-2 linhas: o path relativo do arquivo gerado (`./norte-out/<slug>.html`)
e que abriu no navegador (ou o path pra abrir na mão). Não despeje o HTML no chat quando a
gravação deu certo.

Siga os passos da skill `vitrine` (SKILL.md) — incluindo o renderizador Python stdlib
(zero rede, escapa HTML do usuário) que ela descreve.
