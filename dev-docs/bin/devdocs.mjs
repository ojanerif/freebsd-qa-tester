#!/usr/bin/env node
// dev-docs v4.0 — Local Shell CLI
// Usage: node dev-docs/bin/devdocs.mjs <command> [args]
// No global install required.

import { readFileSync, writeFileSync, existsSync, mkdirSync, readdirSync, statSync } from 'node:fs';
import { resolve, join, relative, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { execSync, spawnSync } from 'node:child_process';
import { createInterface } from 'node:readline';

const __dirname = dirname(fileURLToPath(import.meta.url));
const DEVDOCS   = resolve(__dirname, '..');
const ROOT      = resolve(DEVDOCS, '..');
const LOCAL_DIR = join(DEVDOCS, '.local');
const USER_FILE = join(LOCAL_DIR, 'user.json');
const LOG_FILE  = join(DEVDOCS, 'team', 'activity-log.jsonl');
const INDEX_FILE= join(DEVDOCS, 'index.jsonl');
const SKILLS_FILE = join(DEVDOCS, 'skills', 'skills.jsonl');
const SESSIONS_DIR = join(DEVDOCS, 'sessions');
const CTX_DIR   = join(DEVDOCS, 'context-packs');

const C = { reset:'\x1b[0m', bold:'\x1b[1m', cyan:'\x1b[36m', green:'\x1b[32m',
            yellow:'\x1b[33m', red:'\x1b[31m', dim:'\x1b[2m' };
const ok   = s => console.log(`${C.green}✓${C.reset} ${s}`);
const warn = s => console.log(`${C.yellow}⚠${C.reset} ${s}`);
const err  = s => console.log(`${C.red}✗${C.reset} ${s}`);
const info = s => console.log(`${C.dim}→${C.reset} ${s}`);

// ── Readline helper ────────────────────────────────────────────────────────

function ask(prompt, def = '') {
  const rl = createInterface({ input: process.stdin, output: process.stdout });
  return new Promise(res => {
    rl.question(`${C.bold}${prompt}${def ? ` [${def}]` : ''}${C.reset}: `, ans => {
      rl.close(); res(ans.trim() || def);
    });
  });
}

// ── User ───────────────────────────────────────────────────────────────────

function getUser() {
  if (existsSync(USER_FILE)) return JSON.parse(readFileSync(USER_FILE, 'utf8'));
  let name = '', email = '';
  try { name  = execSync('git config user.name',  { cwd: ROOT }).toString().trim(); } catch {}
  try { email = execSync('git config user.email', { cwd: ROOT }).toString().trim(); } catch {}
  return { user_id: email.split('@')[0] || 'unknown', display_name: name, email, role: 'Owner', suggested: true };
}

async function cmdWhoami(interactive = true) {
  const u = getUser();
  if (u.suggested && interactive) {
    console.log(`\n${C.bold}First run — confirm your identity${C.reset}`);
    u.display_name = await ask('Display name', u.display_name);
    u.email        = await ask('Email', u.email);
    u.user_id      = await ask('User ID', u.user_id);
    u.role         = await ask('Role', u.role);
    delete u.suggested;
    if (!existsSync(LOCAL_DIR)) mkdirSync(LOCAL_DIR, { recursive: true });
    writeFileSync(USER_FILE, JSON.stringify(u, null, 2), 'utf8');
    ok(`Identity saved to dev-docs/.local/user.json (gitignored)`);
  } else {
    console.log(`\n${C.bold}Active user${C.reset}`);
    console.log(`  ID    : ${u.user_id}`);
    console.log(`  Name  : ${u.display_name}`);
    console.log(`  Email : ${u.email}`);
    console.log(`  Role  : ${u.role}\n`);
  }
  return u;
}

// ── Log ────────────────────────────────────────────────────────────────────

function logActivity(event, extra = {}) {
  const u = getUser();
  const entry = { event, user_id: u.user_id, author: u.display_name,
                  timestamp: new Date().toISOString(), ...extra };
  try {
    mkdirSync(dirname(LOG_FILE), { recursive: true });
    writeFileSync(LOG_FILE, JSON.stringify(entry) + '\n', { flag: 'a' });
  } catch {}
}

// ── Index ──────────────────────────────────────────────────────────────────

function readIndex() {
  if (!existsSync(INDEX_FILE)) return [];
  return readFileSync(INDEX_FILE, 'utf8').trim().split('\n')
    .filter(Boolean).map(l => { try { return JSON.parse(l); } catch { return null; } }).filter(Boolean);
}

function readSkills() {
  if (!existsSync(SKILLS_FILE)) return [];
  return readFileSync(SKILLS_FILE, 'utf8').trim().split('\n')
    .filter(Boolean).map(l => { try { return JSON.parse(l); } catch { return null; } }).filter(Boolean);
}

// ── Commands ───────────────────────────────────────────────────────────────

function cmdDoctor() {
  console.log(`\n${C.bold}dev-docs v4.0 — Doctor${C.reset}\n`);
  const checks = [
    ['AI-INSTRUCTIONS.md', join(DEVDOCS, 'AI-INSTRUCTIONS.md')],
    ['index.jsonl',        INDEX_FILE],
    ['project.memory.json',join(DEVDOCS, 'project.memory.json')],
    ['skills/skills.jsonl',SKILLS_FILE],
    ['team/users.registry.json', join(DEVDOCS, 'team', 'users.registry.json')],
    ['dashboard/server.mjs', join(DEVDOCS, 'dashboard', 'server.mjs')],
    ['bin/devdocs.mjs',    join(DEVDOCS, 'bin', 'devdocs.mjs')],
    ['CONSTITUTION.md',    join(DEVDOCS, 'CONSTITUTION.md')],
    ['.gitignore rules',   join(ROOT, '.gitignore')],
  ];
  let pass = 0;
  checks.forEach(([label, path]) => {
    if (existsSync(path)) { ok(label); pass++; }
    else err(`Missing: ${label}`);
  });
  // Check gitignore
  try {
    const gi = readFileSync(join(ROOT, '.gitignore'), 'utf8');
    ['.local/', '.backups/', '.token'].forEach(r => {
      if (gi.includes(r)) ok(`.gitignore covers ${r}`);
      else warn(`.gitignore missing rule for ${r}`);
    });
  } catch {}
  const u = getUser();
  if (!u.suggested) ok(`Local user identity: ${u.display_name}`);
  else warn('No local user identity — run: node dev-docs/bin/devdocs.mjs whoami');
  console.log(`\n${pass}/${checks.length} checks passed.\n`);
}

function cmdSkillsList() {
  const skills = readSkills();
  if (!skills.length) { warn('No skills found in skills.jsonl'); return; }
  console.log(`\n${C.bold}Skills (${skills.length})${C.reset}\n`);
  skills.forEach(s => {
    const conf = s.confidence === 'high' ? C.green : s.confidence === 'medium' ? C.yellow : C.red;
    console.log(`  ${C.cyan}${s.id.padEnd(22)}${C.reset} ${s.name}`);
    console.log(`  ${' '.repeat(22)} ${conf}${s.confidence}${C.reset} · ${s.status} · ${s.category}`);
    if (s.risks?.length) console.log(`  ${' '.repeat(22)} ${C.yellow}⚠ ${s.risks[0]}${C.reset}`);
  });
  console.log();
}

function cmdSkillsSearch(query) {
  if (!query) { err('Provide a search query'); return; }
  const q = query.toLowerCase();
  const results = readSkills().filter(s =>
    (s.name+s.summary+(s.triggers||[]).join(' ')+(s.category||'')).toLowerCase().includes(q));
  if (!results.length) { warn(`No skills match "${query}"`); return; }
  console.log(`\n${C.bold}Results for "${query}"${C.reset}\n`);
  results.forEach(s => {
    console.log(`  ${C.cyan}${s.id}${C.reset} — ${s.name}`);
    console.log(`    ${s.summary}`);
    if (s.commands?.length) console.log(`    ${C.dim}${s.commands[0]}${C.reset}`);
    console.log();
  });
}

async function cmdSkillsVerify(id) {
  const skills = readSkills();
  const s = skills.find(x => x.id === id);
  if (!s) { err(`Skill not found: ${id}`); return; }
  console.log(`\n${C.bold}Verify skill: ${s.name}${C.reset}\n`);
  if (s.commands?.length) {
    console.log('Commands to verify:');
    s.commands.forEach(c => console.log(`  ${C.dim}${c}${C.reset}`));
  }
  const confirm = await ask('Mark as verified and set status=active? (y/N)', 'n');
  if (confirm.toLowerCase() === 'y') {
    const today = new Date().toISOString().slice(0,10);
    s.last_verified = today;
    s.status = 'active';
    const updated = skills.map(x => x.id === id ? s : x);
    writeFileSync(SKILLS_FILE, updated.map(x => JSON.stringify(x)).join('\n') + '\n', 'utf8');
    logActivity('skill_verified', { skill_id: id });
    ok(`Skill ${id} marked active, last_verified=${today}`);
  }
}

function cmdContext(module, task) {
  if (!existsSync(CTX_DIR)) mkdirSync(CTX_DIR, { recursive: true });
  const u = getUser();
  const date = new Date().toISOString().slice(0,10);
  const slug = (task || 'task').toLowerCase().replace(/\s+/g,'-').slice(0,30);
  const fname = `${date}-${module || 'general'}-${slug}.context.md`;
  const fpath = join(CTX_DIR, fname);
  const skills = readSkills().filter(s => s.triggers?.some(t =>
    (task||'').toLowerCase().includes(t.split(' ')[0]))).slice(0,3);
  const content = [
    `# Context Pack: ${module || 'General'} — ${task || 'Task'}`,
    `\n**User:** ${u.display_name}\n**Date:** ${date}\n**Module:** ${module || '—'}\n`,
    `## Goal\n${task || 'TBD'}\n`,
    `## Relevant modules\n- dev-docs/modules/${module || '<module>'}.md\n`,
    `## Suggested skills`,
    ...(skills.length ? skills.map(s => `- skill: ${s.id}  # ${s.name}`) : ['- (none auto-detected)']),
    `\n## Instructions to AI Agent`,
    `Read dev-docs/AI-INSTRUCTIONS.md first.`,
    `Update the relevant module file before ending the session.`,
    `Do not commit credentials or tokens.\n`,
  ].join('\n');
  writeFileSync(fpath, content, 'utf8');
  logActivity('context_pack_created', { file: `dev-docs/context-packs/${fname}`, module, task });
  ok(`Context pack: dev-docs/context-packs/${fname}`);
}

async function cmdSessionStart(module, task) {
  const u = getUser();
  if (!existsSync(SESSIONS_DIR)) mkdirSync(SESSIONS_DIR, { recursive: true });
  const date = new Date().toISOString().slice(0,10);
  const fname = `${date}-${u.user_id}-${module || 'general'}.md`;
  const fpath = join(SESSIONS_DIR, fname);
  const content = [
    `# Session: ${date} — ${u.display_name} — ${module || 'General'}`,
    `\n**User:** ${u.display_name}\n**Agent:** (set by agent)\n**Module:** ${module || '—'}`,
    `**Task:** ${task || '—'}\n**Started:** ${new Date().toISOString()}\n**Ended:** —\n`,
    `## Goal\n${task || 'TBD'}\n`,
    `## Skills used\n\n## Files changed\n\n## Decisions added\n\n## Follow-up\n`,
  ].join('\n');
  writeFileSync(fpath, content, 'utf8');
  logActivity('session_start', { session_file: fname, module, task });
  ok(`Session started: dev-docs/sessions/${fname}`);
  info(`End with: node dev-docs/bin/devdocs.mjs session end`);
}

function cmdSessionEnd() {
  const sessions = existsSync(SESSIONS_DIR)
    ? readdirSync(SESSIONS_DIR).filter(f => f.endsWith('.md')).sort().reverse() : [];
  if (!sessions.length) { warn('No session files found.'); return; }
  const latest = sessions[0];
  logActivity('session_end', { session_file: latest });
  ok(`Session ended: dev-docs/sessions/${latest}`);
  info('Remember to update the relevant module file with decisions and bugs found.');
}

function cmdValidate() {
  console.log(`\n${C.bold}Validating dev-docs v4.0${C.reset}\n`);
  const issues = [];
  const idx = readIndex();
  idx.forEach((e, i) => {
    if (!e.id)   issues.push(`index line ${i+1}: missing id`);
    if (!e.file) issues.push(`${e.id}: missing file`);
    else if (!existsSync(join(ROOT, e.file))) issues.push(`${e.id}: file not found (${e.file})`);
    if (!e.status) issues.push(`${e.id}: missing status`);
  });
  const skills = readSkills();
  const required = ['id','name','category','owner','status','confidence','last_verified'];
  skills.forEach(s => {
    required.forEach(f => { if (!s[f]) issues.push(`skill ${s.id||'?'}: missing ${f}`); });
  });
  // Check skills staleness (>90 days)
  const cutoff = new Date(); cutoff.setDate(cutoff.getDate()-90);
  skills.forEach(s => {
    if (s.last_verified && new Date(s.last_verified) < cutoff)
      warn(`Skill ${s.id} not verified since ${s.last_verified} (stale)`);
  });
  // Required files
  const required_files = [
    'dev-docs/AI-INSTRUCTIONS.md','dev-docs/index.jsonl','dev-docs/CONSTITUTION.md',
    'dev-docs/project.memory.json','dev-docs/skills/skills.jsonl',
    'dev-docs/team/users.registry.json','dev-docs/team/activity-log.jsonl',
  ];
  required_files.forEach(f => {
    if (!existsSync(join(ROOT, f))) issues.push(`Missing required file: ${f}`);
  });

  if (issues.length) { issues.forEach(i => err(i)); console.log(); }
  else ok('All validation checks passed.');
  console.log();
}

function cmdReindex() {
  console.log(`\n${C.bold}Rebuilding index.jsonl${C.reset}\n`);
  const existing = readIndex();
  // Walk modules/apis/infra for .md files and merge new ones
  const dirs = ['modules','apis','infra'];
  const found = [];
  dirs.forEach(dir => {
    const d = join(DEVDOCS, dir);
    if (!existsSync(d)) return;
    readdirSync(d).filter(f => f.endsWith('.md')).forEach(f => {
      const rel = `dev-docs/${dir}/${f}`;
      const id = f.replace('.md','');
      if (!existing.find(e => e.id === id)) {
        found.push({ id, type: dir === 'modules' ? 'module' : dir === 'apis' ? 'api' : 'infra',
          file: rel, keywords: [], description: '', status: 'active',
          last_modified: new Date().toISOString().slice(0,10) });
      }
    });
  });
  const all = [...existing, ...found];
  writeFileSync(INDEX_FILE, all.map(e => JSON.stringify(e)).join('\n') + '\n', 'utf8');
  logActivity('reindex', { count: all.length, new: found.length });
  ok(`index.jsonl rebuilt: ${all.length} entries (${found.length} new)`);
  console.log();
}

function cmdGitDrift() {
  console.log(`\n${C.bold}Git Drift Analysis${C.reset}\n`);
  let changed = [];
  try {
    const out = execSync('git diff --name-only HEAD~1 HEAD 2>/dev/null || git diff --name-only', { cwd: ROOT }).toString().trim();
    changed = out.split('\n').filter(Boolean);
  } catch { warn('Could not run git diff'); return; }
  const docChanged = changed.filter(f => f.startsWith('dev-docs/'));
  const srcChanged = changed.filter(f => !f.startsWith('dev-docs/') && f !== '.gitignore');
  const drift = srcChanged.filter(src => {
    const base = src.split('/').pop().replace(/\.[^.]+$/, '');
    return !docChanged.some(d => d.includes(base));
  });
  info(`Source files changed: ${srcChanged.length}`);
  info(`Dev-docs files changed: ${docChanged.length}`);
  if (drift.length) {
    console.log(`\n${C.yellow}Undocumented changes (no matching dev-docs update):${C.reset}`);
    drift.forEach(f => warn(f));
  } else {
    ok('No drift detected — dev-docs is up to date with source changes.');
  }
  console.log();
}

function cmdServe() {
  const srv = join(DEVDOCS, 'dashboard', 'server.mjs');
  if (!existsSync(srv)) { err('Dashboard server not found: dev-docs/dashboard/server.mjs'); return; }
  info('Starting dev-docs dashboard…');
  const r = spawnSync(process.execPath, [srv], { stdio: 'inherit', cwd: ROOT });
  if (r.error) err(r.error.message);
}

function cmdExport(format) {
  const u = getUser();
  const date = new Date().toISOString().slice(0,10);
  const idx = readIndex();
  const lines = [
    `# dev-docs v4.0 — Onboarding Export`,
    `**Project:** qa-test  **Date:** ${date}  **Generated by:** ${u.display_name}`,
    '',
    '## Module Index',
    ...idx.map(e => `- **${e.id}** (${e.type}): ${e.description}  \`${e.file}\``),
    '',
    '## Skills',
    ...readSkills().map(s => `- **${s.id}**: ${s.summary}  [${s.status}/${s.confidence}]`),
  ];
  const out = join(CTX_DIR, `onboarding-${date}.md`);
  if (!existsSync(CTX_DIR)) mkdirSync(CTX_DIR, { recursive: true });
  writeFileSync(out, lines.join('\n'), 'utf8');
  ok(`Onboarding export: dev-docs/context-packs/onboarding-${date}.md`);
}

// ── Usage ──────────────────────────────────────────────────────────────────

function usage() {
  console.log(`
${C.bold}dev-docs v4.0 — Local Shell CLI${C.reset}

${C.cyan}Usage:${C.reset}  node dev-docs/bin/devdocs.mjs <command> [args]

${C.cyan}Commands:${C.reset}
  ${C.bold}doctor${C.reset}                      Check dev-docs health
  ${C.bold}whoami${C.reset}                      Show or set local user identity
  ${C.bold}serve${C.reset}                       Start local dashboard (port 3434)
  ${C.bold}validate${C.reset}                    Validate index, skills, required files
  ${C.bold}reindex${C.reset}                     Rebuild index.jsonl from dev-docs/modules/apis/infra
  ${C.bold}skills list${C.reset}                 List all skills
  ${C.bold}skills search <query>${C.reset}       Search skills by keyword
  ${C.bold}skills verify <skill-id>${C.reset}    Interactively verify and promote a skill
  ${C.bold}context <module>${C.reset}            Generate context pack  (--task "description")
  ${C.bold}session start${C.reset}               Start a session record  (--module m --task t)
  ${C.bold}session end${C.reset}                 Mark last session as ended
  ${C.bold}git drift${C.reset}                   Check for undocumented source changes
  ${C.bold}export onboarding${C.reset}           Export onboarding document  (--format md)

${C.dim}Project root: ${ROOT}${C.reset}
`);
}

// ── Main ───────────────────────────────────────────────────────────────────

const [,, cmd, sub, ...rest] = process.argv;

const flags = {};
const posArgs = [];
for (let i = 0; i < rest.length; i++) {
  if (rest[i].startsWith('--') && i + 1 < rest.length && !rest[i+1].startsWith('--')) {
    flags[rest[i].slice(2)] = rest[++i];
  } else if (rest[i].startsWith('--')) {
    flags[rest[i].slice(2)] = true;
  } else {
    posArgs.push(rest[i]);
  }
}

switch (cmd) {
  case 'doctor':  cmdDoctor(); break;
  case 'whoami':  await cmdWhoami(); break;
  case 'serve':   cmdServe(); break;
  case 'validate':cmdValidate(); break;
  case 'reindex': cmdReindex(); break;
  case 'skills':
    if (sub === 'list')          cmdSkillsList();
    else if (sub === 'search')   cmdSkillsSearch(posArgs[0] || flags.query);
    else if (sub === 'verify')   await cmdSkillsVerify(posArgs[0] || flags.id);
    else usage();
    break;
  case 'context':
    cmdContext(sub || flags.module, flags.task || posArgs.join(' '));
    break;
  case 'session':
    if (sub === 'start')         await cmdSessionStart(flags.module, flags.task);
    else if (sub === 'end')      cmdSessionEnd();
    else usage();
    break;
  case 'git':
    if (sub === 'drift')         cmdGitDrift();
    else usage();
    break;
  case 'export':
    cmdExport(flags.format || 'md');
    break;
  default: usage();
}
