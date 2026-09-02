#!/usr/bin/env node
// nb-indice.js — a CAPA (indice) da Vitrine local do Norte-box (zero dependencia, zero rede).
//
// O QUE FAZ: varre o diretorio de entregas (./norte-out por padrao) e escreve um unico
// arquivo `<dir>/index.html` — uma CAPA que lista TODAS as entregas (titulo + data + link
// relativo), a mais recente primeiro. Regenerado a cada /vitrine. Sem servidor, sem rede,
// sem processo em background: o script RODA E TERMINA.
//
// LOCAL POR DESIGN: nao abre socket, nao faz fetch, nao spawna nada. Le arquivos .html do
// disco, monta um HTML auto-contido (CSS inline, mesma cara do templates/resposta.html) e sai.
// A capa NAO tem <script src=...>, <link href=...> externo, nem http(s):// no corpo.
//
// FIX DO MTIME (pedido do CEO): a data de cada entrega vem, na ordem de preferencia:
//   (a) do <meta name="norte-ts" content="ISO8601"> embutido DENTRO da entrega — a data que
//       VIAJA no arquivo (robusta a copia/restore, que zeram/trocam o mtime);
//   (b) so se nao houver o meta, cai no mtime do arquivo (best-effort) — e a capa avisa que a
//       data e "do arquivo" (honesto: mtime muda em copia/restore).
//
// DADO E DADO: o titulo de cada entrega e ESCAPADO (& < > " ') antes de entrar na capa — uma
// entrega com <script>/<img onerror> no titulo NAO injeta nada aqui.
//
// KILL-SWITCH: NB_INDICE_OFF=1 (env) OU o arquivo ~/.claude/nb-indice-off -> sai 0 sem tocar nada.
//
// FAIL-OPEN: qualquer erro (arquivo ilegivel, dir nao-gravavel, etc) -> 1 linha honesta no
// stderr + exit 0. NUNCA lanca, NUNCA trava a entrega principal.
//
// Uso:  node nb-indice.js [dir]     (default: ./norte-out)
// Exit: sempre 0 (fail-open por design).
'use strict';

const fs = require('fs');
const os = require('os');
const path = require('path');

// --- kill-switch: env OU arquivo em ~/.claude/nb-indice-off ---
function desligado() {
  if (process.env.NB_INDICE_OFF === '1') return true;
  try {
    const home = os.homedir();
    if (home && fs.existsSync(path.join(home, '.claude', 'nb-indice-off'))) return true;
  } catch (e) { /* na duvida, NAO bloqueia (a ausencia do home nao e motivo pra desligar) */ }
  return false;
}

