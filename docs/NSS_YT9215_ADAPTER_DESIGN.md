# Architecture & Driver Design: Motorcomm YT9215SC Switch Integration with Qualcomm NSS

- **Document ID:** `docs/NSS_YT9215_ADAPTER_DESIGN.md`
- **Project:** `CR8808-CUSTOM-FIRMWARE` (v0.1.0-dev.2)
- **Target Hardware:** Xiaomi CR8808 Ver.B (Internal Codename `CR8818`, Board Profile `ap-mp03.3`, Qualcomm IPQ5018 + Motorcomm YT9215SC)
- **Target Platform:** OpenWrt Mainline / Linux Kernel 6.18 (AArch64 musl)
- **Scope:** Exhaustive Engineering Analysis of YT9215SC CPU Tagging, CPU Conduit Topology, DSA `tag_8021q` Feasibility, and Qualcomm NSS Coexistence
- **Status:** Architectural Design & Hardware Driver Specification

---

## 1. Executive Summary & Problem Scope

Enabling Qualcomm NSS (Network Subsystem) hardware offload on the Xiaomi CR8808 Ver.B requires solving a fundamental hardware protocol mismatch:
1. **The Qualcomm NSS NPU Firmware (`retail_router0.bin`):** Is a closed-source binary running on the IPQ5018 NPU core. It performs hardware packet classification, connection state lookup, NAT rewriting, and DMA queuing. It strictly recognizes **standard Ethernet II frames**, **IEEE 802.1Q VLAN tags (`0x8100`)**, **IEEE 802.1ad QinQ (`0x88a8`)**, and **PPPoE (`0x8864`)**.
2. **The Motorcomm YT9215SC Switch:** Is a 7-port managed Gigabit switch chip. Under Linux DSA, it identifies switch ports using an **8-byte proprietary CPU tag** with a hardware-default EtherType / TPID of **`0x9988`** (`ETH_P_YT921X`).
3. **The Core Architectural Bottleneck:** When NSS is enabled on the CPU conduit (`stmmac` / `dwmac-ipq5018`), frames carrying the `0x9988` tag hit the NSS hardware parser. Because `0x9988` is not an officially recognized L2/L3 protocol in NSS firmware, its silicon behavior is formally **`UNVERIFIED`** on physical hardware; theoretically, it fails L3 header extraction and either drops the frame or punts it to the host CPU slow-path.

This document dissects the exact 8-byte CPU tag structure, maps the dual CPU conduit hardware topology (`port@4` and `port@8`), evaluates the technical feasibility and prerequisites of writing a DSA `tag_8021q` adapter, and evaluates the dual-conduit demux alternative from `zcop/immortalwrt`.

---

## 2. Exhaustive Anatomy of the Motorcomm YT9215SC CPU Tag (8 Bytes)

As verified in David Yang's mainline upstream driver ([`net/dsa/tag_yt921x.c`](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/tree/net/dsa/tag_yt921x.c)) and board DTS:

```
Frame Encapsulation Format on CPU Conduit:
+----+----+-----------------+---------------------------------------+----+---------+
| DA | SA | TagET (0x9988)  |             Tag Body (6B)             | ET | Payload |
+----+----+-----------------+---------------------------------------+----+---------+
  6B   6B        2B                            6B                     2B      NB
```

### 2.1 Field Breakdown of the 8-Byte Tag:

```
Byte 0-1: [ Tag EtherType / TPID ] = 0x9988 (ETH_P_YT921X / YT921X_CPU_TAG_TPID_TPID_DEFAULT)
Byte 2-3: [ VLAN Tag Field ]       = 16-bit internal VLAN identifier (unused on simple TX)
Byte 4-5: [ Rx Port & Command ]    = Ingress metadata from switch to CPU:
          - Bit 15:       YT921X_TAG_PORT_EN (Rx Port Valid flag)
          - Bits 14-11:   YT921X_TAG_RX_PORT_M (4-bit source physical port index: 0..8)
          - Bits 10-0:    YT921X_TAG_RX_CMD_M (Forwarding reason / classification code):
                          * 0x080: YT921X_TAG_RX_CMD_FORWARDED (Hardware already forwarded)
                          * 0x0b2: YT921X_TAG_RX_CMD_UNK_UCAST (Unknown unicast trap to CPU)
                          * 0x0b4: YT921X_TAG_RX_CMD_UNK_MCAST (Unknown multicast trap to CPU)
Byte 6-7: [ Tx Port Mask ]         = Egress steering metadata from CPU to switch:
          - Bit 15:       YT921X_TAG_PORT_EN (Tx Port Valid flag)
          - Bits 10-0:    YT921X_TAG_TX_PORTS_M (Egress port bitmask: BIT(port))
```

