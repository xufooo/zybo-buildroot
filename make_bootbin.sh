#!/bin/bash
# ============================================================================
# make_bootbin.sh — 组装 ZYBO Rev B 的 SD 卡启动文件（SPL 路线，无需 FSBL/bootgen）
# ============================================================================
# 依据（docs/RESEARCH.md）：u-boot v2024.01 的 xilinx_zynq_virt + DEVICE_TREE=zynq-zybo，
# SPL 产出 spl/boot.bin（BootROM 直接加载）；bitstream 由 U-Boot 用 `fpga loadb` 加载。
#
# 产物（默认 build/sdcard-boot/，整体拷入 SD 卡 FAT 分区即可）：
#   BOOT.BIN        ← u-boot 的 spl/boot.bin
#   u-boot.img      ← U-Boot proper（SPL 的载荷）
#   uImage          ← 内核（Buildroot 产物）
#   zybo-audio.dtb  ← 设备树（含音频节点）
#   system.bit      ← PL bitstream（音频 I2S/IIC；来自 build/fpga）
#   uEnv.txt        ← 先 fpga loadb 载入 bitstream，再 bootm 启动内核
#
# 用法：
#   linux/buildroot/make_bootbin.sh [--bit <path/to/*.bit>] [--images <buildroot/output/images>]
#                                   [--out <dir>]
# 说明：本机无 Vitis（无法生成 FSBL），故采用 SPL 路线；若将来要 FSBL+bootgen 单文件
#       BOOT.BIN，可另加分支（bootgen 位于 Vivado/bin）。
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

IMAGES_DIR="${SCRIPT_DIR}/buildroot/output/images"
OUT_DIR="${SCRIPT_DIR}/sdcard-boot"
BIT_FILE=""

while [ $# -gt 0 ]; do
    case "$1" in
        --bit)    BIT_FILE="$2"; shift 2 ;;
        --images) IMAGES_DIR="$2"; shift 2 ;;
        --out)    OUT_DIR="$2"; shift 2 ;;
        -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
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

# ── 校验 Buildroot 产物 ─────────────────────────────────────────────────
SPL_BIN="${IMAGES_DIR}/boot.bin"
UBOOT_IMG="${IMAGES_DIR}/u-boot.img"
UIMAGE="${IMAGES_DIR}/uImage"
DTB="${IMAGES_DIR}/zybo-audio.dtb"

for f in "${SPL_BIN}" "${UBOOT_IMG}" "${UIMAGE}" "${DTB}"; do
    [ -f "$f" ] || die "缺少产物: $f（先完成 Buildroot 构建，且 defconfig 需开启 SPL/IMG/DTS）"
done

# ── 组装 ────────────────────────────────────────────────────────────────
mkdir -p "${OUT_DIR}"
cp -f "${SPL_BIN}"   "${OUT_DIR}/BOOT.BIN"
cp -f "${UBOOT_IMG}" "${OUT_DIR}/u-boot.img"
cp -f "${UIMAGE}"    "${OUT_DIR}/uImage"
cp -f "${DTB}"       "${OUT_DIR}/zybo-audio.dtb"
cp -f "${BIT_FILE}"  "${OUT_DIR}/system.bit"

cat > "${OUT_DIR}/uEnv.txt" <<'EOF'
# ZYBO Rev B 音频播放器启动脚本（U-Boot SPL 路线）
# 1) 载入并编程 PL（bitstream）  2) 启动内核
bitstream_image=system.bit
kernel_image=uImage
fdt_image=zybo-audio.dtb

loadfpga=fatload mmc 0 0x100000 ${bitstream_image}; fpga loadb 0 0x100000 ${filesize}
loadkernel=load mmc 0 0x3000000 ${kernel_image}
loadfdt=load mmc 0 0x2A00000 ${fdt_image}

bootargs=console=ttyPS0,115200 root=/dev/mmcblk0p2 rw rootwait

uenvcmd=run loadfpga; run loadkernel; run loadfdt; setenv bootargs ${bootargs}; bootm 0x3000000 - 0x2A00000
EOF

info "组装完成：${OUT_DIR}"
ls -la "${OUT_DIR}"
echo
info "下一步：把 ${OUT_DIR} 下全部文件拷到 SD 卡 FAT32 分区；"
info "  若尚未有分区镜像，可参考 linux/buildroot/external/board/zybo-revb/genimage.cfg 用 genimage 生成。"
