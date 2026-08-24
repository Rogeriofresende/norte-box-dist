---
name: vitrine
description: Transforma uma entrega em markdown num unico arquivo .html auto-contido (CSS inline, zero rede) em ./norte-out/ e abre no navegador (open no macOS, xdg-open no Linux) — a VITRINE, o lugar onde voce VE a entrega. Use quando o usuario pede "vitrine", "mostra na vitrine", "gera a resposta em HTML", "manda como pagina local", "quero ver a entrega num arquivo", ou os comandos /norte-box:vitrine ou /norte-box:resposta (apelido retrocompat). Slug ASCII sempre (acento/espaco no nome quebra a abertura). Nao usa servidor, nao busca nada da rede.
---

# vitrine — a entrega como HTML local, sem servidor

Você pega um conteúdo em **markdown** (a entrega/resposta que acabou de produzir, ou um
arquivo `.md` que o usuário aponta) e gera **1 arquivo `.html` auto-contido** em `./norte-out/`,
depois abre no navegador. Zero servidor, zero fetch de rede — todo o CSS mora inline no
próprio arquivo, via `templates/resposta.html`.

## Princípios (não-negociáveis)

- **Zero rede.** O HTML final NÃO tem `<script src=...>`, `<link href=...>` externo, `fetch`,
  fonte remota, nem CDN. Tudo inline. O gate de release pode conferir com `grep -c 'http' <arquivo>`.
- **Slug ASCII sempre.** O nome do arquivo é `[a-z0-9-]` derivado do título. Acento/espaço no
  nome quebra a abertura no navegador (some calado). Deriva o slug do título; se não houver
  título, use `resposta`.
- **Não escreve fora de `./norte-out/`.** A saída vai em `./norte-out/<slug>.html` (cwd do
  projeto do usuário). Não sobrescreve sem avisar: se `<slug>.html` já existe, use
  `<slug>-2.html`, `<slug>-3.html`, etc.
- **Fail-open / degradação:** se `./norte-out/` não for gravável → avisa em 1 linha e imprime
  o HTML no chat pro usuário copiar (não trava). Se não houver `open`/`xdg-open` → grava o
  arquivo e imprime o **path absoluto** pro usuário abrir manualmente.

## Passos

1. **Descubra a entrada.** Se o usuário passou um caminho `.md`, leia esse arquivo. Se não,
   use a entrega/resposta corrente (o markdown que você acabou de produzir nesta conversa).
   Guarde num arquivo temporário, ex: `/tmp/vitrine-in.md`.

2. **Derive o título e o slug.**
   - Título = a 1ª linha `# ...` do markdown; se não houver, use a primeira linha não-vazia
     (truncada), ou `Resposta`.
   - Slug = título em minúsculas, sem acento, `[^a-z0-9]+` vira `-`, colapsa `-` repetidos,
     apara `-` das pontas. Vazio → `resposta`.

