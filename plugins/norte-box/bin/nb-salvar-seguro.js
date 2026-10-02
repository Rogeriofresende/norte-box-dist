#!/usr/bin/env node
// nb-salvar-seguro.js — /norte:salvar-seguro. Guarda um valor sensível (senha, chave, código de
// verificação) direto no .env do projeto, por um formulário no navegador da própria máquina.
// O valor NUNCA passa pelo chat, NUNCA é impresso, NUNCA vai pra URL/log/erro, NUNCA sai da máquina.
//
// Lista fechada: só aceita nomes cadastrados em <projeto>/norte-out/segredos.json (quem cadastra é a
// pessoa, com o --cadastrar que ela pede). Destino tem que ficar DENTRO do projeto, sem link simbólico.
// Formulário: 127.0.0.1 + Host exato + Origin exato + senha de uso único na URL + expira em 10 min.
// Gravação: cópia de segurança do arquivo, troca atômica (arquivo temporário + rename), permissão 600.
//
// Uso:
//   node nb-salvar-seguro.js --nome NOME [--projeto DIR]            → abre o formulário (imprime SALVAR_ABRIR <url>)
//   node nb-salvar-seguro.js --cadastrar NOME --rotulo "..." [--formato livre|google-verificacao] [--destino .env]
//   node nb-salvar-seguro.js --listar
// Saídas pra máquina (o Claude lê): SALVAR_ABRIR · SALVO nome=.. destino=.. · ERRO <motivo> · CADASTRADO · LISTA
'use strict';
const http = require('http'), fs = require('fs'), path = require('path'), crypto = require('crypto');

const NOME_OK = /^[A-Z][A-Z0-9_]{1,63}$/;
const FORMATOS = ['livre', 'google-verificacao'];
const EXPIRA_MS = parseInt(process.env.NB_SALVAR_EXPIRA_MS || '600000', 10);

function args(argv) {
  const a = {};
  for (let i = 0; i < argv.length; i++) {
    const k = argv[i];
    if (k.startsWith('--')) { const v = argv[i + 1]; if (v === undefined || v.startsWith('--')) a[k.slice(2)] = true; else { a[k.slice(2)] = v; i++; } }
  }
  return a;
}
function sair(msg, code) { console.log(msg); process.exit(code); }

const A = args(process.argv.slice(2));
const PROJ = fs.realpathSync(path.resolve(A.projeto || process.cwd()));
const CATALOGO = path.join(PROJ, 'norte-out', 'segredos.json');

function lerCatalogo() {
  try {
    const c = JSON.parse(fs.readFileSync(CATALOGO, 'utf8'));
    return Array.isArray(c.segredos) ? c.segredos : [];
  } catch (_) { return []; }
}

// Destino: relativo, dentro do projeto, sem "..", sem link simbólico (nem no arquivo nem na pasta).
function destinoSeguro(rel) {
  if (typeof rel !== 'string' || !rel || path.isAbsolute(rel) || rel.split(/[\\/]/).includes('..')) return null;
  const abs = path.resolve(PROJ, rel);
  if (!abs.startsWith(PROJ + path.sep)) return null;
  let dir;
  try { dir = fs.realpathSync(path.dirname(abs)); } catch (_) { return null; }
  if (!(dir === PROJ || dir.startsWith(PROJ + path.sep))) return null;
  try { if (fs.lstatSync(abs).isSymbolicLink()) return null; } catch (_) { /* ainda não existe: ok */ }
  return abs;
}

