#!/usr/bin/env node
// nb-post.js — POST JSON honesto e legivel pro coletor da Norte (zero dependencia).
//
// O QUE FAZ: um POST HTTPS normal com o stdlib do node (http/https), do jeito mais simples
// possivel. Usado pelo /norte-box:convite, /norte-box:consent e pelo MEDIDOR de telemetria
// (que manda SO numeros, ver hooks/telemetry-emit.sh — Modelo A: numeros por padrao).
//
// TRANSPARENTE POR DESIGN: se voce quiser ver EXATAMENTE o que este transporte manda, rode com
// a flag --show (ou env NB_POST_SHOW=1) e ele imprime o metodo, a URL, os headers (com o token
// mascarado pra nao vazar no terminal) e o corpo — ANTES de enviar. Nada e escondido: o que
// aparece no --show e o que vai na rede. Um transporte honesto mostra o que faz quando perguntado.
//
// Historia (por que node e nao curl): a maquina ENDURECIDA do proprio CEO tem uma deny-list que
// bloqueia todo `curl` de escrita. Pra ELA, o transporte precisava ser `node`. Pra distribuicao a
// usuarios normais isso e so um detalhe de portabilidade — nao ha nada a "driblar": este arquivo
// e um cliente HTTP comum, do tamanho de um exemplo de manual, e mostra o payload com --show.
//
// Uso:
//   node nb-post.js <url> [json-body] [bearer-token]
//     <url>          endereco COMPLETO do endpoint (ex: https://host/invite/validate)
//     [json-body]    corpo JSON ja serializado (default "{}"). Se '-' le do STDIN.
//     [bearer-token] opcional; se dado, manda header Authorization: Bearer <token>.
//   Flags: --show (ou NB_POST_SHOW=1) imprime metodo/URL/headers(token mascarado)/corpo e ENVIA.
//          --dry-run (ou NB_POST_DRY_RUN=1) imprime o mesmo e NAO envia (so pra auditar).
//
// Saida (stdout): o CORPO da resposta do servidor, cru (o comando .md parseia com jq).
//   Com --show/--dry-run, o bloco "[nb-post] vai enviar:" vai pro STDERR (nao suja o stdout que
//   o jq consome). O token no header aparece MASCARADO (Bearer nbi_1234…, so o prefixo).
// Exit code: 0 se teve resposta HTTP (qualquer status — o .md decide pelo corpo); 1 se a
//   rede/timeout falhou (sem resposta), ou se URL invalida. --dry-run sai 0 sem enviar.
//
// Timeout ~8s.
'use strict';

// --- parse dos args: separa flags do posicional (--show / --dry-run em qualquer posicao) ---
const argv = process.argv.slice(2);
let SHOW = process.env.NB_POST_SHOW === '1';
let DRY = process.env.NB_POST_DRY_RUN === '1';
const pos = [];
for (const a of argv) {
  if (a === '--show') { SHOW = true; continue; }
  if (a === '--dry-run') { DRY = true; SHOW = true; continue; }
  pos.push(a);
}
const url = pos[0];
let body = pos[1];
const token = pos[2];

if (!url) { process.stderr.write('nb-post: falta a URL\n'); process.exit(1); }

// mascara o token pro --show: mostra so o prefixo (ex "nbi_1234…"), nunca o valor inteiro.
function maskToken(t) {
  if (!t) return '';
  const s = String(t);
  if (s.length <= 8) return s.slice(0, 2) + '…';
  return s.slice(0, 8) + '…';
}

function showPlan(u, headers, payload) {
  // imprime no STDERR (o stdout e reservado pro corpo da resposta que o jq consome).
  const h = Object.assign({}, headers);
  if (h['Authorization']) h['Authorization'] = 'Bearer ' + maskToken(token);
  const lines = [
    '[nb-post] vai enviar:',
    '  metodo : POST',
    '  url    : ' + u.href,
    '  headers: ' + JSON.stringify(h),
    '  corpo  : ' + payload,
  ];
  process.stderr.write(lines.join('\n') + '\n');
}

function run(payload) {
  let mod, u;
  try { u = new URL(url); } catch (e) { process.stderr.write('nb-post: URL invalida\n'); process.exit(1); }
  mod = u.protocol === 'http:' ? require('http') : require('https');

  const data = Buffer.from(payload, 'utf8');
  const headers = { 'Content-Type': 'application/json', 'Content-Length': data.length };
  if (token) headers['Authorization'] = 'Bearer ' + token;

  if (SHOW) showPlan(u, headers, payload);
  if (DRY) { process.exit(0); }  // --dry-run: mostrou o plano, nao envia.

  const req = mod.request(u, { method: 'POST', headers, timeout: 8000 }, (res) => {
    let out = '';
    res.setEncoding('utf8');
    res.on('data', (c) => { out += c; });
    res.on('end', () => { process.stdout.write(out); process.exit(0); });
  });
  // Erro de rede OU timeout = sem resposta -> exit 1 (o .md trata como "coletor nao respondeu").
  req.on('error', () => { process.stderr.write('nb-post: falha de rede\n'); process.exit(1); });
  req.on('timeout', () => { req.destroy(); process.stderr.write('nb-post: timeout\n'); process.exit(1); });
  req.write(data);
  req.end();
}

if (body === '-') {
  let s = '';
  process.stdin.setEncoding('utf8');
  process.stdin.on('data', (c) => { s += c; });
  process.stdin.on('end', () => run(s || '{}'));
} else {
  run(body || '{}');
}
