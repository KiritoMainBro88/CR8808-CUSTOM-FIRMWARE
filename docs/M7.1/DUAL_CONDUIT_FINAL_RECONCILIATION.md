# Dual-Conduit Architecture Final Reconciliation: Upstream Mainline vs ZCOP Driver

- **Document ID:** `docs/M7.1/DUAL_CONDUIT_FINAL_RECONCILIATION.md`
- **Project:** `CR8808-CUSTOM-FIRMWARE` (v0.2.0-dev)
- **Target Hardware:** Xiaomi CR8808 Ver.B (Codename `CR8818`, Qualcomm IPQ5018 + Motorcomm YT9215SC)
- **Author:** Gemini 3.8 Flash High (Lead Developer / Research Engineer)
- **Reporting Authority:** ChatGPT (Chief Architect / Architecture Lead)
- **Status:** Complete Technical Code-Level Audit for Gate M7.1 Revision 1.2
- **Evidence Classification:** `SOURCE_VERIFIED` (Upstream & ZCOP Repository Code), `REPORTED_UNVERIFIED` (Dual-Conduit Hardware Forwarding on CR8818).

---

## 1. Executive Summary & Code-Level Problem Statement

As established by the Chief Architect:
> *"Một điểm cần làm rõ: YT9215 có khả năng phần cứng hỗ trợ tối đa hai GMAC, nhưng driver upstream đang cấu hình một tagged CPU port. Không thể đồng nhất khả năng phần cứng với tính năng đã được driver triển khai.*
> *Đối với ZCOP, cần tách hai trạng thái:*
> *- Mã nguồn và cấu hình driver: có thể xác minh ở cấp repository.*
> *- Hoạt động dual-conduit trên CR8808 thật: chưa xác minh."*