3. **Converta markdown → HTML e injete no template.** Rode o snippet abaixo (Python 3 puro,
   stdlib — sem `pip install`, sem rede). Ele lê o markdown do stdin, converte um subconjunto
   seguro (títulos, listas, código, tabelas simples, negrito/itálico, links, citações, hr),
   **escapa HTML por padrão** (o conteúdo do usuário é dado, não HTML confiável), monta o slug
   ASCII, injeta em `templates/resposta.html`, resolve colisão de nome e grava em `./norte-out/`.

   ```bash
   TEMPLATE="${CLAUDE_PLUGIN_ROOT}/templates/resposta.html"
   python3 "${CLAUDE_PLUGIN_ROOT}/skills/vitrine/render_inline.py" \
     "$TEMPLATE" < /tmp/vitrine-in.md
   ```

   Como `render_inline.py` não é versionado (só `SKILL.md` entra no pacote — a allowlist só
   cobre `skills/*/SKILL.md`), **gere o renderizador em tempo de execução** a partir do bloco
   abaixo: escreva-o em `/tmp/norte-render.py` e chame com `python3 /tmp/norte-render.py "$TEMPLATE"`.
   O script imprime na última linha `OUT=<path absoluto do .html gerado>`.

   ```python
   #!/usr/bin/env python3
   # Renderizador local: markdown (stdin) -> HTML auto-contido em ./norte-out/. Zero rede.
   import sys, os, re, html, unicodedata

   def slugify(t):
       t = unicodedata.normalize("NFKD", t).encode("ascii", "ignore").decode("ascii")
       t = re.sub(r"[^a-zA-Z0-9]+", "-", t).strip("-").lower()
       return t or "resposta"

   def inline(s):
       s = html.escape(s, quote=False)
       s = re.sub(r"`([^`]+)`", lambda m: "<code>" + m.group(1) + "</code>", s)
       s = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", s)
       s = re.sub(r"(?<!\*)\*([^*]+)\*(?!\*)", r"<em>\1</em>", s)
       s = re.sub(r"\[([^\]]+)\]\(([^)\s]+)\)",
                  lambda m: '<a href="' + html.escape(m.group(2), quote=True) + '">' + m.group(1) + "</a>", s)
       return s

   def md_to_html(md):
       out, i, lines = [], 0, md.split("\n")
       n = len(lines)
       while i < n:
           ln = lines[i]
           if ln.strip().startswith("```"):
               buf, i = [], i + 1
               while i < n and not lines[i].strip().startswith("```"):
                   buf.append(html.escape(lines[i], quote=False)); i += 1
               i += 1
               out.append("<pre><code>" + "\n".join(buf) + "</code></pre>"); continue
           m = re.match(r"^(#{1,6})\s+(.*)$", ln)
           if m:
               lvl = len(m.group(1)); out.append(f"<h{lvl}>{inline(m.group(2))}</h{lvl}>"); i += 1; continue
           if re.match(r"^\s*[-*]\s+", ln):
               out.append("<ul>")
               while i < n and re.match(r"^\s*[-*]\s+", lines[i]):
                   out.append("<li>" + inline(re.sub(r"^\s*[-*]\s+", "", lines[i])) + "</li>"); i += 1
               out.append("</ul>"); continue
           if re.match(r"^\s*\d+\.\s+", ln):
               out.append("<ol>")
               while i < n and re.match(r"^\s*\d+\.\s+", lines[i]):
                   out.append("<li>" + inline(re.sub(r"^\s*\d+\.\s+", "", lines[i])) + "</li>"); i += 1
               out.append("</ol>"); continue
           if "|" in ln and i + 1 < n and re.match(r"^\s*\|?[\s:|-]+\|?\s*$", lines[i + 1]) and "-" in lines[i + 1]:
               def cells(r): return [c.strip() for c in r.strip().strip("|").split("|")]
               head = cells(ln); i += 2
               out.append("<table><thead><tr>" + "".join(f"<th>{inline(c)}</th>" for c in head) + "</tr></thead><tbody>")
               while i < n and "|" in lines[i] and lines[i].strip():
                   out.append("<tr>" + "".join(f"<td>{inline(c)}</td>" for c in cells(lines[i])) + "</tr>"); i += 1
               out.append("</tbody></table>"); continue
           if ln.strip().startswith(">"):
               out.append("<blockquote>" + inline(re.sub(r"^\s*>\s?", "", ln)) + "</blockquote>"); i += 1; continue
           if re.match(r"^\s*(-{3,}|\*{3,})\s*$", ln):
               out.append("<hr>"); i += 1; continue
           if ln.strip() == "":
               i += 1; continue
           out.append("<p>" + inline(ln) + "</p>"); i += 1
       return "\n".join(out)

   def main():
       template_path = sys.argv[1]
       md = sys.stdin.read()
       titulo = "Resposta"
       for l in md.split("\n"):
           m = re.match(r"^#\s+(.*)$", l)
           if m: titulo = m.group(1).strip(); break
           if l.strip(): titulo = l.strip()[:80]; break
       slug = slugify(titulo)
       from datetime import datetime
       meta = "Norte-box &middot; " + datetime.now().strftime("%Y-%m-%d %H:%M")
       with open(template_path, encoding="utf-8") as f:
           tpl = f.read()
       corpo = md_to_html(md)
       out_html = (tpl.replace("{{TITULO}}", html.escape(titulo, quote=False))
                      .replace("{{META}}", meta)
                      .replace("{{CORPO_HTML}}", corpo))
       outdir = os.path.join(os.getcwd(), "norte-out")
       try:
           os.makedirs(outdir, exist_ok=True)
           path = os.path.join(outdir, slug + ".html"); k = 2
           while os.path.exists(path):
               path = os.path.join(outdir, f"{slug}-{k}.html"); k += 1
           with open(path, "w", encoding="utf-8") as f:
               f.write(out_html)
           print("OUT=" + path)
       except OSError as e:
           # fail-open: nao grava -> imprime o HTML pro usuario copiar
           sys.stderr.write("vitrine: ./norte-out/ nao gravavel (" + type(e).__name__ + ") - HTML no stdout\n")
           print(out_html)
           print("OUT=-")

   if __name__ == "__main__":
       main()
   ```

4. **Abra no navegador (best-effort).** Se a última linha foi `OUT=<path>` (não `OUT=-`):
   - macOS: `open "<path>"`
   - Linux: `xdg-open "<path>"` (se ausente, apenas imprima o path absoluto).
   Nunca falhe a skill se a abertura falhar — sempre reporte o path.

5. **Reporte ao usuário** em 1-2 linhas: o arquivo gerado (path relativo `./norte-out/<slug>.html`)
   e que abriu no navegador (ou o path pra abrir manualmente). Não despeje o HTML no chat quando
   a gravação deu certo.

## Prova (o que confirma "pronto")

Num repo qualquer, com um markdown de teste:

```bash
printf '# Titulo de Teste\n\nUm **paragrafo** com `codigo`.\n\n- item 1\n- item 2\n' \
  | python3 /tmp/norte-render.py "${CLAUDE_PLUGIN_ROOT}/templates/resposta.html"
# -> imprime OUT=/.../norte-out/titulo-de-teste.html
grep -c 'http' ./norte-out/titulo-de-teste.html   # -> 0 (auto-contido, zero rede)
```

Sinais de sucesso: existe `./norte-out/<slug>.html`, o slug é ASCII, `grep -c 'http'` no corpo
gerado dá 0, e ele abre no navegador. Depois de conferir, apague o arquivo de teste (`rm`) —
`./norte-out/` é runtime do usuário, não deixa exemplo pra trás no repo.