// --- escapa HTML: DADO E DADO (titulo de entrega e conteudo, nao HTML confiavel) ---
function esc(s) {
  return String(s)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

// --- titulo da entrega: 1o <title>, senao 1o <h1>, senao o nome do arquivo sem .html ---
function extrairTitulo(htmlText, fname) {
  let m = /<title[^>]*>([\s\S]*?)<\/title>/i.exec(htmlText);
  if (m && m[1].trim()) return m[1].trim();
  m = /<h1[^>]*>([\s\S]*?)<\/h1>/i.exec(htmlText);
  if (m && m[1].trim()) {
    // remove tags internas do h1 (ex: <h1><span>X</span></h1>) — fica so o texto
    return m[1].replace(/<[^>]*>/g, '').trim() || fname.replace(/\.html$/i, '');
  }
  return fname.replace(/\.html$/i, '');
}

// --- data da entrega: (a) meta norte-ts embutido; (b) mtime (best-effort) ---
// retorna { iso, texto, fonte } — fonte = 'meta' (viaja no arquivo) ou 'mtime' (do arquivo).
function extrairData(htmlText, fullpath) {
  // FURO 2 (Val): robusto ao FORMATO do meta. Acha a tag <meta ...> que contem name="norte-ts"
  // (em QUALQUER ordem de atributos, com outros atributos no meio, multi-linha) e extrai o content
  // de DENTRO dessa tag. O parser antigo exigia name/content adjacentes -> regredia pro mtime calado.
  let iso = null;
  const metaRe = /<meta\b[^>]*>/gi;
  let mm;
  while ((mm = metaRe.exec(htmlText)) !== null) {
    const tag = mm[0];
    if (/\bname\s*=\s*["']norte-ts["']/i.test(tag)) {
      const cm = /\bcontent\s*=\s*["']([^"']*)["']/i.exec(tag);
      if (cm && cm[1]) { iso = cm[1]; break; }
    }
  }
  if (iso) {
    const d = new Date(iso);
    if (!isNaN(d.getTime())) {
      return { ord: d.getTime(), texto: formatarData(d), fonte: 'meta' };
    }
  }
  // fallback: mtime do arquivo (best-effort — muda em copia/restore, por isso e o plano B).
  try {
    const st = fs.statSync(fullpath);
    return { ord: st.mtime.getTime(), texto: formatarData(st.mtime), fonte: 'mtime' };
  } catch (e) {
    return { ord: 0, texto: 'data desconhecida', fonte: 'mtime' };
  }
}

function pad2(n) { return String(n).padStart(2, '0'); }
function formatarData(d) {
  return d.getFullYear() + '-' + pad2(d.getMonth() + 1) + '-' + pad2(d.getDate())
       + ' ' + pad2(d.getHours()) + ':' + pad2(d.getMinutes());
}

// --- monta o HTML da capa (CSS inline, mesma cara do resposta.html; zero rede) ---
function montarCapa(entradas) {
  const geradoEm = formatarData(new Date());
  const linhas = [];
  if (entradas.length === 0) {
    linhas.push('    <p class="vazio">&#9650; Nada por aqui ainda &mdash; rode <code>/vitrine</code> pra criar a primeira entrega.</p>');
  } else {
    linhas.push('    <ul class="lista">');
    for (const e of entradas) {
      // href RELATIVO: so o nome do arquivo (a capa mora no mesmo dir das entregas).
      // FURO 4 (Val): encodeURI neutraliza espaco/newline/<>" (que quebrariam o href de um nome
      // dropado a mao); o esc por cima fecha o & (-> &amp;) pra o atributo HTML ficar valido.
      const href = esc(encodeURI(e.arquivo));
      const marca = e.fonte === 'mtime' ? ' <span class="hint">(data do arquivo)</span>' : '';
      linhas.push(
        '      <li>' +
        '<a href="' + href + '">' + esc(e.titulo) + '</a>' +
        '<span class="data">' + esc(e.dataTexto) + marca + '</span>' +
        '</li>'
      );
    }
    linhas.push('    </ul>');
  }
  const corpo = linhas.join('\n');
  const n = entradas.length;
  const sub = n === 0 ? 'sem entregas ainda'
            : (n === 1 ? '1 entrega' : n + ' entregas');

  return `<!DOCTYPE html>
<html lang="pt-BR">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Vitrine &middot; Norte-box</title>
<style>
  :root {
    --bg: #0f1115;
    --panel: #171a21;
    --border: #262b36;
    --fg: #e6e8ec;
    --muted: #9aa2b1;
    --accent: #7ee787;
    --code-bg: #10141b;
  }
  * { box-sizing: border-box; }
  html, body { margin: 0; padding: 0; }
  body {
    background: var(--bg);
    color: var(--fg);
    font: 16px/1.65 -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
    padding: 2.5rem 1rem;
  }
  .wrap {
    max-width: 760px;
    margin: 0 auto;
    background: var(--panel);
    border: 1px solid var(--border);
    border-radius: 12px;
    padding: 2rem 2.25rem;
  }
  header.doc-head {
    border-bottom: 1px solid var(--border);
    padding-bottom: 1rem;
    margin-bottom: 1.5rem;
  }
  header.doc-head h1 { font-size: 1.55rem; line-height: 1.25; margin: 0 0 .35rem; }
  header.doc-head .meta { color: var(--muted); font-size: .85rem; }
  a { color: var(--accent); text-decoration: none; }
  a:hover { text-decoration: underline; }
  code {
    background: var(--code-bg);
    border: 1px solid var(--border);
    border-radius: 5px;
    padding: .1rem .35rem;
    font: .9em/1.4 "SFMono-Regular", Menlo, Consolas, monospace;
  }
  ul.lista { list-style: none; padding: 0; margin: 0; }
  ul.lista li {
    display: flex;
    justify-content: space-between;
    align-items: baseline;
    gap: 1rem;
    padding: .7rem 0;
    border-bottom: 1px solid var(--border);
  }
  ul.lista li:last-child { border-bottom: none; }
  ul.lista li a { font-size: 1.05rem; flex: 1 1 auto; word-break: break-word; }
  ul.lista li .data { color: var(--muted); font-size: .82rem; white-space: nowrap; }
  .hint { color: var(--muted); font-size: .75rem; }
  p.vazio { color: var(--muted); }
  footer.doc-foot {
    border-top: 1px solid var(--border);
    margin-top: 2rem;
    padding-top: 1rem;
    color: var(--muted);
    font-size: .8rem;
  }
</style>
</head>
<body>
  <div class="wrap">
    <header class="doc-head">
      <h1>&#9650; Vitrine</h1>
      <div class="meta">${esc(sub)} &middot; gerado localmente ${esc(geradoEm)} &middot; arquivo auto-contido, sem rede</div>
    </header>
    <main>
${corpo}
    </main>
    <footer class="doc-foot">Capa gerada localmente pelo Norte-box &middot; links relativos, sem servidor, sem rede.</footer>
  </div>
</body>
</html>
`;
}

function main() {
  // kill-switch: sai 0 SEM tocar nada.
  if (desligado()) process.exit(0);

  const dir = process.argv[2] || path.join(process.cwd(), 'norte-out');

  let arquivos = [];
  let todosRaw = [];
  try {
    todosRaw = fs.readdirSync(dir);
    arquivos = todosRaw
      .filter((f) => /\.html$/i.test(f))
      .filter((f) => f.toLowerCase() !== 'index.html'); // NUNCA lista a propria capa
  } catch (e) {
    // dir ausente/ilegivel: gera uma capa honesta "nada ainda" SE der pra escrever; senao, sai 0.
    arquivos = [];
    try {
      fs.mkdirSync(dir, { recursive: true });
    } catch (e2) {
      process.stderr.write('nb-indice: dir de entregas ausente e nao-criavel (' + (e2 && e2.code || 'erro') + ') — capa nao gerada.\n');
      process.exit(0);
    }
  }

  const entradas = [];
  for (const f of arquivos) {
    const full = path.join(dir, f);
    let txt = '';
    try {
      txt = fs.readFileSync(full, 'utf8');
    } catch (e) {
      // arquivo ilegivel: nao quebra a capa inteira — pula com aviso honesto.
      process.stderr.write('nb-indice: pulei ' + f + ' (ilegivel: ' + (e && e.code || 'erro') + ')\n');
      continue;
    }
    let titulo, data;
    try {
      titulo = extrairTitulo(txt, f);
      data = extrairData(txt, full);
    } catch (e) {
      titulo = f.replace(/\.html$/i, '');
      data = { ord: 0, texto: 'data desconhecida', fonte: 'mtime' };
    }
    entradas.push({ arquivo: f, titulo, dataTexto: data.texto, ord: data.ord, fonte: data.fonte });
  }

  // ordena: mais RECENTE primeiro; empate desempata por nome (estavel).
  entradas.sort((a, b) => (b.ord - a.ord) || a.arquivo.localeCompare(b.arquivo));

  let capa;
  try {
    capa = montarCapa(entradas);
  } catch (e) {
    process.stderr.write('nb-indice: falha ao montar a capa (' + (e && e.message || 'erro') + ') — index nao gerado.\n');
    process.exit(0);
  }

  // FURO 1 (Val): em disco que NAO diferencia maiuscula (macOS/Windows — o ambiente do CEO e da
  // Viviane), escrever "index.html" sobrescreveria calado um arquivo do usuario chamado
  // "INDEX.HTML"/"Index.html". NAO destruir dado: se existe um colidente que NAO e exatamente
  // "index.html", avisa e NAO escreve (fail-open: o usuario renomeia e a capa volta a ser gerada).
  const colisao = todosRaw.find((f) => f.toLowerCase() === 'index.html' && f !== 'index.html');
  if (colisao) {
    process.stderr.write('nb-indice: existe "' + colisao + '" (colide com index.html em disco que nao diferencia maiuscula) — NAO sobrescrevi pra nao apagar seu arquivo. Renomeie-o e a capa volta a ser gerada.\n');
    process.exit(0);
  }

  try {
    fs.writeFileSync(path.join(dir, 'index.html'), capa, 'utf8');
  } catch (e) {
    process.stderr.write('nb-indice: nao consegui gravar ' + path.join(dir, 'index.html') + ' (' + (e && e.code || 'erro') + ') — a entrega principal segue.\n');
    process.exit(0);
  }

  process.exit(0);
}

try {
  main();
} catch (e) {
  // rede de seguranca final: NUNCA propaga excecao (fail-open absoluto).
  try { process.stderr.write('nb-indice: erro inesperado (' + (e && e.message || 'erro') + ') — ignorado.\n'); } catch (e2) { /* nada */ }
  process.exit(0);
}
