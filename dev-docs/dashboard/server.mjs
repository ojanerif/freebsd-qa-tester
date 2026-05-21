#!/usr/bin/env node
// dev-docs v4.0 — local dashboard server
// Binds to 127.0.0.1:3434 only. Requires Node.js >= 18.
// Usage: node dev-docs/dashboard/server.mjs

import { createServer } from 'node:http';
import { readFileSync, writeFileSync, existsSync, mkdirSync, readdirSync, statSync, copyFileSync } from 'node:fs';
import { resolve, join, relative, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { execSync } from 'node:child_process';

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT = resolve(__dirname, '../../..');       // project root
const DEVDOCS = resolve(__dirname, '..');          // dev-docs/
const TOKEN_FILE = join(DEVDOCS, '.token');
const LOCAL_DIR  = join(DEVDOCS, '.local');
const BACKUP_DIR = join(DEVDOCS, '.backups');
const LOG_FILE   = join(DEVDOCS, 'team', 'activity-log.jsonl');
const INDEX_FILE = join(DEVDOCS, 'index.jsonl');
const SKILLS_FILE = join(DEVDOCS, 'skills', 'skills.jsonl');
const PORT = parseInt(process.env.DEVDOCS_PORT || '3434', 10);

// ── Bootstrap ──────────────────────────────────────────────────────────────

function ensureDirs() {
  for (const d of [LOCAL_DIR, BACKUP_DIR, join(DEVDOCS, 'team')]) {
    if (!existsSync(d)) mkdirSync(d, { recursive: true });
  }
}

function ensureToken() {
  if (!existsSync(TOKEN_FILE)) {
    const tok = Math.random().toString(36).slice(2) + Math.random().toString(36).slice(2);
    writeFileSync(TOKEN_FILE, tok, 'utf8');
    console.log(`[devdocs] Created .token (first run)`);
  }
  return readFileSync(TOKEN_FILE, 'utf8').trim();
}

function safeResolvePath(p) {
  const abs = resolve(ROOT, p);
  if (!abs.startsWith(ROOT + '/') && abs !== ROOT) throw new Error('Path outside project root');
  return abs;
}

// ── User identity ──────────────────────────────────────────────────────────

function getUser() {
  const f = join(LOCAL_DIR, 'user.json');
  if (existsSync(f)) return JSON.parse(readFileSync(f, 'utf8'));
  // suggest from git config
  let name = '', email = '';
  try { name = execSync('git config user.name', { cwd: ROOT }).toString().trim(); } catch {}
  try { email = execSync('git config user.email', { cwd: ROOT }).toString().trim(); } catch {}
  return { user_id: email.split('@')[0] || 'unknown', display_name: name || 'Unknown', email, role: 'Owner', suggested: true };
}

function saveUser(data) {
  const f = join(LOCAL_DIR, 'user.json');
  writeFileSync(f, JSON.stringify(data, null, 2), 'utf8');
}

// ── Logging ────────────────────────────────────────────────────────────────

function logActivity(event, extra = {}) {
  const user = getUser();
  const entry = { event, user_id: user.user_id, author: user.display_name,
                  timestamp: new Date().toISOString(), ...extra };
  try { writeFileSync(LOG_FILE, JSON.stringify(entry) + '\n', { flag: 'a' }); } catch {}
}

// ── Backup ─────────────────────────────────────────────────────────────────

function backupFile(absPath) {
  if (!existsSync(absPath)) return;
  const rel = relative(ROOT, absPath).replace(/\//g, '_');
  const bak = join(BACKUP_DIR, `${Date.now()}_${rel}`);
  try { copyFileSync(absPath, bak); } catch {}
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

// ── Git ────────────────────────────────────────────────────────────────────

function gitStatus() {
  try {
    const out = execSync('git status --short', { cwd: ROOT }).toString().trim();
    return out.split('\n').filter(Boolean).map(l => ({ status: l.slice(0,2).trim(), file: l.slice(3) }));
  } catch { return []; }
}

function gitDrift() {
  try {
    const changed = execSync('git diff --name-only HEAD~1 HEAD 2>/dev/null || git diff --name-only', { cwd: ROOT }).toString().trim().split('\n').filter(Boolean);
    const docChanged = changed.filter(f => f.startsWith('dev-docs/'));
    const srcChanged = changed.filter(f => !f.startsWith('dev-docs/'));
    const drift = srcChanged.filter(src => {
      const base = src.split('/').pop().replace(/\.[^.]+$/, '');
      return !docChanged.some(d => d.includes(base));
    });
    return { srcChanged, docChanged, drift };
  } catch { return { srcChanged: [], docChanged: [], drift: [] }; }
}

// ── Request router ─────────────────────────────────────────────────────────

function body(req) {
  return new Promise((res, rej) => {
    let d = '';
    req.on('data', c => d += c);
    req.on('end', () => { try { res(JSON.parse(d || '{}')); } catch { res({}); } });
    req.on('error', rej);
  });
}

function reply(res, status, data, ct = 'application/json') {
  const payload = ct === 'application/json' ? JSON.stringify(data) : data;
  res.writeHead(status, { 'Content-Type': ct, 'Access-Control-Allow-Origin': '*' });
  res.end(payload);
}

const TOKEN = ensureToken();
ensureDirs();

const server = createServer(async (req, res) => {
  const url = new URL(req.url, `http://127.0.0.1:${PORT}`);
  const path = url.pathname;

  // CORS preflight
  if (req.method === 'OPTIONS') { reply(res, 204, ''); return; }

  // Static dashboard files
  if (path === '/' || path === '/index.html') {
    const f = join(__dirname, 'index.html');
    reply(res, 200, existsSync(f) ? readFileSync(f, 'utf8') : '<h1>dev-docs v4.0</h1>', 'text/html');
    return;
  }
  if (path === '/app.js') {
    const f = join(__dirname, 'app.js');
    reply(res, 200, existsSync(f) ? readFileSync(f, 'utf8') : '', 'text/javascript'); return;
  }
  if (path === '/styles.css') {
    const f = join(__dirname, 'styles.css');
    reply(res, 200, existsSync(f) ? readFileSync(f, 'utf8') : '', 'text/css'); return;
  }

  // ── API ──────────────────────────────────────────────────────────────────
  if (path.startsWith('/api/')) {
    const write = req.method === 'POST' || req.method === 'PUT' || req.method === 'DELETE';
    if (write) {
      const tok = req.headers['x-devdocs-token'] || url.searchParams.get('token');
      if (tok !== TOKEN) { reply(res, 401, { error: 'Invalid token' }); return; }
    }

    if (path === '/api/health') {
      reply(res, 200, { status: 'ok', version: '4.0', port: PORT }); return;
    }

    if (path === '/api/index') {
      reply(res, 200, readIndex()); return;
    }

    if (path === '/api/skills') {
      if (req.method === 'GET') { reply(res, 200, readSkills()); return; }
      if (req.method === 'POST') {
        const d = await body(req);
        backupFile(SKILLS_FILE);
        writeFileSync(SKILLS_FILE, JSON.stringify(d) + '\n', { flag: 'a' });
        logActivity('skill_added', { skill_id: d.id });
        reply(res, 200, { ok: true }); return;
      }
    }

    if (path === '/api/file') {
      const p = url.searchParams.get('path');
      if (!p) { reply(res, 400, { error: 'Missing path' }); return; }
      try {
        const abs = safeResolvePath(p);
        reply(res, 200, { path: p, content: readFileSync(abs, 'utf8') }); return;
      } catch (e) { reply(res, 404, { error: e.message }); return; }
    }

    if (path === '/api/save' && req.method === 'POST') {
      const d = await body(req);
      if (!d.path || d.content === undefined) { reply(res, 400, { error: 'Missing path or content' }); return; }
      // Rudimentary secret scan
      if (/ghp_[A-Za-z0-9]{36}|github_pat_/.test(d.content)) {
        reply(res, 422, { error: 'Possible token detected in content — save rejected' }); return;
      }
      try {
        const abs = safeResolvePath(d.path);
        backupFile(abs);
        mkdirSync(dirname(abs), { recursive: true });
        writeFileSync(abs, d.content, 'utf8');
        logActivity('file_saved', { file: d.path });
        reply(res, 200, { ok: true }); return;
      } catch (e) { reply(res, 500, { error: e.message }); return; }
    }

    if (path === '/api/user') {
      if (req.method === 'GET') { reply(res, 200, getUser()); return; }
      if (req.method === 'POST') {
        const d = await body(req);
        saveUser(d);
        logActivity('user_identity_set', { user_id: d.user_id });
        reply(res, 200, { ok: true }); return;
      }
    }

    if (path === '/api/log' && req.method === 'POST') {
      const d = await body(req);
      logActivity(d.event || 'manual', d);
      reply(res, 200, { ok: true }); return;
    }

    if (path === '/api/git/status') {
      reply(res, 200, { files: gitStatus() }); return;
    }

    if (path === '/api/git/drift') {
      reply(res, 200, gitDrift()); return;
    }

    if (path === '/api/reindex' && req.method === 'POST') {
      // Simple reindex: walk modules/apis/infra and rebuild index.jsonl
      const entries = readIndex();
      backupFile(INDEX_FILE);
      writeFileSync(INDEX_FILE, entries.map(e => JSON.stringify(e)).join('\n') + '\n', 'utf8');
      logActivity('reindex');
      reply(res, 200, { ok: true, count: entries.length }); return;
    }

    if (path === '/api/validate' && req.method === 'POST') {
      const issues = [];
      const idx = readIndex();
      idx.forEach((e, i) => {
        if (!e.id) issues.push(`Line ${i+1}: missing id`);
        if (!e.file) issues.push(`${e.id}: missing file`);
        else if (!existsSync(join(ROOT, e.file))) issues.push(`${e.id}: file not found: ${e.file}`);
      });
      const skills = readSkills();
      skills.forEach(s => {
        if (!s.id || !s.name || !s.category || !s.owner || !s.status || !s.confidence || !s.last_verified)
          issues.push(`skill ${s.id || '?'}: missing required fields`);
      });
      reply(res, 200, { issues, ok: issues.length === 0 }); return;
    }

    if (path === '/api/context-pack' && req.method === 'POST') {
      const d = await body(req);
      const packName = `${d.module || 'general'}-${d.task_type || 'task'}.context.md`;
      const packPath = join(DEVDOCS, 'context-packs', packName);
      const content = `# Context Pack: ${d.module || 'General'} — ${d.task || ''}\n\n` +
        `## Goal\n${d.task || 'TBD'}\n\n## User\n${getUser().display_name}\n\n` +
        `## Relevant modules\n${(d.modules || []).map(m => `- dev-docs/modules/${m}.md`).join('\n')}\n\n` +
        `## Relevant skills\n${(d.skills || []).map(s => `- skill: ${s}`).join('\n')}\n\n` +
        `## Instructions to AI Agent\nUpdate dev-docs after implementation.\n`;
      writeFileSync(packPath, content, 'utf8');
      logActivity('context_pack_created', { pack: packName });
      reply(res, 200, { ok: true, file: `dev-docs/context-packs/${packName}` }); return;
    }

    if (path === '/api/session/start' && req.method === 'POST') {
      const d = await body(req);
      const user = getUser();
      const date = new Date().toISOString().slice(0,10);
      const fname = `${date}-${user.user_id}-${d.module || 'general'}.md`;
      const fpath = join(DEVDOCS, 'sessions', fname);
      const content = `# Session: ${date} — ${user.display_name} — ${d.module || 'General'}\n\n` +
        `**User:** ${user.display_name}\n**Module:** ${d.module || '—'}\n` +
        `**Task:** ${d.task || '—'}\n**Started:** ${new Date().toISOString()}\n\n` +
        `## Goal\n${d.task || 'TBD'}\n\n## Skills used\n\n## Files changed\n\n## Decisions added\n\n## Follow-up\n`;
      writeFileSync(fpath, content, 'utf8');
      logActivity('session_start', { module: d.module, session_file: fname });
      reply(res, 200, { ok: true, file: `dev-docs/sessions/${fname}` }); return;
    }

    if (path === '/api/session/end' && req.method === 'POST') {
      logActivity('session_end');
      reply(res, 200, { ok: true }); return;
    }

    reply(res, 404, { error: 'Not found' }); return;
  }

  reply(res, 404, { error: 'Not found' });
});

server.listen(PORT, '127.0.0.1', () => {
  console.log(`\n  dev-docs v4.0 dashboard`);
  console.log(`  http://127.0.0.1:${PORT}\n`);
  console.log(`  Token file : dev-docs/.token`);
  console.log(`  User file  : dev-docs/.local/user.json`);
  console.log(`  Project    : ${ROOT}\n`);
});
