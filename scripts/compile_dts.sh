#!/bin/bash
set -e

echo "===================================================================="
echo "DTS Validation & Compilation Suite for CR8818"
echo "Target: Linux 6.18 / IPQ5018 / Motorcomm YT9215SC"
echo "===================================================================="

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

echo "--- 4. Testing Patch 0002 Application ---"
PATCH0002="/mnt/d/vibecode/CR8808-CUSTOM-FIRMWARE/patches/nss-cr8818/0002-arm64-dts-ipq5018-cr8818-dual-conduit-nss.patch"
echo "git apply --check on patch 0002 in yangfl_openwrt:"
git -C /root/sources/yangfl_openwrt apply --check "$PATCH0002" 2>&1 || echo "  [FAILED: Patch corrupt or path mismatch]"
echo "git apply --check on patch 0002 in zcop_immortalwrt:"
git -C /root/sources/zcop_immortalwrt apply --check "$PATCH0002" 2>&1 || echo "  [FAILED: Patch corrupt or path mismatch]"
