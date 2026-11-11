#!/usr/bin/env python3
import sys

dts_file = "/root/sources/openwrt-25.12.6/target/linux/qualcommax/files/arch/arm64/boot/dts/qcom/ipq5018-cr8818.dts"
with open(dts_file, "r", encoding="utf-8") as f:
    text = f.read()

# Replace gmac with dp for upstream OpenWrt ESS architecture
text = text.replace("&gmac0", "&dp1")
text = text.replace("&gmac1", "&dp2")
text = text.replace("label-mac-device = &gmac0;", "label-mac-device = &dp1;")
text = text.replace("mac_addr_gmac0", "mac_addr_dp1")
text = text.replace("mac_addr_gmac1", "mac_addr_dp2")
text = text.replace("<&gmac1>", "<&dp2>")
text = text.replace("<&gmac0>", "<&dp1>")

# In OpenWrt qualcommax, uniphy is configured in ipq5018-ess.dtsi under ess_uniphy / ess-switch
# Remove the standalone &uniphy0 block from yangfl
if "&uniphy0" in text:
    lines = text.splitlines(keepends=True)
    new_lines = []
    skip = False
    for line in lines:
        if line.strip().startswith("&uniphy0"):
            skip = True
            continue
        if skip:
            if line.strip() == "};":
                skip = False
            continue
        new_lines.append(line)
    text = "".join(new_lines)

# Add switch block if not present
if "&switch" not in text:
    switch_block = """
&switch {
	status = "okay";

	switch_mac_mode = <MAC_MODE_SGMII_PLUS>;

	qcom,port_phyinfo {
		// MAC0 -> GE Phy --- MDI --- YT9215 Phy4
		port@0 {
			port_id = <1>;
			mdiobus = <&mdio0>;
			phy_address = <7>;
			phy_dac = <0x10 0x10>;
		};

		// MAC1 -> Uniphy --- SGMII+ (2.5G) --- YT9215 Phy8
		port@1 {
			port_id = <2>;
			mdiobus = <&mdio1>;
			phy_address = <8>;
			port_mac_sel = "QGMAC_PORT";
		};
	};
};
"""
    # Insert before &dp1
    text = text.replace("&dp1 {", switch_block + "\n&dp1 {")

with open(dts_file, "w", encoding="utf-8") as f:
    f.write(text)

print("ipq5018-cr8818.dts aligned with upstream OpenWrt 25.12.6 ESS architecture.")
