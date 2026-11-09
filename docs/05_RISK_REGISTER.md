# 05 — Risk Register

| ID | Risk | Mitigation | Gate blocker |
|---|---|---|---|
| R-001 | No UART or independent recovery | No NAND flash until independent recovery proven | YES |
| R-002 | Wrong CR880x target | Verify exact CR8808 Ver.B board/DTS | YES |
| R-003 | YT9215S vs SC mismatch | Verify marking, ID and driver implementation | YES |
| R-004 | NSS incompatible with switch/DSA | Isolated port and subsystem tests | YES |
| R-005 | Loss of Xiaomi cloud/Mesh/UI/OTA | Feature parity matrix and owner approval | YES if required |
| R-006 | Wi-Fi calibration mismatch | Preserve board data and test HE160 | YES |
| R-007 | NAND/UBI/boot layout mismatch | Read-only audit and image layout validation | YES |
| R-008 | Proprietary module/kernel mismatch | Rebuild and regression-test exact modules | YES |
| R-009 | Rust WireGuard failure | Real peer, traffic, reconnect, soak and rollback | YES |
| R-010 | AI agent destructive action | Allowlist, preflight and explicit approval | YES |
| R-011 | RAM pressure/OOM | Long soak and memory pressure telemetry | YES |
| R-012 | Current LAN/Internet loss | PC-only discovery; separate fallback before device test | NO for PC-only |
| R-013 | Unlicensed firmware blobs | Provenance and license review | YES for redistribution |
| R-014 | False success based on compile | Separate build, boot, interface, traffic and soak criteria | YES |