### 2.2 Critical Driver Constant Audit:
```c
#define ETH_P_YT921X                     0x9988
#define YT921X_CPU_TAG_TPID_TPID_DEFAULT 0x9988
#define YT921X_TAG_LEN                   8
```
> [!IMPORTANT]
> The tag EtherType is strictly **`0x9988`** by hardware default (configurable via switch register `YT921X_CPU_TAG_TPID`). It is **NOT** `0x88f7` (which is standard IEEE 1588 PTP). Any architectural document citing `0x88f7` was referencing erroneous community speculation.

---

## 3. Physical & Logical CPU Conduit Topology Verification

A rigorous review of the CR8818 board DTS (`yangfl` commit `b230c2f` and `zcop` commit history) resolves the exact mapping of the switch's two CPU links:

```
              +-----------------------------------------------------------+
              |                   Qualcomm IPQ5018 SoC                    |
              |                                                           |
              |     [ Synopsys DWMAC 0 ]              [ Synopsys DWMAC 1 ]|
              |        (Node: &dp1)                      (Node: &dp2)     |
              |       (Netdev: eth0)                    (Netdev: eth1)    |
              +--------------|---------------------------------|----------+
                             |                                 |
           Qualcomm Internal | GE PHY                          | Qualcomm Uniphy
            (PHY ID: 0x004dd0c0 at 88000.mdio:07)              | SerDes (SGMII 1000M)
                             |                                 |
              +--------------|---------------------------------|----------+
              |           [ Port 4 ]                        [ Port 8 ]    |
              |        (Internal PHY 4)                  (SerDes Channel) |
              |      Role: Secondary Conduit           Role: Primary Conduit
              |            ("cpu2")                          ("cpu1")     |
              |                                                           |
              |                  Motorcomm YT9215SC Switch                |
              |                   (MDIO Address: 0x1d)                    |
              |                                                           |
              |     [ Port 0 ]       [ Port 1 ]       [ Port 2 ]       [ Port 3 ]
              |      (PHY 0)          (PHY 1)          (PHY 2)          (PHY 3)
              +---------|----------------|----------------|----------------|--+
                        |                |                |                |
                     [ LAN1 ]         [ LAN2 ]         [ LAN3 ]         [ WAN ]
```

### 3.1 Clarification of Port 4 vs. Physical WAN:
- **Port 3:** Is wired directly to the **physical external WAN RJ45 port** via internal PHY 3.
- **Port 4:** Is an **internal MAC link** connected via Qualcomm Internal GE PHY to SoC DWMAC 0 (`dp1` / `eth0`). It is **NOT** an independent physical WAN socket.
- **Port 8:** Is an **internal SerDes link** connected to SoC DWMAC 1 (`dp2` / `eth1`) via SGMII 1000M.
- **In `yangfl/openwrt`:**
  - `port@8` is declared as the primary DSA master (`ethernet = <&dp2>`).
  - `port@4` is configured as a DSA slave netdev labeled `cpu` (`phy-mode = "internal"`).
  - In `02_network`, `yangfl` bridges `cpu` (Port 4) and `wan` (Port 3) together under interface `eth0sw`, allowing `eth0` (`&dp1`) to act as the WAN conduit.
