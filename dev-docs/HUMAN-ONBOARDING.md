---
version: "4.0"
last_modified: 2026-05-21
tags: [onboarding, v4]
---

# Human Onboarding — qa-test

Welcome to the FreeBSD Kernel QA Testing Environment. This guide gets you from zero to running your first QA cycle.

## Prerequisites

- FreeBSD 16.0-CURRENT machine (amd64), root or sudo access
- Access to AMD VPN (for SSH fallback to `sos-git.amd.com`)
- Jira access: `amd.atlassian.net`
- Git configured: `git config --global user.name` and `user.email`
- Node.js ≥ 18 (for dev-docs dashboard/CLI only)

## Quick Start

```sh
# 1. Clone the QA harness
git clone https://github.com/ojanerif/freebsd-qa-tester qa-test
cd qa-test

# 2. Run the tester (interactive)
./qa-tester.sh

# 3. Or specify email from the start
./qa-tester.sh --email you@amd.com
```

## Typical QA Cycle

1. **Receive handoff** — Jira ticket (e.g. `SWLSVROS-6519`) with branch + SHA
2. **Option 1** — Sync source to QA branch (clone or fetch+reset)
3. **Option 2** — Build world + kernel + install (30–90 min)
4. **Reboot** into QA kernel (`nextboot` schedules `kernel.qa`)
5. **Option 3** — Verify running kernel SHA matches expected
6. **Option 4** — Run specific QA tests (`qa-branches/<ID>/<ID>.sh`)
7. **Review** report in `reports/<session>/qa-report-*.txt`
8. **Email** report via Option 5 or `--email` flag

## dev-docs Navigation

```sh
# Start the dashboard (requires Node.js)
node dev-docs/dashboard/server.mjs
# Open http://127.0.0.1:3434

# CLI tools
node dev-docs/bin/devdocs.mjs doctor
node dev-docs/bin/devdocs.mjs skills list
node dev-docs/bin/devdocs.mjs session start --module orchestrator --task "QA SWLSVROS-6519"
```

## Key Files

| File | Purpose |
|------|---------|
| `qa-tester.sh` | Main harness — run this |
| `qa-branches/<ID>/<ID>.sh` | Per-ticket test scripts |
| `last-session.env` | Resume last session |
| `reports/<session>/` | Session logs and reports |
| `dev-docs/` | Project memory (v4.0) |

## Who to Contact

- **Osvaldo J. Filho** — `ojanerif@amd.com` — Owner, primary tester
- **FreeBSD test list** — `freebsd-test@mailman-svr.amd.com`
- **Jira** — `https://amd.atlassian.net/browse/SWLSVROS-*`