This document presents a rigorous code-level comparison between **Upstream Linux Mainline (`drivers/net/dsa/yt921x.c` / David Yang's DTS)** and **ZCOP's Out-Of-Tree Enhanced Fork (`zcop/immortalwrt`)**. 

The fundamental finding is: **Upstream Linux mainline DSA driver configures only a single CPU port on the Motorcomm YT9215.** While the silicon has hardware capability for two MAC connections, upstream Linux exposes only one. Dual-conduit is exclusively an out-of-tree, experimental capability implemented by ZCOP via custom driver hooks and proprietary Device Tree bindings.

---

## 2. Upstream Linux Mainline Implementation (`SOURCE_VERIFIED`)

In upstream Linux mainline (`drivers/net/dsa/yt921x.c`, authored by David Yang), switch CPU port configuration is governed by `yt921x_chip_setup_dsa()`:

```c
static int yt921x_chip_setup_dsa(struct yt921x_priv *priv)
{
    ...
    priv->cpu_port = __ffs(priv->cpu_ports_mask);

    ret = yt921x_write(priv, YT921X_EXT_CPU_PORT,
                       YT921X_EXT_CPU_PORT_TAG_EN |
                       YT921X_EXT_CPU_PORT_PORT_EN |
                       priv->cpu_port);
    if (ret)
        return ret;
    ...
}
```

### Upstream Code Limitations:
1. **Single CPU Port Selection:** The function computes `priv->cpu_port = __ffs(priv->cpu_ports_mask)`, selecting only the **first (lowest-numbered) CPU port** found in the Device Tree bitmask.
2. **Single Register Target:** It writes that single CPU port index into `YT921X_EXT_CPU_PORT` (`0x8000c`).
3. **No Secondary Conduit Awareness:** Upstream mainline DSA contains zero code to program a second conduit port, zero secondary tag handling, and zero per-port CPU conduit routing for YT9215.
4. **David Yang DTS Target (`ipq5018-cr8818.dts`):** Upstream Device Tree declares **only Port 8** as a CPU port connected to `&gmac1` via SGMII. Port 4 is left completely unassigned.

**Conclusion for Upstream:** Under pure upstream OpenWrt with mainline DSA, **only a single conduit is possible (Port 8 via `eth1`)**.

---

## 3. ZCOP Enhanced Driver Implementation (`SOURCE_VERIFIED` in ZCOP Tree)

In `zcop/immortalwrt` (commit `7b307fa`), ZCOP implemented a dedicated out-of-tree driver (`compatible = "motorcomm,yt9215-enhanced"`) to realize dual-conduit routing:

### 3.1 Device Tree Declarations in `ipq5018-cr881x.dts`:
```dts
ethernet-switch@1d {
    compatible = "motorcomm,yt9215-enhanced";
    reg = <0x1d>;

    motorcomm,secondary-conduit-user-mask = <0x8>; /* Bit 3 = Port 3 (WAN) */

    ports {
        port@3 {
            reg = <3>;
            label = "wan";
            phy-mode = "internal";
        };

        port@4 {
            reg = <4>;
            label = "cpu";
            phy-mode = "internal";
            motorcomm,conduit-role = "secondary-conduit";
            ethernet = <&gmac0>;
            fixed-link { speed = <1000>; full-duplex; };
        };

        port@8 {
            reg = <8>;
            phy-mode = "2500base-x";
            motorcomm,conduit-role = "primary-conduit";
            ethernet = <&gmac1>;
            fixed-link { speed = <2500>; full-duplex; };
        };
    };
};
```

### 3.2 ZCOP Dual-Conduit Mechanics:
1. **DTS Bindings:** ZCOP introduced custom, non-standard Device Tree properties:
   - `motorcomm,secondary-conduit-user-mask = <0x8>`: Explicitly designates Port 3 (WAN) to route towards the secondary conduit.
   - `motorcomm,conduit-role = "secondary-conduit"`: Flags Port 4 as secondary conduit.
   - `motorcomm,conduit-role = "primary-conduit"`: Flags Port 8 as primary conduit.
2. **Switch VLAN & Forwarding Table Partitioning:**
   Instead of relying on register `0x8000c` (which only selects one external CPU port), ZCOP programs the switch's internal **VLAN Isolation & Port Forwarding Matrix (`PORT_MEM` / `VLAN_MEM`)**:
   - Port 3 (WAN) is isolated into a hardware VLAN group containing only Port 3 and Port 4. Packets entering Port 3 egress untagged out of Port 4 towards `&gmac0` (`dp1`).
   - Ports 0–2 (LAN) are partitioned into a LAN VLAN group containing Ports 0–2 and Port 8. Packets entering LAN egress tagged out of Port 8 towards `&gmac1` (`dp2`).
3. **Tagger Implementation (`tag_yt921x_enhanced.c`):**
   - Transmit path (TX): Frames transmitted on `eth0` (`dp1`) enter Port 4 directly without tags. Frames on `eth1` (`dp2`) carry the Motorcomm 8-byte tag.
   - Receive path (RX): Frames arriving on `eth0` are stripped of any switch tagging; frames on `eth1` are demuxed by the 8-byte DSA tagger.

---

## 4. Hardware Capability vs Driver Implementation

To avoid conflation between raw silicon potential and software support, hardware capability must be rigorously distinguished from driver implementation:

| Architectural Layer | Single-Conduit Baseline (David Yang Upstream) | Dual-Conduit Enhanced (ZCOP Out-Of-Tree) |
|---|---|---|
| **Silicon Hardware Capability** | **Supported:** Switch silicon supports 2 MAC interfaces (Port 4 internal GE PHY & Port 8 SGMII). | **Supported:** Switch silicon supports 2 MAC interfaces (Port 4 internal GE PHY & Port 8 SGMII). |
| **Driver Implementation** | **Upstream Linux Mainline (`drivers/net/dsa/yt921x.c`)**:<br>Restricts setup to **one tagged CPU port** (`0x8000c`). | **Out-of-tree vendor driver (`motorcomm,yt9215-enhanced`)**:<br>Custom VLAN/port isolation matrices and secondary conduit masks. |
| **CPU Port Allocation in Code** | Hardcoded single CPU port via `__ffs(cpu_ports_mask)` | Dynamic split via `secondary-conduit-user-mask = <0x8>` |
| **Repository Code Verification** | `SOURCE_VERIFIED` in Linux kernel.org and OpenWrt mainline | `SOURCE_VERIFIED` at repository level (`zcop/immortalwrt` commit `7b307fa`) |
| **Physical Hardware Verification on CR8818** | `SOURCE_VERIFIED` via David Yang's working single-port DTS | **`REPORTED_UNVERIFIED`** (No line-rate switching captures or bi-directional multi-GMAC traces on CR8818) |

---

## 5. Architectural Directive for Milestone M7.1 Revision 1.2

1. **Silicon Capability $\neq$ Driver Feature:** While the Motorcomm YT9215 silicon physically routes two GMAC interfaces, the upstream Linux mainline driver deliberately configures only a single tagged CPU port. Hardware capability cannot be cited as proof of driver readiness.
2. **Track A (Daily Driver):** **Must use Single-Conduit Baseline (David Yang Upstream)** via Port 8 (`eth1`). It is 100% compliant with clean mainline DSA, requires zero out-of-tree switch patches, and delivers stable gigabit forwarding.
3. **Track B (Experimental NSS):** Dual-conduit is categorized strictly as an **unupstreamed research prototype**:
   - Driver source & DTS bindings are **`SOURCE_VERIFIED`** at repository level.
   - Live hardware execution on real CR8818 routers remains strictly **`REPORTED_UNVERIFIED`**.
   - Any evaluation must proceed in an isolated sandbox tree tracking ZCOP's custom driver patches.
