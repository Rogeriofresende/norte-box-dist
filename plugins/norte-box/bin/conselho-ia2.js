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
// anonimizarVozes — esconde a MARCA/papel de cada voz e EMBARALHA a ordem, pra o juiz
// decidir pelo argumento, não pelo crachá (corta o viés de confirmação num conselho de 1 pessoa).
// Contrato: as vozes chegam separadas por linha em branco; tira o rótulo (o "🔨 Construtor: "
// / "🌐 Voz de fora — Gemini: " antes do primeiro ':') e renomeia pra Voz A/B/C/D embaralhadas.
function anonimizarVozes(vozes) {
  const partes = String(vozes).split(/\n\s*\n/).map(s => s.trim()).filter(Boolean);
  if (partes.length < 2) return { texto: vozes, cego: false }; // 1 voz só: não há marca a esconder
  const semRotulo = partes.map(p => p.replace(/^[^\n:]{1,80}?:\s*/, '').trim());
  for (let i = semRotulo.length - 1; i > 0; i--) { // Fisher-Yates
    const j = Math.floor(Math.random() * (i + 1));
    [semRotulo[i], semRotulo[j]] = [semRotulo[j], semRotulo[i]];
  }
  const letras = 'ABCDEFGH';
  const texto = semRotulo.map((v, i) => `Voz ${letras[i] || (i + 1)}: ${v}`).join('\n\n');
  return { texto, cego: true };
}

function promptJuiz(q, vozes, cego) {
  const abertura = cego
    ? `Você é o JUIZ DE FORA (de OUTRA marca de IA) de um conselho sobre: "${q}". As vozes abaixo estão ANÔNIMAS e embaralhadas — você NÃO sabe qual IA nem qual papel escreveu cada uma. Julgue SÓ pelo argumento, jamais pelo crachá.`
    : `Você é o JUIZ DE FORA (de OUTRA marca de IA) de um conselho sobre: "${q}". As vozes disseram:`;
  return `${abertura}\n${vozes}\nComo juiz independente e cego, responda em pt-BR, curto: (1) veredito em 1 linha; (2) onde as vozes discordam; (3) o menor primeiro passo concreto.`;
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
    let prompt;
    if (modo === 'juiz') {
      // kill-switch: NORTE_CONSELHO_JUIZ_CEGO=0 volta ao juiz que vê as marcas.
      const cegoOn = process.env.NORTE_CONSELHO_JUIZ_CEGO !== '0';
      const anon = cegoOn ? anonimizarVozes(vozes) : { texto: vozes, cego: false };
      if (process.env.NORTE_CONSELHO_DEBUG) { // prova o antes/depois sem vazar no stdout
        process.stderr.write('--- vozes ANÔNIMAS que o juiz vai receber (cego=' + anon.cego + ') ---\n' + anon.texto + '\n---\n');
      }
      prompt = promptJuiz(q, anon.texto, anon.cego);
    } else {
      prompt = promptVoz(q);
    }
    console.log(await call(cfg, prompt));
  } catch (e) { console.log('IA2_ERRO: ' + (e && e.message || 'falha')); }
})();
