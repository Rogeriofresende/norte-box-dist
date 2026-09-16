#!/usr/bin/env node
// nb-conselho-conectar-web.js — a TELINHA de "conectar sua outra IA".
// Sobe um formulário em 127.0.0.1 (SÓ a máquina do usuário). Ele escolhe ChatGPT/Gemini e cola a
// chave num campo escondido → vai direto pro arquivo trancado ~/.norte-box/conselho-ia2.json (600).
// A chave NUNCA passa pelo chat, NUNCA é impressa, NUNCA sai da máquina (loopback).
const http = require('http'), fs = require('fs'), os = require('os'), path = require('path');

const PORT = parseInt(process.env.NB_CONECTAR_PORT || '8770', 10);
const F = path.join(os.homedir(), '.norte-box', 'conselho-ia2.json');
fs.mkdirSync(path.dirname(F), { recursive: true });

const FORM = `<!doctype html><html lang="pt-BR"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>Conectar sua outra IA — Norte</title>
<style>
 body{background:#0d1117;color:#e6edf3;font:16px/1.55 -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;display:flex;min-height:100vh;align-items:center;justify-content:center;margin:0;padding:20px}
 .card{background:#161b22;border:1px solid #30363d;border-radius:14px;padding:28px;max-width:440px;width:100%}
 h1{font-size:20px;margin:0 0 8px;color:#bef264}
 p{color:#8b949e;font-size:14px;margin:0 0 18px}
 label.big{display:block;font-size:14px;margin:16px 0 8px;color:#e6edf3}
 .row{display:flex;gap:16px;margin-bottom:6px}
 .opt{flex:1;border:1px solid #30363d;border-radius:10px;padding:12px;cursor:pointer;text-align:center;font-size:15px}
 .opt input{margin-right:6px}
 input[type=password]{width:100%;padding:12px;background:#0a0f14;color:#d8e8da;border:1px solid #30363d;border-radius:8px;font:14px ui-monospace,Menlo,monospace}
 .hint{color:#8b949e;font-size:12px;margin-top:6px}
 button{margin-top:20px;width:100%;padding:13px;background:#1f4a2e;color:#a8f0c0;border:1px solid #4caf72;border-radius:10px;font-size:16px;cursor:pointer}
 button:hover{background:#245a37}
</style></head><body>
 <div class="card">
  <h1>Conectar sua outra IA</h1>
  <p>Assim o conselho ganha uma voz e um juiz de <b>outra marca</b> — independência de verdade. A chave fica só na sua máquina; a Norte não vê nem guarda nada.</p>
  <form method="POST" action="/salvar" autocomplete="off">
   <label class="big">Qual IA você vai conectar?</label>
   <div class="row">
    <label class="opt"><input type="radio" name="provider" value="gemini" checked>Gemini</label>
    <label class="opt"><input type="radio" name="provider" value="openai">ChatGPT</label>
   </div>
   <label class="big">Cole a chave dela</label>
   <input type="password" name="key" placeholder="cole aqui — fica escondido" autocomplete="off" autofocus>
   <div class="hint">A chave não aparece na tela nem no chat. Vai direto pro cofre da sua máquina.</div>
   <button type="submit">Conectar</button>
  </form>
 </div>
</body></html>`;

function send(res, code, html) { res.writeHead(code, { 'Content-Type': 'text/html; charset=utf-8' }); res.end(html); }

const srv = http.createServer((req, res) => {
  if (req.method === 'GET' && req.url === '/') return send(res, 200, FORM);
  if (req.method === 'POST' && req.url === '/salvar') {
    let b = '';
    req.on('data', c => { b += c; if (b.length > 8000) req.destroy(); });
    req.on('end', () => {
      const p = new URLSearchParams(b);
      const provider = p.get('provider'), key = (p.get('key') || '').trim();
      if (!['gemini', 'openai'].includes(provider) || !key) {
        return send(res, 400, '<p style="font:16px system-ui;padding:40px;color:#f85149">Faltou escolher a IA ou colar a chave. <a href="/">voltar</a></p>');
      }
      fs.writeFileSync(F, JSON.stringify({ provider, key }), { mode: 0o600 });
      fs.chmodSync(F, 0o600);
      const nome = provider === 'openai' ? 'ChatGPT' : 'Gemini';
      send(res, 200, `<div style="font:16px system-ui;padding:40px;background:#0d1117;color:#e6edf3;min-height:100vh"><h2 style="color:#bef264">✓ ${nome} conectada!</h2><p>Pode fechar esta aba. Da próxima vez que você usar o /conselho, ela entra como uma voz e um juiz de fora.</p></div>`);
      console.log('IA2_CONECTADA provider=' + provider); // NUNCA a chave
      setTimeout(() => srv.close(() => process.exit(0)), 300);
    });
    return;
  }
  send(res, 404, 'nao encontrado');
});
srv.listen(PORT, '127.0.0.1', () => console.log('CONECTAR_ABRIR http://127.0.0.1:' + PORT));
