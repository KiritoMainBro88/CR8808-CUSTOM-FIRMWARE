#!/usr/bin/env python3
import os
import shutil

SRC = "/root/sources/openwrt-25.12.6"
YANG = "/root/sources/yangfl_openwrt"

# 1. DTS files
dts_dir = os.path.join(SRC, "target/linux/qualcommax/files/arch/arm64/boot/dts/qcom")
os.makedirs(dts_dir, exist_ok=True)
shutil.copy(os.path.join(YANG, "target/linux/qualcommax/dts/ipq5018-xiaomi-base.dtsi"), dts_dir)
shutil.copy(os.path.join(YANG, "target/linux/qualcommax/dts/ipq5018-cr8818.dts"), dts_dir)

cr_symlink = os.path.join(dts_dir, "ipq5018-xiaomi-cr8818.dts")
if not os.path.exists(cr_symlink):
    os.symlink("ipq5018-cr8818.dts", cr_symlink)
print("1. DTS files copied and symlinked successfully.")

# 2. ipq50xx.mk
mk_path = os.path.join(SRC, "target/linux/qualcommax/image/ipq50xx.mk")
with open(mk_path, "r", encoding="utf-8") as f:
    content = f.read()

if "Device/xiaomi_cr8818" not in content:
    device_def = """
define Device/xiaomi_cr8818
	$(call Device/FitImage)
	$(call Device/UbiFit)
	DEVICE_VENDOR := Xiaomi
	DEVICE_MODEL := CR8818
	BLOCKSIZE := 128k
	PAGESIZE := 2048
	DEVICE_DTS_CONFIG := config@mp03.3
	DEVICE_DTS := ipq5018-cr8818
	SOC := ipq5018
	KERNEL_SIZE := 36864k
	NAND_SIZE := 128m
	DEVICE_PACKAGES := ath11k-firmware-ipq5018-qcn6122 \\
		ipq-wifi-xiaomi_cr8818
ifneq ($(CONFIG_TARGET_ROOTFS_INITRAMFS),)
	ARTIFACTS := initramfs-factory.ubi
	ARTIFACT/initramfs-factory.ubi := append-image-stage initramfs-uImage.itb | ubinize-kernel
endif
endef
TARGET_DEVICES += xiaomi_cr8818
"""
    with open(mk_path, "a", encoding="utf-8") as f:
        f.write(device_def)
    print("2. Device/xiaomi_cr8818 appended to ipq50xx.mk.")
else:
    print("2. Device/xiaomi_cr8818 already exists in ipq50xx.mk.")

# 3. 02_network
net_path = os.path.join(SRC, "target/linux/qualcommax/ipq50xx/base-files/etc/board.d/02_network")
with open(net_path, "r", encoding="utf-8") as f:
    net_content = f.read()

if "xiaomi,cr8818" not in net_content:
    net_entry = """\txiaomi,cr8818)
\t\tucidef_set_interface "wan_sw" device "sw-cpu sw-wan" protocol none ipv6 0
\t\tucidef_set_interfaces_lan_wan "lan1 lan2 lan3" "wan"
\t\t;;
"""
    if "xiaomi,ax6000)" in net_content:
        net_content = net_content.replace("xiaomi,ax6000)\n", "xiaomi,ax6000)\n" + net_entry)
    else:
        # insert before default / esac
        net_content = net_content.replace("esac", net_entry + "esac")
    with open(net_path, "w", encoding="utf-8") as f:
        f.write(net_content)
    print("3. 02_network patched.")
else:
    print("3. 02_network already has xiaomi,cr8818.")

# 4. 11-ath11k-caldata
cal_path = os.path.join(SRC, "target/linux/qualcommax/ipq50xx/base-files/etc/hotplug.d/firmware/11-ath11k-caldata")
with open(cal_path, "r", encoding="utf-8") as f:
    cal_content = f.read()

if "xiaomi,cr8818" not in cal_content:
    cal_content = cal_content.replace("xiaomi,ax6000|\\", "xiaomi,ax6000|\\\n\txiaomi,cr8818|\\")
    with open(cal_path, "w", encoding="utf-8") as f:
        f.write(cal_content)
    print("4. 11-ath11k-caldata patched.")
else:
    print("4. 11-ath11k-caldata already has xiaomi,cr8818.")

# 5. platform.sh
plat_path = os.path.join(SRC, "target/linux/qualcommax/ipq50xx/base-files/lib/upgrade/platform.sh")
with open(plat_path, "r", encoding="utf-8") as f:
    plat_content = f.read()

if "xiaomi,cr8818" not in plat_content:
    plat_content = plat_content.replace("xiaomi,ax6000)", "xiaomi,ax6000|\\\n\txiaomi,cr8818)")
    plat_content = plat_content.replace("xiaomi,ax6000|\\", "xiaomi,ax6000|\\\n\txiaomi,cr8818|\\")
    with open(plat_path, "w", encoding="utf-8") as f:
        f.write(plat_content)
    print("5. platform.sh patched.")
else:
    print("5. platform.sh already has xiaomi,cr8818.")

print("All board support files ported successfully.")
