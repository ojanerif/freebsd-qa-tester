---
module: qa-tests
type: module
status: active
stack: POSIX sh, pmcstat, pmc, libpmc, kyua, cc (spoof tool build)
last_modified: 2026-05-19
related: [[orchestrator], [build-pipeline], [reporting]]
tags: [qa-test, module]
---

# Module: qa-tests

Per-ticket QA test scripts that are discovered, parsed, and executed by the
orchestrator (`qa-tester.sh`). Each script lives under
`qa-branches/<QA_ID>/<QA_ID>.sh` and follows a strict header + output protocol
so the orchestrator can extract metadata without running the script and so
post-run counters can be tallied automatically.

---

## 1. Test Script Format

### 1.1 Location Convention

```
qa-branches/<QA_ID>/<QA_ID>.sh
```

Both the directory name and the script name must equal the Jira ticket ID
(e.g. `SWLSVROS-6363`). The orchestrator constructs the path as:

```sh
QA_FILE="${SCRIPT_DIR}/qa-branches/${QA_ID}/${QA_ID}.sh"
```

### 1.2 Required Header

The header must appear at the top of the file, before any executable code.
It is parsed by `_load_qa_testfile()` in `qa-tester.sh` (lines 216–249).

```sh
#!/bin/sh
# QA: <TICKET_ID> - <short description>
# Branch: <full branch name>
# SHA:    <40-char commit hash>
# Upstream PR: <URL>
```

`_load_qa_testfile()` uses `grep`/`sed` on the comment lines to populate the
orchestrator's session variables:

| Header comment    | Variable populated  |
|-------------------|---------------------|
| `# Branch:`       | `QA_BRANCH`         |
| `# SHA:`          | `EXPECTED_SHA`      |
| `# Upstream PR:`  | `UPSTREAM_PR`       |

**Fallback** — if any of the `# Branch:` / `# SHA:` comment lines are absent,
the parser falls back to looking for bare variable assignments at the top of the
script:

```sh
EXPECTED_BRANCH="<full branch name>"
EXPECTED_SHA="<40-char commit hash>"
```

This allows scripts that were authored before the comment convention was
established to still be loaded correctly.

### 1.3 Required Output Protocol

`_exec_specific_tests()` in `qa-tester.sh` (lines 721–749) runs the script
with `sh` and counts tagged output lines to produce the session summary. Every
test result line must use one of the four prefixes below.

| Prefix              | Meaning                              |
|---------------------|--------------------------------------|
| `[PASS] <desc>`     | Test passed                          |
| `[FAIL] <desc>`     | Test failed                          |
| `[SKIP] <desc>`     | Test skipped (precondition not met)  |
| `[INFO] <desc>`     | Informational message only           |

**Exit code contract**

- `exit 0` — all tests in the script passed (or only skips, no failures).
- Non-zero exit — at least one `[FAIL]` was recorded.

The orchestrator records the final outcome as `PASS` or `FAIL` in
`results.tsv` and includes the `PASS:N FAIL:N SKIP:N` counters in the session
report.

### 1.4 Snippet — Header Template for New Scripts

```sh
#!/bin/sh
# QA: <TICKET_ID> - <short description of the change under test>
# Branch: <full remote branch name, e.g. amdese/qa/TICKET-nnn-slug-YYYYMMDD>
# SHA:    <40-character commit hash>
# Upstream PR: <https://github.com/freebsd/freebsd-src/pull/NNNN>

set -u

QA_ID="<TICKET_ID>"
EXPECTED_SHA="<40-character commit hash>"
EXPECTED_BRANCH="<full remote branch name>"

PASS=0; FAIL=0; SKIP=0

pass() { printf '[PASS] %s\n' "$1"; PASS=$((PASS + 1)); }
fail() { printf '[FAIL] %s\n' "$1"; FAIL=$((FAIL + 1)); }
skip() { printf '[SKIP] %s\n' "$1"; SKIP=$((SKIP + 1)); }
info() { printf '[INFO] %s\n' "$1"; }

# ... test cases ...

if [ "${FAIL}" -eq 0 ]; then exit 0; else exit 1; fi
```

