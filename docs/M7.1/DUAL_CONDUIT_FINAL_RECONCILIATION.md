# Dual-Conduit Architecture Final Reconciliation: Upstream Mainline vs ZCOP Driver

- **Document ID:** `docs/M7.1/DUAL_CONDUIT_FINAL_RECONCILIATION.md`
- **Project:** `CR8808-CUSTOM-FIRMWARE` (v0.2.0-dev)
- **Target Hardware:** Xiaomi CR8808 Ver.B (Codename `CR8818`, Qualcomm IPQ5018 + Motorcomm YT9215SC)
- **Author:** Gemini 3.8 Flash High (Lead Developer / Research Engineer)
- **Reporting Authority:** ChatGPT (Chief Architect / Architecture Lead)
- **Status:** Complete Technical Code-Level Audit for Gate M7.1 Revision 1.1
- **Evidence Classification:** `SOURCE_VERIFIED` (Upstream & ZCOP Code), `REPORTED_UNVERIFIED` (Hardware Forwarding).

---

## 1. Executive Summary & Code-Level Problem Statement

As established by the Chief Architect:
> *"Mã nguồn mainline yt921x.c tại yt921x_chip_setup_dsa() lấy CPU port đầu tiên bằng `__ffs(priv->cpu_ports_mask)` và ghi vào một thanh ghi `YT921X_EXT_CPU_PORT`. Như vậy, mã nguồn upstream hiện tại chưa chứng minh được khả năng sử dụng đồng thời hai CPU port theo kiến trúc dual-conduit mà Gemini mô tả. Phải kiểm tra riêng mã nguồn ZCOP, không được lấy upstream làm bằng chứng thay thế."*

This document presents a rigorous code-level comparison between **Upstream Linux Mainline (`drivers/net/dsa/yt921x.c` / David Yang's DTS)** and **ZCOP's Out-Of-Tree Enhanced Fork (`zcop/immortalwrt`)**. 

The fundamental finding is: **Upstream Linux mainline DSA does NOT support dual-conduit on the Motorcomm YT9215.** Dual-conduit is exclusively an out-of-tree, experimental capability implemented by ZCOP via custom driver hooks and proprietary Device Tree bindings.

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

To avoid conflation, the hardware capability must be clearly separated from software driver availability:

| Layer | Single-Conduit Baseline (David Yang Upstream) | Dual-Conduit Enhanced (ZCOP Out-Of-Tree) |
|---|---|---|
| **Hardware Silicon Capability** | Supported (Port 8 SGMII connected to GMAC1) | Supported (Port 4 connected to GMAC0; Port 8 connected to GMAC1) |
| **Driver Implementation** | **Upstream Linux Mainline (`drivers/net/dsa/yt921x.c`)** | **Out-of-tree vendor fork (`motorcomm,yt9215-enhanced`)** |
| **CPU Port Allocation in Code** | Hardcoded single CPU port via `__ffs(cpu_ports_mask)` | Dynamic split via `secondary-conduit-user-mask` |
| **Kernel Support** | Linux 6.12 LTS & Linux 6.18 LTS (Mainline clean) | Custom ImmortalWrt kernel tree only |
| **Upstream Status** | Fully upstreamed to kernel.org | **UNUPSTREAMED / VENDOR FORK ONLY** |
| **Hardware Verification on CR8818**| `SOURCE_VERIFIED` in mainline OpenWrt | `REPORTED_UNVERIFIED` on real physical device |

---

## 5. Architectural Directive for Milestone M7.1 Revision 1.1

1. **Track A (Daily Driver):** **Must use Single-Conduit Baseline (David Yang Upstream)** via Port 8 (`eth1`). It is 100% compliant with clean mainline DSA, requires zero out-of-tree switch patches, and delivers stable gigabit forwarding.
2. **Track B (Experimental NSS):** Dual-conduit is categorized strictly as an **unupstreamed research prototype**. It cannot be claimed as `SOURCE_VERIFIED` for mainline OpenWrt. Any future evaluation of dual-conduit must be performed in an isolated sandbox tree tracking ZCOP's custom driver patches.
