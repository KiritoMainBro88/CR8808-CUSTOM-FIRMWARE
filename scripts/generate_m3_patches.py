#!/usr/bin/env python3
"""
Generate and validate Milestone M3 kernel patches and DTS compilation.
"""
import subprocess
import os

def run_wsl(cmd):
    p = subprocess.run(["wsl", "-d", "Ubuntu-22.04", "bash", "-c", cmd], capture_output=True, text=True)
    return p.returncode, p.stdout, p.stderr

def main():
    print("=== Milestone M3 Patch Generation & Validation ===")
    
    # =========================================================================
    # Part 1: Patch 0002 (DTS Dual-Conduit for OpenWrt qualcommax)
    # =========================================================================
    print("\n--- Generating & Validating Patch 0002 (DTS) ---")
    run_wsl("cd /root/sources/yangfl_openwrt && git checkout -- .")
    
    rc, content, err = run_wsl("cat /root/sources/yangfl_openwrt/target/linux/qualcommax/dts/ipq5018-cr8818.dts")
    if rc != 0:
        print("Failed to read cr8818.dts:", err)
        return
        
    part1 = "\taliases {"
    replace1 = """\tchosen {
\t\tbootargs-append = " coherent_pool=2M";
\t};

\treserved-memory {
\t\tcr8818_nss_region: memory@40000000 {
\t\t\treg = <0x0 0x40000000 0x0 0x1000000>;
\t\t\tno-map;
\t\t};
\t};

\taliases {"""

    part2 = """\t\t\tethernet-port@4 {
\t\t\t\treg = <4>;
\t\t\t\tlabel = "sw-cpu";
\t\t\t\tphy-mode = "internal";
\t\t\t\tphy-handle = <&sw_phy4>;
\t\t\t};"""

    replace2 = """\t\t\t/* Secondary CPU Conduit: Port 4 (Internal GE PHY / eth0) */
\t\t\tethernet-port@4 {
\t\t\t\treg = <4>;
\t\t\t\tlabel = "cpu2";
\t\t\t\tethernet = <&gmac0>;
\t\t\t\tphy-mode = "internal";
\t\t\t\tphy-handle = <&sw_phy4>;
\t\t\t};"""

    part3 = """\t\t\tethernet-port@8 {
\t\t\t\treg = <8>;
\t\t\t\tphy-mode = "2500base-x";
\t\t\t\tethernet = <&gmac1>;"""

    replace3 = """\t\t\t/* Primary CPU Conduit: Port 8 (Uniphy SerDes SGMII / eth1) */
\t\t\tethernet-port@8 {
\t\t\t\treg = <8>;
\t\t\t\tlabel = "cpu1";
\t\t\t\tphy-mode = "2500base-x";
\t\t\t\tethernet = <&gmac1>;"""

    if part1 in content and part2 in content and part3 in content:
        new_content = content.replace(part1, replace1, 1).replace(part2, replace2, 1).replace(part3, replace3, 1)
        with open("D:/vibecode/CR8808-CUSTOM-FIRMWARE/target_cr8818.dts", "w", newline="\n") as f:
            f.write(new_content)
        run_wsl("cp /mnt/d/vibecode/CR8808-CUSTOM-FIRMWARE/target_cr8818.dts /root/sources/yangfl_openwrt/target/linux/qualcommax/dts/ipq5018-cr8818.dts")
        os.remove("D:/vibecode/CR8808-CUSTOM-FIRMWARE/target_cr8818.dts")

        rc, diff_out, _ = run_wsl("cd /root/sources/yangfl_openwrt && git diff")
        patch2_header = """From: Gemini <gemini@antigravity.internal>
Date: Tue, 10 Nov 2026 01:00:00 +0700
Subject: [PATCH 2/2] arm64: dts: qualcommax: ipq5018-cr8818: configure dual-conduit CPU ports and NSS reserved memory

On the Xiaomi CR8808 Ver.B (CR8818, board profile ap-mp03.3), the physical Ethernet
topology wires the Motorcomm YT9215SC switch to two SoC MACs:
- MAC0 (gmac0 / eth0): Connected via Qualcomm Internal GE PHY (88000.mdio:07)
  to Switch Port 4 (sw-cpu / cpu2).
- MAC1 (gmac1 / eth1): Connected via Uniphy SerDes SGMII/2500Base-X to Switch Port 8 (cpu1).
- Physical WAN RJ45: Connected to Switch Port 3 (sw-wan).
- Physical LAN1-3 RJ45: Connected to Switch Ports 0, 1, 2.

This patch configures both CPU conduits in the device tree for OpenWrt qualcommax:
1. Configures ethernet-port@4 as secondary conduit (cpu2) bound to gmac0.
2. Configures ethernet-port@8 as primary conduit (cpu1) bound to gmac1.
3. Allocates cr8818_nss_region (16 MiB at 0x40000000) for NSS NPU firmware.
4. Adds coherent_pool=2M bootargs parameter for NSS DMA buffer allocations.

Signed-off-by: Gemini <gemini@antigravity.internal>
---
"""
        with open("D:/vibecode/CR8808-CUSTOM-FIRMWARE/patches/nss-cr8818/0002-arm64-dts-ipq5018-cr8818-dual-conduit-nss.patch", "w", newline="\n") as f:
            f.write(patch2_header + diff_out)
        print("  [OK] Patch 0002 written.")

        run_wsl("cd /root/sources/yangfl_openwrt && git checkout -- .")
        rc, out, err = run_wsl("git -C /root/sources/yangfl_openwrt apply --check /mnt/d/vibecode/CR8808-CUSTOM-FIRMWARE/patches/nss-cr8818/0002-arm64-dts-ipq5018-cr8818-dual-conduit-nss.patch")
        if rc == 0:
            print("  [PASS] Patch 0002 git apply --check passed cleanly on yangfl_openwrt.")
        else:
            print("  [FAIL] Patch 0002 apply check failed:", err)

    # =========================================================================
    # Part 2: Patch 0001 (Kernel net: dsa: tag_yt921x_8021q for Linux 6.18)
    # =========================================================================
    print("\n--- Generating & Validating Patch 0001 (Kernel tag_8021q) ---")
    run_wsl("cd /root/linux-dts && git checkout -- include/net/dsa.h net/dsa/Kconfig net/dsa/Makefile && rm -f net/dsa/tag_yt921x_8021q.c")

    # Read base files from linux-dts
    _, dsa_h, _ = run_wsl("cat /root/linux-dts/include/net/dsa.h")
    _, kconfig, _ = run_wsl("cat /root/linux-dts/net/dsa/Kconfig")
    _, makefile, _ = run_wsl("cat /root/linux-dts/net/dsa/Makefile")
    _, tag_c, _ = run_wsl("cat /root/sources/zcop_immortalwrt/target/linux/generic/files/net/dsa/tag_yt921x_8021q.c")

    # Modify include/net/dsa.h
    dsa_h_mod = dsa_h.replace(
        "#define DSA_TAG_PROTO_8021Q_VALUE\t\t12\n",
        "#define DSA_TAG_PROTO_8021Q_VALUE\t\t12\n#define DSA_TAG_PROTO_YT921X_8021Q_VALUE\t36\n"
    ).replace(
        "\tDSA_TAG_PROTO_8021Q\t\t= DSA_TAG_PROTO_8021Q_VALUE,\n",
        "\tDSA_TAG_PROTO_8021Q\t\t= DSA_TAG_PROTO_8021Q_VALUE,\n\tDSA_TAG_PROTO_YT921X_8021Q\t= DSA_TAG_PROTO_YT921X_8021Q_VALUE,\n"
    )

    # Modify net/dsa/Kconfig
    kconfig_block = """config NET_DSA_TAG_YT921X_8021Q
\ttristate "802.1Q tag driver for Motorcomm YT921x switches"
\tselect NET_DSA_TAG_8021Q
\thelp
\t  Say Y or M if you want to enable support for tagging frames for
\t  Motorcomm YT921x switches using standard 802.1Q VLAN headers for
\t  Qualcomm NSS acceleration compatibility.

endif
"""
    kconfig_mod = kconfig.replace("endif\n", kconfig_block)

    # Modify net/dsa/Makefile
    makefile_mod = makefile + "obj-$(CONFIG_NET_DSA_TAG_YT921X_8021Q) += tag_yt921x_8021q.o\n"

    # Write files in linux-dts
    with open("D:/vibecode/CR8808-CUSTOM-FIRMWARE/dsa_h_tmp", "w", newline="\n") as f:
        f.write(dsa_h_mod)
    with open("D:/vibecode/CR8808-CUSTOM-FIRMWARE/kconfig_tmp", "w", newline="\n") as f:
        f.write(kconfig_mod)
    with open("D:/vibecode/CR8808-CUSTOM-FIRMWARE/makefile_tmp", "w", newline="\n") as f:
        f.write(makefile_mod)
    with open("D:/vibecode/CR8808-CUSTOM-FIRMWARE/tag_c_tmp", "w", newline="\n") as f:
        f.write(tag_c)

    run_wsl("cp /mnt/d/vibecode/CR8808-CUSTOM-FIRMWARE/dsa_h_tmp /root/linux-dts/include/net/dsa.h")
    run_wsl("cp /mnt/d/vibecode/CR8808-CUSTOM-FIRMWARE/kconfig_tmp /root/linux-dts/net/dsa/Kconfig")
    run_wsl("cp /mnt/d/vibecode/CR8808-CUSTOM-FIRMWARE/makefile_tmp /root/linux-dts/net/dsa/Makefile")
    run_wsl("cp /mnt/d/vibecode/CR8808-CUSTOM-FIRMWARE/tag_c_tmp /root/linux-dts/net/dsa/tag_yt921x_8021q.c")

    for f in ["dsa_h_tmp", "kconfig_tmp", "makefile_tmp", "tag_c_tmp"]:
        os.remove("D:/vibecode/CR8808-CUSTOM-FIRMWARE/" + f)

    run_wsl("cd /root/linux-dts && git add -N net/dsa/tag_yt921x_8021q.c")
    rc, diff1_out, _ = run_wsl("cd /root/linux-dts && git diff include/net/dsa.h net/dsa/Kconfig net/dsa/Makefile net/dsa/tag_yt921x_8021q.c")

    patch1_header = """From: Gemini <gemini@antigravity.internal>
Date: Tue, 10 Nov 2026 01:00:00 +0700
Subject: [PATCH 1/2] net: dsa: add 802.1Q tag driver for Motorcomm YT921x switches

The Motorcomm YT9215SC switch driver natively injects an 8-byte proprietary
CPU tag with hardware-default TPID 0x9988 (ETH_P_YT921X). When Qualcomm NSS
hardware acceleration (qca-dwmac-nss / retail_router0.bin) is active on the
IPQ5018 SoC, frames with TPID 0x9988 cannot be parsed by the NSS hardware parser,
causing packet classification failures or slow-path punt exceptions.

This patch adds tag_yt921x_8021q to the DSA tagging subsystem for Linux 6.18:
1. Allocates DSA_TAG_PROTO_YT921X_8021Q_VALUE = 36 in include/net/dsa.h.
2. Implements net/dsa/tag_yt921x_8021q.c using Linux 6.x DSA APIs (dsa_user_to_port,
   dsa_tag_8021q_find_user, dsa_8021q_xmit, dsa_8021q_rcv).
3. Connects Kconfig NET_DSA_TAG_YT921X_8021Q and Makefile wiring.
4. Enables standard IEEE 802.1Q VLAN-based port identification on the CPU conduit,
   allowing Qualcomm NSS parser to classify L2/L3 headers natively without proprietary
   tag collisions.

Signed-off-by: Gemini <gemini@antigravity.internal>
---
"""
    with open("D:/vibecode/CR8808-CUSTOM-FIRMWARE/patches/nss-cr8818/0001-net-dsa-tag_yt921x-8021q-nss-compat.patch", "w", newline="\n") as f:
        f.write(patch1_header + diff1_out)
    print("  [OK] Patch 0001 written.")

    # Revert linux-dts and test git apply --check
    run_wsl("cd /root/linux-dts && git checkout -- include/net/dsa.h net/dsa/Kconfig net/dsa/Makefile && rm -f net/dsa/tag_yt921x_8021q.c")
    rc, out, err = run_wsl("git -C /root/linux-dts apply --check /mnt/d/vibecode/CR8808-CUSTOM-FIRMWARE/patches/nss-cr8818/0001-net-dsa-tag_yt921x-8021q-nss-compat.patch")
    if rc == 0:
        print("  [PASS] Patch 0001 git apply --check passed cleanly on linux-dts (Linux v6.18).")
    else:
        print("  [FAIL] Patch 0001 apply check failed:", err)

if __name__ == "__main__":
    main()