---

## 2. Existing Test: SWLSVROS-6363

**File:** `qa-branches/SWLSVROS-6363/SWLSVROS-6363.sh`

**Ticket:** Surface raw TSC in pmcstat log output + fix JSON format bug

**Branch:** `amdese/qa/SWLSVROS-6363-surface-raw-tsc-in-log-output-and-fix-JSON-format-bug-20260416`

**SHA:** `2646acf6efb3ec6e44ff3f80d0f51ed19a7fbc53`

**Upstream PR:** <https://github.com/freebsd/freebsd-src/pull/2085>

### 2.1 Scope

The script validates two distinct changes shipped on the QA branch:

1. `pmcstat` must emit a raw TSC (timestamp counter) value as the last field on
   every sampled-data line in its decoded output, and must record `tsc_freq=<hz>`
   in the `initlog` record.
2. `pmc filter -j` (backed by `libpmc_json.cc`) must produce valid NDJSON where
   every record contains a `"tsc"` field — exercising the JSON format bug fix.

### 2.2 Test Cases

| ID   | Description                                                                                  | Depends on |
|------|----------------------------------------------------------------------------------------------|------------|
| T1a  | HEAD SHA at `/usr/src` matches `EXPECTED_SHA`                                                | —          |
| T1b  | Branch name matches; detached HEAD with matching SHA is treated as non-critical               | —          |
| T2a  | `make -C /usr/src/lib/libpmc` succeeds                                                       | —          |
| T2b  | `make -C /usr/src/usr.sbin/pmcstat` succeeds                                                 | —          |
| T2c  | `make -C /usr/src/usr.sbin/pmc` succeeds                                                     | —          |
| T3   | Install of libpmc, pmcstat, and pmc; skipped if any T2 step failed                          | T2a–T2c    |
| T4   | `sudo pmcstat -S instructions -O /tmp/SWLSVROS-6363_test.pmc sleep 1` captures a non-empty log | —      |
| T5a  | Decoded output (`pmcstat -R`) contains an `initlog` record with `tsc_freq=<hz>`             | T4         |
| T5b  | All sampled data lines (non-`initlog`) end with a 10-or-more digit unsigned integer (TSC)   | T4         |
| T5c  | No negative TSC values; guards against a `%jd` signed-format regression                     | T4         |
| T6   | `pmcstat -R <log> -G <svg>` produces a non-empty SVG flamegraph; skipped if "no samples"    | T4         |
| T7a  | `pmc filter -j <log> <json>` produces non-empty output                                      | T4         |
| T7b  | Every non-blank line in the JSON output is a well-formed JSON object (`{…}`)                | T4, T7a    |
| T7c  | JSON records contain a `"tsc"` field                                                         | T4, T7a    |

**Total: 13 test cases.**

### 2.3 Temporary Files

All artefacts are written under `/tmp/` with a `SWLSVROS-6363_` prefix:

| Path                                    | Purpose                          |
|-----------------------------------------|----------------------------------|
| `/tmp/SWLSVROS-6363_test.pmc`           | Raw binary PMC log (T4 output)   |
| `/tmp/SWLSVROS-6363_flamegraph.svg`     | SVG flamegraph (T6 output)       |
| `/tmp/SWLSVROS-6363_output.json`        | NDJSON output from `pmc filter`  |
| `/tmp/SWLSVROS-6363_logs/`             | Per-step build and capture logs  |

Build log files inside the logs directory follow the pattern
`build_<component>.log`, `install_<component>.log`, `capture.log`,
`flamegraph.log`, and `json.log`.

### 2.4 Dependency Graph

```
T1a  T1b  ──  branch/SHA verification (independent)
T2a  T2b  T2c  ──  component builds (independent of each other)
T3  ──  requires T2a + T2b + T2c all PASS; skipped otherwise
T4  ──  PMC capture (independent of T2/T3 — uses installed binaries)
T5a  T5b  T5c  ──  require T4 PASS; skipped otherwise
T6  ──  requires T4 PASS; skipped if log has no samples
T7a  ──  requires T4 PASS; skipped otherwise
T7b  T7c  ──  require T4 PASS and T7a PASS; skipped otherwise
```

