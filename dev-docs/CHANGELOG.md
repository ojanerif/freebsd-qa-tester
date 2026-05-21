---
version: "4.0"
last_modified: 2026-05-21
tags: [changelog, v4]
---

# Changelog — dev-docs

All notable changes to the dev-docs memory system for qa-test.

## [4.0] — 2026-05-21

### Added
- v4.0 Project Memory OS structure
- `skills/` — project skills database (skills.jsonl + 8 initial skills)
- `context-packs/` — task-focused AI context bundles
- `sessions/` — formal session start/end records
- `team/` — user registry, roles, ownership, activity log
- `dashboard/` — local Node.js web visualizer
- `bin/devdocs.mjs` — local shell CLI
- `project.memory.json` — machine-readable project identity
- `PROJECT-MEMORY.md` — human-readable project overview
- `CONSTITUTION.md` — non-negotiable project rules
- `HUMAN-ONBOARDING.md` — new developer guide
- `repos.json` — multi-repo map
- `agents.json` — AI agent registry
- `.gitignore` rules for `.local/`, `.backups/`, `.token`

### Changed
- `AI-INSTRUCTIONS.md` — updated to v4.0 protocol
- `index.jsonl` — rebuilt to include all v4.0 entries
- `_global.md` — updated `last_modified` and learning log

### Fixed
- `qa-tester.sh`: `tr -d '-:'` → `sed 's/^-//;s/:$//'` (FreeBSD tr bug)
- `qa-tester.sh`: Added `--email` CLI flag, `send_report_email()`, menu option 5

## [3.x] — 2026-04-28 to 2026-05-18

- Initial bootstrap: 6 modules + 2 infra entries
- Added global snippets for two-phase QA scripts and BE side-load sequence
- Documented SWLSVROS-6363, SWLSVROS-6414, SWLSVROS-6519