function validar(formato, bruto) {
  const v = String(bruto || '').trim();
  if (formato === 'google-verificacao') {
    const m = v.match(/google-site-verification"?\s*content="([^"]+)"/);
    const cod = m ? m[1] : v;
    return /^[A-Za-z0-9_-]{20,100}$/.test(cod) ? cod : '';
  }
  if (!v || v.length > 4096 || /[\r\n]/.test(v)) return '';
  return v;
}

function aspas(v) { return /[\s#"'$`\\]/.test(v) ? '"' + v.replace(/\\/g, '\\\\').replace(/"/g, '\\"') + '"' : v; }

function gravar(abs, nome, valor) {
  const ts = new Date().toISOString().replace(/[-:]/g, '').replace(/\..*/, '');
  let antes = '';
  if (fs.existsSync(abs)) {
    antes = fs.readFileSync(abs, 'utf8');
    fs.copyFileSync(abs, abs + '.bak-' + ts);
    try { fs.chmodSync(abs + '.bak-' + ts, 0o600); } catch (_) { /* Windows: a pasta do usuário protege */ }
  }
  const linha = nome + '=' + aspas(valor);
  const re = new RegExp('^' + nome + '=.*$', 'm');
  const depois = re.test(antes) ? antes.replace(re, () => linha) : antes + (antes && !antes.endsWith('\n') ? '\n' : '') + linha + '\n';
  const tmp = abs + '.tmp-' + process.pid + '-' + crypto.randomBytes(4).toString('hex');
  fs.writeFileSync(tmp, depois, { mode: 0o600 });
  fs.renameSync(tmp, abs);
  try { fs.chmodSync(abs, 0o600); } catch (_) { /* idem */ }
  // confere a escrita (sem imprimir): o OK só sai se o arquivo final tem a linha
  return re.test(fs.readFileSync(abs, 'utf8'));
}

function gitignoraEnv(abs) {
  const gi = path.join(PROJ, '.gitignore');
  if (!fs.existsSync(path.join(PROJ, '.git'))) return true;
  try {
    const t = fs.readFileSync(gi, 'utf8');
    const base = path.basename(abs);
    return t.split(/\r?\n/).some(l => l.trim() === base || l.trim() === '/' + base || l.trim() === '.env*' || l.trim() === '*.env');
  } catch (_) { return false; }
}

// ---------- --listar / --cadastrar ----------
if (A.listar) {
  const l = lerCatalogo();
  sair('LISTA ' + (l.length ? l.map(s => s.nome + '→' + (s.destino || '.env')).join(' · ') : '(vazia)'), 0);
}
if (A.cadastrar) {
  const nome = String(A.cadastrar);
  const formato = A.formato || 'livre';
  const destino = A.destino || '.env';
  const rotulo = typeof A.rotulo === 'string' ? A.rotulo.slice(0, 120) : nome;
  if (!NOME_OK.test(nome)) sair('ERRO nome-invalido (use LETRAS_MAIUSCULAS_E_NUMEROS)', 2);
  if (!FORMATOS.includes(formato)) sair('ERRO formato-invalido (' + FORMATOS.join('|') + ')', 2);
  if (!destinoSeguro(destino)) sair('ERRO destino-fora-do-projeto', 2);
  const l = lerCatalogo().filter(s => s.nome !== nome);
  l.push({ nome, rotulo, formato, destino });
  fs.mkdirSync(path.dirname(CATALOGO), { recursive: true });
  fs.writeFileSync(CATALOGO, JSON.stringify({ segredos: l }, null, 2) + '\n');
  sair('CADASTRADO ' + nome + ' destino=' + destino, 0);
}

// ---------- formulário ----------
const nome = String(A.nome || '');
const item = lerCatalogo().find(s => s.nome === nome);
if (!item) sair('ERRO nome-fora-da-lista (cadastre antes: --cadastrar ' + (NOME_OK.test(nome) ? nome : 'NOME') + ' --rotulo "...")', 2);
const destino = item.destino || '.env';
const ABS = destinoSeguro(destino);
if (!ABS) sair('ERRO destino-fora-do-projeto', 2);
const formato = FORMATOS.includes(item.formato) ? item.formato : 'livre';

const PORT = parseInt(A.porta || process.env.NB_SALVAR_PORT || '8771', 10);
const ACESSO = crypto.randomBytes(24).toString('hex');
const ORIGEM = 'http://127.0.0.1:' + PORT;
const esc = s => String(s).replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));

const dica = formato === 'google-verificacao'
  ? 'No Google Search Console, em "Tag HTML", clique em Copiar e cole a linha inteira aqui.'
  : 'Cole o valor aqui. Ele fica escondido.';
const PAGINA = `<!doctype html><html lang="pt-BR"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>Salvar com segurança — Norte</title>
<style>
 body{background:#0d1117;color:#e6edf3;font:16px/1.55 -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;display:flex;min-height:100vh;align-items:center;justify-content:center;margin:0;padding:20px}
 .card{background:#161b22;border:1px solid #30363d;border-radius:14px;padding:28px;max-width:460px;width:100%}
 h1{font-size:20px;margin:0 0 8px;color:#bef264} p{color:#8b949e;font-size:14px;margin:0 0 14px}
 .onde{background:#0a0f14;border:1px solid #30363d;border-radius:8px;padding:10px 12px;font-size:13px;color:#8b949e;margin-bottom:14px}
 .onde b{color:#e6edf3}
 input[type=password]{width:100%;box-sizing:border-box;padding:12px;background:#0a0f14;color:#d8e8da;border:1px solid #30363d;border-radius:8px;font:14px ui-monospace,Menlo,monospace}
 button{margin-top:18px;width:100%;padding:13px;background:#1f4a2e;color:#a8f0c0;border:1px solid #4caf72;border-radius:10px;font-size:16px;cursor:pointer}
</style></head><body><div class="card">
 <h1>🔒 Salvar com segurança</h1>
 <p>${esc(item.rotulo || nome)}. ${esc(dica)} Não passa pelo chat.</p>
 <div class="onde">Vai ser guardado como <b>${esc(nome)}</b> no arquivo <b>${esc(destino)}</b> deste projeto. Só nesta máquina.</div>
 <form method="POST" action="/s/${ACESSO}" autocomplete="off">
  <input type="password" name="v" placeholder="cole aqui — fica escondido" autocomplete="off" autofocus>
  <button type="submit">Salvar com segurança</button>
 </form>
</div></body></html>`;

function resp(res, code, msg, ok) {
  res.writeHead(code, { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store', 'X-Frame-Options': 'DENY', 'Referrer-Policy': 'same-origin' });
  res.end(`<div style="font:16px system-ui;padding:40px;background:#0d1117;color:${ok ? '#bef264' : '#f85149'};min-height:100vh">${esc(msg)}</div>`);
}

const inicio = Date.now();
let usado = false;
const srv = http.createServer((req, res) => {
  try {
    if (req.headers.host !== '127.0.0.1:' + PORT) return resp(res, 403, 'Endereço não reconhecido.');
    if (Date.now() - inicio > EXPIRA_MS) return resp(res, 410, 'Este formulário expirou. Peça para abrir de novo.');
    const caminho = (req.url || '').split('?')[0];
    if (caminho !== '/s/' + ACESSO || usado) return resp(res, 404, 'Formulário não encontrado (ou já usado).');
    if (req.method === 'GET') {
      res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store', 'X-Frame-Options': 'DENY', 'Referrer-Policy': 'same-origin' });
      return res.end(PAGINA);
    }
    if (req.method !== 'POST') return resp(res, 405, 'Não permitido.');
    const origem = req.headers.origin;
    if (origem !== ORIGEM) return resp(res, 403, 'Pedido vindo de outra página — recusado.');
    const site = req.headers['sec-fetch-site'];
    if (site && site !== 'same-origin') return resp(res, 403, 'Pedido vindo de outra página — recusado.');
    let b = '';
    req.on('data', c => { b += c; if (b.length > 16384) req.destroy(); });
    req.on('end', () => {
      try {
        const valor = validar(formato, new URLSearchParams(b).get('v'));
        b = '';
        if (!valor) return resp(res, 400, formato === 'google-verificacao' ? 'Não reconheci a Tag HTML do Google. Nada foi gravado.' : 'Valor vazio ou com quebra de linha. Nada foi gravado.');
        const ok = gravar(ABS, nome, valor);
        if (!ok) { console.log('ERRO gravacao-nao-confirmada'); return resp(res, 500, 'Não consegui confirmar a gravação. O arquivo anterior tem cópia de segurança.'); }
        usado = true;
        resp(res, 200, '✓ Guardado. Pode fechar esta aba e voltar pra conversa.', true);
        console.log('SALVO nome=' + nome + ' destino=' + destino + (gitignoraEnv(ABS) ? '' : ' AVISO=arquivo-nao-esta-no-gitignore'));
        setTimeout(() => srv.close(() => process.exit(0)), 300);
      } catch (e) {
        console.log('ERRO ' + (e && e.code ? e.code : (e && e.name) || 'erro')); // só o tipo, nunca o valor
        resp(res, 500, 'Erro ao gravar. O arquivo anterior foi preservado.');
      }
    });
  } catch (e) {
    console.log('ERRO ' + ((e && e.name) || 'erro'));
    try { resp(res, 500, 'Erro.'); } catch (_) { /* nada */ }
  }
});
srv.on('error', e => sair('ERRO porta-ocupada-' + (e && e.code), 3));
srv.listen(PORT, '127.0.0.1', () => console.log('SALVAR_ABRIR ' + ORIGEM + '/s/' + ACESSO));
setTimeout(() => { console.log('ERRO expirou-sem-uso'); process.exit(4); }, EXPIRA_MS + 1000).unref();
