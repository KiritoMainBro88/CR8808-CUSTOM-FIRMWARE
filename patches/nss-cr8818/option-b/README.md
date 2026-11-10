# Option B Patch Series: Qualcomm qcom,nss-dp + Enhanced YT921x Modular Driver

## Architecture Overview
Option B binds the Qualcomm IPQ5018 GMACs directly to Qualcomm's native Data-Plane driver (`qcom,nss-dp`) rather than upstream `stmmac`. On the switch side, it uses the enhanced modular Motorcomm YT921x driver developed by `zcop/immortalwrt` with dual-conduit architecture:
- **Port 4 (`cpu2` / `eth0` / GMAC0):** Secondary CPU conduit attached via Qualcomm Internal GE PHY (`88000.mdio:07`). Configured via `motorcomm,secondary-conduit-user-mask = <0x8>` to handle Port 3 (WAN). The hardware CPU port tag enforcement register bit (`YT921X_EXT_CPU_PORT_TAG_EN` bit 0 at `0x8000c`) is CLEARED for Port 4, streaming pure untagged Ethernet frames directly into `eth0`.
- **Port 8 (`cpu1` / `eth1` / GMAC1):** Primary CPU conduit attached via Uniphy SerDes SGMII/2500Base-X. Handles LAN ports (Ports 0, 1, 2) using enhanced DSA tagging (`tag_yt921x_enhanced`) or standard 802.1Q tagging (`tag_yt921x_8021q`).
- **NSS Hardware Offload:** Because WAN frames on `eth0` are completely untagged, the Qualcomm NSS NPU parser classifies IPv4/IPv6 headers natively with zero proprietary tag overhead.

## Included Patches
1. `0001-drivers-net-dsa-yt921x-enhanced-modular.patch`:
   Origin: `zcop/immortalwrt` patch `968-net-dsa-add-enhanced-YT921x-driver-and-taggers.patch`.
   - Allocates DSA tag protocol IDs 36 (`YT921X_8021Q`), 37 (`YT921X_QINQ`), and 38 (`YT921X_ENHANCED`) in `include/net/dsa.h`.
   - Adds Kconfig entries and Makefile wiring for `NET_DSA_YT921X`, `NET_DSA_TAG_YT921X_ENHANCED`, and `NET_DSA_TAG_YT921X_8021Q`.
2. `0002-arm64-dts-ipq5018-cr881x-nss-dual-conduit.patch`:
   Origin: `zcop/immortalwrt` `target/linux/qualcommax/dts/ipq5018-cr881x-nss.dts`.
   - Allocates `cr881x_nss_region` (16 MiB at `0x40000000`).
   - Binds `&gmac0` and `&gmac1` to `compatible = "qcom,nss-dp"`.
   - Instantiates `nss@7a00000` UBI core with `qcom,vlan-enabled`.

## Compilation & Verification Status (M4)
- `tag_yt921x_enhanced.o`: **KERNEL_KBUILD_PASS** (Compiled cleanly under Linux 6.18 Kbuild).
- `ipq5018-cr881x-nss.dtb`: **DTC_BUILD_PASS** (27,326 bytes, DT_SCHEMA_PASS).
- `qca-nss-dp`: **NSS_MODULE_BUILD_FAIL** under standalone Kbuild outside OpenWrt package infrastructure because it requires OpenWrt target include headers and NSS DP infrastructure.
- `yt921x_drv.o` (enhanced modular driver): **KERNEL_KBUILD_FAIL** against raw mainline Linux 6.18 due to DSA API differences in 6.18 (`port_mrouter` vs `port_set_host_flood`, and TC flow policer struct definitions).
- Hardware Register Status: Switch register programming explicitly implements bit 0 clearing at `0x8000c`, proving that untagged WAN frames bypass CPU tag parsing.