---

## 3. Existing Test: SWLSVROS-6414

**File:** `qa-branches/SWLSVROS-6414/SWLSVROS-6414.sh`

**Ticket:** Zen6 IBS init validation — ibs_ctl2 qualifier init + EXTERROR rejection

**Branch:** `amdese/qa/SWLSVROS-6414-zen6-ibs-init-validation-20260518`

**SHA:** `2faf5a49bcb4031093bd8b440a543c2eb0516a8e`

**Upstream PR:** <https://reviews.freebsd.org/D56914>

**KERNCONF:** `GENERIC-NOHWPMC`

**Build mode:** `buildworld + buildkernel` (lib/libpmc and usr.sbin/pmcstat are userland)

### 3.1 Scope

This cycle has no Zen6 host. The script validates:

1. Pre-Zen6 regression — ibs-op and ibs-fetch smoke on Zen3/4/5 must be behaviorally identical to the parent commit.
2. EXTERROR rejection — new Zen6-only qualifiers (`fetchlat`, `addr63`, `streamstore`) must be rejected by the kernel on pre-Zen6; libpmc no longer gates them in userland.
3. hwpmc load/unload cycle — no leaks, no asserts, no dmesg warnings on pre-Zen6.
4. Log replay — existing IBS logs (no ctl2 fields) must decode cleanly through patched pmcstat.
5. Manpage — `man 3 pmc.ibs` renders; new qualifiers and Zen6 CPUID note documented.
6. Build — clean `buildworld + buildkernel` on amd64 with GENERIC-NOHWPMC; no new warnings in touched files.

Zen6-only happy paths (ctl2[0] IbsDis, LATFLTEN, addr63 filter, streaming-store, IbsOpData2 decode) are deferred to a follow-up cycle once Zen6 hardware is allocated.

### 3.2 Test Cases

| ID    | Description                                                                                          | Depends on      |
|-------|------------------------------------------------------------------------------------------------------|-----------------|
| T1a   | HEAD SHA at `/usr/src` matches `EXPECTED_SHA`                                                        | —               |
| T1b   | Branch name matches; detached HEAD with matching SHA is non-critical                                 | —               |
| T1c   | All four touched source files present (`hwpmc_ibs.c`, `libpmc.c`, `pmcstat.c`, `pmc.ibs.3`)        | —               |
| T2    | `buildworld` succeeds                                                                                 | —               |
| T3a   | `GENERIC-NOHWPMC` KERNCONF file present                                                              | —               |
| T3b   | `buildkernel KERNCONF=GENERIC-NOHWPMC` succeeds                                                      | T3a             |
| T3c   | No new warnings in `hwpmc_ibs.c`, `libpmc.c`, `pmcstat.c` in build log                             | T3b             |
| T4a   | Active Boot Environment identified for rollback                                                       | —               |
| T4b   | QA Boot Environment created                                                                           | —               |
| T4c   | `installkernel` into QA BE succeeded                                                                  | T3b, T4b        |
| T4d   | `etcupdate -p` (pre-install) succeeded                                                                | T4c             |
| T4e   | `installworld` into QA BE succeeded                                                                   | T4c             |
| T4f   | `etcupdate -B` (post-install merge) succeeded                                                         | T4e             |
| T4g   | QA BE activated for next boot                                                                         | T4c             |
| T5    | Running kernel SHA matches QA branch (gates T6-T10)                                                  | reboot          |
| T6a   | `hwpmc.ko` loaded / already present                                                                   | T5              |
| T6b   | `/dev/pmc` device node present                                                                        | T6a             |
| T6c   | `ibs-op` counter allocated and released cleanly                                                       | T6a             |
| T6d   | `ibs-fetch` counter allocated and released cleanly                                                    | T6a             |
| T6e   | No panic/assert/warning in dmesg after kmod exercise                                                  | T6c, T6d        |
| T6f   | `hwpmc.ko` unloaded cleanly (no leaks); skipped if pre-loaded                                        | T6a             |
| T7a   | `pmcstat -P ibs-op` smoke succeeds on pre-Zen6 host                                                  | T5              |
| T7b   | `pmcstat -P ibs-fetch` smoke succeeds on pre-Zen6 host                                               | T5              |
| T7c   | ibs-op log decodes cleanly via `pmcstat -R`                                                           | T7a             |
| T7d   | ibs-fetch log decodes cleanly via `pmcstat -R`                                                        | T7b             |
| T8a   | `ibs-op,fetchlat=10` rejected by kernel with EXTERROR on pre-Zen6                                    | T5              |
| T8b   | `ibs-op,addr63=1` rejected by kernel with EXTERROR on pre-Zen6                                       | T5              |
| T8c   | `ibs-op,streamstore=1` rejected by kernel with EXTERROR on pre-Zen6                                  | T5              |
| T8d   | `ibs-fetch,fetchlat=10` rejected by kernel with EXTERROR on pre-Zen6                                 | T5              |
| T8e   | No panic/assert in dmesg after EXTERROR rejection tests                                               | T8a–T8d         |
| T9a   | `pmcstat -R` replay of existing IBS log succeeds                                                      | T7a or T7b      |
| T9b   | Replay output contains no decode errors or garbage fields (ctl2-absent log)                           | T9a             |
| T10a  | `man 3 pmc.ibs` renders without error                                                                 | T5              |
| T10b  | Keywords `fetchlat`, `addr63`, `streamstore`, `L3MISSONLY`, `CPUID` in rendered manpage              | T10a            |
| T10c  | Source manpage (`share/man/man3/pmc.ibs.3`) references Zen6 / ctl2 / IbsDis                         | T5              |

