#!/bin/bash
set -e

echo "===================================================================="
echo "DTS Validation & Compilation Suite for CR8818"
echo "Target: Linux 6.18 / IPQ5018 / Motorcomm YT9215SC"
echo "===================================================================="

# Ensure qualcommax SoC DTSI patches are applied to linux-dts
echo "--- Ensuring OpenWrt qualcommax DTS patches are applied to /root/linux-dts ---"
for p in /root/sources/yangfl_openwrt/target/linux/qualcommax/patches-6.18/*.patch; do
    if git -C /root/linux-dts apply --check "$p" >/dev/null 2>&1; then
        git -C /root/linux-dts apply "$p"
        echo "  [APPLIED] $(basename "$p")"
    fi
done

INC_DIRS=(
    "-I/root/linux-dts/include"
    "-I/root/linux-dts/include/dt-bindings"
    "-I/root/linux-dts/include/dt-bindings/input"
    "-I/root/linux-dts/arch/arm64/boot/dts/qcom"
    "-I/root/linux-dts/arch/arm64/boot/dts"
    "-I/root/sources/zcop_immortalwrt/target/linux/qualcommax/dts"
    "-I/root/sources/zcop_immortalwrt/target/linux/qualcommax/files/arch/arm64/boot/dts/qcom"
    "-I/root/sources/zcop_immortalwrt/target/linux/qualcommax/files/include"
    "-I/root/sources/yangfl_openwrt/target/linux/qualcommax/dts"
    "-I/root/sources/yangfl_openwrt/target/linux/qualcommax/files/arch/arm64/boot/dts/qcom"
    "-I/root/sources/yangfl_openwrt/target/linux/qualcommax/files/include"
    "-include" "/root/sources/zcop_immortalwrt/target/linux/qualcommax/files/include/dt-bindings/net/qca-uniphy.h"
)

OUT_DIR="/root/dts_validation/out"
mkdir -p "$OUT_DIR"

echo "--- 1. Testing Option B: zcop ipq5018-cr881x.dts (Base dual-conduit) ---"
cpp -nostdinc "${INC_DIRS[@]}" -undef -D__DTS__ -x assembler-with-cpp \
    /root/sources/zcop_immortalwrt/target/linux/qualcommax/dts/ipq5018-cr881x.dts \
    "$OUT_DIR/ipq5018-cr881x.preprocessed.dts"

dtc -I dts -O dtb -o "$OUT_DIR/ipq5018-cr881x.dtb" "$OUT_DIR/ipq5018-cr881x.preprocessed.dts" 2>"$OUT_DIR/cr881x_dtc.log" || true
if [ -f "$OUT_DIR/ipq5018-cr881x.dtb" ]; then
    echo "  [PASS] Option B Base DTB built successfully ($(wc -c < "$OUT_DIR/ipq5018-cr881x.dtb") bytes)"
else
    echo "  [FAIL] Option B Base DTB compilation failed:"
    cat "$OUT_DIR/cr881x_dtc.log"
fi

echo "--- 2. Testing Option B: zcop ipq5018-cr881x-nss.dts (Dual-conduit + qcom,nss-dp) ---"
cpp -nostdinc "${INC_DIRS[@]}" -undef -D__DTS__ -x assembler-with-cpp \
    /root/sources/zcop_immortalwrt/target/linux/qualcommax/dts/ipq5018-cr881x-nss.dts \
    "$OUT_DIR/ipq5018-cr881x-nss.preprocessed.dts"

dtc -I dts -O dtb -o "$OUT_DIR/ipq5018-cr881x-nss.dtb" "$OUT_DIR/ipq5018-cr881x-nss.preprocessed.dts" 2>"$OUT_DIR/cr881x_nss_dtc.log" || true
if [ -f "$OUT_DIR/ipq5018-cr881x-nss.dtb" ]; then
    echo "  [PASS] Option B NSS DTB built successfully ($(wc -c < "$OUT_DIR/ipq5018-cr881x-nss.dtb") bytes)"
else
    echo "  [FAIL] Option B NSS DTB compilation failed:"
    cat "$OUT_DIR/cr881x_nss_dtc.log"
fi

echo "--- 3. Testing Option A: yangfl ipq5018-cr8818.dts (Upstream STMMAC baseline) ---"
cpp -nostdinc "${INC_DIRS[@]}" -undef -D__DTS__ -x assembler-with-cpp \
    /root/sources/yangfl_openwrt/target/linux/qualcommax/dts/ipq5018-cr8818.dts \
    "$OUT_DIR/ipq5018-cr8818.preprocessed.dts"

dtc -I dts -O dtb -o "$OUT_DIR/ipq5018-cr8818.dtb" "$OUT_DIR/ipq5018-cr8818.preprocessed.dts" 2>"$OUT_DIR/yangfl_dtc.log" || true
if [ -f "$OUT_DIR/ipq5018-cr8818.dtb" ]; then
    echo "  [PASS] Option A Baseline DTB built successfully ($(wc -c < "$OUT_DIR/ipq5018-cr8818.dtb") bytes)"
else
    echo "  [FAIL] Option A Baseline DTB compilation failed:"
    cat "$OUT_DIR/yangfl_dtc.log"
fi

echo "--- 4. Testing Patch 0002 Application & Compilation on Option A ---"
PATCH0002="/mnt/d/vibecode/CR8808-CUSTOM-FIRMWARE/patches/nss-cr8818/0002-arm64-dts-ipq5018-cr8818-dual-conduit-nss.patch"
echo "git apply --check on patch 0002 in yangfl_openwrt:"
if git -C /root/sources/yangfl_openwrt apply --check "$PATCH0002"; then
    echo "  [PASS] Patch 0002 applied cleanly to yangfl_openwrt."
    git -C /root/sources/yangfl_openwrt apply "$PATCH0002"
    cpp -nostdinc "${INC_DIRS[@]}" -undef -D__DTS__ -x assembler-with-cpp \
        /root/sources/yangfl_openwrt/target/linux/qualcommax/dts/ipq5018-cr8818.dts \
        "$OUT_DIR/ipq5018-cr8818-dual-conduit.preprocessed.dts"
    dtc -I dts -O dtb -o "$OUT_DIR/ipq5018-cr8818-dual-conduit.dtb" "$OUT_DIR/ipq5018-cr8818-dual-conduit.preprocessed.dts" 2>"$OUT_DIR/cr8818_dual_dtc.log" || true
    if [ -f "$OUT_DIR/ipq5018-cr8818-dual-conduit.dtb" ]; then
        echo "  [PASS] Option A Dual-Conduit Patched DTB built successfully ($(wc -c < "$OUT_DIR/ipq5018-cr8818-dual-conduit.dtb") bytes)"
    else
        echo "  [FAIL] Option A Dual-Conduit Patched DTB compilation failed:"
        cat "$OUT_DIR/cr8818_dual_dtc.log"
    fi
    git -C /root/sources/yangfl_openwrt checkout -- .
else
    echo "  [FAIL] Patch 0002 apply check failed"
fi

echo "--- 5. Testing Patch 0001 Application on Linux v6.18 Kernel Tree ---"
PATCH0001="/mnt/d/vibecode/CR8808-CUSTOM-FIRMWARE/patches/nss-cr8818/0001-net-dsa-tag_yt921x-8021q-nss-compat.patch"
echo "git apply --check on patch 0001 in linux-dts (Linux v6.18):"
if git -C /root/linux-dts apply --check "$PATCH0001"; then
    echo "  [PASS] Patch 0001 applied cleanly to Linux v6.18 kernel tree."
else
    echo "  [FAIL] Patch 0001 apply check failed"
fi

echo "===================================================================="
echo "DTS & Patch Verification Complete"
echo "===================================================================="
