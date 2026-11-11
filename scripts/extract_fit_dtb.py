#!/usr/bin/env python3
"""
Extract and decompile DTB from FIT image container.
Used for Milestone M10.1 audit of openwrt-qualcommax-ipq50xx-xiaomi_cr8818-initramfs-uImage.itb.
"""
import sys
import os
import struct
import subprocess

def extract_fit_dtb(fit_path, out_dtb_path, out_dts_path=None):
    if not os.path.exists(fit_path):
        print(f"Error: FIT image not found: {fit_path}", file=sys.stderr)
        return False

    with open(fit_path, "rb") as f:
        data = f.read()

    OF_DT_BEGIN_NODE = 1
    OF_DT_END_NODE = 2
    OF_DT_PROP = 3
    OF_DT_NOP = 4
    OF_DT_END = 9

    magic, totalsize, off_dt_struct, off_dt_strings = struct.unpack(">4I", data[:16])
    if magic != 0xd00dfeed:
        print(f"Error: Invalid FIT magic: {hex(magic)}", file=sys.stderr)
        return False

    def get_str(offset):
        end = data.find(b"\0", off_dt_strings + offset)
        return data[off_dt_strings + offset:end].decode("ascii", errors="ignore")

    idx = off_dt_struct
    node_stack = []
    fdt_bytes = None
    current_image = None

    while idx < totalsize:
        token = struct.unpack(">I", data[idx:idx+4])[0]
        idx += 4
        if token == OF_DT_BEGIN_NODE:
            end = data.find(b"\0", idx)
            name = data[idx:end].decode("ascii", errors="ignore")
            idx = (end + 4) & ~3
            node_stack.append(name)
            if len(node_stack) == 3 and node_stack[1] == "images":
                current_image = name
        elif token == OF_DT_END_NODE:
            popped = node_stack.pop()
            if popped == current_image:
                current_image = None
        elif token == OF_DT_PROP:
            val_len, name_off = struct.unpack(">2I", data[idx:idx+8])
            idx += 8
            val_bytes = data[idx:idx+val_len]
            idx = (idx + val_len + 3) & ~3
            prop_name = get_str(name_off)
            if current_image == "fdt-1" and prop_name == "data":
                fdt_bytes = val_bytes
        elif token == OF_DT_NOP:
            pass
        elif token == OF_DT_END:
            break

    if not fdt_bytes:
        print("Error: fdt-1 node or data not found in FIT image!", file=sys.stderr)
        return False

    with open(out_dtb_path, "wb") as f:
        f.write(fdt_bytes)
    print(f"Successfully extracted DTB ({len(fdt_bytes)} bytes) to {out_dtb_path}")

    if out_dts_path:
        res = subprocess.run(["dtc", "-I", "dtb", "-O", "dts", out_dtb_path, "-o", out_dts_path], capture_output=True, text=True)
        if res.returncode != 0:
            print(f"Warning: dtc decompile failed: {res.stderr}", file=sys.stderr)
            return False
        print(f"Successfully decompiled DTB to {out_dts_path}")
    return True

if __name__ == "__main__":
    fit = sys.argv[1] if len(sys.argv) > 1 else "artifacts/m10_images/openwrt-qualcommax-ipq50xx-xiaomi_cr8818-initramfs-uImage.itb"
    out_dtb = sys.argv[2] if len(sys.argv) > 2 else "artifacts/m10_images/extracted_cr8818.dtb"
    out_dts = sys.argv[3] if len(sys.argv) > 3 else "artifacts/m10_images/extracted_cr8818.dts"
    success = extract_fit_dtb(fit, out_dtb, out_dts)
    sys.exit(0 if success else 1)