**Total: 34 test cases (Phase A: T1–T4; Phase B: T5–T10).**

### 3.3 Temporary Files

| Path                                           | Purpose                                   |
|------------------------------------------------|-------------------------------------------|
| `/tmp/SWLSVROS-6414_t6_ibs_op.pmc`            | ibs-op log from T6 load/unload exercise   |
| `/tmp/SWLSVROS-6414_t6_ibs_fetch.pmc`         | ibs-fetch log from T6 load/unload exercise|
| `/tmp/SWLSVROS-6414_ibs_op_smoke.pmc`         | ibs-op smoke log from T7                  |
| `/tmp/SWLSVROS-6414_ibs_fetch_smoke.pmc`      | ibs-fetch smoke log from T7               |
| `/tmp/SWLSVROS-6414_logs/`                    | Per-step build, install, and capture logs  |

### 3.4 Dependency Graph

```
Phase A (pre-reboot):
T1a  T1b  T1c  ──  SHA / branch / file checks (independent)
T2  ──  buildworld
T3a  ──  KERNCONF file present
T3b  ──  buildkernel (requires T3a)
T3c  ──  no-new-warnings check (requires T3b)
T4a  ──  identify rollback BE
T4b  ──  create QA BE
T4c  ──  installkernel (requires T3b + T4b)
T4d  ──  etcupdate -p (requires T4c; non-fatal)
T4e  ──  installworld (requires T4c)
T4f  ──  etcupdate -B (requires T4e; non-fatal)
T4g  ──  activate QA BE (requires T4c)

Phase B (after reboot into QA BE):
T5  ──  running kernel SHA check (gates T6-T10)
T6a-f  ──  hwpmc load / exercise / unload
T7a-d  ──  IBS op + fetch smoke + decode
T8a-e  ──  EXTERROR rejection for Zen6-only qualifiers
T9a-b  ──  log replay (reuses T6/T7 logs)
T10a-c  ──  manpage render + content check
```

### 3.5 QA Result

**Status:** QA-PASS
**Date:** 2026-05-19
**Branch tested:** `amdese/qa/SWLSVROS-6414-zen6-ibs-init-validation-20260518`
**SHA:** `2faf5a49bcb4031093bd8b440a543c2eb0516a8e`

---

