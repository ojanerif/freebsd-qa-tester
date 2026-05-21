---
scope: global
last_modified: 2026-05-18
tags: [global, architecture, patterns]
---

# Global Patterns & Decisions

Patterns appearing in 3 or more modules belong here. Module-specific decisions stay in their own file.

## Architecture Overview

`qa-test` is a single-file POSIX shell harness (`qa-tester.sh`, ~900 lines) that orchestrates the full FreeBSD kernel patch QA lifecycle for AMD's AMDESE team. The script is divided into layered subsystems — session management, command execution, build pipeline, test runner, and reporting — all sharing a common logging/result-recording API. Per-ticket QA test scripts live in `qa-branches/<QA_ID>/` and are self-describing via structured header comments.

## Cross-cutting Decisions

### [DECISION] POSIX sh only — no bashisms
**Date:** 2026-04-28
**Context:** The target platform is FreeBSD CURRENT, whose `/bin/sh` is a strict POSIX shell, not bash.
**Decision:** The entire codebase uses `/bin/sh` with no bash-specific syntax (no `[[`, no `$(( ))` arrays, no `local` except within functions where POSIX permits it).
**Impact:** qa-tester.sh, all qa-branches/*.sh scripts

### [DECISION] Append-only results tracking via TSV
**Date:** 2026-04-28
**Context:** Need a format readable by both shell scripts (awk) and humans.
**Decision:** `results.tsv` uses tab-separated STATUS\tNAME\tNOTE; the `record()` function appends to it and simultaneously prints colored output. Never overwritten mid-session — only truncated at session start.
**Impact:** reporting, command-engine

### [DECISION] Dual-write session state
**Date:** 2026-04-28
**Context:** Sessions may span reboots; per-session state must be immutable while a global resume file must always reflect the latest run.
**Decision:** `_save_session_state()` writes to both `reports/<session>/state.env` (frozen per-session) and `last-session.env` (always-current global).
**Impact:** session-manager, orchestrator

## Shared Utilities & Patterns

### [SNIPPET] Structured header metadata in QA test scripts
**Use:** Every QA test script at qa-branches/<ID>/<ID>.sh must carry this header so the orchestrator can auto-extract branch, SHA, and PR without user input.
```sh
#!/bin/sh
# QA: <TICKET_ID> - <short description>
# Branch: <full branch name>
# SHA:    <full 40-char commit hash>
# Upstream PR: <URL>
```

### [SNIPPET] POSIX-safe exit code capture (subshell-safe)
**Use:** When you need to capture both stdout/stderr and exit code from a command without a subshell, because assignment in a pipe loses the exit code.
```sh
_rc_tmp=$(mktemp /tmp/qa-rc.XXXXXX)
{ some_command; printf '%s' "$?" > "${_rc_tmp}"; } 2>&1 | tee -a "${LOG_FILE}"
_rc=$(cat "${_rc_tmp}"); rm -f "${_rc_tmp}"
```

### [SNIPPET] Consistent [PASS]/[FAIL]/[SKIP] markers for test scripts
**Use:** Every assertion in a qa-branches/*.sh script must emit exactly one of these markers so the orchestrator can count results.
```sh
pass() { printf '[PASS] %s\n' "$1"; PASS=$((PASS + 1)); }
fail() { printf '[FAIL] %s\n' "$1"; FAIL=$((FAIL + 1)); }
skip() { printf '[SKIP] %s\n' "$1"; SKIP=$((SKIP + 1)); }
```

### [SNIPPET] mktemp-based temp file lifecycle
**Use:** All temporary files use mktemp with a descriptive prefix and are always cleaned up with `rm -f` even on failure paths.
```sh
_tmp=$(mktemp /tmp/qa-<purpose>.XXXXXX)
# ... use _tmp ...
rm -f "${_tmp}"
```

### [SNIPPET] Two-phase QA script structure (Phase A build/install, Phase B runtime)
**Use:** Any QA ticket that requires buildworld + buildkernel + BE install. Phase A runs on the current boot; Phase B runs after rebooting into the QA BE. The script auto-detects which phase applies by checking the running kernel SHA (T5). Seen in: SWLSVROS-6316, SWLSVROS-6414, SWLSVROS-6519.
```sh
# Phase A guard (T1-T4): build + install; always runs
# Phase B guard (T5+): gated on KERNEL_OK after SHA check
KERNEL_OK=0
UNAME_V=$(uname -v)
RUNNING_SHORT=$(printf '%s' "${UNAME_V}" \
    | grep -oE 'g[0-9a-f]{7,12}' | head -1 | sed 's/^g//')
if printf '%s' "${EXPECTED_SHA}" | grep -q "^${RUNNING_SHORT}"; then
    pass "T5: Running kernel SHA matches QA branch"
    KERNEL_OK=1
else
    fail "T5: SHA mismatch -- reboot into QA BE then re-run"
fi
if [ "${KERNEL_OK}" -eq 0 ]; then
    for _t in T6 T7 T8 T9 T10; do skip "${_t}: Skipped -- not on QA kernel"; done
else
    # Phase B tests here ...
fi
```

### [SNIPPET] BE side-load install sequence (buildworld + buildkernel cycle)
**Use:** Every ticket that touches both kernel and userland and requires etcupdate. Canonical 7-step sequence used by SWLSVROS-6316, SWLSVROS-6414, SWLSVROS-6519.
```sh
# T4a: identify rollback BE
OLD_BE=$(bectl list -H 2>/dev/null | awk '{ if (index($2,"R")) print $1 }' | head -1)
# T4b: create QA BE (destroy if already exists)
bectl create "${BE_NAME}"
# T4c–T4f: mount, installkernel, etcupdate -p, installworld, etcupdate -B, umount
bectl mount "${BE_NAME}" "${MNT}"
make -C "${SRC_DIR}" installkernel DESTDIR="${MNT}" KERNCONF="${KERNCONF}"
etcupdate -p -D "${MNT}" -s "${SRC_DIR}"
make -C "${SRC_DIR}" installworld DESTDIR="${MNT}"
etcupdate -B -D "${MNT}" -s "${SRC_DIR}"
bectl umount "${BE_NAME}"
# T4g: activate for next boot
bectl activate "${BE_NAME}"
# NOTE: MAKEOBJDIRPREFIX must be exported, not passed on the command line.
```

## Known Systemic Issues

None documented at bootstrap time.

## New Module Template

When creating a new module file, copy this template exactly:

```
---
module: <id>
type: module | api | infra
status: active
stack: <stack>
last_modified: <today>
related: []
tags: [qa-test, <type>]
---

# <Module Name>
> One sentence purpose.

## Overview

## Main Files
- `path/file` — responsibility

## Dependencies
- modules: [[name]]
- apis: [[name]]
- tables: name

## Decisions

## Known Bugs

## TODOs

## Snippets

## Learning Log
```

## Learning Log

2026-04-28 | Bootstrap complete. 6 modules + 2 infra entries identified. Imported architecture, session-management, and workflow docs. 4 cross-cutting patterns captured. | all
2026-05-18 | Added two global snippets that now appear in 3+ QA test scripts: two-phase script structure (Phase A build/install, Phase B runtime gated on kernel SHA) and BE side-load install sequence (7-step bectl/etcupdate pattern). Triggered by SWLSVROS-6414 and SWLSVROS-6519 joining SWLSVROS-6316. | all
