import os

def main():
    cal_path = "/root/sources/openwrt-25.12.6/target/linux/qualcommax/ipq50xx/base-files/etc/hotplug.d/firmware/11-ath11k-caldata"
    if not os.path.exists(cal_path):
        print(f"Error: {cal_path} not found")
        return 1

    with open(cal_path, "r") as f:
        content = f.read()

    # 1. 2.4 GHz radio block
    old_24 = """\txiaomi,ax6000)
\t\tcaldata_extract "0:art" 0x1000 0x20000
\t\t;;"""

    new_24 = """\txiaomi,ax6000|\\
\txiaomi,cr8818)
\t\tcaldata_extract "0:art" 0x1000 0x20000
\t\t;;"""

    if old_24 not in content:
        print("Error: old_24 not found")
        return 1
    content = content.replace(old_24, new_24)

    # 2. 5.0 GHz radio block
    old_50 = """\tyuncore,ax830)
\t\tcaldata_extract "0:ART" 0x4c000 0x20000
\t\tlabel_mac=$(mtd_get_mac_binary 0:ART 0)
\t\tath11k_patch_mac $(macaddr_add $label_mac 3) 0
\t\tath11k_remove_regdomain
\t\tath11k_set_macflag
\t\t;;"""

    new_50 = """\txiaomi,cr8818)
\t\tcaldata_extract "0:art" 0x26800 0x20000
\t\t;;
\tyuncore,ax830)
\t\tcaldata_extract "0:ART" 0x4c000 0x20000
\t\tlabel_mac=$(mtd_get_mac_binary 0:ART 0)
\t\tath11k_patch_mac $(macaddr_add $label_mac 3) 0
\t\tath11k_remove_regdomain
\t\tath11k_set_macflag
\t\t;;"""

    if old_50 not in content:
        print("Error: old_50 not found")
        return 1
    content = content.replace(old_50, new_50)

    with open(cal_path, "w") as f:
        f.write(content)

    print("SUCCESS: 11-ath11k-caldata successfully patched!")
    return 0

if __name__ == "__main__":
    import sys
    sys.exit(main())
