# qa-test — AI Agent Instructions

This file is the authoritative instruction set for any AI agent working
on this project. It is referenced by all agent-specific rule files.
When in conflict, this file takes precedence.

## Memory System

This project uses a structured developer memory system in dev-docs/.
The system persists decisions, bugs, patterns, and learned knowledge
across sessions and across different AI agents.

### How to look up a module

dev-docs/index.jsonl is a newline-delimited JSON index.
Each line describes one module, api, or infra component.
Use grep to find the relevant entry, then read only that file.

Examples:
  grep "session"   dev-docs/index.jsonl
  grep "report"    dev-docs/index.jsonl
  grep "build"     dev-docs/index.jsonl
  grep "keyword"   dev-docs/index.jsonl

Each entry has this shape:
  {
    "id": "module-name",
    "type": "module | api | infra",
    "file": "dev-docs/modules/module-name.md",
    "keywords": ["dirname", "ClassName", "function_name"],
    "description": "one sentence",
    "status": "active | paused | deprecated",
    "last_modified": "YYYY-MM-DD"
  }

### File to module mapping

| Path pattern or filename                   | Module id       |
|--------------------------------------------|-----------------|
| qa-tester.sh (main(), run_menu(), gather_info()) | orchestrator |
| qa-tester.sh (load_previous_session(), _save_session_state()) | session-manager |
| qa-tester.sh (run_cmd(), run_long_cmd(), info/pass/fail/warn) | command-engine |
| qa-tester.sh (action_build_world(), action_clone_branch(), action_fetch_latest(), action_check_kernel()) | build-pipeline |
| qa-tester.sh (generate_report(), _print_final_result(), record()) | reporting |
| qa-branches/<QA_ID>/<QA_ID>.sh            | qa-tests        |
| last-session.env, reports/*/state.env      | session-manager |
| reports/*/results.tsv, reports/*/qa-report-*.txt | reporting |
| file not listed above                      | grep index.jsonl first; if no match, create new module |

## Startup Protocol

At the start of every task:
1. Read this file if you have not already done so this session
2. grep dev-docs/index.jsonl for the module you are working on
3. Read that single module file — do not load other modules
4. If the module file does not exist, create it using the New Module
   Template in dev-docs/_global.md before starting work
5. Begin the task

## Shutdown Protocol

Before ending any task:
1. Append new entries to the relevant module file using the formats below
2. Append one line to that module's Learning Log section
3. Update last_modified in the module frontmatter to today
4. If you created a new module, append its entry to dev-docs/index.jsonl
5. If a pattern now appears in 3 or more modules, append it to
   dev-docs/_global.md under the appropriate section

## Entry Formats

Use these formats when appending to any module file.
Always append — never edit or delete past entries.

### Decision
## [DECISION] <title>
**Date:** YYYY-MM-DD
**Context:** why this decision was needed
**Decision:** what was chosen and implemented
**Discarded alternatives:** what was considered and why rejected
**Impact:** files or modules affected

### Bug
## [BUG] <short description>
**Found:** YYYY-MM-DD
**Symptom:** observable behavior
**Root cause:** underlying reason
**Fix/Workaround:** what resolves it
**Status:** resolved | workaround | open

### TODO
## [TODO] <title>
**Priority:** high | medium | low
**Context:** why it needs doing
**Status:** pending | in-progress | done

### Snippet
## [SNIPPET] <pattern name>
**Use:** when to apply this pattern
```lang
code here
```

### Learning Log entry format
YYYY-MM-DD | observation about the module or system | <module-id>

## Project Stack

| Layer         | Tools                                          |
|---------------|------------------------------------------------|
| Shell         | POSIX /bin/sh (FreeBSD)                        |
| Platform      | FreeBSD CURRENT (16.0-CURRENT)                 |
| Kernel build  | make buildworld, make buildkernel              |
| Source control| Git                                            |
| Test runner   | kyua (preferred) or *_test.sh fallback         |
| PMC testing   | pmcstat, pmc                                   |
| Issue tracker | Jira (amd.atlassian.net)                       |
| Reporting     | Custom shell TSV + plain text                  |

## Conventions

- All dev-docs content in English
- Obsidian-compatible: YAML frontmatter, [[wiki-links]], #tags
- Append only — never edit past entries, only add new dated ones
- Filenames: kebab-case, no accents or spaces
- index.jsonl: one valid JSON object per line, no surrounding array
- QA test scripts live at qa-branches/<QA_ID>/<QA_ID>.sh
- Script metadata (Branch, SHA, Upstream PR) is encoded in header comments
- POSIX sh only — no bashisms anywhere in this project
