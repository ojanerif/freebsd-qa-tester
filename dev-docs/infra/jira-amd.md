---
module: jira-amd
type: infra
status: active
stack: Jira, AMD SSO
last_modified: 2026-04-28
related: [[orchestrator], [session-manager]]
tags: [qa-test, infra, jira]
---

# jira-amd

## Overview

The AMD Atlassian Jira instance used for QA ticket tracking. Every test run in qa-test is anchored to a `SWLSVROS-` ticket. The `QA_ID` variable (e.g. `SWLSVROS-1234`) is the primary identifier throughout the harness — it drives branch selection, script lookup, and Jira URL synthesis. Users never enter a URL directly; the harness builds it from `QA_ID`.

---

## Key Details

| Field | Value |
|---|---|
| Base URL | `https://amd.atlassian.net` |
| Ticket URL pattern | `https://amd.atlassian.net/browse/<QA_ID>` |
| Ticket prefix | `SWLSVROS-` (Software Linux & OS — FreeBSD OS) |
| Variable | `JIRA_URL` in `qa-tester.sh` |
| URL source | Auto-synthesized from `QA_ID`; never entered by the user |
| Test script path | `qa-branches/<QA_ID>/<QA_ID>.sh` |

**URL synthesis (conceptual):**
```sh
JIRA_URL="https://amd.atlassian.net/browse/${QA_ID}"
```

**`QA_ID` as the central key:** The `QA_ID` value (e.g. `SWLSVROS-4321`) is the single input that fans out into:
- The Jira ticket URL (`JIRA_URL`).
- The QA branch name on the kernel repo (`amdese/qa/<QA_ID>-...`).
- The local test script (`qa-branches/<QA_ID>/<QA_ID>.sh`).

---

## Access / Auth

- **AMD SSO required:** The Jira instance is behind Atlassian Access federated with AMD's identity provider. A browser session or API token must be authenticated via AMD SSO.
- **VPN dependency:** `amd.atlassian.net` may be reachable from the public internet depending on AMD's Atlassian configuration, but AMD SSO login itself typically requires either VPN or a corporate device enrolled in the IdP. Verify connectivity before scripting any Jira API calls.
- **API tokens:** If the harness ever needs to POST comments or transition issues programmatically, an Atlassian API token (generated at `id.atlassian.com`) scoped to the AMD org is required — basic password auth is disabled on Atlassian Cloud.

---

## Known Issues

- `JIRA_URL` is display/logging only in the current harness — no Jira API calls are made at runtime. If API integration is added later, SSO token handling will need to be designed.
- The `SWLSVROS-` prefix expansion ("Software Linux & OS - FreeBSD OS") is inferred; confirm with the AMD team if the project key is ever renamed or a new project key is introduced for FreeBSD-specific work.
- Tickets not yet created in Jira (e.g., a pre-release `QA_ID` used for local dev) will produce a valid-looking `JIRA_URL` that returns a 404 — the harness does not validate ticket existence before proceeding.

---

## Learning Log

| Date | Note | Module |
|---|---|---|
| 2026-04-28 | First read. SWLSVROS- prefix tickets. JIRA_URL is auto-synthesized from QA_ID. | jira-amd |
