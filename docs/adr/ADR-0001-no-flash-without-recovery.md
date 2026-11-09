# ADR-0001 — No Persistent Flash Without Independent Recovery

- Status: ACCEPTED
- Date: 2026-11-09

## Context
Owner has no UART and cannot independently recover a router that fails to boot. The router also supplies the owner's current LAN/Internet.

## Decision
No persistent firmware flash or bootloader/partition/NAND/NVRAM modification until an independent recovery path has been demonstrated and the owner explicitly approves the exact procedure.

## Consequences
PC-only discovery and builds can proceed. Hardware validation may be blocked if no safe RAM boot path exists. Dual boot alone is not accepted as recovery proof.
