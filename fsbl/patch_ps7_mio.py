#!/usr/bin/env python3
# ============================================================================
# patch_ps7_mio.py — Fix our ps7_init with the MIO electrical parameters from
# the official ps7_init
# ============================================================================
# Background: in our XSA the PS7 MIO electrical parameters are Vivado defaults
# (Speed=slow / IO_Type=3 / PULLUP=1), which differ from the official Xilinx
# ps7_init values (Speed=fast / IO_Type=1 / PULLUP=0). Running the FSBL with
# that ps7_init causes:
#   · SD0 (MIO40..45): card init fails, command timeout + command CRC -> "SD: Unable to open file BOOT.BIN: 3"
#   · UART1 (MIO48/49): the serial port **transmits but cannot receive** (no login possible)
#   · the Ethernet/USB MIO pins likewise (wrong input-side electrical parameters)
# The mainline U-Boot (SPL flow) currently running on the board uses those
# official values, and SD, Ethernet and serial all work.
#
# So: for MIO pins present on **both sides**, keep our own function selection
# (L3_SEL must match, asserted) and replace only the electrical parameters with
# the official reference values. Pins our design does not use are left alone.
#
# Usage: patch_ps7_mio.py <our ps7_init.c> <official reference ps7_init.c>
# ============================================================================
import re
import sys

WRITE_RE = re.compile(r'(EMIT_MASKWRITE\((0[xX]F80007[0-9A-Fa-f]{2})\s*,\s*0x00003FFFU\s*,\s*)'
                      r'0x([0-9A-Fa-f]{8})U')


def parse(path):
    """Return {pin number: (value, match object, original full line)}"""
    out = {}
    for line in open(path, encoding='utf-8', errors='ignore'):
        m = WRITE_RE.search(line)
        if not m:
            continue
        pin = (int(m.group(2), 16) - 0xF8000700) // 4
        if 0 <= pin <= 53:
            out[pin] = (int(m.group(3), 16), m, line)
    return out


def l3sel(v):
    return (v >> 5) & 0x7


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    ours_p, ref_p = sys.argv[1], sys.argv[2]
    ours, ref = parse(ours_p), parse(ref_p)

    changed, skipped = [], []
    text = open(ours_p, encoding='utf-8', errors='ignore').read()
    for pin in sorted(set(ours) & set(ref)):
        ov, om, oline = ours[pin]
        rv, _, _ = ref[pin]
        if l3sel(ov) != l3sel(rv):
            skipped.append((pin, l3sel(ov), l3sel(rv)))
            continue                       # function selection differs -> do not copy
        if ov == rv:
            continue
        new_line = (f"{om.group(1)}0x{rv:08X}U"
                    + oline[om.end():])
        text = text.replace(oline, new_line, 1)
        changed.append((pin, ov, rv))

    open(ours_p, 'w', encoding='utf-8').write(text)
    print(f"  MIO electrical parameters aligned with the official reference: {len(changed)} pins changed")
    for pin, ov, rv in changed:
        print(f"    MIO_PIN_{pin:<2d} 0x{ov:08X} -> 0x{rv:08X}")
    if skipped:
        print(f"  (skipped {len(skipped)} pins with a different function selection: {skipped})")


if __name__ == '__main__':
    main()
