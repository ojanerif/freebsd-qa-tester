---
module: command-engine
type: module
status: active
stack: POSIX sh, FreeBSD
last_modified: 2026-04-28
related: [[orchestrator], [reporting]]
tags: [qa-test, module]
---

# command-engine

## Purpose

Provides the full execution layer for `qa-tester.sh`: structured logging, interactive prompting, per-test result recording, and two command-runner primitives (`run_cmd` / `run_long_cmd`). Every other module writes to the log and results files exclusively through these functions.

---

## Location

`qa-tester.sh`, lines 75–209.

---

## Responsibilities

| Area | Lines | What it owns |
|---|---|---|
| Logging | 75–88 | Timestamped, levelled output to stdout + `${LOG_FILE}` |
| Interactive helpers | 90–118 | Prompting, default handling, Y/n gating |
| Result tracking | 122–132 | Appending rows to `${RESULTS_FILE}` (results.tsv) |
| Command runners | 136–209 | Executing subprocesses with PASS/FAIL accounting |

---

## Functions

### Logging (lines 75–88)

#### `ts()`
Returns the current wall-clock time as `HH:MM:SS`. Called inline by every log function; not meant to be called directly by callers outside this module.

#### `info()`, `pass()`, `fail()`, `warn()`
Uniform signature: accept `$*` as the message.

Each function:
1. Formats a line as `<ts> [LEVEL] <msg>`.
2. Writes it to stdout — with ANSI color wrapping the level tag when stdout is a terminal.
3. Appends the same line (including any escape sequences, which terminals consume) to `${LOG_FILE}` via `tee -a`.

Color mapping: `[INFO]` → CYN, `[PASS]` → GRN, `[FAIL]` → RED, `[WARN]` → YLW.

#### `section(label)`
Prints a decorated section divider to the terminal: a bold-blue line of `────…` characters, the label indented on its own line, then a second rule. Writes a plain `=== label ===` block directly to `${LOG_FILE}` (bypasses `tee` — the terminal rendering would produce garbage in a log viewer).

---

### Interactive Helpers (lines 90–118)

#### `hint(msg)`
Prints a single cyan-colored hint line to stdout. Does not log. Used for inline guidance text before an `ask` call.

#### `ask(prompt, default, varname)`
Prompts the user with a bold prompt string. If `default` is non-empty it is shown in yellow inside brackets. Reads one line with `read -r`. Falls back to `default` if the user presses Enter without input. Assigns the result to the shell variable named by `varname` using `eval` — the only occurrence of `eval` in the entire script.

#### `ask_yn(prompt, default)`
Specialized wrapper around `ask` for boolean decisions. `default` is `y` or `n` (defaults to `y`). Renders `[Y/n]` when the default is yes, `[y/N]` when no. Returns `0` for yes, `1` for no, matching standard shell convention for use in `if` statements.

---

### Result Tracking (lines 122–132)

#### `record(status, name, note)`
Appends a TSV row to `${RESULTS_FILE}`:

```
STATUS<TAB>NAME<TAB>NOTE
```

Valid status values and their log dispatch:

| status | log function called |
|---|---|
| `PASS` | `pass()` |
| `FAIL` | `fail()` |
| `WARN` | `warn()` |
| `SKIP` | `info()` prefixed with "SKIP" |

All test modules must go through `record()` rather than calling `pass()`/`fail()` directly, so that `${RESULTS_FILE}` stays authoritative for the reporting module.

---

### Command Runners (lines 136–209)

#### `run_cmd(label, cmd...)`
Runs a command expected to complete quickly (seconds). Captures full stdout+stderr, logs it, and records PASS or FAIL.

Key behavior:
- Logs the full command string via `info "CMD: $*"` before execution.
- Uses the **mktemp exit-code capture pattern** (see Snippets) to recover `$?` after piping through `tee`. Without this, the pipe would cause `$?` to reflect `tee`'s exit code instead of the command's.
- On PASS records `pass "${_label}"`. On FAIL records `fail "${_label} (exit=${_rc})"` and returns the original exit code.
- Returns the command's exit code to the caller so test logic can branch on it.

#### `run_long_cmd(label, cmd...)`
Runs a command that may take many seconds or minutes. Designed to keep the terminal informative rather than silent.

