// dev-docs v4.0 — dashboard app (ES modules, no build step)

const API = '';
let TOKEN = localStorage.getItem('devdocs_token') || '';
let allSkills = [];
let allIndex = [];

// ── Auth token ─────────────────────────────────────────────────────────────

async function ensureToken() {
  if (!TOKEN) {
    TOKEN = prompt('Enter dev-docs write token (from dev-docs/.token):') || '';
    if (TOKEN) localStorage.setItem('devdocs_token', TOKEN);
  }
}

function headers(write = false) {
  const h = { 'Content-Type': 'application/json' };
  if (write) h['x-devdocs-token'] = TOKEN;
  return h;
}

async function api(path, opts = {}) {
  const res = await fetch(API + path, opts);
  if (!res.ok) throw new Error(`${res.status} ${await res.text()}`);
  return res.json();
}

// ── Navigation ──────────────────────────────────────────────────────────────

document.querySelectorAll('#sidebar li').forEach(li => {
  li.addEventListener('click', () => {
    document.querySelectorAll('#sidebar li').forEach(x => x.classList.remove('active'));
    li.classList.add('active');
    document.querySelectorAll('.view').forEach(v => v.classList.remove('active'));
    const view = document.getElementById(`view-${li.dataset.view}`);
    if (view) view.classList.add('active');
    onViewSwitch(li.dataset.view);
  });
});

function onViewSwitch(view) {
  if (view === 'reader')   loadIndex();
  if (view === 'skills')   loadSkills();
  if (view === 'git')      loadGit();
  if (view === 'health')   { /* manual */ }
  if (view === 'activity') loadActivity();
  if (view === 'sessions') loadSessions();
}

// ── User ────────────────────────────────────────────────────────────────────

async function loadUser() {
  try {
    const u = await api('/api/user');
    document.getElementById('user-badge').textContent =
      `${u.display_name || u.user_id}${u.suggested ? ' (git config)' : ''}`;
  } catch {}
}

// ── Reader ──────────────────────────────────────────────────────────────────

async function loadIndex() {
  try {
    allIndex = await api('/api/index');
    renderIndex(allIndex);
    document.getElementById('file-viewer').classList.add('hidden');
    document.getElementById('index-list').classList.remove('hidden');
  } catch (e) { console.error(e); }
}

function renderIndex(entries) {
  const q = document.getElementById('search').value.toLowerCase();
  const filtered = q ? entries.filter(e =>
    (e.id+e.description+(e.keywords||[]).join(' ')).toLowerCase().includes(q)) : entries;

  document.getElementById('index-list').innerHTML = filtered.map(e => `
    <div class="card">
      <h3><a onclick="openFile('${e.file}')">${e.id}</a></h3>
      <p>${e.description || ''}</p>
      <div class="meta">
        <span class="badge active">${e.type}</span>
        <span class="badge ${e.status}">${e.status}</span>
        ${e.last_modified ? `<span>${e.last_modified}</span>` : ''}
      </div>
    </div>`).join('');
}

document.getElementById('search').addEventListener('input', () => renderIndex(allIndex));

async function openFile(path) {
  try {
    const r = await api(`/api/file?path=${encodeURIComponent(path)}`);
    document.getElementById('index-list').classList.add('hidden');
    document.getElementById('file-viewer').classList.remove('hidden');
    document.getElementById('file-content').textContent = r.content;
  } catch (e) { alert(e.message); }
}

function closeFile() {
  document.getElementById('file-viewer').classList.add('hidden');
  document.getElementById('index-list').classList.remove('hidden');
}

window.openFile = openFile;
window.closeFile = closeFile;

// ── Skills ──────────────────────────────────────────────────────────────────

async function loadSkills() {
  try { allSkills = await api('/api/skills'); renderSkills(); } catch (e) { console.error(e); }
}

function filterSkills() { renderSkills(); }

