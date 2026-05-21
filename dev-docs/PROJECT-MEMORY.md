---
version: "4.0"
last_modified: 2026-05-21
tags: [project-memory, v4]
---

# Project Memory — qa-test

> FreeBSD Kernel QA Testing Environment for AMD AMDESE. POSIX sh harness that orchestrates patch validation: clone → build → install → verify → test → report.

## Identity

| Field        | Value                                         |
|--------------|-----------------------------------------------|
| Project      | qa-test                                       |
| Owner        | Osvaldo J. Filho (ojanerif@amd.com)           |
| Platform     | FreeBSD 16.0-CURRENT · amd64                  |
| Stack        | POSIX sh, make, git, kyua, pmcstat            |
| Issue prefix | SWLSVROS-* (amd.atlassian.net)                |
| QA repo      | github.com/ojanerif/freebsd-qa-tester         |
| Source repo  | github.com/AMDESE/freebsd-src                 |
| dev-docs     | v4.0 - Project Memory OS                      |

## Current Active QA Tickets

| Ticket           | Status     | SHA (short)  | Notes                          |
|------------------|------------|--------------|--------------------------------|
| SWLSVROS-6519    | active     | a3712a188aee | IBS errata #1238/#1293 cycle 2 |
| SWLSVROS-6414    | QA-PASS    | —            | Zen6 IBS ibs_ctl2 init         |
| SWLSVROS-6363    | closed     | —            | PMC/TSC                        |

## Architecture

Single-file POSIX sh harness (`qa-tester.sh`, ~950 lines) divided into:
- **orchestrator** — `main()`, `run_menu()`, `gather_info()`
- **session-manager** — `_save_session_state()`, `load_previous_session()`
- **command-engine** — `run_cmd()`, `run_long_cmd()`, `info/pass/fail/warn/record`
- **build-pipeline** — `action_sync_source()`, `action_build_world()`, `action_check_kernel()`
- **reporting** — `generate_report()`, `send_report_email()`
- **qa-tests** — `qa-branches/<QA_ID>/<QA_ID>.sh`

## Key Conventions

- POSIX `/bin/sh` only — no bashisms
- Append-only results.tsv (STATUS\tNAME\tNOTE)
- Dual-write session state (`state.env` + `last-session.env`)
- QA scripts: structured `# Branch:` / `# SHA:` headers
- Email: `sendmail` → dma → `atlsmtp10.amd.com`

## Learning Log

2026-05-21 | Migrated to dev-docs v4.0 Project Memory OS | project
