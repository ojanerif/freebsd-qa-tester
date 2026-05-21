---
module: amdese-freebsd-src
type: infra
status: active
stack: Git, FreeBSD
last_modified: 2026-04-28
related: [[build-pipeline]]
tags: [qa-test, infra, git]
---

# amdese-freebsd-src

## Overview

The AMD AMDESE FreeBSD kernel source repository hosted on GitHub. This is the target of all `git clone` and `git fetch` operations performed by the qa-test harness. The repo contains QA-specific branches that map directly to test tickets and carry the kernel source tree used for each test run.

---

## Key Details

| Field | Value |
|---|---|
| Primary URL | `https://github.com/AMDESE/freebsd-src` |
| Fallback URL | `ssh://git@sos-git.amd.com/freebsd-src.git` |
| Variable (primary) | `KERNEL_REPO` in `qa-tester.sh` |
| Variable (fallback) | `KERNEL_REPO_ALT` in `qa-tester.sh` |
| Clone destination | `/usr/src` |
| Clone depth | `--depth 100` (~500 MB shallow clone) |
| Branch pattern | `amdese/qa/<TICKET_ID>-<description>-<YYYYMMDD>` |

**Clone command:**
```sh
git clone --branch <QA_BRANCH> --depth 100 <URL> /usr/src
```

**URL resolution order:**
1. HTTPS primary (`KERNEL_REPO`) — tried first; works without SSH key configuration.
2. SSH fallback (`KERNEL_REPO_ALT`) — used when the HTTPS clone fails (firewall block, missing VPN, etc.).

**Depth rationale:** `--depth 100` balances clone speed against history availability. A full clone of this repo is several GB; shallow at 100 commits lands around 500 MB, which is acceptable for CI-style QA runs that only need to build the tip of the branch.

---

## Access / Auth

- **HTTPS (primary):** No authentication required. Public GitHub repository. Works on any network without additional configuration.
- **SSH (fallback):** Requires:
  - Active AMD VPN connection.
  - A valid SSH key registered with `sos-git.amd.com`.
  - The key must be loaded in the agent or present at the default path before `qa-tester.sh` runs.

---

## Known Issues

- If the HTTPS clone silently stalls rather than failing hard (e.g., a transparent proxy intercepts the connection), the fallback to SSH may not trigger automatically — monitor clone timeouts.
- `--depth 100` means `git log` history beyond 100 commits is unavailable; any bisect or blame operation deeper than that requires `git fetch --unshallow`.
- The SSH remote hostname `sos-git.amd.com` is only resolvable inside the AMD network/VPN; DNS will fail on public networks.

---

## Learning Log

| Date | Note | Module |
|---|---|---|
| 2026-04-28 | First read. Primary HTTPS remote + SSH fallback. Shallow --depth 100 clone. | amdese-freebsd-src |
