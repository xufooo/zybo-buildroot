#!/bin/bash
# ============================================================================
# make_bootbin.sh — assemble the ZYBO Rev B SD card boot files (SPL route, no FSBL/bootgen needed)
# ============================================================================
# NOTE: the released SD image uses the FSBL form instead (see README.md).
#
# Boot chain: BOOT.BIN (= U-Boot's spl/boot.bin, loaded directly by the BootROM)
#         -> u-boot.img -> distro_bootcmd scans the FAT partition, finds boot.scr and runs it
#         -> boot.scr programs the PL with fpga loadb, then boots the kernel with bootm
#
# Why boot.scr instead of uEnv.txt: mainline U-Boot's distro_bootcmd only auto-runs
# boot.scr / extlinux.conf; automatic uEnv.txt import is an OpenWrt/Digilent customization
# and cannot be relied on. uEnv.txt is still generated (as a fallback).
#
# Output (default ./sdcard-boot/; copy the whole directory onto the SD card FAT32 partition):
#   BOOT.BIN  u-boot.img  uImage  zybo-audio.dtb  system.bit  boot.scr  uEnv.txt
#
# Usage:
#   ./make_bootbin.sh [--bit <*.bit>] [--images <dir>] [--out <dir>] [--mkimage <path>]
#   mkimage source: $MKIMAGE -> system mkimage -> ../.tools/bin/mkimage
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

IMAGES_DIR="${SCRIPT_DIR}/buildroot/output/images"
OUT_DIR="${SCRIPT_DIR}/sdcard-boot"
BIT_FILE=""
MKIMAGE="${MKIMAGE:-}"

while [ $# -gt 0 ]; do
    case "$1" in
        --bit)      BIT_FILE="$2"; shift 2 ;;
        --images)   IMAGES_DIR="$2"; shift 2 ;;
        --out)      OUT_DIR="$2"; shift 2 ;;
        --mkimage)  MKIMAGE="$2"; shift 2 ;;
        -h|--help)  sed -n '2,26p' "$0"; exit 0 ;;
        *) echo "unknown argument: $1"; exit 1 ;;
    esac
done

info() { echo -e "\033[0;32m[BOOTBIN]\033[0m $*"; }
die()  { echo -e "\033[0;31m[ERROR]\033[0m $*" >&2; exit 1; }

# --- Locate the bitstream ---------------------------------------------------
if [ -z "${BIT_FILE}" ]; then
    BIT_FILE="$(ls -t "${SCRIPT_DIR}"/*.bit "${SCRIPT_DIR}"/../*.bit \
                       "${SCRIPT_DIR}"/../build/fpga/*.xpr/*.runs/impl_1/*_wrapper.bit \
                       2>/dev/null | head -1 || true)"
fi
[ -n "${BIT_FILE}" ] && [ -f "${BIT_FILE}" ] || die "bitstream not found; specify it with --bit (the *_wrapper.bit produced by Vivado)"

# --- Locate mkimage ---------------------------------------------------------
if [ -z "${MKIMAGE}" ]; then
    if command -v mkimage >/dev/null 2>&1; then
        MKIMAGE="$(command -v mkimage)"
    elif [ -x "${SCRIPT_DIR}/../.tools/bin/mkimage" ]; then
        MKIMAGE="${SCRIPT_DIR}/../.tools/bin/mkimage"
    fi
fi
[ -n "${MKIMAGE}" ] && [ -x "${MKIMAGE}" ] || die "mkimage not found (install uboot-tools, or specify it with --mkimage)"

# --- Validate the Buildroot artifacts ---------------------------------------
SPL_BIN="${IMAGES_DIR}/boot.bin"
UBOOT_IMG="${IMAGES_DIR}/u-boot.img"
UIMAGE="${IMAGES_DIR}/uImage"
DTB="${IMAGES_DIR}/zybo-audio.dtb"

for f in "${SPL_BIN}" "${UBOOT_IMG}" "${UIMAGE}" "${DTB}"; do
    [ -f "$f" ] || die "missing artifact: $f (run the Buildroot build first)"
done

# --- Assemble ---------------------------------------------------------------
mkdir -p "${OUT_DIR}"
cp -f "${SPL_BIN}"   "${OUT_DIR}/BOOT.BIN"
cp -f "${UBOOT_IMG}" "${OUT_DIR}/u-boot.img"
cp -f "${UIMAGE}"    "${OUT_DIR}/uImage"
cp -f "${DTB}"       "${OUT_DIR}/zybo-audio.dtb"
cp -f "${BIT_FILE}"  "${OUT_DIR}/system.bit"

# --- boot.cmd -> boot.scr (U-Boot script; distro_bootcmd runs it automatically) ---
cat > "${OUT_DIR}/boot.cmd" <<'EOF'
# ZYBO Rev B audio player boot script (executed by distro_bootcmd)
echo "== ZYBO audio: loading FPGA bitstream =="
fatload mmc 0:1 0x100000 system.bit
fpga loadb 0 0x100000 ${filesize}

echo "== ZYBO audio: loading kernel =="
fatload mmc 0:1 0x3000000 uImage
fatload mmc 0:1 0x2A00000 zybo-audio.dtb

setenv bootargs console=ttyPS0,115200 root=/dev/mmcblk0p2 rootwait rw
bootm 0x3000000 - 0x2A00000
EOF
"${MKIMAGE}" -A arm -T script -C none -n "zybo-audio boot script" \
    -d "${OUT_DIR}/boot.cmd" "${OUT_DIR}/boot.scr" >/dev/null
info "boot.scr generated ($(basename "${MKIMAGE}"))"

# --- uEnv.txt (fallback; OpenWrt-style loaders import it automatically) -----
cat > "${OUT_DIR}/uEnv.txt" <<'EOF'
bootargs=console=ttyPS0,115200 root=/dev/mmcblk0p2 rootwait rw
EOF

info "assembled: ${OUT_DIR}"
ls -la "${OUT_DIR}"
echo
info "Next: copy everything under ${OUT_DIR} to the SD card FAT32 partition (write rootfs.ext4/tar.zst to the ext4 partition)."
