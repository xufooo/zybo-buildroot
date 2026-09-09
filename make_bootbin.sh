#!/bin/bash
# ============================================================================
# make_bootbin.sh — 组装 ZYBO Rev B 的 SD 卡启动文件（SPL 路线，无需 FSBL/bootgen）
# ============================================================================
# 启动链：BOOT.BIN(=u-boot 的 spl/boot.bin，BootROM 直接加载)
#         → u-boot.img → distro_bootcmd 扫描 FAT 分区找到 boot.scr 并执行
#         → boot.scr 里 fpga loadb 编程 PL，再 bootm 启动内核
#
# 为什么用 boot.scr 而不是 uEnv.txt：mainline U-Boot 的 distro_bootcmd 只自动执行
# boot.scr / extlinux.conf；uEnv.txt 的自动导入是 OpenWrt/Digilent 的定制，不能依赖。
# uEnv.txt 仍然生成（备用）。
#
# 产物（默认 ./sdcard-boot/，整体拷入 SD 卡 FAT32 分区）：
#   BOOT.BIN  u-boot.img  uImage  zybo-audio.dtb  system.bit  boot.scr  uEnv.txt
#
# 用法：
#   ./make_bootbin.sh [--bit <*.bit>] [--images <dir>] [--out <dir>] [--mkimage <path>]
#   mkimage 来源：$MKIMAGE → 系统 mkimage → ../.tools/bin/mkimage
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
        *) echo "未知参数: $1"; exit 1 ;;
    esac
done

info() { echo -e "\033[0;32m[BOOTBIN]\033[0m $*"; }
die()  { echo -e "\033[0;31m[ERROR]\033[0m $*" >&2; exit 1; }

# ── 定位 bitstream ───────────────────────────────────────────────────────
if [ -z "${BIT_FILE}" ]; then
    BIT_FILE="$(ls -t "${SCRIPT_DIR}"/*.bit "${SCRIPT_DIR}"/../*.bit \
                       "${SCRIPT_DIR}"/../build/fpga/*.xpr/*.runs/impl_1/*_wrapper.bit \
                       2>/dev/null | head -1 || true)"
fi
[ -n "${BIT_FILE}" ] && [ -f "${BIT_FILE}" ] || die "找不到 bitstream；用 --bit 指定（Vivado 产出的 *_wrapper.bit）"

# ── 定位 mkimage ─────────────────────────────────────────────────────────
if [ -z "${MKIMAGE}" ]; then
    if command -v mkimage >/dev/null 2>&1; then
        MKIMAGE="$(command -v mkimage)"
    elif [ -x "${SCRIPT_DIR}/../.tools/bin/mkimage" ]; then
        MKIMAGE="${SCRIPT_DIR}/../.tools/bin/mkimage"
    fi
fi
[ -n "${MKIMAGE}" ] && [ -x "${MKIMAGE}" ] || die "找不到 mkimage（安装 uboot-tools，或用 --mkimage 指定）"

# ── 校验 Buildroot 产物 ─────────────────────────────────────────────────
SPL_BIN="${IMAGES_DIR}/boot.bin"
UBOOT_IMG="${IMAGES_DIR}/u-boot.img"
UIMAGE="${IMAGES_DIR}/uImage"
DTB="${IMAGES_DIR}/zybo-audio.dtb"

for f in "${SPL_BIN}" "${UBOOT_IMG}" "${UIMAGE}" "${DTB}"; do
    [ -f "$f" ] || die "缺少产物: $f（先完成 Buildroot 构建）"
done

# ── 组装 ────────────────────────────────────────────────────────────────
mkdir -p "${OUT_DIR}"
cp -f "${SPL_BIN}"   "${OUT_DIR}/BOOT.BIN"
cp -f "${UBOOT_IMG}" "${OUT_DIR}/u-boot.img"
cp -f "${UIMAGE}"    "${OUT_DIR}/uImage"
cp -f "${DTB}"       "${OUT_DIR}/zybo-audio.dtb"
cp -f "${BIT_FILE}"  "${OUT_DIR}/system.bit"

# ── boot.cmd → boot.scr（U-Boot 脚本，distro_bootcmd 会自动执行）─────────
cat > "${OUT_DIR}/boot.cmd" <<'EOF'
# ZYBO Rev B 音频播放器启动脚本（由 distro_bootcmd 执行）
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
info "boot.scr 已生成（$(basename "${MKIMAGE}")）"

# ── uEnv.txt（备用；OpenWrt 风格 loader 会自动导入）────────────────────────
cat > "${OUT_DIR}/uEnv.txt" <<'EOF'
bootargs=console=ttyPS0,115200 root=/dev/mmcblk0p2 rootwait rw
EOF

info "组装完成：${OUT_DIR}"
ls -la "${OUT_DIR}"
echo
info "下一步：把 ${OUT_DIR} 下全部文件拷到 SD 卡 FAT32 分区（rootfs.ext4/tar.zst 写到 ext4 分区）。"
