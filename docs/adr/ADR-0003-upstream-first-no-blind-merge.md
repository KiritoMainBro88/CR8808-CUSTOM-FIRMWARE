# ADR-0003 — Upstream-First Integration, No Blind Merge

- Status: ACCEPTED
- Date: 2026-11-09

## Context
Candidate trees differ in kernel, DTS, switch, NSS and Wi-Fi assumptions.

## Decision
Audit and pin exact commits. Integrate selected changes as small patches/cherry-picks with provenance, dependency, tests and revert plan. Do not merge whole repositories blindly.

## Consequences
More integration effort, clearer maintenance and lower risk of incompatible subsystems.
