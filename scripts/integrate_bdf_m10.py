import os
import shutil
import sys

def main():
    base_dir = "/root/sources/openwrt-25.12.6"
    pkg_dir = os.path.join(base_dir, "package/firmware/ipq-wifi")
    src_dir = os.path.join(pkg_dir, "src")
    zcop_src_dir = "/root/sources/zcop_immortalwrt/package/firmware/ipq-wifi/src"

    os.makedirs(src_dir, exist_ok=True)

    # 1. Copy BDF files
    f1_src = os.path.join(zcop_src_dir, "board-xiaomi_cr881x.ipq5018")
    f1_dst = os.path.join(src_dir, "board-xiaomi_cr8818.ipq5018")
    f2_src = os.path.join(zcop_src_dir, "board-xiaomi_cr881x.qcn6122")
    f2_dst = os.path.join(src_dir, "board-xiaomi_cr8818.qcn6122")

    shutil.copyfile(f1_src, f1_dst)
    shutil.copyfile(f2_src, f2_dst)
    print(f"Copied {f1_dst} ({os.path.getsize(f1_dst)} bytes)")
    print(f"Copied {f2_dst} ({os.path.getsize(f2_dst)} bytes)")

    # 2. Patch Makefile
    makefile_path = os.path.join(pkg_dir, "Makefile")
    with open(makefile_path, "r") as f:
        content = f.read()

    # Add Build/Prepare if not present
    if "Inject local board-2.bin overrides" not in content:
        prep_block = """define Build/Prepare
\t$(call Build/Prepare/Default)
\t# Inject local board-2.bin overrides when present
\t[ -d $(CURDIR)/src ] && cp -f $(CURDIR)/src/board-* $(PKG_BUILD_DIR)/ || true
endef

define Build/Compile"""
        content = content.replace("define Build/Compile", prep_block)

    # Add to ALLWIFIBOARDS
    if "\txiaomi_cr8818 \\\n" not in content:
        content = content.replace("\txiaomi_ax6000 \\\n", "\txiaomi_ax6000 \\\n\txiaomi_cr8818 \\\n")

    # Add generate-ipq-wifi-package
    target_eval = "$(eval $(call generate-ipq-wifi-package,xiaomi_cr8818,Xiaomi CR8818))\n"
    if target_eval not in content:
        content = content.replace(
            "$(eval $(call generate-ipq-wifi-package,xiaomi_ax6000,Xiaomi AX6000))\n",
            "$(eval $(call generate-ipq-wifi-package,xiaomi_ax6000,Xiaomi AX6000))\n" + target_eval
        )

    with open(makefile_path, "w") as f:
        f.write(content)
    print(f"Patched {makefile_path}")

    # 3. Check / update .config
    config_path = os.path.join(base_dir, ".config")
    with open(config_path, "r") as f:
        cfg = f.read()

    if "CONFIG_PACKAGE_ipq-wifi-xiaomi_cr8818=y" not in cfg:
        cfg += "\nCONFIG_PACKAGE_ipq-wifi-xiaomi_cr8818=y\n"
        with open(config_path, "w") as f:
            f.write(cfg)
        print("Added CONFIG_PACKAGE_ipq-wifi-xiaomi_cr8818=y to .config")
    else:
        print("CONFIG_PACKAGE_ipq-wifi-xiaomi_cr8818=y already in .config")

    return 0

if __name__ == "__main__":
    sys.exit(main())
