# PROMPT 01 — Read-only router baseline (LATER; NOT AUTHORIZED NOW)

Do not execute this prompt during P0/P1. It is a template for a later task only.

Precondition: ChatGPT architecture review has completed, the user explicitly approves a specific read-only command list, and the owner confirms the PC has an independent Internet fallback if required.

Rules:
- Read-only commands only.
- Do not upload files.
- Do not write `/tmp`.
- Do not start/stop services.
- Do not alter routes, firewall, Wi-Fi, sysctl, IRQ, cron or NVRAM.
- Do not reboot.
- Redact secrets and unnecessary identifiers.

Collect only the approved commands and save raw output under `reports/<date>/router-baseline/`. Stop if any command could write state or has ambiguous side effects.
