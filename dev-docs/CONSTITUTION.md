---
version: "4.0"
last_modified: 2026-05-21
tags: [constitution, governance, v4]
---

# Project Constitution — qa-test

> Non-negotiable rules for decisions, memory, AI usage and quality in this project.

## 1. Memory Rules

1. All project knowledge lives in `dev-docs/`. No decisions, bugs or conventions in comments alone.
2. Memory is append-only. Never edit or delete past entries — add new dated ones.
3. Every DECISION, BUG and TODO entry must have: date, author, status.
4. Module files must be updated in the same session as the code they describe.
5. `dev-docs/.local/`, `.backups/`, `.token` are **never committed**.

## 2. Code Rules

1. POSIX `/bin/sh` only — no bashisms anywhere in this project.
2. No security vulnerabilities: no command injection, no unquoted variables in shell.
3. All temp files use `mktemp` and are cleaned up on all exit paths.
4. New shell functions require a comment block if logic is non-obvious.
5. `tr` character sets: `-` must be first or last to be literal (FreeBSD `tr` rule).

## 3. AI Agent Rules

1. Agents must read `dev-docs/AI-INSTRUCTIONS.md` at session start.
2. Agents must update the relevant module file before ending a session.
3. Agents must not commit credentials, tokens, or `.env` content.
4. Agents must not run destructive commands (`rm -rf`, `git reset --hard`, reboot) without explicit user confirmation.
5. Generated skills start as `DRAFT` — a human must promote to `ACTIVE`.

## 4. Quality Gates

1. `sh -n <file>` must pass with no errors before any push.
2. Email token (`GH_TOKEN`) must never appear in committed files.
3. Skills with `confidence: low` must display a warning before execution.
4. Session files older than 90 days move to `dev-docs/_archive/`.

## 5. Governance

- **Owner:** Osvaldo J. Filho
- **Review:** Any change to CONSTITUTION.md requires a new `[DECISION]` entry in `_global.md`.
- **Violations:** Logged in `dev-docs/team/activity-log.jsonl` under `event: "constitution_violation"`.
