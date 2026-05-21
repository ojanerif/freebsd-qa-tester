# qa-test — AI Agent Instructions
## dev-docs v4.0 - Project Memory OS

**Version:** dev-docs v4.0 — Project Memory OS
**Author:** Osvaldo J. Filho
**Date:** May 21, 2026
**Audience:** AI agents (Claude Code, Gemini, Cline), engineering team

This file is the authoritative instruction set for every AI agent working on this project.
Referenced by: CLAUDE.md, AGENTS.md, GEMINI.md, .clinerules, .windsurfrules.
When in conflict, this file takes precedence.

---

## Startup Protocol

At the start of every task:
1. Read this file if not already read this session
2. Read `dev-docs/project.memory.json` for project identity
3. `grep dev-docs/index.jsonl` for the module you are working on
4. Read **only that module file** — do not load other modules
5. If the module does not exist, create it using the template in `dev-docs/_global.md`
6. Check `dev-docs/skills/skills.jsonl` for skills relevant to the task (match triggers)
7. Begin the task

## Shutdown Protocol

Before ending any task:
1. Append new entries (DECISION / BUG / TODO / SNIPPET) to the relevant module file
2. Append one line to that module's Learning Log section
3. Update `last_modified` in the module frontmatter to today (2026-05-21 format)
4. If you created a new module, append its entry to `dev-docs/index.jsonl`
5. If a pattern appears in 3+ modules, append it to `dev-docs/_global.md`
6. Log your session to `dev-docs/team/activity-log.jsonl` if significant

---

## Memory System

### How to look up a module

`dev-docs/index.jsonl` is a newline-delimited JSON index.
Each line describes one module, api, infra or skill entry.

```sh
grep "session"     dev-docs/index.jsonl
grep "report"      dev-docs/index.jsonl
grep "email"       dev-docs/index.jsonl
grep "kernel"      dev-docs/index.jsonl
```

Each entry shape:
```json
{
  "id": "module-name",
  "type": "module | api | infra | skill | context-pack",
  "file": "dev-docs/modules/module-name.md",
  "keywords": ["function_name", "ClassName"],
  "description": "one sentence",
  "status": "active | paused | deprecated",
  "last_modified": "YYYY-MM-DD"
}
```

### File to module mapping

| Path pattern                               | Module id        |
|--------------------------------------------|------------------|
| `qa-tester.sh` (main, run_menu, gather_info) | orchestrator   |
| `qa-tester.sh` (load_previous_session, _save_session_state) | session-manager |
| `qa-tester.sh` (run_cmd, run_long_cmd, info/pass/fail/warn) | command-engine |
| `qa-tester.sh` (action_build_world, action_sync_source, action_check_kernel) | build-pipeline |
| `qa-tester.sh` (generate_report, send_report_email, _print_final_result) | reporting |
| `qa-branches/<QA_ID>/<QA_ID>.sh`           | qa-tests         |
| `last-session.env`, `reports/*/state.env`  | session-manager  |
| `reports/*/results.tsv`, `reports/*/qa-report-*.txt` | reporting |
| file not listed above                      | grep index.jsonl first; if no match, create new module |

---

## Skills

When a user request matches a skill trigger, check `dev-docs/skills/skills.jsonl`.
Each skill has: id, name, triggers, commands, risks, and a `prompt` field.
Read the `prompt` field before executing the skill.
Skills with `confidence: low` — warn the user before executing.
Skills with `status: draft` — confirm with user before treating as authoritative.

---

## v4.0 Directory Structure