## 4. Existing Test: SWLSVROS-6519

**File:** `qa-branches/SWLSVROS-6519/SWLSVROS-6519.sh`

**Ticket:** IBS errata workarounds for Family 19h (Zen3) — #1238, #1293, #1347

**Branch (cycle 2):** `amdese/qa/SWLSVROS-6519-ibs-errata-20260518-r2`

**SHA (cycle 2):** `a3712a188aeebd326697144d8f5507e41b21cedb`

**Branch (cycle 1):** `amdese/qa/SWLSVROS-6519-ibs-errata-20260515`

**SHA (cycle 1):** `24c2050d4e62120c6315d62d5529f251d768645d`

**Upstream PR:** <https://github.com/freebsd/freebsd-src/pull/2200>

**KERNCONF:** `GENERIC-NOHWPMC`

**Build mode:** `buildworld + buildkernel` (pmcstat_log.c is userland)

### 4.1 Scope

Cycle 2 key change: errata 1293 sanitization moved from `hwpmc_ibs.h` (kernel) into `pmcstat_log.c` (userland). The script verifies this refactor is complete and the errata paths behave correctly.

Errata covered:
- **#1293** (Family 19h, Model 00h–0Fh): zero IBS_OP_DATA2 when DcMissNoMabAlloc or SwPf set — **now in pmcstat**
- **#1238** (Family 19h, Model < 10h): suppress IbsIcMiss in pmcstat fetch decode
- **#1347** (Family 19h, Model < 10h): L1TLB page-size alt encoding — decode deferred

Cpuid-spoof tooling (`ibs_errata_spoof.c`, `test_ibs_errata.sh`) is optional. When present, T7/T8/T9 run; when absent, they skip with instructions.

### 4.2 Test Cases

| ID    | Description                                                                                                | Depends on   |
|-------|------------------------------------------------------------------------------------------------------------|--------------|
| T1a   | HEAD SHA matches                                                                                            | —            |
| T1b   | Branch name / detached HEAD with SHA confirmed                                                              | —            |
| T1c   | Touched files present: `hwpmc_ibs.c`, `hwpmc_ibs.h`, `pmcstat_log.c`                                     | —            |
| T1d   | Errata 1293 logic present in `pmcstat_log.c` (cycle-2 move complete)                                      | —            |
| T1e   | Errata 1238 IbsIcMiss suppression present in `pmcstat_log.c`                                              | —            |
| T1f   | `hwpmc_ibs.h` does NOT contain errata 1293 mask (removed in cycle 2)                                      | —            |
| T2    | `buildworld` succeeded                                                                                      | —            |
| T3a   | `GENERIC-NOHWPMC` KERNCONF present                                                                          | —            |
| T3b   | `buildkernel KERNCONF=GENERIC-NOHWPMC` succeeded                                                            | T3a          |
| T3c   | No new warnings in `hwpmc_ibs.c` / `hwpmc_ibs.h`                                                          | T3b          |
| T4a–g | BE creation, installkernel, etcupdate -p, installworld, etcupdate -B, activate                              | T3b          |
| T5    | Running kernel SHA matches (gates T6–T10)                                                                   | reboot       |
| T6a   | `pmcstat -S ibs-fetch -n 50000 -l 3` capture succeeds                                                      | T5           |
| T6b   | `pmcstat -S ibs-op -n 50000 -l 3` capture succeeds (with background workload)                              | T5           |
| T6c   | ibs-fetch log decoded via `pmcstat -R -o`                                                                   | T6a          |
| T6d   | ibs-op log decoded via `pmcstat -R -o`                                                                      | T6b          |
| T6e   | No panic/assert in dmesg after native capture                                                               | T6a, T6b     |
| T6f   | Errata 1238 path exercised on native Zen3 B0 (skipped on other hosts)                                      | T6c          |
| T6g   | Errata 1293 path exercised on native Zen3 B0 (skipped on other hosts)                                      | T6d          |
| T7a   | `ibs_errata_spoof.c` compiled successfully (skipped if not found)                                          | T5           |
| T7b   | `test_ibs_errata.sh` harness: all PASS, 0 FAIL (WARN on T5/T6 is benign)                                  | T7a          |
| T8a   | Op log spoofed to Zen3 B0 (`AuthenticAMD-25-0F-0`)                                                         | T7a, T6b     |
| T8b   | Spoofed Zen3 B0 op log decoded cleanly by `pmcstat -R`                                                      | T8a          |
| T8c   | Diff original vs Zen3 B0 decode is NON-EMPTY (errata 1293 fired); or SKIP if no triggering samples         | T8b          |
| T9a   | Op log spoofed to Model 0x10 (`AuthenticAMD-25-10-0`, not affected)                                        | T7a, T6b     |
| T9b   | Model 0x10 spoofed log decoded cleanly                                                                      | T9a          |
| T9c   | Diff original vs Model 0x10 decode is EMPTY (mask is no-op for non-affected model)                         | T9b          |
| T10a  | `pmcstat -P instructions -l 3` (sampling mode) — no panic, accepted                                        | T5           |
| T10b  | `pmcstat -S instructions -l 3` (system-wide) — no panic, accepted                                          | T5           |
| T10c  | Instructions sampling log decoded cleanly via `pmcstat -R`                                                  | T10a         |
| T10d  | No panic/assert in dmesg at end of full test run                                                            | all          |

