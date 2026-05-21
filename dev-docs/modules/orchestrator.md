---
module: orchestrator
type: module
status: active
stack: POSIX sh, FreeBSD
last_modified: 2026-05-21
related: [[session-manager], [command-engine], [build-pipeline], [qa-tests], [reporting]]
tags: [qa-test, module]
---

# Orchestrator
> Single entry point that wires together session management, user input collection, and the persistent action menu for the FreeBSD Kernel QA testing environment.

## Overview

The orchestrator is the top-level controller of `qa-tester.sh`. It runs in three sequential phases every time the script is invoked:

1. **Initialization** (top-level, lines 28–71) — sets up all path variables, creates the session report directory, truncates output files, and configures color escape codes.
2. **Pre-flight** (`main` → `load_previous_session` → `gather_info`, lines 881–896 and 271–374) — detects and optionally resumes a previous session, then collects or confirms the QA ticket ID, build paths, and parallel-job count before saving state.
3. **Action loop** (`run_menu`, lines 850–875) — presents a numbered menu indefinitely; each choice dispatches to an action function. The loop only exits when the user enters `q` or `Q`.

The script is a single POSIX sh file (~900 lines) with no bashisms and runs on FreeBSD only. `set -u` is active from line 28 onward, so every variable is initialized at the top of the initialization block before any function is called.

## Main Files
- `qa-tester.sh` — the entire orchestrator (and all other modules); entry point, session setup, menu loop, and dispatch table

## Dependencies
- modules: [[session-manager]], [[command-engine]], [[build-pipeline]], [[qa-tests]], [[reporting]]

## Decisions

### [DECISION] Single-file architecture
**Date:** 2026-04-28
**Context:** The tool targets a bare FreeBSD kernel QA workflow with no package manager or dependency installer available on the test host.
**Decision:** Keep all logic in one self-contained POSIX sh script so it can be dropped onto any FreeBSD machine and run immediately.
**Discarded alternatives:** Splitting into sourced library files (would require managing relative paths and sourcing order); Python/Ruby wrapper (not guaranteed to be present on a fresh FreeBSD install).
**Impact:** All modules share one file; changes anywhere require reading the full script to understand side-effects.

### [DECISION] `set -u` with full variable pre-initialization
**Date:** 2026-04-28
**Context:** POSIX sh does not provide typed variables or default-value guarantees. Unset variable references in deeply nested functions cause silent empty-string expansion bugs.
**Decision:** Enable `set -u` at line 28 and initialize every global variable to an explicit empty string or computed default in the initialization block (lines 46–60) before any function is called.
**Discarded alternatives:** Using `${VAR:-}` fallbacks everywhere (masks genuine bugs); not using `set -u` (allows silent failures).
**Impact:** Any new global variable must be declared in the initialization block or the script will abort on first use.

### [DECISION] Auto-generated vs. user-supplied session name
**Date:** 2026-04-28
**Context:** Testers run multiple sessions per day and also need to resume a specific named session from a previous run.
**Decision:** `SESSION_NAME` defaults to `session_YYYYMMDD_HHMMSS` (derived from `TIMESTAMP` at startup) but is overridden by `$1` when the script is invoked with an argument.
**Discarded alternatives:** Always prompting for a name interactively (too slow for automated re-runs); always auto-generating (prevents targeted resume by name).
**Impact:** Report directory, log file, and state file paths all derive from `SESSION_NAME`, so supplying `$1` deterministically pins all output paths.

### [DECISION] Persistent menu loop with no forced exit on error
**Date:** 2026-04-28
**Context:** Kernel build and test actions can fail independently (e.g., build fails but the tester still wants to run other checks). Exiting on any failure would force a full restart.
**Decision:** `run_menu` is an infinite `while true` loop; action functions return non-zero on failure but the loop continues. Only `q`/`Q` exits with code 0.
**Discarded alternatives:** Exiting after the first failed action (too disruptive); making failures non-fatal inside action functions and swallowing the return code (hides errors).
**Impact:** The tester can retry or skip failed steps freely. Action functions must never call `exit` themselves except for unrecoverable fatal errors.

## Known Bugs

None recorded at time of first read.

## TODOs

None recorded at time of first read.

## Snippets