Key behavior:
- Redirects all output to a mktemp file and runs the command in the background (`"$@" > _out_tmp 2>&1 &`), capturing the PID into `_pid`.
- When stdout is a terminal, enters a `kill -0 $pid` polling loop (1 s sleep per tick) that renders an animated spinner (`| / - \`), elapsed time as `MM:SS`, and the last non-blank line of the output file — truncated to fit the available columns reported by `tput cols`.
- After `wait $_pid` resolves, appends the full output file to `${LOG_FILE}`.
- On failure prints the last 20 lines of output to stdout for immediate visibility, then removes the temp file.
- Does not use the mktemp RC trick because it calls `wait`, which reliably returns the background process's exit code directly.

---

## Snippets

### mktemp exit-code capture pattern

Used in `run_cmd` (line 143) to preserve `$?` across a pipe. A pipeline runs each segment in a subshell, so the exit code of the left-hand command is lost by the time the pipeline exits.

```sh
_rc_tmp=$(mktemp /tmp/qa-rc.XXXXXX)
{ "$@"; printf '%s' "$?" > "${_rc_tmp}"; } 2>&1 | tee -a "${LOG_FILE}"
_rc=$(cat "${_rc_tmp}" 2>/dev/null || printf '1')
rm -f "${_rc_tmp}"
```

How it works: `$@` and `printf` run in the same subshell (grouped with `{}`), so `printf` sees the true `$?` of `$@` and writes it to a temp file before the subshell exits. The parent reads that file after the pipeline finishes. The `|| printf '1'` guards against a race where the file was not created at all.

### Color-guard pattern

Set at startup (lines 64–71). All color variables are assigned only when file descriptor 1 is a terminal; otherwise they are empty strings. Because every `printf` format string embeds the variable rather than a hard-coded escape, the same code path produces colored output interactively and clean plain-text output when piped or redirected.

```sh
if [ -t 1 ]; then
    RED=$(printf '\033[0;31m');  GRN=$(printf '\033[0;32m')
    YLW=$(printf '\033[1;33m');  BLU=$(printf '\033[0;34m')
    CYN=$(printf '\033[0;36m');  BLD=$(printf '\033[1m')
    RST=$(printf '\033[0m')
else
    RED=''; GRN=''; YLW=''; BLU=''; CYN=''; BLD=''; RST=''
fi
```

Usage in a log function:

```sh
pass() { printf '%s %b[PASS]%b %s\n' "$(ts)" "$GRN" "$RST" "$*" | tee -a "${LOG_FILE}"; }
```

When stdout is not a tty, `$GRN` and `$RST` expand to empty strings, so the log file contains no escape sequences.

---

## Data Flow

```
caller
  └─ run_cmd / run_long_cmd
       ├─ info()  ──────────────────────────────► stdout + LOG_FILE
       ├─ subprocess stdout+stderr  ─────────────► stdout + LOG_FILE (via tee / cat)
       └─ record(PASS|FAIL, label, note)
            ├─ pass() / fail()  ─────────────────► stdout + LOG_FILE
            └─ printf TSV row  ──────────────────► RESULTS_FILE
```

---

## Dependencies

| Dependency | Type | Notes |
|---|---|---|
| `${LOG_FILE}` | global var | Set by orchestrator before any log function is called |
| `${RESULTS_FILE}` | global var | Set by orchestrator; path to results.tsv |
| `mktemp` | FreeBSD built-in | Used for rc temp file and output temp file |
| `tput cols` | terminal | Queried at spinner start; falls back to 100 if unavailable |
| `date +%s` | POSIX date | Used for elapsed-time calculation in `run_long_cmd` |
| `kill -0` | POSIX signal | Used to poll background PID liveness in `run_long_cmd` |

---

## Gotchas

- `ask()` uses `eval` to assign to a named variable. The `varname` argument must be a valid shell identifier. Passing user-controlled input as `varname` would be a code-injection risk; all current callers pass a literal string.
- `section()` writes to `${LOG_FILE}` directly with `>>`, not through `tee`. This means the section header never appears on stdout in the log representation — only on the terminal.
- `run_long_cmd` spinner only activates when `[ -t 1 ]`. In CI or piped contexts the process runs silently; the output still lands in `${LOG_FILE}` via `cat _out_tmp >> LOG_FILE` after `wait`.
- `run_cmd` pipes through `tee -a`, which means the command's output is visible on the terminal in real time even before `pass`/`fail` is recorded.
- Both runners remove their temp files unconditionally (`rm -f`). If the script is killed mid-run, `/tmp/qa-rc.*` or `/tmp/qa-out.*` files may be orphaned.

---

## Learning Log

2026-04-28 | First read. Execution layer uses mktemp trick for POSIX-safe exit code capture and kill -0 polling for the spinner. Color output gracefully degrades when not a tty. | command-engine