**Total: 34 test cases (Phase A: T1–T4; Phase B: T5–T10).**

### 4.3 Spoof Tool Location

The script searches for `ibs_errata_spoof.c` and `test_ibs_errata.sh` in order:

1. `/tmp/ibs_errata/` (default drop location)
2. The script's own directory (`qa-branches/SWLSVROS-6519/`)
3. `${SRC_DIR}/tools/test/ibs_errata/`
4. `${SRC_DIR}/tools/test/`

If not found, T7/T8/T9 skip with instructions. To enable: copy both files to `/tmp/ibs_errata/` and re-run.

### 4.4 Temporary Files

| Path | Purpose |
|------|---------|
| `/tmp/SWLSVROS-6519_fetch.log` | ibs-fetch capture (T6a) |
| `/tmp/SWLSVROS-6519_op.log` | ibs-op capture (T6b) |
| `/tmp/SWLSVROS-6519_op_zen3b0.log` | Zen3 B0 spoofed op log (T8a) |
| `/tmp/SWLSVROS-6519_op_model10.log` | Model 0x10 spoofed op log (T9a) |
| `/tmp/SWLSVROS-6519_ibs_errata_spoof` | Compiled spoof binary (T7a) |
| `/tmp/SWLSVROS-6519_logs/` | All per-step build, capture, decode, diff logs |

### 4.5 Dependency Graph

```
Phase A (pre-reboot):
T1a-f  ──  SHA / branch / source-level cycle-2 invariants (independent)
T2  ──  buildworld
T3a  ──  KERNCONF present
T3b  ──  buildkernel (requires T3a)
T3c  ──  no-new-warnings (requires T3b)
T4a-g  ──  BE create / install / activate (requires T3b)

Phase B (after reboot):
T5  ──  kernel SHA check (gates T6-T10)
T6a-g  ──  native IBS capture + decode + errata paths
T7a  ──  spoof binary build (optional; skips T7b/T8/T9 if absent)
T7b  ──  errata 1238 harness (requires T7a)
T8a-c  ──  errata 1293 op-side spoof (requires T7a + T6b)
T9a-c  ──  negative control Model 0x10 (requires T7a + T6b)
T10a-d  ──  non-IBS PMC regression sweep
```

---

## 5. CI Suite Runner

### 3.1 Entry Point

`_exec_full_suite()` in `qa-tester.sh` (lines 752–818) is invoked by menu
options 6 and 7.

### 3.2 Execution Flow

