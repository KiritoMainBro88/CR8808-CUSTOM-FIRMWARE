#!/usr/bin/env python3
import sys

dts_file = "/root/sources/openwrt-25.12.6/target/linux/qualcommax/files/arch/arm64/boot/dts/qcom/ipq5018-cr8818.dts"
with open(dts_file, "r", encoding="utf-8") as f:
    text = f.read()

# Add #address-cells = <1>; #size-cells = <0>; to ethernet-ports if not present
if "ethernet-ports {" in text and "#address-cells = <1>;" not in text:
    text = text.replace("ethernet-ports {", "ethernet-ports {\n\t\t\t#address-cells = <1>;\n\t\t\t#size-cells = <0>;")

with open(dts_file, "w", encoding="utf-8") as f:
    f.write(text)

print("Updated ethernet-ports address-cells and size-cells.")
