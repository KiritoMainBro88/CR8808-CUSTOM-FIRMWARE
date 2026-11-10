# Option A Patch Series: Upstream stmmac + qca-dwmac-nss + YT921x

## Architecture Overview
Option A attempts to bind the Qualcomm IPQ5018 Synopsys DesignWare MAC (`dwmac-ipq5018` / `stmmac`) directly to the Qualcomm NSS firmware via the `qca-dwmac-nss` data-plane glue driver (originated by kuncy7). On the switch side, it attempts to use DSA `tag_8021q` adapter tagging to bypass the Motorcomm proprietary 8-byte CPU tag (0x9988) collision with the NSS firmware.

## Included Patches
1. `0001-net-dsa-tag_yt921x_8021q.patch`:
   Implements DSA `tag_yt921x_8021q` protocol (TPID 0x8100, VID 100+port) using standard Linux 6.x DSA APIs (`dsa_user_to_port`, `dsa_tag_8021q_find_user`, `dsa_8021q_xmit`, `dsa_8021q_rcv`).
2. `0002-arm64-dts-ipq5018-cr8818-stmmac-nss.patch`:
   Device Tree patch for `ipq5018-cr8818.dts` configuring single-conduit GMAC with `cr8818_nss_region` (16 MiB at 0x40000000) and `coherent_pool=2M`.
3. `0003-net-stmmac-qca-dwmac-claim-api.patch`:
   Exposes the custom stmmac DMA claim APIs (`qca_dwmac_dp_dma_stop`, `qca_dwmac_dp_rings_set`, `qca_dwmac_dp_dma_start`) required for `qca-dwmac-nss.ko` to park host DMA and hand GMAC to NSS firmware.

## Compilation & Verification Status (M4)
- `qca-dwmac-nss.ko`: **NSS_MODULE_BUILD_PASS** (Compiled to real AArch64 ELF kernel module with Kbuild).
- `tag_yt921x_8021q.o`: **KERNEL_KBUILD_PASS** (Compiled cleanly with Kbuild once ID 36 was allocated in `dsa.h`).
- Upstream `yt921x.c`: **KERNEL_KBUILD_FAIL** against clean Linux 6.18 due to forward-ported APIs from Linux 6.19/7.x (`flow_action_police`, `kvzalloc_obj`, `dsa_bridge_ports`).
- Switch Register Status: Upstream `yt921x.c` **lacks register reprogramming** to disable CPU port tag enforcement (`YT921X_EXT_CPU_PORT_TAG_EN` bit 0 at 0x8000c). Thus, switch hardware drops untagged/802.1Q frames.
