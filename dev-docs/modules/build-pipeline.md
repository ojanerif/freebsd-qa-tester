---
module: build-pipeline
type: module
status: active
stack: POSIX sh, FreeBSD make, Git
last_modified: 2026-04-30
# updated: 2026-04-30 — SRC_DIR default changed to dev/; KERNCONF added
related: [[orchestrator], [session-manager], [command-engine]]
tags: [qa-test, module]
---

# Module: build-pipeline

## Purpose

The build-pipeline module manages the full lifecycle of fetching, cloning, building, and verifying a FreeBSD kernel for QA testing. It exposes four sequential action functions in `qa-tester.sh` that take a source tree from a remote Git branch through to a running, verified kernel on the test machine.

---

## Responsibilities

- Synchronize the local source tree with the target QA branch on the remote (`action_fetch_latest`, `action_clone_branch`)
- Compile and install the FreeBSD kernel and world (`action_build_world`)
- Confirm that the running kernel matches the expected commit SHA (`action_check_kernel`)
- Record PASS / WARN / FAIL outcomes per step and persist `ACTUAL_SHA` to `state.env`
- Provide user-facing confirmation gates before destructive or long-running operations

---

## Source Location

File: `qa-tester.sh`

| Action | Line range |
|---|---|
| `action_fetch_latest` | 507–536 |
| `action_clone_branch` | 542–608 |
| `action_build_world` | 614–652 |
| `action_check_kernel` | 658–714 |

---

## Actions

### Action 1 — `action_fetch_latest` (lines 507–536)

Updates an existing local clone to match the remote QA branch.

**Precondition:** `SRC_DIR` must already contain a valid Git repository (`.git` present).

**Steps:**

1. `git fetch --prune origin` — fetches all refs and removes stale remote-tracking branches
2. `git reset --hard origin/<QA_BRANCH>` — hard-resets the working tree to the remote branch tip

**SHA verification:**

- Extracts `ACTUAL_SHA` via `git rev-parse HEAD` after the reset
- Compares `ACTUAL_SHA` against `EXPECTED_SHA` (set in session config)
- PASS: exact match
- WARN: mismatch (the branch may have moved ahead of the expected commit since the session was configured)
- FAIL: any Git command exits non-zero

**State output:** Appends `ACTUAL_SHA=<hash>` to `state.env`.

---

### Action 2 — `action_clone_branch` (lines 542–608)

Performs a fresh shallow clone of the QA branch into `SRC_DIR`.

**Precondition check:** If `SRC_DIR` already contains a `.git` directory, the action warns the user and asks interactively whether to `rm -rf SRC_DIR` before proceeding. Declining aborts the action.

**Clone command:**

```sh
git clone --branch <QA_BRANCH> --depth 100 <KERNEL_REPO> <SRC_DIR>
```

- `--depth 100`: shallow clone limited to the last 100 commits. Shallow enough to keep the download fast for a ~500 MB repository, deep enough to cover typical QA branch histories.
- Executed via `run_long_cmd` with a spinner because the operation can take several minutes.

**Fallback:** If the primary clone fails and `KERNEL_REPO_ALT` is configured, the action retries using the alternate URL. If both attempts fail, FAIL is recorded.

**Repository URL strategy:**

| Variable | URL type | Notes |
|---|---|---|
| `KERNEL_REPO` | HTTPS (`github.com/AMDESE`) | Tried first; works without SSH key setup |
| `KERNEL_REPO_ALT` | SSH (`sos-git.amd.com`) | Fallback; requires configured SSH key |

**SHA verification:** Identical PASS / WARN / FAIL logic as `action_fetch_latest`. `ACTUAL_SHA` is appended to `state.env`.

---

### Action 3 — `action_build_world` (lines 614–652)

Compiles and installs the FreeBSD kernel and userland from source.

**Precondition:** `SRC_DIR` must be a valid Git repository.

**User confirmation:** The action asks for explicit confirmation before starting, noting that the process can take 30–90 minutes. Declining aborts without recording a result.

**Build sequence (each step runs via `run_long_cmd` with a spinner):**

| Step | Command | Parallelized |
|---|---|---|
| 1 | `make -j<MAKE_JOBS> -C <SRC_DIR> buildworld` | Yes (`-j`) |
| 2 | `make -j<MAKE_JOBS> -C <SRC_DIR> buildkernel` | Yes (`-j`) |
| 3 | `make -C <SRC_DIR> installworld` | No |
| 4 | `make -C <SRC_DIR> installkernel` | No |

