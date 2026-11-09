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
| P1-005 | Final Gate G1 sign-off & Git history remediation decision | P1/P2 | BLOCKED | ChatGPT + User | P1-REV |
| P2-001 | Re-audit router baseline using approved read-only commands | P2 | BLOCKED | Gemini | P1-005 + explicit approval |
| P2-002 | Create feature parity inventory against RA82 | P2 | NOT_STARTED | Gemini | Router evidence |
| P2-003 | Select base and integration strategy | P2 | BLOCKED | ChatGPT + User | P1-004, P2-001 |
| P3-001 | Implement approved target and driver changes | P3 | NOT_STARTED | Gemini | P2-003 |
| P3-002 | Integrate Rust WireGuard package/service | P3 | NOT_STARTED | Gemini | P2-003 |
| P4-001 | Reproducible PC build and static validation | P4 | NOT_STARTED | Gemini | P3 |
| P5-001 | Non-persistent hardware validation feasibility | P5 | BLOCKED | ChatGPT + User | P4 + safe recovery design |
| P6-001 | Release candidate and deployment decision | P6 | BLOCKED | User | All gates |

## Current instruction
Phase P1 Architecture Review Response task (`P1-REV`) is completed on branch `review/g1-architecture-corrections`. Deliverable produced at `reports/2026-11-09/CHATGPT_G1_REVIEW_RESPONSE.md`. Awaiting Product Owner and Architecture Lead decisions on Git history remediation and Phase P2 read-only command approval. Gemini execution stopped.
