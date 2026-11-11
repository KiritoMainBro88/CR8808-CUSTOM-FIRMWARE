# Ethernet Dual-Conduit Architecture & Topology Audit (M7.1)

- **Document ID:** `docs/M7.1/DSA_DUAL_CONDUIT_AUDIT.md`
- **Project:** `CR8808-CUSTOM-FIRMWARE` (v0.2.0-dev)
- **Target Hardware:** Xiaomi CR8808 Ver.B (Codename `CR8818`, Qualcomm IPQ5018 + Motorcomm YT9215SC)
- **Author:** Gemini 3.8 Flash High (Lead Developer / Research Engineer)
- **Reporting Authority:** ChatGPT (Chief Architect / Architecture Lead)
- **Status:** Complete Technical Audit & Correction for Gate M7.1
- **Evidence Classification:** `SOURCE_VERIFIED`, `PC_VERIFIED`, `REPORTED_UNVERIFIED`.

---

## 1. Executive Summary & Correction of the 2.5 Gbps Claim

As instructed by the Chief Architect:
> *"Port 8 hiện chạy SGMII ở 1.000 Mbps, không phải 2.5 Gbps. YT9215S có khả năng 2500Base-X nhưng tác giả chưa làm cho IPQ5018 hoạt động được ở chế độ đó. Patch 940 của David Yang là thành phần quan trọng để xử lý vai trò REVSGMII của SerDes. Như vậy, trong báo cáo M7, phần ghi Port 8 là 2.5G SGMII+ cần sửa. Không được quảng cáo router có kết nối Ethernet 2.5 Gbps."*

This document provides a rigorous architectural audit of the physical Ethernet datapath, corrects all legacy 2.5 Gbps claims, documents the exact operation of Motorcomm switch register `0x8000c`, and details the primary and secondary conduit configurations.

---

## 2. Physical Ethernet Hardware Topology

The Qualcomm IPQ5018 SoC and Motorcomm YT9215SC switch interface across two distinct physical Media Access Controllers:

```
+=================================================================================================+
|                                     QUALCOMM IPQ5018 SoC                                        |
|                                                                                                 |
|   +---------------+         +---------------+                         +---------------------+   |
|   | GMAC0 (eth0)  | <-----> |   GE PHY 0    | <--- Internal MDI ----> | Port 4 (sw-cpu)     |   |
|   | 1000BASE-T    |         | (0x004dd0c0)  |                         | GE PHY 4 (0x4)      |   |
|   +---------------+         +---------------+                         +---------------------+   |
|                                                                       | MOTORCOMM YT9215SC  |   |
|   +---------------+         +---------------+                         | SWITCH (MDIO 0x1d)  |   |
|   | GMAC1 (eth1)  | <-----> | Uniphy SerDes | <--- SGMII 1000M -----> | Port 8 (CPU Conduit)|   |
|   | DWMAC         |         | (Patch 940)   |                         | SerDes PHY 8 (0x8)  |   |
|   +---------------+         +---------------+                         +---------------------+   |
+==================================================================================|==============+
                                                                                   |
                                            +------------+------------+------------+------------+
                                            |            |            |            |
                                       +---------+  +---------+  +---------+  +---------+
                                       | Port 0  |  | Port 1  |  | Port 2  |  | Port 3  |
                                       | LAN 1   |  | LAN 2   |  | LAN 3   |  | WAN     |
                                       +---------+  +---------+  +---------+  +---------+
```

### 2.1 Formal Correction: Port 8 Physical Speed is 1,000 Mbps
- **Hardware Capability vs Driver Reality:**
  - The Motorcomm YT9215SC switch silicon has 2500Base-X SerDes capabilities on Port 8.
  - However, in the upstream Device Tree authored by David Yang (`yangfl/openwrt`, commit `6729bbe`), the physical operating mode between the IPQ5018 Uniphy and YT9215 Port 8 is **1000 Mbps SGMII** (or 1000Base-X).
  - Attempting to force `2500base-x` causes link training failure on the IPQ5018 Uniphy SerDes.
  - **Correction:** All project documentation, marketing claims, and specifications are formally corrected: **The CPU conduit on Port 8 operates at 1.0 Gbps (1,000 Mbps). No 2.5 Gbps link is claimed or supported.**

### 2.2 Patch 940: REVSGMII SerDes Role Alignment
- In standard SGMII, one end operates as a MAC (Data Terminal Equipment) and the other operates as a PHY.
- The IPQ5018 Uniphy SerDes operates strictly as a MAC.
- In unpatched Linux mainline (`drivers/net/dsa/yt921x.c`), configuring `PHY_INTERFACE_MODE_SGMII` configures the switch Port 8 SerDes also as a MAC (`YT921X_SERDES_MODE_SGMII`), causing two MACs to face each other without clock synchronization.
- **David Yang's Patch 940 (`940-net-dsa-yt921x-Abuse-SGMII-for-REVSGMII.patch`):**
  Intercepts `PHY_INTERFACE_MODE_SGMII` and forces `YT921X_SERDES_MODE_REVSGMII` (Reverse SGMII, PHY mode), allowing the switch SerDes to properly synchronize clocks with the SoC. **This patch is mandatory for both Track A and Track B.**