- **In `zcop/immortalwrt`:**
  - `port@8` is primary conduit `cpu1` (`ethernet = <&dp2>`).
  - `port@4` is secondary conduit `cpu2` (`ethernet = <&dp1>`).
  - Driver `tag_yt921x_enhanced.c` inspects `secondary-conduit-user-mask = <0x8>`: packets for Port 3 (bit 3 = `0x8`) are directed out conduit `eth0`, while LAN ports (0, 1, 2) use `eth1`.

---

## 4. Technical Feasibility & Rigorous Analysis of DSA `tag_8021q` for YT9215SC

In earlier discussions, it was suggested that YT9215 could be made compatible with Qualcomm NSS simply by "adding a 300-line `tag_8021q` adapter". A deep review of the Linux kernel DSA subsystem (`net/dsa/tag_8021q.c`, `include/net/dsa_8021q.h`) reveals that this assertion is an oversimplification.

### 4.1 How DSA `tag_8021q` Operates in Linux:
`tag_8021q` eliminates proprietary vendor tags by repurposing standard IEEE 802.1Q VLAN headers:
1. **Sub-VLAN Encoding:** Every switch port is assigned two internal VLANs:
   - **Rx VLAN:** Encodes the ingress source port (`VID = rx_base + port_id`).
   - **Tx VLAN:** Directs frames to a specific egress port (`VID = tx_base + port_id`).
2. **Conduit Encapsulation:** Frames traversing the CPU conduit carry standard 802.1Q tags (TPID `0x8100`).
3. **NSS Transparency:** Because `0x8100` is a standard IEEE EtherType, the Qualcomm NSS firmware hardware parser parses the packet without error, offloading L3 NAT and routing.

### 4.2 Hardware Silicon Requirements for `tag_8021q`:
For a switch chip to successfully support DSA `tag_8021q`, the hardware silicon and register set must support four advanced switching primitives:

| Silicon Requirement | Description | Status in Motorcomm YT9215SC |
|---|---|---|
| **1. 4K VLAN Table Access** | Switch must allow dynamic programming of all 4096 VID entries (member port bitmask, untagged egress bitmask). | **SUPPORTED (`SOURCE_VERIFIED`).** Registers `0x80014` (PVID) and VLAN table registers allow 4K entry programming. |
| **2. Independent VLAN Filtering Control** | Must allow conduit port to receive tagged frames without dropping them when user bridge VLAN filtering is disabled. | **SUPPORTED (`SOURCE_VERIFIED`).** YT9215 supports per-port 802.1Q enable/disable and ingress filtering flags. |
| **3. Dual-Tagging / QinQ Egress** | If a user packet already contains a customer 802.1Q tag (e.g. VLAN 100), the switch must push a second outer 802.1Q tag (QinQ `0x88a8` or `0x8100`) to encode the DSA port. | **UNCERTAIN / UNVERIFIED (`UNKNOWN`).** YT9215 register map has QinQ registers, but outer tag push/pop behavior under DSA is undocumented in open sources. |
| **4. Egress Untagging per Port-VLAN Pair** | When transmitting out to LAN clients, the switch must automatically strip the internal `tag_8021q` VLAN tag so clients receive clean untagged frames. | **SUPPORTED (`SOURCE_VERIFIED`).** YT9215 VLAN table entries contain an `UNTAG_MASK` bitfield. |

### 4.3 Why `tag_8021q` Implementation is High-Effort R&D (Not a Simple Shim):
Implementing `tag_8021q` on YT9215SC requires:
1. Writing full `dsa_switch_ops` hooks:
   - `.tag_8021q_vlan_add`
   - `.tag_8021q_vlan_del`
2. Handling VLAN table collisions between Linux bridge VLANs (`bridge vlan add`) and internal DSA `tag_8021q` VLAN reservations (which consume ~64 VIDs out of the 4096 space).
3. Coordinating FDB (Forwarding Database) address learning: If MAC learning is enabled on the CPU port, the switch might bind host MAC addresses to internal `tag_8021q` VIDs, breaking cross-port routing when NSS injects packets.
4. **Conclusion:** Developing a robust `tag_8021q` driver for YT9215SC is a substantial, multi-week Linux kernel engineering task requiring dedicated JTAG/oscilloscope debugging and register verification. It cannot be assumed to work out of the box.

