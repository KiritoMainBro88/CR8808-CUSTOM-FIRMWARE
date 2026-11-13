#!/bin/sh
# scripts/verify_userspace_artifacts.sh
# Offline ABI, SHA-256, Footprint & Optional QEMU Verification for CR8808 ARMv7 Userspace Artifacts
# Targets: iperf3-armv7, ethtool-armv7, boringtun-cli-armv7

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

CHECK_QEMU=0
JSON_OUT=0
STAGE_DIR=""
ARTIFACTS_ROOT="${ARTIFACTS_ROOT:-${REPO_ROOT}/artifacts}"
QEMU_BIN=""
RAM_LIMIT_KB="${RAM_LIMIT_KB:-10240}" # Conservative tmpfs artifact staging check (<10 MB)

usage() {
    cat << EOF
Usage: $0 [OPTIONS]
  --check-qemu           Run non-destructive --version/--help smoke tests under qemu-arm if installed
  --stage-dir <dir>      Verify copying validated artifacts cleanly to a volatile staging directory
  --artifacts-root <dir> Override artifacts root directory (for hermetic testing)
  --json                 Emit structured JSON report
  -h, --help             Show help
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --check-qemu) CHECK_QEMU=1 ;;
        --stage-dir) shift; STAGE_DIR="${1:-}"; [ -n "$STAGE_DIR" ] || exit 1 ;;
        --artifacts-root) shift; ARTIFACTS_ROOT="${1:-}"; [ -n "$ARTIFACTS_ROOT" ] || exit 1 ;;
        --json|-j) JSON_OUT=1 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "[USR-VERIFY ERROR] Unknown argument: $1" >&2; usage >&2; exit 1 ;;
    esac
    shift
done

for _cand in qemu-arm-static qemu-arm; do
    if command -v "$_cand" >/dev/null 2>&1; then
        QEMU_BIN="$_cand"
        break
    fi
done

json_escape() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

TOTAL=0
PASSED=0
FAILED=0
TOTAL_BYTES=0
RESULTS_JSON=""

verify_one() {
    _dir="$1"
    _bin="$2"
    _sum_file="${_dir}/SHA256SUMS"
    _full="${_dir}/${_bin}"
    TOTAL=$((TOTAL + 1))

    _sha_status="FAIL"
    _elf_status="FAIL"
    _qemu_status="SKIPPED"
    _sz=0
    _interp="UNKNOWN"

    if [ ! -f "$_full" ] || [ ! -f "$_sum_file" ]; then
        FAILED=$((FAILED + 1))
        [ "$JSON_OUT" -eq 0 ] && echo "  [FAIL] $_bin missing binary or SHA256SUMS"
    else
        _sz=$(wc -c < "$_full" | tr -d ' ')
        TOTAL_BYTES=$((TOTAL_BYTES + _sz))

        if (cd "$_dir" && sha256sum -c "SHA256SUMS" 2>/dev/null | grep -qE "^${_bin}: OK$"); then
            _sha_status="PASS"
        fi

        _hdr=""
        if command -v readelf >/dev/null 2>&1; then
            _hdr=$(readelf -h -l -A "$_full" 2>/dev/null || true)
        fi
        if printf '%s' "$_hdr" | grep -q "ELF32" && printf '%s' "$_hdr" | grep -q "ARM"; then
            if printf '%s' "$_hdr" | grep -q "Requesting program interpreter:"; then
                _interp="DYNAMIC"
                _elf_status="PASS_ARM32_DYN"
            else
                _interp="STATIC"
                _elf_status="PASS_ARM32_STATIC"
            fi
        elif command -v file >/dev/null 2>&1; then
            _fdesc=$(file "$_full" 2>/dev/null || true)
            if printf '%s' "$_fdesc" | grep -qi "ELF 32-bit.*ARM"; then
                _elf_status="PASS_ARM32"
                _interp=$(printf '%s' "$_fdesc" | grep -qi "statically linked" && echo "STATIC" || echo "DYNAMIC")
            fi
        fi

        if [ "$CHECK_QEMU" -eq 1 ]; then
            if [ -n "$QEMU_BIN" ]; then
                _qflag="--version"
                case "$_bin" in
                    boringtun*) _qflag="--help" ;;
                esac
                if "$QEMU_BIN" "$_full" "$_qflag" >/dev/null 2>&1; then
                    _qemu_status="PASS"
                else
                    _qemu_status="FAIL"
                fi
            else
                _qemu_status="SKIPPED_NO_QEMU"
            fi
        fi

        if [ "$_sha_status" = "PASS" ] && printf '%s' "$_elf_status" | grep -q "^PASS" && [ "$_qemu_status" != "FAIL" ]; then
            PASSED=$((PASSED + 1))
            if [ -n "$STAGE_DIR" ]; then
                mkdir -p "$STAGE_DIR"
                cp -f "$_full" "${STAGE_DIR}/${_bin}"
                chmod +x "${STAGE_DIR}/${_bin}"
            fi
            [ "$JSON_OUT" -eq 0 ] && echo "  [PASS] $_bin (${_sz}B, sha=${_sha_status}, elf=${_elf_status}, qemu=${_qemu_status})"
        else
            FAILED=$((FAILED + 1))
            [ "$JSON_OUT" -eq 0 ] && echo "  [FAIL] $_bin (${_sz}B, sha=${_sha_status}, elf=${_elf_status}, qemu=${_qemu_status})"
        fi
    fi

    _item="{\"binary\":\"$(json_escape "$_bin")\",\"bytes\":${_sz},\"sha256\":\"${_sha_status}\",\"elf\":\"${_elf_status}\",\"linkage\":\"${_interp}\",\"qemu\":\"${_qemu_status}\"}"
    if [ -z "$RESULTS_JSON" ]; then
        RESULTS_JSON="$_item"
    else
        RESULTS_JSON="${RESULTS_JSON},${_item}"
    fi
}

[ "$JSON_OUT" -eq 0 ] && echo "=== CR8808 ARMv7 Userspace Artifact Verification ==="
verify_one "${ARTIFACTS_ROOT}/m12_userspace" "iperf3-armv7"
verify_one "${ARTIFACTS_ROOT}/m12_userspace" "ethtool-armv7"
verify_one "${ARTIFACTS_ROOT}/m12_wireguard" "boringtun-cli-armv7"

TOTAL_KB=$((TOTAL_BYTES / 1024))
FOOTPRINT_OK="PASS"
if [ "$TOTAL_KB" -gt "$RAM_LIMIT_KB" ]; then
    FOOTPRINT_OK="WARN_EXCEEDS_TMPFS_BUDGET"
fi

if [ "$JSON_OUT" -eq 1 ]; then
    cat << EOF
{
  "total": ${TOTAL},
  "passed": ${PASSED},
  "failed": ${FAILED},
  "total_bytes": ${TOTAL_BYTES},
  "total_kb": ${TOTAL_KB},
  "tmpfs_footprint_status": "${FOOTPRINT_OK}",
  "qemu_bin": "$(json_escape "${QEMU_BIN:-NONE}")",
  "artifacts": [${RESULTS_JSON}]
}
EOF
else
    echo "Summary: passed=${PASSED}/${TOTAL} failed=${FAILED} total=${TOTAL_KB} KB tmpfs_budget=${FOOTPRINT_OK}"
fi

[ "$FAILED" -eq 0 ]
