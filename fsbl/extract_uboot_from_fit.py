#!/usr/bin/env python3
# ============================================================================
# extract_uboot_from_fit.py — Extract a flat U-Boot usable by the FSBL from
# u-boot.img (FIT)
# ============================================================================
# Background: under the SPL flow u-boot.img is a **FIT** (-f auto -E, external
# data layout):
#   [FIT device tree 5996B][firmware-1: U-Boot payload 1014224B][fdt-1: zynq-zybo 14392B][dtbs of other boards...]
# Trimming the first 64 bytes as a legacy uImage header is wrong (those 64
# bytes are only the beginning of the FIT device tree); the result is not
# U-Boot, and the FSBL handoff will always crash.
#
# The FSBL flow has no SPL, so U-Boot has to locate the device tree on its own:
# under CONFIG_OF_SEPARATE mainline U-Boot looks for the dtb at the **end** of
# the image (`_end`) (lib/fdtdec.c: fdt_find_separate()), so the flat image
# handed to the FSBL must be the Buildroot u-boot.bin = U-Boot payload +
# appended dtb.
#
# This script does exactly that: read the FIT -> verify crc32 -> concatenate
# firmware + this board's dtb into a flat image.
#
# Usage: extract_uboot_from_fit.py <u-boot.img> <output u-boot.bin> [board keyword, default zybo]
# ============================================================================
import binascii
import struct
import sys

FDT_MAGIC = 0xD00DFEED
FDT_BEGIN_NODE, FDT_END_NODE, FDT_PROP, FDT_NOP, FDT_END = 1, 2, 3, 4, 9


def parse_fdt(data):
    """Parse the FDT into {node path: {property: value (bytes)}}"""
    magic, totalsize, off_struct, off_strings = struct.unpack_from('>4I', data, 0)
    if magic != FDT_MAGIC:
        sys.exit(f"not an FDT: magic=0x{magic:08x}")
    strings = data[off_strings:]
    nodes, path, off = {}, [], off_struct
    while True:
        tok = struct.unpack_from('>I', data, off)[0]
        off += 4
        if tok == FDT_BEGIN_NODE:
            end = data.index(b'\0', off)
            name = data[off:end].decode()
            off = (end + 1 + 3) & ~3
            path.append(name)
        elif tok == FDT_END_NODE:
            path.pop()
        elif tok == FDT_PROP:
            length, nameoff = struct.unpack_from('>2I', data, off)
            off += 8
            val = data[off:off + length]
            off = (off + length + 3) & ~3
            pname = strings[nameoff:strings.index(b'\0', nameoff)].decode()
            nodes.setdefault('/'.join(path), {})[pname] = val
        elif tok in (FDT_NOP,):
            continue
        elif tok == FDT_END:
            break
        else:
            sys.exit(f"malformed FDT structure: token={tok} @0x{off - 4:x}")
    return nodes, totalsize


def u32(b):
    return struct.unpack('>I', b)[0]


def sval(props, key):
    """String properties in a DTB carry a trailing NUL"""
    return props.get(key, b'').rstrip(b'\0').decode()


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    img, out = sys.argv[1], sys.argv[2]
    want = (sys.argv[3] if len(sys.argv) > 3 else 'zybo').lower()
    data = open(img, 'rb').read()
    nodes, totalsize = parse_fdt(data)
    data_start = totalsize                     # start of the FIT external data = right after the device tree
    if data_start % 4:
        sys.exit("FIT data area is not aligned")

    def blob(node):
        props = nodes[node]
        off, size = u32(props['data-offset']), u32(props['data-size'])
        return data[data_start + off:data_start + off + size], props

    fw_node = next(n for n in nodes if n.startswith('/images/')
                   and sval(nodes[n], 'type') == 'firmware')
    firmware, props = blob(fw_node)
    hsh = nodes.get(fw_node + '/hash', {})
    algo = sval(hsh, 'algo')
    declared = u32(hsh['value'])
    if algo != 'crc32':
        sys.exit(f"only crc32 is supported, the FIT uses {algo}")
    actual = binascii.crc32(firmware)
    print(f"  U-Boot payload: {fw_node} {len(firmware)} B crc32={actual:08x} (FIT declares {declared:08x})")
    if actual != declared:
        sys.exit("U-Boot payload crc32 mismatch — u-boot.img may be incomplete")

    dtb_node = next((n for n in nodes if n.startswith('/images/')
                     and sval(nodes[n], 'type') == 'flat_dt'
                     and want in sval(nodes[n], 'description').lower()), None)
    if not dtb_node:
        sys.exit(f"no device tree whose description contains '{want}' found in the FIT")
    dtb, props = blob(dtb_node)
    hd = nodes.get(dtb_node + '/hash', {})
    print(f"  Appended device tree: {dtb_node} {len(dtb)} B description={sval(props, 'description')} "
          f"crc32={binascii.crc32(dtb):08x} (FIT declares {u32(hd['value']):08x})")

    open(out, 'wb').write(firmware + dtb)      # CONFIG_OF_SEPARATE: dtb appended at the end of the image
    print(f"  Output: {out} {len(firmware) + len(dtb)} B (= payload + appended dtb)")


if __name__ == '__main__':
    main()