`installworld` and `installkernel` intentionally omit `-j` because parallel install is not safe on FreeBSD (file ordering and ownership operations can conflict).

**Failure handling:** Any step failure immediately stops the pipeline (the function returns 1). Subsequent steps are not attempted.

**Post-install reboot prompt:** After a successful `installkernel`, the action warns the user that a reboot is required to activate the new kernel and asks:

```
Reboot now? [y/N]
```

Default is `n`. The user must explicitly answer `y` to trigger an immediate reboot. Regardless of the answer, the new kernel will not be active until the next boot, which means `action_check_kernel` must be run after the system has rebooted.

---

### Action 4 — `action_check_kernel` (lines 658–714)

Verifies that the currently running kernel matches the expected commit SHA.

**Primary verification method — `uname -v` hash extraction:**

FreeBSD embeds the short Git commit hash as a `gXXXXXXX` token in the `uname -v` string. The action extracts it with:

```sh
uname -v | grep -oE 'g[0-9a-f]{7,12}'
```

The extracted hash (without the `g` prefix) is compared against the leading N characters of `EXPECTED_SHA`.

**Fallback:** If `uname -v` does not contain an embedded `g<hash>` token (e.g., a stock release kernel), the action falls back to running `git rev-parse HEAD` inside `SRC_DIR`.

**Outcomes:**

- PASS: running hash prefix matches `EXPECTED_SHA`
- WARN: hash present but does not match (kernel may be from a different build)
- FAIL: hash cannot be extracted by either method

**User hint displayed on non-PASS result:**

```
If you ran option 3, reboot to activate the new kernel.
```

---

## Key Design Notes

- **Shallow clone depth (`--depth 100`):** Balances download size against history depth. Most QA branch workflows do not need more than 100 commits of history for bisect or log operations.
- **HTTPS-first remote strategy:** `KERNEL_REPO` (HTTPS) is always attempted first because it works in environments without SSH key configuration. `KERNEL_REPO_ALT` (SSH) exists for air-gapped or firewall-restricted environments where HTTPS to GitHub is blocked.
- **`uname -v` as primary kernel verification:** FreeBSD's build system embeds the Git short SHA as `gXXXXXXX` in the kernel version string at compile time. This makes `uname -v` the most reliable post-reboot verification method, since it does not depend on the source tree being present or on the filesystem state of `SRC_DIR`.
- **No `-j` on install steps:** `make installworld` and `make installkernel` perform privileged filesystem operations (ownership, permissions, mtree) that are not safe to run in parallel. Omitting `-j` is intentional and must not be changed.
- **Reboot gap between actions 3 and 4:** There is an inherent operational gap between `action_build_world` (action 3) and `action_check_kernel` (action 4). The pipeline does not enforce continuity across a reboot; the user is responsible for running action 4 after the system comes back up.

---

## Snippets

### uname -v hash extraction pattern

```sh
# Extract the embedded git short hash from the running FreeBSD kernel version string.
# FreeBSD encodes the hash as gXXXXXXX (7–12 lowercase hex chars prefixed with 'g').
# Example uname -v output:
#   FreeBSD 14.0-CURRENT #0 main-n265374-g3a1b2c4d5e6: Tue Apr 28 10:00:00 UTC 2026
#
running_hash=$(uname -v | grep -oE 'g[0-9a-f]{7,12}')
# Strip the leading 'g' before comparing against EXPECTED_SHA
running_hash="${running_hash#g}"
```

---

## Dependencies

| Dependency | Used by | Notes |
|---|---|---|
| `git` | actions 1, 2, 4 | Must be in PATH |
| `make` (FreeBSD) | action 3 | GNU make is not compatible with FreeBSD src |
| `run_long_cmd` | actions 2, 3 | Internal helper; wraps command with spinner and timeout logging |
| `asks_yn` | actions 2, 3 | Internal helper; prompts user for y/n with configurable default |
| `state.env` | actions 1, 2 | Persistent key=value file; `ACTUAL_SHA` is appended here |
| `MAKE_JOBS` | action 3 | Set in session config; controls parallelism for build steps |
| `EXPECTED_SHA` | actions 1, 2, 4 | Set in session config; defines the target commit |
| `QA_BRANCH` | actions 1, 2 | Set in session config; names the remote branch to track |
| `KERNEL_REPO` | action 2 | Primary clone URL (HTTPS) |
| `KERNEL_REPO_ALT` | action 2 | Fallback clone URL (SSH); optional |

