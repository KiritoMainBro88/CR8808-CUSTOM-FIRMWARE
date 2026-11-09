# ADR-0002 — Separate Existing Lab From Product Repository

- Status: ACCEPTED
- Date: 2026-11-09

## Context
Existing `D:\vibecode\test_wifi` workspace and Gemini conversation contain prior investigations.

## Decision
Preserve them. Use `D:\vibecode\CR8808-CUSTOM-FIRMWARE` as the only new product repository. Import only selected evidence with provenance and hashes.

## Consequences
Avoids loss of existing context and prevents unreviewed experiments becoming product code.