```
dev-docs/
├── AI-INSTRUCTIONS.md       ← This file
├── PROJECT-MEMORY.md        ← Project overview
├── CONSTITUTION.md          ← Non-negotiable rules
├── HUMAN-ONBOARDING.md      ← New developer guide
├── CHANGELOG.md             ← Version history
├── index.jsonl              ← Machine-readable module index
├── project.memory.json      ← Project identity (JSON)
├── repos.json               ← Multi-repo map
├── agents.json              ← AI agent registry
├── _global.md               ← Cross-cutting patterns
├── modules/                 ← Module memory files
├── apis/                    ← API memory files
├── infra/                   ← Infrastructure memory files
├── skills/
│   ├── skills.jsonl         ← Skills database
│   ├── categories.md        ← Category definitions
│   ├── templates/           ← Skill authoring template
│   └── playbooks/           ← Multi-step skill sequences
├── context-packs/           ← Task-focused AI context bundles
├── sessions/                ← Session start/end records
├── reviews/                 ← Decision review records
├── boards/                  ← Kanban / status boards
├── team/
│   ├── users.registry.json  ← Team member registry
│   ├── roles.md             ← Role definitions
│   ├── ownership.md         ← Module ownership
│   └── activity-log.jsonl   ← Audit trail (append-only)
├── dashboard/               ← Local Node.js web visualizer
│   ├── server.mjs           ←   node dev-docs/dashboard/server.mjs
│   ├── index.html
│   ├── app.js
│   └── styles.css
├── bin/
│   └── devdocs.mjs          ← Local shell CLI
├── _attachments/            ← Evidence, screenshots, exports
├── _archive/                ← Sessions > 90 days old
├── .generated/              ← Auto-generated artifacts (partial gitignore)
├── .local/                  ← GITIGNORED — local user identity
├── .backups/                ← GITIGNORED — pre-save backups
└── .token                   ← GITIGNORED — dashboard write token
```

---

## Entry Formats

Always **append** — never edit or delete past entries.

### Decision
```
## [DECISION] <title>
**Date:** YYYY-MM-DD
**Author:** Name
**Context:** why this decision was needed
**Decision:** what was chosen and implemented
**Discarded alternatives:** what was considered and why rejected
**Impact:** files or modules affected
**Status:** active | superseded
```

### Bug
```
## [BUG] <short description>
**Found:** YYYY-MM-DD
**Author:** Name
**Symptom:** observable behavior
**Root cause:** underlying reason
**Fix/Workaround:** what resolves it
**Status:** resolved | workaround | open
```

### TODO
```
## [TODO] <title>
**Priority:** high | medium | low
**Author:** Name
**Context:** why it needs doing
**Status:** pending | in-progress | done
```

### Snippet
```
## [SNIPPET] <pattern name>
**Use:** when to apply this pattern
\`\`\`lang
code here
\`\`\`
```

### Learning Log entry
```
YYYY-MM-DD | observation | <module-id>
```

---

## Project Stack

| Layer         | Tools                                          |
|---------------|------------------------------------------------|
| Shell         | POSIX /bin/sh (FreeBSD)                        |
| Platform      | FreeBSD CURRENT (16.0-CURRENT)                 |
| Kernel build  | make buildworld, make buildkernel              |
| Source control| Git                                            |
| Test runner   | kyua (preferred) or *_test.sh fallback         |
| PMC testing   | pmcstat, pmc                                   |
| Issue tracker | Jira (amd.atlassian.net) — SWLSVROS-* prefix   |
| Reporting     | TSV + plain text + MIME email via sendmail/dma |
| dev-docs CLI  | node dev-docs/bin/devdocs.mjs                  |
| dev-docs UI   | node dev-docs/dashboard/server.mjs (port 3434) |

## Conventions

- All dev-docs content in English
- Obsidian-compatible: YAML frontmatter, `[[wiki-links]]`, #tags
- Append only — never edit past entries, only add new dated ones
- Filenames: kebab-case, no accents or spaces
- `index.jsonl`: one valid JSON object per line, no surrounding array
- QA test scripts live at `qa-branches/<QA_ID>/<QA_ID>.sh`
- POSIX sh only — no bashisms anywhere in this project
- `tr` character sets: `-` must be first or last (FreeBSD tr rule)
- Email: sendmail → dma → atlsmtp10.amd.com; sender=freebsd-ci-actions@amd.com

## Security Rules for AI Agents

- Never commit `dev-docs/.local/`, `.backups/`, `.token`, or any `GH_TOKEN`/PAT
- Never run `rm -rf`, `git reset --hard`, or `reboot` without explicit user confirmation
- Never write outside the project root
- Generated skills start as `draft` — human promotes to `active`
- Scan for secrets before any file write
