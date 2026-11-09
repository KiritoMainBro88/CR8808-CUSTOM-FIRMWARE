# Upstream Linux Compatibility Matrix: Motorcomm YT921X Switch & OpenWrt 6.18

- **Document ID:** `docs/UPSTREAM_COMPATIBILITY_MATRIX.md`
- **Project:** `CR8808-CUSTOM-FIRMWARE` (v0.1.0-dev.2)
- **Target Hardware:** Xiaomi CR8808 Ver.B (Codename `CR8818`, Board String `ap-mp03.3`, Qualcomm IPQ5018 + Motorcomm YT9215)
- **Target Platform:** OpenWrt Clean DSA Baseline (Linux 6.18 Kernel, `qualcommax/ipq50xx`, AArch64 musl)
- **Status:** Authoritative Upstream Integration Specification
- **Revision:** Round 5.1 Review (Integration of yangfl/openwrt Commit b230c2f, David Yang Upstream Provenance, and SerDes REVSGMII Analysis)

---

## 1. Executive Summary & Kernel Divergence Analysis

A critical architectural finding must be formally established:
- **Upstream Author & Mainline Merge (Linux 6.19):** Motorcomm YT9215 support was authored by **David Yang (`mmyangfl@gmail.com`)**, reviewed by Andrew Lunn, signed off by Jakub Kicinski, and officially merged into Linux mainline in **Linux 6.19** via `CONFIG_NET_DSA_YT921X` (`drivers/net/dsa/yt921x.c`) and DSA tagger `CONFIG_NET_DSA_TAG_YT921X` (`net/dsa/tag_yt921x.c`).
- **Target Kernel Linux 6.18:** The OpenWrt target kernel planned for our baseline is **Linux 6.18**. Because Linux 6.18 predates Linux 6.19, the Motorcomm YT921X switch driver does **NOT** exist natively in clean Linux 6.18.
- **Architectural Consequence:** Our Phase 1 firmware is **NOT** "pure unpatched upstream 6.18". It is **Upstream-Derived DSA Backported from Linux 6.19 to Linux 6.18**.
- **Crucial SerDes Role Patch:** David Yang's OpenWrt implementation for CR8818 (`yangfl/openwrt` commit `b230c2f`) includes patch `940-net-dsa-yt921x-Abuse-SGMII-for-REVSGMII.patch`, which is mandatory for resolving the MAC-to-MAC collision over the SGMII SerDes between IPQ5018 and YT9215 Port 8.

---

## 2. Comparative Matrix: Driver Implementations Across Kernel Trees

| Attribute / Layer | Stock Xiaomi RA82 v1.4.31 (Linux 4.4.60) | Target Phase 1 Baseline (OpenWrt Linux 6.18) | Mainline Linux (Linux 6.19+) | `zcop` ImmortalWrt (Linux 6.6 / 6.12 NSS) |
|---|---|---|---|---|
| **Driver Location** | Out-of-tree vendor blob (`yt_switch.ko`) | Backport patch into `drivers/net/dsa/yt921x.c` | Native upstream `drivers/net/dsa/yt921x.c` | Out-of-tree package / target patch |
| **DSA Tagger Path** | None (SSDK ioctl / proprietary trunk) | Backport patch into `net/dsa/tag_yt921x.c` | Native upstream `net/dsa/tag_yt921x.c` | Out-of-tree `tag_yt921x_enhanced.c` |
| **Kernel Config** | Proprietary vendor symbols | `CONFIG_NET_DSA_YT921X=y`<br>`CONFIG_NET_DSA_TAG_YT921X=y` | `CONFIG_NET_DSA_YT921X=y`<br>`CONFIG_NET_DSA_TAG_YT921X=y` | Custom target kmod symbols |
| **Tagger Protocol** | Vendor proprietary framing | `DSA_TAG_PROTO_YT921X` (Single-conduit) | `DSA_TAG_PROTO_YT921X` (Single-conduit) | Enhanced multi-conduit tagger |
| **Secondary Conduit Mask** | N/A | **Unsupported / Ignored** | **Unsupported / Ignored** | Supported (`secondary-conduit-user-mask = <0x8>`) |
| **CPU Conduits** | GMAC0 (`eth0`) + GMAC1 (`eth1`) | **Single Conduit:** GMAC1 / Port 8 (SGMII 1000M) | **Single Conduit:** GMAC1 / Port 8 (SGMII 1000M) | **Dual Conduit:** GMAC0 / Port 4 + GMAC1 / Port 8 |
| **Phylink Integration** | None (custom vendor polling thread) | Modern Linux Phylink framework | Modern Linux Phylink framework | Hybrid Phylink + NSS-DP link state |
| **NSS Acceleration** | Proprietary QCA SSDK + closed blobs | **NONE (Pure CPU software flowtable)** | **NONE (Pure CPU software flowtable)** | Full hardware NSS ECM offload |
| **Code Provenance** | Qualcomm / Motorcomm closed BSP | **100% Upstream-derived (backport from 6.19)** | **100% Mainline Upstream** | Community fork (`zcop`) |

---

