'use strict';
// norte-box · troca de conta pela letra. No Terminal do VS Code, a barrinha da caixa termina em 🄰/🄱 (a conta da
// conversa aberta pelo nb-claude). Cmd+clique na letra → lista com as 2 contas → escolhe → confirma → a caixa troca
// ESTA conversa (nb-trocar-conta de-fora): ela fecha quando parar e reabre na outra conta, com o histórico.
// Sem link escondido na letra (link vscode:// faz o VS Code perguntar "abrir?"): o complemento reconhece "▲N … 🄱"
// na linha do terminal. Qual conversa: ~/.norte-box/troca/letra/<sid>.json, anotado pela barrinha.
// Nunca lê nem mostra chave. Ganchos de teste: NB_HOME · NB_TROCA_MOTOR · NB_TROCA_NODE
const fs = require('fs');
const os = require('os');
const path = require('path');
const { execFile, execFileSync } = require('child_process');

const HOME = process.env.NB_HOME || os.homedir();
const TROCA = path.join(HOME, '.norte-box', 'troca');
const LETRA = { A: '🄰', B: '🄱' };
const PADRAO = /▲(\d+)\b.*?(🄰|🄱)/u;

// O motor é o da versão MAIS NOVA da caixa instalada — atualizar a caixa não exige reinstalar o complemento.
function motor() {
  if (process.env.NB_TROCA_MOTOR) return process.env.NB_TROCA_MOTOR;
  const cache = path.join(HOME, '.claude', 'plugins', 'cache', 'norte-box');
  const achados = [];
  try {
    for (const m of fs.readdirSync(cache)) {
      let vs = [];
      try { vs = fs.readdirSync(path.join(cache, m)); } catch (e) { continue; }
      for (const v of vs) {
        const b = /^(\d+)\.(\d+)\.(\d+)/.exec(v);
        const f = path.join(cache, m, v, 'bin', 'nb-trocar-conta');
        if (b && fs.existsSync(f)) achados.push({ f, n: [+b[1], +b[2], +b[3]] });
      }
    }
  } catch (e) { return ''; }
  achados.sort((x, y) => x.n[0] - y.n[0] || x.n[1] - y.n[1] || x.n[2] - y.n[2]);
  return achados.length ? achados[achados.length - 1].f : '';
}

// Roda o motor com o node do próprio VS Code (quem instala pode não ter node no PATH do VS Code).
function rodar(args) {
  const m = motor();
  if (!m) return Promise.resolve({ out: 'NAO|a norte-box não está instalada' });
  const node = process.env.NB_TROCA_NODE || process.execPath;
  const env = Object.assign({}, process.env, { ELECTRON_RUN_AS_NODE: '1' });
  return new Promise((resolve) => {
    execFile(node, [m].concat(args), { timeout: 40000, env }, (err, out) => {
      resolve({ out: String(out || '').trim() });
    });
  });
}

function pai(pid) {
  try {
    return Number(execFileSync('ps', ['-o', 'ppid=', '-p', String(pid)], { encoding: 'utf8', timeout: 3000 }).trim()) || 0;
  } catch (e) { return 0; }
}

function descende(pid, ancestral) {
  for (let i = 0; i < 15 && pid > 1; i++) {
    if (pid === ancestral) return true;
    pid = pai(pid);
  }
  return false;
}

function vivo(pid) { try { process.kill(pid, 0); return true; } catch (e) { return false; } }

