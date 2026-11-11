import struct
import sys

def read_bdf(path):
    print(f"=== Reading {path} ===")
    with open(path, "rb") as f:
        data = f.read()
    print(f"File size: {len(data)} bytes")
    print("First 32 bytes hex:", data[:32].hex())
    # ath11k board-2.bin header:
    # 0x00: Magic or TLV
    offset = 0
    item = 0
    while offset + 4 <= len(data) and item < 10:
        tag, length = struct.unpack("<HH", data[offset:offset+4])
        payload = data[offset+4:offset+4+length]
        print(f"  Item {item}: Offset=0x{offset:04x}, Tag=0x{tag:04x}, Length={length}")
        if tag == 1: # ATH11K_BD_IE_BOARD
            print(f"    -> Board Data length: {length}")
        elif tag == 2: # ATH11K_BD_IE_BOARD_NAME
            name = payload.decode('ascii', errors='replace')
            print(f"    -> Board Name: '{name}'")
        elif tag == 3: # ATH11K_BD_IE_BOARD_DATA
            print(f"    -> Board Data Payload length: {length}")
        offset += 4 + length
        item += 1

if __name__ == "__main__":
    for p in sys.argv[1:]:
        read_bdf(p)
