# Project Backlog

Status values: `READY`, `IN_PROGRESS`, `BLOCKED`, `DONE`, `NOT_STARTED`.

| ID | Task | Phase | Status | Owner | Dependency |
|---|---|---|---|---|---|
| P0-001 | Read project instructions and initialize Git safely | P0 | DONE | Gemini | None |
| P0-002 | Create project directory tree | P0 | DONE | Gemini | P0-001 |
| P1-001 | Audit PC/Windows/WSL2 resources without installing tools | P1 | DONE | Gemini | P0-002 |
| P1-002 | Audit upstream repositories, licenses, branches and commits | P1 | DONE | Gemini | P0-002 |
| P1-003 | Inspect CR881x/CR8808 target, DTS, switch and NSS source support | P1 | DONE | Gemini | P1-002 |
| P1-004 | Produce source/hardware compatibility report | P1 | DONE | Gemini | P1-001..003 |
| P1-GH | GitHub repository integration, security audit and remote push | P1 | DONE | Gemini | P1-004 |
| P1-REV | ChatGPT Architecture Review response & technical corrections | P1 | DONE | Gemini | P1-GH |
| P1-G1F | Gate G1 architecture finalization, parity matrix & design specs | P1 | DONE | Gemini | P1-REV |
| P1-REV2 | Gate G1 Round 2 corrections (PHY/Switch, DSA, Parity, Recovery, R0) | P1 | DONE | Gemini | P1-G1F |
| P1-CLN | Git history cleanup application (Option 1 force-push) | P1 | BLOCKED | Product Owner | P1-REV2 dry-run approval |
| P2-001 | Re-audit router baseline using approved Class R0 read-only commands | P2 | BLOCKED | Gemini | R0 Manifest approval |
| P2-002 | Finalize feature parity inventory against on-device baseline | P2 | NOT_STARTED | Gemini | P2-001 |
| P2-003 | Select base and integration strategy | P2 | DONE | ChatGPT + User | Clean DSA baseline approved |
| P3-001 | Implement approved clean DSA target and YT9215 driver changes | P3 | NOT_STARTED | Gemini | P2-003, P1-CLN |
| P3-002 | Integrate Rust BoringTun package and procd service | P3 | NOT_STARTED | Gemini | P2-003 |
| P4-001 | Setup WSL2 build toolchain & reproducible PC compilation | P4 | NOT_STARTED | Gemini | P3 |
| P5-001 | Non-persistent RAM initramfs netboot hardware validation | P5 | BLOCKED | ChatGPT + User | P4 + safe recovery design |
| P6-001 | Release candidate and deployment decision | P6 | BLOCKED | User | All gates |

## Current instruction
Gate G1 Round 2 Architecture Corrections completed (`P1-REV2`). Branch `feature/g1-corrections-round2` created and synchronized. Deliverables updated & authored:
- `reports/2026-11-09/G1_REVIEW_ROUND2.md` (Authoritative Round 2 deliverable)
- `docs/FEATURE_PARITY_MATRIX.md` (Rebuilt with empirical taxonomy)
- `docs/DSA_BASELINE_DESIGN.md` (DSA driver divergence & AArch64 ABI)
- `docs/NSS_INTEGRATION_DESIGN.md` (Driver ownership & Phase 1 prerequisite)
- `docs/RECOVERY_AND_ROLLBACK_DESIGN.md` (Real Xiaomi boot flags & TFTP reality)
- `docs/R0_READONLY_AUDIT_MANIFEST.md` (QSDK tooling reality & risk levels)
- `reports/2026-11-09/FINAL_G1_ARCHITECTURE_DECISION.md` (Disambiguated switch from internal PHY)
- `docs/02_DEVICE_BASELINE.md` (Internal SoC PHY separated)

Tasks `P1-CLN` (applying Git history rewrite to GitHub remote) and `P2-001` (running Class R0 router audit) remain BLOCKED awaiting Product Owner and Architecture Lead approvals. Gemini execution stopped.
