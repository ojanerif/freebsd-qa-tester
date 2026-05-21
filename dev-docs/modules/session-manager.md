---
module: session-manager
type: module
status: active
stack: POSIX sh, FreeBSD
last_modified: 2026-04-28
related: [[orchestrator]]
tags: [qa-test, module]
---

# Session Manager
> Persists and restores QA session state across reboots and re-invocations via dual-write state files and three resume modes.

## Overview

The session manager owns two responsibilities: (1) loading and offering to resume a previous session at startup, and (2) saving a consistent snapshot of all 11 session state variables after the tester confirms their settings.

The central design constraint is reboot safety. Because a full FreeBSD kernel build can take hours, the tester may reboot the machine mid-test. On the next invocation, `load_previous_session()` detects `last-session.env`, shows the saved values, and offers three resume paths. Choosing REUSE skips every prompt and goes straight to the action menu, making post-reboot continuation a single keypress.

State is written to two files in parallel by `_save_session_state()`:

- `reports/<session>/state.env` — frozen per-session copy; never mutated after creation.
- `last-session.env` — always reflects the most recent save, used as the resume source on next invocation.

A third helper, `_load_qa_testfile()`, bridges the session and test subsystems: given a `QA_ID`, it locates the per-ticket test script, parses its structured header comments to populate `QA_BRANCH`, `EXPECTED_SHA`, and `UPSTREAM_PR`, and synthesizes `JIRA_URL`. It is called from `gather_info()` (in [[orchestrator]]) for NEW and MODIFY modes, but is skipped entirely in REUSE mode because these values are already loaded from the state file.

## Main Files

- `qa-tester.sh` lines 216–249 — `_load_qa_testfile()`: locates and parses a QA test script header
- `qa-tester.sh` lines 251–265 — `_save_session_state()`: dual-writes all 11 state variables
- `qa-tester.sh` lines 271–306 — `load_previous_session()`: detects, displays, and offers to resume a saved session
- `last-session.env` (project root) — always-current global resume file; valid sh assignment syntax
- `reports/<session>/state.env` — frozen per-session snapshot; written once at the end of `gather_info()`

## Dependencies

- modules: [[orchestrator]] (calls `load_previous_session()` before `gather_info()`; calls `_save_session_state()` at the end of `gather_info()`)
- infra: [[jira-amd]] (JIRA_URL is synthesized here as `https://amd.atlassian.net/browse/${QA_ID}`)
- infra: [[amdese-freebsd-src]] (default values for `KERNEL_REPO` and `KERNEL_REPO_ALT` are set in the NEW resume path)
- files: `qa-branches/<QA_ID>/<QA_ID>.sh` (parsed by `_load_qa_testfile()`)

## Decisions

### [DECISION] Dual-write to both state.env and last-session.env
**Date:** 2026-04-28
**Context:** Sessions may span reboots. A per-session snapshot must be immutable for audit/reproducibility, but a global file must always reflect the latest run for easy resume.
**Decision:** `_save_session_state()` builds the content string once in a local variable and writes it to both `reports/<session>/state.env` and `last-session.env` atomically in sequence.
**Discarded alternatives:** Writing only a single file would either lose immutability (if overwritten) or lose the global resume capability (if kept per-session only).
**Impact:** session-manager, orchestrator

### [DECISION] Source last-session.env with `. "${LAST_SESSION_FILE}"` — requires valid sh syntax
**Date:** 2026-04-28
**Context:** The simplest way to restore shell variables is to source a file of assignments. This mandates that the file must always be valid POSIX sh.
**Decision:** `_save_session_state()` uses `printf` with single-quoted values (`KEY='value'`) so the output is always valid sh assignment syntax. Special characters inside values could theoretically break this, but QA IDs, paths, and URLs are constrained enough for this to be safe in practice.
**Discarded alternatives:** A custom key=value parser would be more robust but adds complexity for little real-world gain given the narrow character set of the actual values.
**Impact:** session-manager

### [DECISION] JIRA_URL is synthesized, not user-entered
**Date:** 2026-04-28
**Context:** The Jira URL is always `https://amd.atlassian.net/browse/<QA_ID>`. Asking the user to enter it would be redundant and error-prone.
**Decision:** `_load_qa_testfile()` sets `JIRA_URL` automatically from `QA_ID` after the test file is found. It is then persisted like any other state variable.
**Discarded alternatives:** None considered; derivation is deterministic.
**Impact:** session-manager, jira-amd infra

### [DECISION] Header comments take precedence over variable assignments in QA test scripts
**Date:** 2026-04-28
**Context:** Older QA test scripts used bare `EXPECTED_BRANCH=` and `EXPECTED_SHA=` variable assignments. Newer scripts use structured `# Branch:` / `# SHA:` / `# Upstream PR:` header comments (see global pattern in `_global.md`).
**Decision:** `_load_qa_testfile()` tries the `# Branch:` / `# SHA:` comment patterns first. Only if those yield empty strings does it fall back to parsing the `EXPECTED_BRANCH=` / `EXPECTED_SHA=` variable assignments.
**Discarded alternatives:** Requiring all scripts to use only one format would break backwards compatibility with existing qa-branches scripts.
**Impact:** session-manager, qa-tests

