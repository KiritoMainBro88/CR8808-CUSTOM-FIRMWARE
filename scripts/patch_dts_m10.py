import os

def main():
    dts_path = "/root/sources/openwrt-25.12.6/target/linux/qualcommax/files/arch/arm64/boot/dts/qcom/ipq5018-cr8818.dts"
    if not os.path.exists(dts_path):
        print(f"Error: {dts_path} not found")
        return 1

    with open(dts_path, "r") as f:
        content = f.read()

    # 1. Update mdio1 with switch_reset_pins and timings
    old_mdio = """&mdio1 {
\tstatus = "okay";

\tpinctrl-0 = <&mdio1_pins>;
\tpinctrl-names = "default";
\treset-gpios = <&tlmm 39 GPIO_ACTIVE_LOW>;"""

    new_mdio = """&mdio1 {
\tstatus = "okay";

\tpinctrl-0 = <&mdio1_pins>, <&switch_reset_pins>;
\tpinctrl-names = "default";
\treset-gpios = <&tlmm 39 GPIO_ACTIVE_LOW>;
\treset-assert-us = <10000>;
\treset-deassert-us = <50000>;"""

    if old_mdio not in content:
        print("Error: old_mdio not found in content")
        return 1
    content = content.replace(old_mdio, new_mdio)

    # 2. Add switch_reset_pins to tlmm
    old_tlmm = """&tlmm {
\tbutton_pins: button-state {
\t\tpins = "gpio38", "gpio28";
\t\tfunction = "gpio";
\t\tdrive-strength = <8>;
\t\tbias-pull-up;
\t};

\tleds_pins: leds-state {"""

    new_tlmm = """&tlmm {
\tbutton_pins: button-state {
\t\tpins = "gpio38", "gpio28";
\t\tfunction = "gpio";
\t\tdrive-strength = <8>;
\t\tbias-pull-up;
\t};

\tswitch_reset_pins: switch-reset-state {
\t\tpins = "gpio39";
\t\tfunction = "gpio";
\t\tdrive-strength = <8>;
\t\tbias-pull-down;
\t};

\tleds_pins: leds-state {"""

    if old_tlmm not in content:
        print("Error: old_tlmm not found in content")
        return 1
    content = content.replace(old_tlmm, new_tlmm)

    # 3. Update wifi, wifi1 and add q6v5_wcss
    old_wifi = """/*
 * ath11k Wi-Fi consumes too large memory spaces and too few spaces are
 * available for users. To prevent OOM when using LuCI or other softwares,
 * disable Wi-Fi related peripherals at the moment.
 */
&wifi {
\tstatus = "disabled";

\tqcom,rproc = <&q6_wcss_pd1>;
\tqcom,ath11k-calibration-variant = "Xiaomi-CR8818";
\tqcom,ath11k-fw-memory-mode = <1>;
\tqcom,bdf-addr = <0x4c400000>;
};

&wifi1 {
\tstatus = "disabled";

\tqcom,rproc = <&q6_wcss_pd2>;
\tqcom,userpd-subsys-name = "q6v5_wcss_userpd2";
\tqcom,ath11k-calibration-variant = "Xiaomi-CR8818";
\tqcom,ath11k-fw-memory-mode = <1>;
\tqcom,bdf-addr = <0x4d100000>;
\tqcom,m3-dump-addr = <0x4df00000>;
};"""

    new_wifi = """&q6v5_wcss {
\tstatus = "okay";

\tqcom,bootargs_smem = <507>;
\tboot-args = <0x2 4 2 18 0 0>;
};

&wifi {
\tstatus = "okay";

\tqcom,rproc = <&q6_wcss_pd1>;
\tqcom,board_id = <0x23>;
\tqcom,ath11k-fw-memory-mode = <1>;
\tqcom,bdf-addr = <0x4c400000>;
};

&wifi1 {
\tstatus = "okay";

\tqcom,rproc = <&q6_wcss_pd2>;
\tqcom,userpd-subsys-name = "q6v5_wcss_userpd2";
\tqcom,board_id = <0x60>;
\tqcom,ath11k-fw-memory-mode = <1>;
\tqcom,bdf-addr = <0x4d100000>;
\tqcom,m3-dump-addr = <0x4df00000>;
};"""

    if old_wifi not in content:
        print("Error: old_wifi not found in content")
        return 1
    content = content.replace(old_wifi, new_wifi)

    with open(dts_path, "w") as f:
        f.write(content)

    print("SUCCESS: ipq5018-cr8818.dts successfully patched!")
    return 0

if __name__ == "__main__":
    import sys
    sys.exit(main())