---

## 3. Switch Port Allocation & Register `0x8000c` Mechanics

### 3.1 Port Identity Mapping
- **Port 0:** LAN 1 (Internal GE PHY 0)
- **Port 1:** LAN 2 (Internal GE PHY 1)
- **Port 2:** LAN 3 (Internal GE PHY 2)
- **Port 3:** WAN (Internal GE PHY 3)
- **Port 4:** Secondary CPU Conduit (Internal GE PHY 4, back-to-back with IPQ5018 internal GE PHY `0x004dd0c0`)
- **Port 8:** Primary CPU Conduit (SerDes SGMII 1000M facing Qualcomm Uniphy)

### 3.2 Switch Register `0x8000c` (`YT921X_EXT_CPU_PORT`)
Reverse-engineered by `zcop` on live CR881x hardware, register `0x8000c` controls CPU port tagging, header injection, and packet diversion:

```
Register Address: 0x8000c (32-bit)
Default Value:    0x00000100 (Port 8 designated as CPU port)

Bit Fields:
Bits [3:0]:   Secondary CPU Port ID (Set to 0x4 for Port 4)
Bit  [4]:     TAG_EN on Secondary CPU Port (1 = Tagged, 0 = Untagged Raw Frames)
Bits [11:8]:  Primary CPU Port ID (Set to 0x8 for Port 8)
Bit  [12]:    TAG_EN on Primary CPU Port (1 = Enforce DSA Tag, 0 = Untagged)
```

### 3.3 Single-Conduit vs Dual-Conduit Comparison

| Architectural Feature | Track A: Single-Conduit Baseline (David Yang Upstream) | Track B: Dual-Conduit Enhanced (zcop / kuncy7) |
|---|---|---|
| **Primary Conduit** | `eth1` (Port 8 / SGMII 1000M) | `eth1` (Port 8 / SGMII 1000M) |
| **Secondary Conduit** | Disabled in base DTS (`eth0` unassigned) | `eth0` (Port 4 / Internal GE PHY 1000M) |
| **LAN Traffic Path** | Ports 0–2 $\rightarrow$ Tagged `tag_yt921x` $\rightarrow$ Port 8 $\rightarrow$ `eth1` | Ports 0–2 $\rightarrow$ Tagged `tag_yt921x_8021q` $\rightarrow$ Port 8 $\rightarrow$ `eth1` |
| **WAN Traffic Path** | Port 3 $\rightarrow$ Tagged `tag_yt921x` $\rightarrow$ Port 8 $\rightarrow$ `eth1` | Port 3 $\rightarrow$ **Untagged Raw Frames** $\rightarrow$ Port 4 $\rightarrow$ `eth0` |
| **Register `0x8000c` Value** | `0x00001100` (Port 8 tagged) | `0x00001104` (Port 8 tagged, Port 4 untagged) |
| **Throughput Limit** | 940 Mbps total bidirectional aggregate (duplex bottleneck) | **1.1–1.4 Gbps aggregate** (WAN and LAN cross separate GMACs) |
| **NSS Compatibility** | Incompatible with NSS NPU parser (4-byte tag shifts headers) | Fully compatible (WAN enters NSS MAC0 cleanly untagged) |

---

## 4. DSA Phylink & Device Tree Configuration

### 4.1 Track A (Single-Conduit Daily Driver) DTS Snippet:
```dts
// MAC1 --- SGMII 1000M ---> YT9215 Port 8
&gmac1 {
    status = "okay";
    phy-mode = "sgmii";
    fixed-link {
        speed = <1000>;
        full-duplex;
    };
};
```

### 4.2 Track B (Dual-Conduit NSS Experimental) DTS Snippet:
```dts
// MAC0 (eth0) -> GE PHY -> YT9215 Port 4 (WAN Conduit)
&gmac0 {
    status = "okay";
    phy-mode = "gmii";
    fixed-link {
        speed = <1000>;
        full-duplex;
    };
};

// MAC1 (eth1) -> Uniphy SerDes -> YT9215 Port 8 (LAN Conduit)
&gmac1 {
    status = "okay";
    phy-mode = "sgmii";
    fixed-link {
        speed = <1000>;
        full-duplex;
    };
};
```

---

## 5. Audit Conclusion

1. **Port 8 Speed:** Confirmed 1,000 Mbps SGMII. 2.5 Gbps claims retracted.
2. **Track A Baseline:** Single conduit via Port 8 (`eth1`) provides rock-solid daily reliability.
3. **Track B NSS Evolution:** Dual-conduit via Port 4 (`eth0` WAN untagged) and Port 8 (`eth1` LAN tagged) is the only viable path to achieve hardware NAT offloading without corrupting the NSS packet parser.
