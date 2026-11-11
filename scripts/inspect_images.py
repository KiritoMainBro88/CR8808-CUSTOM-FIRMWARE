import struct
import sys
import os

def inspect_image(path):
    print(f"=== Inspecting {os.path.basename(path)} ===")
    if not os.path.exists(path):
        print(f"File not found: {path}")
        return
    with open(path, "rb") as f:
        data = f.read()
    size = len(data)
    print(f"Total size: {size} bytes ({size / (1024*1024):.2f} MB)")
    magic = data[:4]
    print(f"Header magic: {magic} ({magic.hex()})")
    
    if magic == b"UBI#":
        version = data[4]
        ec = struct.unpack(">Q", b"\x00\x00\x00\x00" + data[8:12])[0]
        vid_offset = struct.unpack(">I", data[16:20])[0]
        data_offset = struct.unpack(">I", data[20:24])[0]
        print(f"UBI Version: {version}, VID header offset: {vid_offset}, Data offset: {data_offset}")
        
        # Scan for VID headers
        pos = 0
        vids = []
        vol_names = set()
        while True:
            idx = data.find(b"UBI!", pos)
            if idx == -1:
                break
            vol_id = struct.unpack(">I", data[idx+4:idx+8])[0]
            lnum = struct.unpack(">I", data[idx+8:idx+12])[0]
            data_size = struct.unpack(">I", data[idx+16:idx+20])[0]
            vids.append((vol_id, lnum, data_size, idx))
            pos = idx + 4
        print(f"Found {len(vids)} VID headers across image.")
        vol_ids = sorted(list(set(v[0] for v in vids)))
        print(f"Volume IDs: {[hex(v) for v in vol_ids]}")
        
        # Check for UBI layout volume (0x7fffefff)
        layout_idx = data.find(b"\x7f\xff\xef\xff")
        # Check volume name records
        for vname in [b"kernel", b"rootfs", b"rootfs_data", b"ubi_rootfs"]:
            if vname in data:
                print(f"Found volume name string: '{vname.decode()}' in UBI image")
                
    elif magic == b"\xd0\x0d\xfe\xed":
        print("Device Tree Blob (DTB / FIT Image) detected!")
        totalsize = struct.unpack(">I", data[4:8])[0]
        print(f"FIT Image header totalsize: {totalsize} bytes ({totalsize / (1024*1024):.2f} MB)")
    else:
        # Check if sysupgrade tar or raw FIT
        fit_idx = data.find(b"\xd0\x0d\xfe\xed")
        if fit_idx != -1:
            print(f"FIT Image found at offset {fit_idx}")
        sqfs_idx = data.find(b"hsqs")
        if sqfs_idx != -1:
            print(f"SquashFS header ('hsqs') found at offset {sqfs_idx}")

if __name__ == "__main__":
    for p in sys.argv[1:]:
        inspect_image(p)