function renderSkills() {
  const q = document.getElementById('skill-search').value.toLowerCase();
  const cat = document.getElementById('skill-cat').value;
  const filtered = allSkills.filter(s =>
    (!q || (s.name+s.summary+(s.triggers||[]).join(' ')).toLowerCase().includes(q)) &&
    (!cat || s.category === cat));
  document.getElementById('skills-list').innerHTML = filtered.map(s => `
    <div class="card">
      <h3>${s.name}</h3>
      <p>${s.summary}</p>
      <div class="meta">
        <span class="badge ${s.status}">${s.status}</span>
        <span class="badge ${s.confidence}">${s.confidence}</span>
        <span>${s.category}</span> · <span>${s.last_verified}</span>
      </div>
      ${s.risks?.length ? `<p style="color:var(--warn);margin-top:6px;font-size:11px">⚠ ${s.risks.join('; ')}</p>` : ''}
    </div>`).join('') || '<p style="color:var(--text3)">No skills found.</p>';
}

window.filterSkills = filterSkills;

// ── Sessions ────────────────────────────────────────────────────────────────

async function loadSessions() {
  try {
    const idx = await api('/api/index');
    // sessions aren't in index yet; just show context packs and a placeholder
    document.getElementById('sessions-list').innerHTML =
      `<div class="card"><h3>Sessions</h3><p>Session files live in <code>dev-docs/sessions/</code>.<br>
      Use the CLI: <code>node dev-docs/bin/devdocs.mjs session start --module &lt;m&gt;</code></p></div>`;
  } catch {}
}

async function startSession() {
  await ensureToken();
  const mod = prompt('Module name (e.g. orchestrator):') || 'general';
  const task = prompt('Task description:') || '';
  try {
    const r = await api('/api/session/start', {
      method: 'POST', headers: headers(true),
      body: JSON.stringify({ module: mod, task })
    });
    alert(`Session started: ${r.file}`);
  } catch (e) { alert(e.message); }
}

window.startSession = startSession;

// ── Context Packs ───────────────────────────────────────────────────────────

async function generateContextPack() {
  await ensureToken();
  const mod = document.getElementById('cp-module').value;
  const task = document.getElementById('cp-task').value;
  const skills = document.getElementById('cp-skills').value.split(',').map(s => s.trim()).filter(Boolean);
  try {
    const r = await api('/api/context-pack', {
      method: 'POST', headers: headers(true),
      body: JSON.stringify({ module: mod, task, skills, modules: [mod] })
    });
    document.getElementById('cp-result').textContent = `Created: ${r.file}`;
  } catch (e) { document.getElementById('cp-result').textContent = `Error: ${e.message}`; }
}

window.generateContextPack = generateContextPack;

// ── Git ─────────────────────────────────────────────────────────────────────

async function loadGit() {
  try {
    const s = await api('/api/git/status');
    document.getElementById('git-status-out').textContent =
      s.files.length ? s.files.map(f => `${f.status.padEnd(3)} ${f.file}`).join('\n') : 'Clean working tree.';
    const d = await api('/api/git/drift');
    let driftText = '';
    if (d.drift?.length) driftText = `Undocumented changes:\n${d.drift.join('\n')}`;
    else driftText = 'No drift detected.';
    document.getElementById('git-drift-out').textContent = driftText;
  } catch (e) { document.getElementById('git-status-out').textContent = e.message; }
}

// ── Health ──────────────────────────────────────────────────────────────────

async function runValidate() {
  await ensureToken();
  try {
    const r = await api('/api/validate', { method: 'POST', headers: headers(true), body: '{}' });
    document.getElementById('health-out').textContent =
      r.ok ? '✓ All checks passed.' : r.issues.join('\n');
  } catch (e) { document.getElementById('health-out').textContent = e.message; }
}

window.runValidate = runValidate;

// ── Activity ────────────────────────────────────────────────────────────────

async function loadActivity() {
  try {
    const r = await api('/api/file?path=dev-docs/team/activity-log.jsonl');
    const entries = r.content.trim().split('\n').filter(Boolean)
      .map(l => { try { return JSON.parse(l); } catch { return null; } }).filter(Boolean).reverse();
    document.getElementById('activity-list').innerHTML = entries.map(e =>
      `<div class="entry"><strong>${e.event}</strong> — ${e.author || e.user_id || '?'}
       <span class="ts">${e.timestamp ? new Date(e.timestamp).toLocaleString() : ''}</span>
       ${e.file ? ` · <code>${e.file}</code>` : ''}${e.note ? ` — ${e.note}` : ''}</div>`
    ).join('');
  } catch (e) { document.getElementById('activity-list').innerHTML = `<p>${e.message}</p>`; }
}

// ── Init ────────────────────────────────────────────────────────────────────

loadUser();
loadIndex();