### Initialization block — path and color setup (lines 28–71)
```sh
set -u

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SESSION_NAME="${1:-session_${TIMESTAMP}}"
REPORT_DIR="${SCRIPT_DIR}/reports/${SESSION_NAME}"
LOG_FILE="${REPORT_DIR}/session.log"
REPORT_FILE="${REPORT_DIR}/qa-report-${TIMESTAMP}.txt"
RESULTS_FILE="${REPORT_DIR}/results.tsv"
STATE_FILE="${REPORT_DIR}/state.env"
LAST_SESSION_FILE="${SCRIPT_DIR}/last-session.env"

mkdir -p "${REPORT_DIR}"
: > "${RESULTS_FILE}"
: > "${LOG_FILE}"
```
`REPORT_FILE` embeds `TIMESTAMP` (not `SESSION_NAME`) so multiple runs inside one named session produce distinct report files. `RESULTS_FILE` and `LOG_FILE` are truncated (`: >`) on every startup, even for a named resume.

### `gather_info` — QA ID retry loop (lines 339–346)
```sh
local _qa_ok=0
while [ "${_qa_ok}" -eq 0 ]; do
    ask "QA ID" "${QA_ID:-}" QA_ID
    if _load_qa_testfile; then
        _qa_ok=1
    else
        printf '%bTry a different ID or Ctrl-C to abort.%b\n' "$YLW" "$RST"
    fi
done
```
The loop spins until `_load_qa_testfile` returns 0. That function sets `QA_FILE` to `qa-branches/<ID>/<ID>.sh` and returns 1 if the file does not exist. It also parses `QA_BRANCH`, `EXPECTED_SHA`, and `UPSTREAM_PR` from comment headers (`# Branch:`, `# SHA:`, `# Upstream PR:`) or fallback shell variable assignments inside the test script.

### `run_menu` — dispatch table (lines 850–875)
```sh
run_menu() {
    local _choice
    while true; do
        show_menu
        printf '%b Choice%b: ' "$BLD" "$RST"
        read -r _choice

        case "${_choice}" in
            1) action_fetch_latest   ;;
            2) action_clone_branch   ;;
            3) action_build_world    ;;
            4) action_check_kernel   ;;
            5) action_run_specific   ;;
            6) action_run_full_suite ;;
            7) action_run_all        ;;
            q|Q)
                printf '\n%bSession log : %s%b\n' "$BLD" "${LOG_FILE}"  "$RST"
                printf '%bReport dir  : %s%b\n\n' "$BLD" "${REPORT_DIR}" "$RST"
                exit 0 ;;
            "")
                ;;
            *)  warn "Unknown choice '${_choice}' — enter 1-7 or q." ;;
        esac
    done
}
```
An empty `Enter` keypress is silently ignored. Any other unknown input prints a warning and re-displays the menu.

### `main` — three-phase entry point (lines 881–896)
```sh
main() {
    # ... entry banner ...
    load_previous_session
    gather_info
    run_menu
}

main "$@"
```
`main` receives `"$@"` but only `$1` (session name) is meaningful; it was already consumed at initialization time via `SESSION_NAME="${1:-session_${TIMESTAMP}}"`, so `main "$@"` is effectively a no-op argument pass-through kept for consistency.

## [BUG] tr -d '-:' illegal option on FreeBSD
**Found:** 2026-05-21
**Symptom:** `tr: illegal option -- :` printed during `action_check_kernel`; AMD branch SHA never extracted from `uname -v`.
**Root cause:** FreeBSD `tr` treats `-` as an option prefix when it appears in the middle of the delete set. `'-:'` was parsed as option `-:`.
**Fix/Workaround:** Replaced `tr -d '-:'` with `sed 's/^-//;s/:$//'` at qa-tester.sh:674.
**Status:** resolved

## [DECISION] Email delivery via sendmail/dma, same pattern as freebsd-ci-actions/run.sh
**Date:** 2026-05-21
**Context:** Adding email reporting to qa-tester.sh. Need to pick SMTP transport and defaults.
**Decision:** Mirror freebsd-ci-actions/run.sh exactly: `SENDER_EMAIL=freebsd-ci-actions@amd.com`, `REPORT_EMAIL=freebsd-test@mailman-svr.amd.com,ojanerif@amd.com`, delivery via `sendmail` (dma → atlsmtp10.amd.com). MIME multipart: plain summary as body, report file as attachment.
**Discarded alternatives:** Inline plain text only (no attachment); external curl/SMTP — not available on base FreeBSD.
**Impact:** qa-tester.sh (new `send_report_email`, `--email` flag, `EMAIL_REQUESTED` var, menu option 5, gather_info prompt)

## Learning Log

2026-04-28 | First read. Orchestrator is a single 900-line POSIX sh file. Documented main loop, menu dispatch, and initialization. | orchestrator
2026-05-21 | Fixed tr -d '-:' bug (FreeBSD tr treats - mid-set as a flag); replaced with sed. Added --email CLI flag, REPORT_EMAIL/SENDER_EMAIL/EMAIL_REQUESTED vars, interactive email prompt in gather_info, send_report_email() MIME function, and menu option 5. | orchestrator