---

## 5. The Alternative Architecture: Physical Dual-Conduit Demux

If `tag_8021q` is deferred due to complexity, the hardware topology of CR8818 offers an alternative architecture: **Physical Dual-Conduit Hardware Partitioning**.

```
                           +------------------------+
                           |  Qualcomm NSS Core     |
                           |  (retail_router0.bin)  |
                           +-----------+------------+
                                       |
                   Accelerates WAN <-> LAN IPv4 NAT Flows
                                       |
                +----------------------+----------------------+
                |                                             |
                v (100% UNTAGGED)                             v (Bypassed / Slow-Path)
        [ GMAC0 / eth0 ]                              [ GMAC1 / eth1 ]
                |                                             |
        Qualcomm Internal PHY                         Uniphy SerDes
        (Fixed-Link 1000M)                            (SGMII 1000M)
                |                                             |
        [ Switch Port 4 ]                             [ Switch Port 8 ]
                |                                             |
   Hardwired Internal Bridge                     Multiplexed DSA Trunk
                |                                  (Ports 0, 1, 2: LAN)
        [ Switch Port 3 ]                                     |
                |                                     [ LAN1, LAN2, LAN3 ]
             [ WAN ]
```

### 5.1 How Dual-Conduit Demux Operates:
1. **WAN Path (Pure Untagged Fast-Path):**
   - Switch Port 3 (Physical WAN) is bridged in hardware silicon directly to Switch Port 4 (Internal PHY -> GMAC0 / `eth0`).
   - Packets on this link are **100% pure untagged Ethernet II frames** (no DSA tag, no `0x9988`, no `tag_8021q`).
   - When `qca-dwmac-nss` claims `eth0`, the NSS firmware parses incoming WAN packets effortlessly because there are zero foreign tags.
2. **LAN Path:**
   - LAN Ports 0, 1, 2 are switched locally in hardware by the YT9215 at 1 Gbps wire speed.
   - For LAN-to-CPU traffic, packets traverse Switch Port 8 (SGMII) to GMAC1 (`eth1`).
   - If LAN uses an untagged PVID or standard bridge, NSS can bridge flows between `eth0` (WAN) and `eth1` (LAN).

### 5.2 Trade-Off Comparison:

| Feature / Metric | Strategy 1: `tag_8021q` Driver Port | Strategy 2: Dual-Conduit Hardware Demux |
|---|---|---|
| **Software Architecture** | Clean, unified standard DSA model | Partitioned dual-conduit custom DTS |
| **Driver Modification** | Requires ~300+ lines in `yt921x.c` | Zero switch driver changes (DTS configuration only) |
| **WAN NSS Offload** | Full wire-speed (~940 Mbps) | Full wire-speed (~940 Mbps) |
| **LAN Port Isolation** | Full software control per port | Limited (Ports 0–2 share LAN conduit) |
| **Implementation Risk** | High (VLAN table/FDB collisions) | Medium (DTS routing & switch matrix setup) |
| **Readiness Status** | Conceptual R&D | Proven in `zcop` topology |

---

## 6. Actionable Implementation Blueprint for Phase C Prototype

When Phase C (Implementation Prototype) is authorized, the engineering workflow will proceed as follows:

1. **Step 1: Benchmark Dual-Conduit Demux (Fastest Proof-of-Concept):**
   - Adopt the `zcop` / `yangfl` hardware mapping (`eth0` on Port 4 for WAN, `eth1` on Port 8 for LAN).
   - Verify if `qca-dwmac-nss` can claim `eth0` as a standalone untagged interface.
   - Measure if ECM can offload traffic arriving on `eth0`.
2. **Step 2: Prototype `yt921x_8021q` in Sandbox:**
   - On branch `feature/nss-cr8818-research`, stub out `dsa_tag_8021q_ops` in a cloned `yt921x.c`.
   - Implement basic PVID cross-tagging.
   - Compile in PC buildroot to verify kernel symbol resolution and data structure compatibility.
3. **Step 3: Verification Gate:**
   - Strictly no flashing to hardware until local PC compilation succeeds with zero warnings.