// Mesmo número em 2 terminais → vale o que roda NESTE terminal; número repetido sem nenhum deste → não adivinha.
function acharConversa(n, terminalPid) {
  const dir = path.join(TROCA, 'letra');
  let cands = [];
  try {
    for (const f of fs.readdirSync(dir)) {
      if (!f.endsWith('.json') || f.startsWith('.')) continue;
      try {
        const d = JSON.parse(fs.readFileSync(path.join(dir, f), 'utf8'));
        if (String(d.n) === String(n) && /^[0-9a-fA-F-]{8,64}$/.test(d.sid || '') && d.pai && vivo(Number(d.pai))) cands.push(d);
      } catch (e) { /* gravando agora */ }
    }
  } catch (e) { return null; }
  if (terminalPid) {
    const deste = cands.filter((d) => descende(Number(d.pai), terminalPid));
    if (deste.length) cands = deste;
    else if (cands.length > 1) return null;
  }
  cands.sort((a, b) => (b.ts || 0) - (a.ts || 0));
  return cands[0] || null;
}

async function trocar(vscode, d) {
  const n = d.n, de = d.de === 'B' ? 'B' : 'A';
  if (fs.existsSync(path.join(TROCA, 'letra-off'))) return 'desligado';
  const r = await rodar(['json']);
  let c = null;
  try { c = JSON.parse(r.out); } catch (e) { /* sem medição */ }
  const item = (k) => {
    const f = c && c[k];
    const atual = k === de;
    if (!f || !f.chave) return { label: LETRA[k] + ' ' + k, description: atual ? 'atual' : 'sem chave guardada', conta: k, pode: false, atual };
    const cheia = typeof f.pct === 'number' && f.pct >= (c.quase || 95);
    const pct = typeof f.pct === 'number' ? f.pct + '%' : '?';
    const desc = atual ? 'atual' : (f.erro || (cheia ? (f.volta || 'cheia') : (typeof f.pct === 'number' ? '' : 'sem medição')));
    return { label: LETRA[k] + ' ' + k + ' · ' + pct, description: desc, conta: k,
      pode: !atual && !cheia && !f.erro && typeof f.pct === 'number', atual };
  };
  const esc = await vscode.window.showQuickPick([item('A'), item('B')], { placeHolder: 'Trocar a conta da conversa ▲' + n });
  if (!esc) return 'cancelou';
  if (!esc.pode) {
    vscode.window.setStatusBarMessage(esc.atual ? 'Já está na ' + de : 'Não dá pra trocar pra ' + esc.conta + ' agora: ' + (esc.description || ''), 5000);
    return 'nao-pode';
  }
  const ok = await vscode.window.showQuickPick([{ label: '✓ Trocar', sim: true }, { label: '✗ Cancelar', sim: false }],
    { placeHolder: 'Trocar ▲' + n + ' para ' + esc.conta + '? (fecha quando parar e reabre com o histórico)' });
  if (!ok || !ok.sim) return 'cancelou';
  vscode.window.setStatusBarMessage('Trocando para ' + esc.conta + '…', 6000);
  const t = await rodar(['de-fora', d.sid, esc.conta]);
  const ult = t.out.split('\n').pop() || '';
  if (ult.startsWith('OK|')) return 'trocou-' + esc.conta;
  vscode.window.showWarningMessage('Não trocou: ' + (ult.split('|')[1] || 'erro'));
  return 'falhou';
}

function linkProvider(vscode) {
  return {
    async provideTerminalLinks(ctx) {
      const m = PADRAO.exec(ctx.line || '');
      if (!m) return [];
      let tpid = 0;
      try { tpid = (await ctx.terminal.processId) || 0; } catch (e) { /* sem pid */ }
      const ini = m.index + m[0].length - m[2].length;
      return [{ startIndex: ini, length: m[2].length, tooltip: 'Trocar a conta desta conversa', n: m[1], tpid }];
    },
    async handleTerminalLink(link) {
      const d = acharConversa(link.n, link.tpid);
      if (!d) { vscode.window.setStatusBarMessage('Não achei esta conversa', 4000); return 'sem-conversa'; }
      return trocar(vscode, d);
    },
  };
}

function activate(context) {
  const vscode = require('vscode');
  context.subscriptions.push(vscode.window.registerTerminalLinkProvider(linkProvider(vscode)));
}

module.exports = { activate, deactivate() {}, trocar, linkProvider, acharConversa, motor, PADRAO };
