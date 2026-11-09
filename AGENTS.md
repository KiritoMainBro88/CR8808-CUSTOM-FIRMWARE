# AGENTS.md — Project-wide Agent Contract

**This file is authoritative for every AI agent and human contributor in this repository.**
If a task prompt conflicts with this file, stop and ask for clarification. Safety rules in this file cannot be overridden by an ordinary task prompt.

## 1. Project identity

- Project: `CR8808-CUSTOM-FIRMWARE`
- Target product: Xiaomi CR8808 Ver.B.
- Project owner / final approver: User.
- Architecture and review lead: ChatGPT, acting through review instructions and decisions relayed by the user.
- Implementation and workstation operator: Gemini agent(s).
- Existing lab workspace: `D:\vibecode\test_wifi`.
- New product workspace: `D:\vibecode\CR8808-CUSTOM-FIRMWARE`.

The product name is CR8808 Ver.B. Prior audit output reportedly showed internal identifier `CR8818` and board string `ap-mp03.3`; these are not permission to rename the product or infer compatibility with every CR881x model.

## 2. Role hierarchy

1. **User / Product Owner:** final authority over scope, priorities, and all router-impacting actions.
2. **ChatGPT / Architecture Reviewer:** requirements, architecture, design review, risk assessment, technical decisions and acceptance criteria. The user relays tasks and results between ChatGPT and Gemini.
3. **Gemini / Implementer:** inspect, code, build, test and collect evidence within the approved scope. Gemini must not self-approve architecture or destructive actions.
4. **Specialist sub-agents:** research, implementation, test and review roles described in `agents/roles/`. They report to the main Gemini orchestrator.

Do not tell the user that ChatGPT has directly contacted Gemini. The operational handoff is: ChatGPT prepares a task → user pastes it into Gemini → Gemini returns evidence → user pastes the result back for review.

## 3. Workspace isolation

- All new project files must be created under this repository.
- Preserve `D:\vibecode\test_wifi` and its existing Gemini conversation.
- Do not run `git init`, `git clean`, `git reset`, mass rename, deletion, or refactoring inside `test_wifi`.
- Treat `test_wifi` as read-only evidence unless the user approves a specific, named change.
- Never copy secrets, private keys, passwords, tokens or unnecessary personal/network identifiers from the lab workspace.
- Do not mix generated binaries and source code. Build output belongs in ignored build/artifact folders.

## 4. Mandatory phase gate

The current phase is **P0/P1: project setup and discovery**.

Allowed now:
- Read project documents and source repositories.
- Initialize Git in this new project folder if it is not already initialized.
- Create the documented directory tree.
- Audit PC/WSL2/Linux resources and installed tools without installing anything.
- Clone/read candidate repositories into a separate source cache or `upstream/` working area, without merging them into the product tree.
- Inspect source code, licenses, DTS, drivers, build systems and commit history.
- Write reports under `reports/`.
- Build small host-side analysis tools if they do not modify the router or existing lab workspace.

Not allowed now:
- SSH into the router.
- Upload files to the router.
- Run commands on the router.
- Change Wi-Fi, firewall, route, VLAN, DNS, IRQ, sysctl, cron, service or VPN settings.
- Stop Go WireGuard.
- Restart services or reboot.
- Build or flash an image intended for installation.
- Write to NAND/MTD/NVRAM/bootloader/bootconfig/partition table.

The first Gemini task is `prompts/00_GEMINI_KICKOFF.md`. Do not jump to later prompts.

## 5. Router action safety classes

### Class R0 — Read-only
Examples: read `/proc`, `uname`, board metadata, module list, route table, counters. Even read-only router access is not authorized in the current kickoff task; a later task must explicitly authorize the exact read-only command list.

### Class R1 — Volatile / potentially disruptive
Examples: upload to `/tmp`, run a temporary daemon, create a temporary interface, alter firewall or runtime network state, stop/restart a service. Requires a task-specific explicit user approval before execution.

### Class R2 — Persistent / destructive
Examples: `sysupgrade`, `mtd`, `flash`, `ubiformat`, `nandwrite`, NAND erase, `dd` to MTD, `fw_setenv`, NVRAM write, bootconfig/partition/bootloader modification, persistent service configuration. Prohibited until a separate written GO decision and independently validated recovery plan exist.

Do not infer approval for a later action from approval of an earlier action.

## 6. Required preflight before any router-side mutation

Before requesting permission, provide a concise change proposal containing:
1. Task/requirement ID.
2. Exact commands, in execution order.
3. Exact files, interfaces, services or partitions affected.
4. Whether each operation is RAM-only or persistent.
5. Expected LAN/Internet interruption and duration.
6. Failure modes and worst credible outcome.
7. Rollback commands and evidence that rollback is available.
8. Whether rollback depends on UART, programmer, bootloader access or a second device.
9. Success criteria and stop conditions.

If rollback depends on UART or hardware recovery unavailable to the owner, mark **NO-GO**.

## 7. Evidence rules

Every technical statement in reports must be labelled:
- `OWNER_CONFIRMED`
- `DEVICE_READBACK`
- `SOURCE_VERIFIED`
- `MEASURED`
- `REPORTED_UNVERIFIED`
- `INFERRED`
- `UNKNOWN`

For every test, record:
- date/time and timezone;
- host/device identity and software version;
- exact command or test procedure;
- raw output/log path;
- result: PASS / FAIL / BLOCKED / NOT_RUN;
- limitations and confidence.

Never invent:
- commit SHAs, branch names, paths, device output, benchmark numbers, test results or compatibility claims.
- “100% compatible” claims based on compilation or source similarity.
- NSS offload claims based only on installed packages or loaded modules.
- WireGuard functionality claims based only on daemon process or interface creation.

Distinguish:
- binary starts vs. tunnel passes traffic;
- interface exists vs. peer handshake succeeds;
- switch L2 forwarding vs. Qualcomm NSS NAT/PPPoE offload;
- build success vs. hardware compatibility;
- virtual memory (`VmSize`) vs. physical resident memory (`VmRSS`).

## 8. Source control rules

- Create branches for work; do not commit directly to `main`.
- Suggested branches: `main`, `develop`, `feature/<topic>`, `research/<topic>`, `fix/<topic>`.
- Do not force-push shared branches.
- Do not rewrite history after review unless explicitly requested.
- Every meaningful change requires a commit with a descriptive message.
- Pin upstream sources by exact commit SHA only after source audit and architecture review.
- Never track secrets or generated firmware images in Git by default.

## 9. Engineering workflow for every change

1. Identify requirement/issue ID.
2. State problem and evidence.
3. Propose design and affected components.
4. Obtain architecture review for cross-subsystem changes.
5. Implement the smallest reviewable change.
6. Run static checks and build.
7. Run targeted tests and relevant regression tests.
8. Save raw logs and a test report.
9. Update docs, manifest and changelog.
10. Submit a review summary; do not merge or release without the required approval.

## 10. Required final response format from Gemini

Every task completion report must use:

### A. Summary
What was done and what was not done.

### B. Changed files
Exact relative paths and purpose.

### C. Evidence
Commands, source URLs, commit SHAs, raw log paths and key excerpts.

### D. Verification
PASS / FAIL / BLOCKED / NOT_RUN for each acceptance criterion.

### E. Risks and unknowns
Explicitly list unresolved questions; do not fill gaps by assumption.

### F. Recommendation
Next smallest safe task and why.

### G. Approval required
List any action requiring user approval. If none, say `None`.

Stop after the requested task. Do not autonomously advance to the next phase.