### [DECISION] REUSE mode skips _load_qa_testfile() entirely
**Date:** 2026-04-28
**Context:** In REUSE mode, all 11 state variables are already populated by sourcing `last-session.env`. Re-parsing the QA test file would be redundant and could fail if the file moved.
**Decision:** `gather_info()` returns early after a confirmation prompt when `RESUME_MODE=reuse`, calling `_save_session_state()` to refresh the per-session snapshot without touching any variables.
**Discarded alternatives:** Always re-parsing the test file on resume would add robustness against stale state but complicates the reboot-safe use case.
**Impact:** session-manager, orchestrator

## Known Bugs

None documented at this time.

## TODOs

### [TODO] Guard against single-quote characters in state variable values
**Priority:** low
**Context:** `_save_session_state()` wraps values in single quotes. A value containing a literal single quote (e.g., a repo path with an apostrophe) would produce invalid sh syntax in the state files and break sourcing on resume.
**Status:** pending

### [TODO] Validate last-session.env before sourcing
**Priority:** low
**Context:** If `last-session.env` is manually edited or truncated (e.g., by a crashed write), sourcing it could leave variables partially set or throw a parse error that aborts the script.
**Status:** pending

## Snippets

### [SNIPPET] _save_session_state — dual-write pattern
**Use:** Build content once, write to both per-session and global state files in a single function call.
```sh
_save_session_state() {
    local _c
    _c=$(printf \
        "QA_ID='%s'\nQA_FILE='%s'\nJIRA_URL='%s'\nUPSTREAM_PR='%s'\n\
KERNEL_REPO='%s'\nKERNEL_REPO_ALT='%s'\nQA_BRANCH='%s'\nEXPECTED_SHA='%s'\n\
SRC_DIR='%s'\nOBJ_DIR='%s'\nMAKE_JOBS='%s'\n" \
        "${QA_ID}" "${QA_FILE}" \
        "${JIRA_URL}" "${UPSTREAM_PR:-}" \
        "${KERNEL_REPO}" "${KERNEL_REPO_ALT}" \
        "${QA_BRANCH}" "${EXPECTED_SHA}" \
        "${SRC_DIR}" "${OBJ_DIR}" "${MAKE_JOBS}")
    printf '%s\n' "${_c}" > "${STATE_FILE}"
    printf '%s\n' "${_c}" > "${LAST_SESSION_FILE}"
}
```

### [SNIPPET] _load_qa_testfile — comment-first, variable fallback parsing
**Use:** Extract metadata from a QA test script header, falling back to legacy variable assignment syntax if the structured comments are absent.
```sh
QA_BRANCH=$(grep '^# Branch:' "${QA_FILE}" | head -1 \
    | sed 's/^# Branch:[[:space:]]*//')
EXPECTED_SHA=$(grep '^# SHA:' "${QA_FILE}" | head -1 \
    | sed 's/^# SHA:[[:space:]]*//')

# Fallback for older scripts that use bare variable assignments
if [ -z "${QA_BRANCH}" ]; then
    QA_BRANCH=$(grep '^EXPECTED_BRANCH=' "${QA_FILE}" | head -1 \
        | sed "s/^EXPECTED_BRANCH=//;s/^['\"]//;s/['\"]$//")
fi
```

### [SNIPPET] load_previous_session — three-mode resume gate
**Use:** Detect a saved session, display its key values, and set RESUME_MODE to control whether gather_info() prompts the user or skips straight to the menu.
```sh
load_previous_session() {
    [ ! -f "${LAST_SESSION_FILE}" ] && return
    . "${LAST_SESSION_FILE}"          # populate all 11 state variables
    # ... display saved values ...
    ask "Choice" "1" _RESUME_CHOICE
    case "${_RESUME_CHOICE}" in
        2) RESUME_MODE="modify" ;;    # saved values become prompt defaults
        3) RESUME_MODE="new"          # reset all variables to system defaults
           QA_ID=""; QA_FILE=""; QA_BRANCH=""; EXPECTED_SHA=""
           JIRA_URL=""; UPSTREAM_PR=""
           KERNEL_REPO="https://github.com/AMDESE/freebsd-src"
           KERNEL_REPO_ALT="ssh://git@sos-git.amd.com/freebsd-src.git"
           SRC_DIR="/usr/src"; OBJ_DIR="/usr/obj"
           MAKE_JOBS="$(sysctl -n hw.ncpu 2>/dev/null || printf '4')" ;;
        *) RESUME_MODE="reuse" ;;     # default: skip all prompts
    esac
}
```

## Learning Log

2026-04-28 | First read. Session manager handles reboot-safe resume via dual-write state files and 3 resume modes. | session-manager