---

## Error Handling Summary

| Condition | Outcome | Notes |
|---|---|---|
| Git command non-zero exit | FAIL | Applies to fetch, reset, clone, rev-parse |
| SHA mismatch after sync | WARN | Branch may have moved; not a hard failure |
| `SRC_DIR` has `.git`, user declines wipe | Abort | Action 2 only; no result recorded |
| Build step non-zero exit | FAIL + return 1 | Pipeline stops; subsequent steps skipped |
| `uname -v` has no `g<hash>` token | Try AMD branch-suffix pattern `-<sha>:` first; fallback to `git rev-parse HEAD` if still empty | Action 4 only |
| Both clone URLs fail | FAIL | Action 2 records single FAIL after both attempts |
| `nextboot` exits non-zero | FAIL + return 1 | Action 3 only; kernel is installed but not scheduled |

---

## [BUG] action_check_kernel misses SHA in AMD-style branch names
**Found:** 2026-04-30
**Symptom:** `action_check_kernel` prints WARN "No git hash found in uname -v" even when the running kernel IS the correct QA build. Falls back to source tree check and issues misleading "reboot may be needed" PASS.
**Root cause:** The primary regex `g[0-9a-f]{7,12}` requires a `g` prefix (standard FreeBSD format). AMD QA branches embed the SHA as a branch name suffix: `<branch>-<sha>:` — no `g` prefix. Example: `amdese/qa/SWLSVROS-6310-...-b2aba04a91f4:`.
**Fix/Workaround:** Added secondary pattern `-[0-9a-f]{7,12}:` (lines 657–663). Tried after the primary fails; extracts the SHA from the AMD branch suffix. Source-tree fallback now only fires when both patterns return empty.
**Status:** resolved

---

## [DECISION] Source cloned into dev/ and KERNCONF prompt added
**Date:** 2026-04-30
**Context:** Source was previously cloned to /usr/src, which is the system source tree and may conflict with installed FreeBSD sources. User also needs to choose the kernel configuration (KERNCONF) at setup time rather than hardcoding GENERIC.
**Decision:** Changed default SRC_DIR from /usr/src to ${SCRIPT_DIR}/dev so the QA source tree lives inside the project directory and does not touch the system tree. Added KERNCONF variable (default GENERIC) prompted during gather_info Build Settings section. KERNCONF is passed to buildkernel and installkernel; persisted in last-session.env and state.env.
**Discarded alternatives:** None — keeping /usr/src would risk overwriting the running system's source tree.
**Impact:** qa-tester.sh defaults (line 53), gather_info (Build Settings section), _save_session_state, action_build_world (buildkernel and installkernel commands), report output.

---

## [DECISION] Install QA kernel to /boot/kernel.qa via nextboot
**Date:** 2026-04-30
**Context:** Installing directly to /boot/kernel overwrites the running kernel; if the new kernel panics or fails to boot there is no safe fallback without physical access.
**Decision:** Changed `installkernel` to use `KODIR=/boot/kernel.qa`, leaving `/boot/kernel` untouched. After install, `nextboot -k kernel.qa` schedules the QA kernel for one boot only. If the boot fails, a second reboot returns automatically to the original `/boot/kernel`.
**Discarded alternatives:** Boot Environments (beadm) — requires UFS+ZFS or ZFS root, adds pkg dependency, heavier than needed for single-kernel QA testing.
**Impact:** `qa-tester.sh` action_build_world (lines 611–632); no change to installworld or build steps.

---

## Learning Log

| Date | Notes | Module |
|---|---|---|
| 2026-04-28 | First read. Build pipeline is 4 sequential actions. Clone uses --depth 100 shallow. Kernel verification extracts gXXXXXXX from uname -v. Reboot is required between action 3 and action 4. | build-pipeline |
| 2026-04-30 | installkernel now installs to /boot/kernel.qa via KODIR; nextboot -k kernel.qa provides one-shot fallback safety. Original /boot/kernel untouched. | build-pipeline |
| 2026-04-30 | AMD QA branches embed SHA as `-<sha>:` branch suffix in uname -v, not as `g<sha>`. Added secondary regex to catch this; prevents false fallback to source-tree check. | build-pipeline |
| 2026-04-30 | Default SRC_DIR changed from /usr/src to ${SCRIPT_DIR}/dev so the QA source tree stays inside the project directory. KERNCONF variable added (default GENERIC); prompted during gather_info; passed to buildkernel and installkernel. | build-pipeline |
