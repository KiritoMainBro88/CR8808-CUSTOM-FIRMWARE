# 07 — Release and Recovery Policy

## Release artifact requirements
Every candidate release must include:
- source manifest with exact commit SHAs;
- build config, toolchain and environment;
- patch list with provenance;
- image filename, size and SHA-256;
- SBOM and license report;
- test matrix with PASS/FAIL/BLOCKED/NOT_RUN;
- feature parity matrix;
- known limitations and upgrade notes;
- recovery plan and rollback procedure;
- explicit release approval.

## No-UART constraint
The owner does not have UART and cannot independently recover a router that fails to boot. Therefore:
- Dual boot is not considered sufficient recovery proof by itself.
- A second partition is not considered a complete rescue plan unless the fallback mechanism is verified on this exact hardware and can be invoked without unavailable tools.
- No persistent flash while the only recovery route requires UART, NAND programmer, soldering or unverified bootloader commands.
- A RAM boot test is not automatically safe; the exact mechanism and failure behavior must be documented first.
- No flash authorization is implied by building an image or testing a temporary process.

## GO/NO-GO checklist
All must be YES:
1. Exact target verified.
2. Full image layout reviewed.
3. Stock firmware backup obtained and its restore path verified.
4. Independent recovery path demonstrated without unavailable UART.
5. Boot slot/fallback behavior understood and tested.
6. No unresolved critical hardware/driver risks.
7. Required feature parity accepted.
8. Test matrix passed.
9. User has reviewed risks and explicitly approved this exact image and procedure.

Any NO or UNKNOWN = NO-GO.