## 3. Backport Patch Architecture for OpenWrt Linux 6.18

To build the Phase 1 Clean DSA baseline on Linux 6.18, the following patch artifacts must be maintained in the build repository:

```
target/linux/qualcommax/patches-6.18/
├── 700-net-dsa-yt921x-driver.patch               # Adds drivers/net/dsa/yt921x.c and Kconfig/Makefile hooks
├── 701-net-dsa-tag-yt921x.patch                  # Adds net/dsa/tag_yt921x.c and tag protocol enum
├── 702-net-dsa-phylink-motorcomm.patch            # Adds Motorcomm PHY link-state hooks if required
└── 703-net-dsa-yt921x-Abuse-SGMII-for-REVSGMII.patch # Forces YT921X_SERDES_MODE_REVSGMII on Port 8 (yangfl patch 940)
```

### 3.1 Analysis of REVSGMII SerDes Mode Requirement (yangfl Patch 940)
- **Problem:** The IPQ5018 Uniphy SerDes interface connecting to switch Port 8 acts as a MAC. The Motorcomm switch SerDes must operate in **PHY role** (`REVSGMII`).
- However, Linux kernel phylink lacks a distinct `PHY_INTERFACE_MODE_REVSGMII` enum. Unpatched mainline `yt921x.c` configures `YT921X_SERDES_MODE_SGMII` (MAC role), creating two conflicting MACs and preventing link synchronization.
- **Solution:** As authored by David Yang in patch `940-net-dsa-yt921x-Abuse-SGMII-for-REVSGMII.patch`:
  ```c
  switch (interface) {
  case PHY_INTERFACE_MODE_SGMII:
      /* abuse SGMII for REVSGMII */
      ctrl = YT921X_SERDES_MODE_REVSGMII;
      break;
  ```
- **Conclusion:** Patch 703 is strictly mandatory for establishing an SGMII link between IPQ5018 GMAC1 and YT9215 Port 8.

### 3.1 Kernel Configuration Symbols (`kconfig`)
```ini
# Core Distributed Switch Architecture (DSA)
CONFIG_NET_DSA=y
CONFIG_NET_DSA_TAG_YT921X=y

# Motorcomm Ethernet Switch Driver
CONFIG_NET_DSA_YT921X=y

# Synopsys DesignWare MAC (Host SoC)
CONFIG_STMMAC_ETH=y
CONFIG_STMMAC_PLATFORM=y
CONFIG_DWMAC_IPQ5018=y

# Physical Layer Framework
CONFIG_PHYLINK=y
CONFIG_MOTORCOMM_PHY=y
```

### 3.2 Device Tree Bindings (`dts`)
In Linux 6.18 with the backported driver, the DTS binding strictly adheres to the upstream documentation schema (`Documentation/devicetree/bindings/net/dsa/motorcomm,yt921x.yaml`):

```dts
&mdio1 {
    status = "okay";
    pinctrl-0 = <&mdio1_pins>;
    pinctrl-names = "default";

    switch: switch@1d {
        compatible = "motorcomm,yt9215", "motorcomm,yt921x";
        reg = <0x1d>;
        reset-gpios = <&tlmm 39 GPIO_ACTIVE_LOW>;
        reset-assert-us = <50000>;
        reset-deassert-us = <250000>;

        dsa,member = <0 0>;

        ports {
            #address-cells = <1>;
            #size-cells = <0>;

            port@0 {
                reg = <0>;
                label = "lan1";
                phy-mode = "internal";
                phy-handle = <&sw_phy0>;
            };

            port@1 {
                reg = <1>;
                label = "lan2";
                phy-mode = "internal";
                phy-handle = <&sw_phy1>;
            };

            port@2 {
                reg = <2>;
                label = "lan3";
                phy-mode = "internal";
                phy-handle = <&sw_phy2>;
            };

            port@3 {
                reg = <3>;
                label = "wan";
                phy-mode = "internal";
                phy-handle = <&sw_phy3>;
            };

            /* Port 4 is disabled in Phase 1 Clean DSA */

            port@8 {
                reg = <8>;
                label = "cpu";
                ethernet = <&gmac1>;  /* Logical GMAC1 (CPU Conduit) */
                phy-mode = "sgmii";

                fixed-link {
                    speed = <1000>;
                    full-duplex;
                };
            };
        };

        mdio {
            #address-cells = <1>;
            #size-cells = <0>;

            sw_phy0: phy@0 { reg = <0>; };
            sw_phy1: phy@1 { reg = <1>; };
            sw_phy2: phy@2 { reg = <2>; };
            sw_phy3: phy@3 { reg = <3>; };
        };
    };
};
```

---

## 4. Upstream Evolution Path (Kernel 6.18 -> 6.19+)

When OpenWrt upstream transitions target `qualcommax` from Linux 6.18 to Linux 6.19 or Linux 6.20:
1. The backport patches (`700-*`, `701-*`) become obsolete and are dropped.
2. The board DTS remains 100% compatible without modifications because the upstream binding schema is preserved.
3. Zero migration debt is incurred because we adhere strictly to the upstream driver model rather than introducing proprietary tag formats into Phase 1.
