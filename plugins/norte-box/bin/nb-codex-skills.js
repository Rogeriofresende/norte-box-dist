#!/usr/bin/env node
// nb-codex-skills.js — gera codex-skills/ (a caixa no Codex) a partir de commands/*.md + skills/*/SKILL.md.
//
// Por que existe (NRT-_995031, 05/10): o Codex instala a caixa pelo mesmo catálogo, mas sozinho só
// converte 8 dos 38 comandos (pula os que usam $ARGUMENTS e os longos) e deixa ${CLAUDE_PLUGIN_ROOT}
// literal no texto — no shell do Codex essa variável não existe, então nenhum script é achado.
// Aqui a gente converte TUDO com as duas trocas, e o .codex-plugin/plugin.json aponta pra cá.
// O Claude Code ignora .codex-plugin/ e codex-skills/ → zero mudança pra quem usa Claude.
//
// uso: node bin/nb-codex-skills.js           (regera codex-skills/)
//      node bin/nb-codex-skills.js --check   (exit 1 se codex-skills/ estiver desatualizado)
'use strict';
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const OUT = path.join(ROOT, 'codex-skills');
const CHECK = process.argv.includes('--check');

// Raiz da caixa no Codex = versão mais nova no cache de plugins do Codex. No Claude (e nos ganchos do
// Codex, que exportam CLAUDE_PLUGIN_ROOT) a variável vem preenchida e vence.
const RAIZ = '${CLAUDE_PLUGIN_ROOT:-$(ls -d "${CODEX_HOME:-$HOME/.codex}"/plugins/cache/norte-box/norte/*/ 2>/dev/null | sort -V | tail -1)}';

function trocarRaiz(txt) {
  return txt
    .replace(/\$\{CLAUDE_PLUGIN_ROOT:-\}/g, RAIZ)
    .replace(/\$\{CLAUDE_PLUGIN_ROOT\}/g, RAIZ)
    .replace(/\$CLAUDE_PLUGIN_ROOT(?![A-Za-z0-9_])/g, RAIZ);
}

function separar(md) {
  const m = md.match(/^---\n([\s\S]*?)\n---\n?([\s\S]*)$/);
  if (!m) return { fm: {}, corpo: md };
  const fm = {};
  for (const linha of m[1].split('\n')) {
    const k = linha.match(/^([A-Za-z0-9_-]+):\s*(.*)$/);
    if (k) fm[k[1]] = k[2].replace(/^"(.*)"$/, '$1');
  }
  return { fm, corpo: m[2] };
}

const aspas = (s) => JSON.stringify(String(s || ''));

const AVISO_CODEX = [
  '> **No Codex:** onde este texto disser `/norte:<nome>`, a pessoa digita `$norte:<nome>` (ou pede em português).',
  '> Os comandos de terminal abaixo já acham a pasta da caixa sozinhos — rode-os como estão.',
].join('\n');

function skillDeComando(nome, md) {
  const { fm, corpo } = separar(md);
  const usaArgs = /\$ARGUMENTS/.test(corpo);
  let texto = trocarRaiz(corpo).replace(/\$ARGUMENTS/g, '<ARGUMENTOS>');
  const nota = usaArgs
    ? '\n> `<ARGUMENTOS>` = o que a pessoa escreveu junto com o pedido (pode ser vazio).\n'
    : '';
  return `---\nname: ${aspas(nome)}\ndescription: ${aspas((fm.description || nome) + ` (comando /norte:${nome})`)}\n---\n\n${AVISO_CODEX}\n${nota}\n${texto.trimStart()}`;
}

function skillDeSkill(md) {
  const { fm, corpo } = separar(md);
  const cab = md.match(/^---\n[\s\S]*?\n---\n?/);
  const head = cab ? cab[0] : `---\nname: ${aspas(fm.name)}\n---\n`;
  return `${head}\n${AVISO_CODEX}\n\n${trocarRaiz(corpo).trimStart()}`;
}

function gerar() {
  const arquivos = new Map(); // caminho relativo → conteúdo
  const skillsDir = path.join(ROOT, 'skills');
  const nomesSkill = new Set();
  for (const d of fs.readdirSync(skillsDir).sort()) {
    const f = path.join(skillsDir, d, 'SKILL.md');
    if (!fs.existsSync(f)) continue;
    nomesSkill.add(d);
    arquivos.set(path.join(d, 'SKILL.md'), skillDeSkill(fs.readFileSync(f, 'utf8')));
  }
  const cmdDir = path.join(ROOT, 'commands');
  for (const f of fs.readdirSync(cmdDir).filter((x) => x.endsWith('.md')).sort()) {
    const nome = f.replace(/\.md$/, '');
    if (nomesSkill.has(nome)) continue; // a skill de mesmo nome já cobre (ex.: vitrine)
    arquivos.set(path.join(nome, 'SKILL.md'), skillDeComando(nome, fs.readFileSync(path.join(cmdDir, f), 'utf8')));
  }
  return arquivos;
}

function lerAtual() {
  const atual = new Map();
  if (!fs.existsSync(OUT)) return atual;
  for (const d of fs.readdirSync(OUT)) {
    const f = path.join(OUT, d, 'SKILL.md');
    if (fs.existsSync(f)) atual.set(path.join(d, 'SKILL.md'), fs.readFileSync(f, 'utf8'));
  }
  return atual;
}

const novo = gerar();
if (CHECK) {
  const atual = lerAtual();
  const dif = [...new Set([...novo.keys(), ...atual.keys()])].filter((k) => novo.get(k) !== atual.get(k));
  if (dif.length) {
    console.error(`codex-skills/ DESATUALIZADO (${dif.length}): ${dif.slice(0, 8).join(', ')} — rode: node bin/nb-codex-skills.js`);
    process.exit(1);
  }
  console.log(`codex-skills/ em dia (${novo.size} skills)`);
  process.exit(0);
}
fs.rmSync(OUT, { recursive: true, force: true });
for (const [rel, txt] of novo) {
  fs.mkdirSync(path.join(OUT, path.dirname(rel)), { recursive: true });
  fs.writeFileSync(path.join(OUT, rel), txt);
}
console.log(`codex-skills/ gerado: ${novo.size} skills`);
