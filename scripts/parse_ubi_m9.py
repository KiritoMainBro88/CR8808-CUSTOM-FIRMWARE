import struct
import sys

def parse_ubi(path):
    print(f"=== Parsing {path} ===")
    with open(path, "rb") as f:
        data = f.read()
    peb_size = 131072 # 128 KiB
    total_pebs = len(data) // peb_size
    print(f"Total file size: {len(data)} bytes ({total_pebs} PEBs)")
    
    volumes = {}
    for peb in range(total_pebs):
        block = data[peb*peb_size:(peb+1)*peb_size]
        magic = block[:4]
        if magic != b'UBI#':
            continue
        vid_magic = block[2048:2052]
        if vid_magic == b'UBI!':
            # UBI VID header format
            # uint32_t magic (UBI!)
            # uint8_t version
            # uint8_t vol_type
            # uint8_t copy_flag
            # uint8_t compat
            # uint32_t vol_id
            # uint32_t lnum
            # uint32_t leb_ver (reserved)
            # uint32_t data_size
            # uint32_t used_ebs
            # uint32_t data_pad
            # uint32_t data_crc
            vol_id, lnum = struct.unpack(">II", block[2056:2064])
            data_size = struct.unpack(">I", block[2068:2072])[0]
            if vol_id not in volumes:
                volumes[vol_id] = {"count": 0, "max_lnum": 0, "total_data_size": 0}
            volumes[vol_id]["count"] += 1
            if lnum > volumes[vol_id]["max_lnum"]:
                volumes[vol_id]["max_lnum"] = lnum
            volumes[vol_id]["total_data_size"] += data_size
        elif block[2048:2048+4] == b'\xff\xff\xff\xff':
            # empty VID
            pass
            
    print(f"Volume summary for {path}:")
    for vid, info in sorted(volumes.items()):
        name = "unknown"
        if vid == 0:
            name = "kernel (vol_id 0)"
        elif vid == 1:
            name = "rootfs (vol_id 1)"
        elif vid == 2:
            name = "rootfs_data (vol_id 2)"
        elif vid == 0x7fffffff:
            name = "layout volume (internal UBI metadata)"
        print(f"  Vol ID 0x{vid:x} ({name}): PEB count = {info['count']}, max LEB = {info['max_lnum']}, total data = {info['total_data_size']} bytes")

if __name__ == "__main__":
    for p in sys.argv[1:]:
        parse_ubi(p)
