#!/usr/bin/env node
// conselho-ia2.js — motor do Nível 2: chama a OUTRA IA do usuário (marca diferente).
//   node conselho-ia2.js voz  "<decisão>"
//   node conselho-ia2.js juiz "<decisão>" "<texto das vozes>"
// Lê a chave guardada por nb-conselho-conectar.sh. NUNCA imprime a chave.
// Suporta: gemini (provado) e openai/ChatGPT (mesmo formato, chave Bearer).
const fs = require('fs'), os = require('os'), path = require('path');

const F = path.join(os.homedir(), '.norte-box', 'conselho-ia2.json');
const modo = process.argv[2] || 'voz';
const q = process.argv[3] || '';
const vozes = process.argv[4] || '';

if (!fs.existsSync(F)) { console.log('IA2_NAO_CONECTADA'); process.exit(0); }
const cfg = JSON.parse(fs.readFileSync(F, 'utf8'));

function promptVoz(q) {
  return `Você é uma voz INDEPENDENTE num conselho sobre a decisão: "${q}". Você é de OUTRA IA (marca diferente do Claude do usuário) — traga um ângulo que um só modelo não veria e discorde com franqueza onde fizer sentido. Responda 2-3 linhas, pt-BR, começando pelo seu veredito.`;
}
function promptJuiz(q, vozes) {
  return `Você é o JUIZ DE FORA (de OUTRA marca de IA) de um conselho sobre: "${q}". As vozes disseram:\n${vozes}\nComo juiz independente e cego, responda em pt-BR, curto: (1) veredito em 1 linha; (2) onde as vozes discordam; (3) o menor primeiro passo concreto. Não puxe pra nenhuma voz por ser de tal marca.`;
}

async function call(cfg, prompt) {
  if (cfg.provider === 'gemini') {
    const model = process.env.NORTE_IA2_MODEL || 'gemini-flash-lite-latest';
    const url = `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${cfg.key}`;
    const r = await fetch(url, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ contents: [{ role: 'user', parts: [{ text: prompt }] }] }) });
    if (!r.ok) throw new Error('HTTP ' + r.status);
    const j = await r.json();
    return (((j.candidates || [])[0] || {}).content || {}).parts.map(p => p.text).join('').trim();
  }
  if (cfg.provider === 'openai') {
    const model = process.env.NORTE_IA2_MODEL || 'gpt-4o-mini';
    const r = await fetch('https://api.openai.com/v1/chat/completions', { method: 'POST', headers: { 'Content-Type': 'application/json', 'Authorization': 'Bearer ' + cfg.key }, body: JSON.stringify({ model, messages: [{ role: 'user', content: prompt }] }) });
    if (!r.ok) throw new Error('HTTP ' + r.status);
    const j = await r.json();
    return (((j.choices || [])[0] || {}).message || {}).content.trim();
  }
  throw new Error('provider desconhecido: ' + cfg.provider);
}

(async () => {
  try {
    const prompt = modo === 'juiz' ? promptJuiz(q, vozes) : promptVoz(q);
    console.log(await call(cfg, prompt));
  } catch (e) { console.log('IA2_ERRO: ' + (e && e.message || 'falha')); }
})();
