# 02 — Device Baseline and Evidence Register

## Product identity
- Commercial device: Xiaomi CR8808 Ver.B — `OWNER_CONFIRMED`.
- Prior audit reported internal model string `CR8818` and board string `ap-mp03.3` — `REPORTED_UNVERIFIED`.
- Do not call the commercial product CR8818. Do not infer all CR881x variants are identical.

## Preliminary baseline

| Item | Prior reported value | Evidence status |
|---|---|---|
| SoC | Qualcomm IPQ5018 | REPORTED_UNVERIFIED |
| CPU | Dual Cortex-A53, approximately 1 GHz | REPORTED_UNVERIFIED |
| RAM | 256 MB physical | REPORTED_UNVERIFIED |
| Switch | Motorcomm YT9215S or YT9215SC | REPORTED_UNVERIFIED; exact suffix unresolved |
| 5 GHz radio | QCN6102 | REPORTED_UNVERIFIED |
| 2.4 GHz | Integrated IPQ5018 radio | REPORTED_UNVERIFIED |
| NAND | Winbond W25N01GWZEIG, 128 MB | REPORTED_UNVERIFIED |
| Firmware | Xiaomi RA82 v1.4.31 | REPORTED_UNVERIFIED |
| Kernel | Linux 4.4.60 | REPORTED_UNVERIFIED |
| Wi-Fi | 5 GHz HE160, channel 40 | REPORTED_UNVERIFIED |
| Router IP | Default gateway (e.g. 192.168.x.1) | REPORTED_UNVERIFIED; redacted in public docs |
| PC IP | Local test client (e.g. 192.168.x.y) | REPORTED_UNVERIFIED; redacted in public docs |

## Read-only evidence required later
Only under a separately approved read-only task:
- `ubus call system board`
- `/etc/board.json`
- `nvram get model` (read only)
- `uname -a`, `/proc/version`, `/proc/cpuinfo`
- `/proc/meminfo`, `/proc/mtd`, `dmesg`
- Xiaomi version metadata
- `lsmod`, switch driver and chip ID
- radio/driver/HE160 state
- bridge, VLAN, interfaces, routes and firewall
- NSS/ECM counters and module versions
- boot flags (read only)

Do not expose private keys, passwords, tokens, serials or unnecessary identifiers.

## Evidence labels
`OWNER_CONFIRMED`, `DEVICE_READBACK`, `SOURCE_VERIFIED`, `MEASURED`, `REPORTED_UNVERIFIED`, `INFERRED`, `UNKNOWN`.
