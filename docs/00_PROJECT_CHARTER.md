# 00 — Project Charter

- Project: CR8808-CUSTOM-FIRMWARE
- Version: 0.2
- Date: 2026-11-09
- Product Owner: User
- Architecture / Review Lead: ChatGPT
- Implementation / Workstation Operator: Gemini agents
- Target product: Xiaomi CR8808 Ver.B
- Current phase: P0/P1
- Flash authorization: NO-GO

## Problem
The current Xiaomi RA82 firmware provides the owner's working router environment. The owner wants an updateable, maintainable firmware with deeper optimization, but cannot use UART recovery and depends on this router for PC Internet access.

## Product vision
Create a maintainable firmware integration repository with pinned upstream sources, documented hardware support, controlled patches, reproducible builds, test evidence and a safe release process.

## Success criteria
- Exact target hardware identity established.
- Required Ethernet and Wi-Fi functions demonstrated on device.
- HE160 remains available.
- NSS is proven by hardware counters and controlled benchmarks if integrated.
- Rust/BoringTun is the sole permanent WireGuard implementation after acceptance; Go is removed only after Rust passes all required tests.
- Feature parity is transparent and approved.
- Build is reproducible from locked revisions and configuration.
- Recovery strategy is independently validated before any persistent installation.

## Scope
In scope: board support, DTS, switch/ethernet, Wi-Fi, NSS, network stack, Rust WireGuard, performance, security updates, build/release engineering.

Out of scope until separately approved: bootloader changes, partition changes, persistent flash, proprietary cloud reverse engineering, RF calibration modification.

## Project gates
G0 Initiation → G1 Discovery → G2 Architecture → G3 PC build → G4 non-persistent hardware validation → G5 release candidate → G6 flash authorization.

A failed gate blocks progression.
