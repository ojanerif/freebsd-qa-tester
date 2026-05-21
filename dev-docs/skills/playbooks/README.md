---
last_modified: 2026-05-21
tags: [skills, playbooks, v4]
---

# Playbooks

Playbooks are multi-step skill sequences for common end-to-end workflows.
Each playbook references skills from `skills.jsonl` in order.

## Full QA Cycle

**Use:** Validate a new AMD kernel patch from Jira ticket to email report.

1. `sync-qa-branch` — Fetch the QA source branch
2. `build-kernel` — Build world + kernel + install
3. *(reboot into QA kernel)*
4. `verify-kernel` — Confirm running SHA matches expected
5. `run-qa-tests` — Execute `qa-branches/<QA_ID>/<QA_ID>.sh`
6. `send-email-report` — Mail results to FreeBSD test list

**Estimated time:** 45–120 minutes (build is the bottleneck)

## New Ticket Setup

**Use:** Prepare a fresh test environment for a new Jira ticket.

1. `create-qa-testfile` — Author the test script with structured headers
2. `sync-qa-branch` — Clone/reset source to the ticket branch
3. `check-git-drift` — Confirm dev-docs is up to date

## Quick Verification (post-reboot)

**Use:** After rebooting into a QA kernel, confirm the environment and run tests.

1. `verify-kernel` — Check SHA
2. `run-qa-tests` — Run tests
3. `send-email-report` — Send results
