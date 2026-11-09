# 09 — WireGuard Go → BoringTun Rust Migration Plan

## Target state
BoringTun Rust is the only permanent WireGuard server implementation. Go is retained temporarily only as a known-good reference until Rust passes acceptance. Do not run both permanently unless a separate test explicitly requires it.

## Stages
1. Source audit: BoringTun version, patches, license, target ABI, dependencies and service model.
2. Host build: reproducible ARM target build and static/dynamic dependency audit.
3. Static validation: UAPI behavior, signal handling, TUN support, privileges, socket lifecycle.
4. Isolated device test: only with task-specific approval; temporary port/interface, no default-route changes.
5. Functional test: real peer handshake, bidirectional transfer, DNS, MTU, roaming/reconnect.
6. Performance test: TCP/UDP throughput, loaded latency, CPU per core, RSS, packet loss and jitter.
7. Reliability: start/stop/restart, crash behavior, long soak, boot ordering.
8. Migration: Rust becomes primary; verify firewall and routing.
9. Go removal: only after Rust acceptance and rollback test.

## Acceptance criteria
- Real peer completes handshake.
- Traffic passes both directions for sustained test.
- DNS and MTU are correct.
- Reconnect after network interruption works.
- Service survives restart and expected lifecycle.
- No unexplained crash, leak, OOM or route hijack.
- CPU/RSS and latency meet thresholds agreed after baseline.
- No unintended default route or firewall impact.
- Rollback is documented and tested.

Process running, interface creation, UAPI query or a 100-packet ping alone is not proof of production readiness.