```
_exec_full_suite()
│
├─ Check for ci-tests/ at SCRIPT_DIR
│   └─ MISSING → record FAIL "ci-tests directory missing", return 1
│
├─ kyua available AND ci-tests/Kyuafile present?
│   └─ YES → kyua test --kyuafile ci-tests/Kyuafile
│             count "passed" / "failed|broken" lines from kyua output
│             record PASS or FAIL "Full suite (kyua)"
│
└─ Fallback (kyua absent or no Kyuafile)
    find ci-tests/ -name '*_test.sh' | sort
    for each script:
        sh <script>
        exit 0 → pass "Suite: <name> — OK"
        non-0  → fail "Suite: <name> — FAILED (exit N)" + tail -5 output
    0 scripts found → record WARN "no test scripts found"
    all passed      → record PASS "N/N scripts passed"
    any failed      → record FAIL "N of N scripts failed"
```

### 3.3 Kyua Integration

When `kyua` is installed and `ci-tests/Kyuafile` exists, the suite is run via:

```sh
kyua test --kyuafile ci-tests/Kyuafile
```

Pass/fail counts are extracted from kyua's stdout by matching lines that end
with ` passed` or ` failed`/` broken`.

### 3.4 Shell Fallback

If kyua is unavailable or no `Kyuafile` is present, every `*_test.sh` file
found recursively under `ci-tests/` is executed directly with `sh`. Each
script's exit code determines pass/fail; output is appended to the session log.
The `[PASS]`/`[FAIL]` markers printed by individual scripts are not re-counted
at the suite level — only the script exit code is used for the suite result.

### 3.5 Current Status

> **TODO:** `ci-tests/` does not exist in the project. Until it is created,
> invoking menu option 6 or 7 will always record `FAIL "ci-tests directory
> missing"` and return early. No CI tests are currently defined. To unblock
> the CI suite:
>
> 1. Create the directory: `mkdir -p ci-tests/`
> 2. Add at least one `*_test.sh` script, or add a `Kyuafile` if using kyua.
> 3. If using kyua, install it with: `pkg install kyua`

---

## Learning Log

| Date       | Notes                                                                                                                                                           | Module    |
|------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------|-----------|
| 2026-04-28 | First read. One QA test exists (SWLSVROS-6363, 13 test cases for PMC/TSC). ci-tests/ directory is absent — CI suite will always fail until created. Script format is well-defined. | qa-tests |
| 2026-05-06 | SWLSVROS-6316 failures: /usr/src was on SWLSVROS-6310 branch; switched to SWLSVROS-6316 via local fetch from dev/src. Broken HWPMC_DBG symlink (/usr/src/sys/amd64/conf/HWPMC_DBG -> /tools/configs/HWPMC_DBG, target nonexistent) replaced with real config file based on AMD_IBS_KERNCONF template (ident HWPMC_DBG). Both fixes resolve T1a/T1b/T1c/T5 and T3a respectively. | qa-tests |
| 2026-05-18 | Created SWLSVROS-6414 (Zen6 IBS ibs_ctl2 init validation). No Zen6 host available this cycle; script covers pre-Zen6 regression (T7), EXTERROR rejection of Zen6-only qualifiers on Zen3/4/5 (T8), hwpmc load/unload (T6), log replay (T9), and manpage (T10). KERNCONF=GENERIC-NOHWPMC; world+kernel build required. 10 phase-B test groups (T5-T10), 4 build groups (T1-T4). Zen6-only paths deferred. | qa-tests |
| 2026-05-18 | Created SWLSVROS-6519 (IBS errata #1238/#1293/#1347 Family 19h). Cycle 2: errata 1293 moved from kernel to pmcstat_log.c. Script covers source-level cycle-2 invariants (T1d/T1e/T1f), native capture+decode (T6), automated errata 1238 harness via cpuid spoof (T7), manual errata 1293 op-side spoof coverage with diff verification (T8), negative control Model 0x10 (T9), non-IBS PMC regression (T10). Spoof tooling optional -- T7/T8/T9 skip gracefully if absent. | qa-tests |
| 2026-05-19 | SWLSVROS-6414 (amdese/qa/SWLSVROS-6414-zen6-ibs-init-validation-20260518, SHA 2faf5a49bcb4031093bd8b440a543c2eb0516a8e) tagged QA-PASS. | qa-tests |
