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
 .row{display:flex;gap:14px;margin-bottom:8px}
 .opt{flex:1;border:1.5px solid #30363d;border-radius:12px;padding:16px 10px;cursor:pointer;text-align:center;display:flex;flex-direction:column;align-items:center;gap:9px;background:#0a0f14;transition:all .15s;position:relative}
 .opt:hover{border-color:#4a5568}
 .opt svg{width:34px;height:34px;display:block}
 .opt .nome{font-size:15px;font-weight:600;color:#e6edf3}
 .opt input{position:absolute;opacity:0;width:0;height:0;pointer-events:none}
 .opt:has(input:checked){border-color:#bef264;background:#131b0e;box-shadow:0 0 0 1px #bef264}
 .opt:has(input:checked)::after{content:'✓';position:absolute;top:7px;right:11px;color:#bef264;font-weight:700;font-size:14px}
 .opt.dim{opacity:.5}
 .vaiconectar{font-size:13px;color:#8b949e;margin:2px 0 4px;text-align:center}
 .vaiconectar b{color:#bef264}
 .col{flex:1;display:flex;flex-direction:column}
 .comopegar{display:block;text-align:center;margin-top:7px;font-size:11.5px;color:#8b949e;text-decoration:none;line-height:1.35}
 .comopegar:hover{color:#bef264;text-decoration:underline}
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
    <div class="col">
    <label class="opt" id="opt-gemini">
     <input type="radio" name="provider" value="gemini" checked>
     <svg viewBox="0 0 24 24" aria-hidden="true"><defs><linearGradient id="gm" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#4285F4"/><stop offset=".5" stop-color="#9b72cb"/><stop offset="1" stop-color="#d96570"/></linearGradient></defs><path fill="url(#gm)" d="M12 2c.5 5.2 3.6 8.3 8.5 8.5-5 .2-8 3.3-8.5 8.5-.5-5.2-3.6-8.3-8.5-8.5 4.9-.2 8-3.3 8.5-8.5z"/></svg>
     <span class="nome">Gemini</span>
    </label>
    <a class="comopegar" href="https://aistudio.google.com/apikey" target="_blank" rel="noopener">não tem a chave? veja como pegar ↗</a>
    </div>
    <div class="col">
    <label class="opt" id="opt-openai">
     <input type="radio" name="provider" value="openai">
     <svg viewBox="0 0 24 24" aria-hidden="true" fill="none" stroke="#19c37d" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M6.5 5.5h11a2 2 0 0 1 2 2v6a2 2 0 0 1-2 2H12l-4 3.5V15.5H6.5a2 2 0 0 1-2-2v-6a2 2 0 0 1 2-2z"/><path d="M12 8.2l.9 1.9 1.9.9-1.9.9-.9 1.9-.9-1.9-1.9-.9 1.9-.9z" fill="#19c37d" stroke="none"/></svg>
     <span class="nome">ChatGPT</span>
    </label>
    <a class="comopegar" href="https://platform.openai.com/api-keys" target="_blank" rel="noopener">não tem a chave? veja como pegar ↗</a>
    </div>
   </div>
   <p class="vaiconectar">Vai conectar: <b id="qual">Gemini</b></p>
   <label class="big">Cole a chave dela</label>
   <input type="password" name="key" placeholder="cole aqui — fica escondido" autocomplete="off" autofocus>
   <div class="hint">A chave não aparece na tela nem no chat. Vai direto pro cofre da sua máquina.</div>
   <button type="submit">Conectar</button>
  </form>
 </div>
 <script>
  (function(){
   var qual=document.getElementById('qual');
   var og=document.getElementById('opt-gemini'), oo=document.getElementById('opt-openai');
   function upd(){
    var sel=document.querySelector('input[name=provider]:checked');
    var isG=sel&&sel.value==='gemini';
    if(qual) qual.textContent=isG?'Gemini':'ChatGPT';
    if(og) og.classList.toggle('dim',!isG);
    if(oo) oo.classList.toggle('dim',isG);
   }
   document.querySelectorAll('input[name=provider]').forEach(function(r){r.addEventListener('change',upd)});
   upd();
  })();
 </script>
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
