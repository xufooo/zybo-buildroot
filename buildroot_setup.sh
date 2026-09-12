#!/bin/bash
# ============================================================================
# buildroot_setup.sh — ZYBO Audio DSP: Buildroot One-Click Setup & Build
# ============================================================================
# This script runs ON YOUR UBUNTU 22.04 VM (not on Windows).
#
# Usage:
#   ./buildroot_setup.sh setup    — Clone Buildroot + create defconfig
#   ./buildroot_setup.sh build    — Build everything (kernel + u-boot + rootfs)
#   ./buildroot_setup.sh rebuild  — Incremental rebuild (kernel only)
#   ./buildroot_setup.sh clean    — Clean build artifacts
#   ./buildroot_setup.sh sd-card  — Show SD card assembly notes
#
# Quick start:
#   cd ZYBO/projects/audio_player/linux/buildroot
#   ./buildroot_setup.sh setup
#   ./buildroot_setup.sh build
# ============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
EXTERNAL_DIR="${SCRIPT_DIR}/external"
BUILDROOT_DIR="${SCRIPT_DIR}/buildroot"
BUILDROOT_VERSION="2026.02.3"
BUILDROOT_URL="https://github.com/buildroot/buildroot.git"
DEFCONFIG_NAME="zybo_revb_audio_defconfig"
JOBS="${JOBS:-$(nproc)}"

# ── Colors ──────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

info()  { echo -e "${GREEN}[BUILDROOT]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARNING]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# ── Check dependencies ────────────────────────────────────────────────────
check_deps() {
    info "Checking system dependencies..."

    local missing=""
    for pkg in make gcc g++ bison flex libssl-dev bc rsync cpio unzip wget; do
        if ! dpkg -s "$pkg" &>/dev/null && ! command -v "$pkg" &>/dev/null; then
            missing="$missing $pkg"
        fi
    done

    if [ -n "$missing" ]; then
        warn "Missing packages:$missing"
        info "Installing with apt..."
        sudo apt-get update
        sudo apt-get install -y build-essential flex bison libssl-dev \
            libncurses-dev rsync cpio unzip wget bc python3
    fi

    info "Dependencies OK"
}

# ── Clone Buildroot ────────────────────────────────────────────────────────
clone_buildroot() {
    if [ -d "${BUILDROOT_DIR}" ]; then
        info "Buildroot already cloned at ${BUILDROOT_DIR}"
        return 0
    fi

    info "Cloning Buildroot ${BUILDROOT_VERSION}..."
    git clone --depth 1 --branch "${BUILDROOT_VERSION}" \
        "${BUILDROOT_URL}" "${BUILDROOT_DIR}"

    info "Buildroot cloned successfully"
}

# ── Create defconfig ──────────────────────────────────────────────────────
setup_defconfig() {
    info "Creating default configuration: ${DEFCONFIG_NAME}"

    cd "${BUILDROOT_DIR}"

    # Register the external tree and apply our defconfig
    make BR2_EXTERNAL="${EXTERNAL_DIR}" "${DEFCONFIG_NAME}"

    info "Configuration created. Run 'make menuconfig' to customize."
}

# ── Build ──────────────────────────────────────────────────────────────────
do_build() {
    if [ ! -f "${BUILDROOT_DIR}/.config" ]; then
        error "No .config found. Run './buildroot_setup.sh setup' first."
    fi

    cd "${BUILDROOT_DIR}"

    info "Starting Buildroot build (${JOBS} parallel jobs)..."
    info "First build (with toolchain): ~60 minutes"
    info "Incremental build: ~5-10 minutes"
    echo ""

    make -j"${JOBS}"

    info "=========================================="
    info " BUILD COMPLETE"
    info "=========================================="
    echo ""
    info "Output files:"
    find output/images -type f | sort | while read f; do
        echo "  ${f}"
    done
    echo ""
    info "Note: no sdcard.img is built — genimage is disabled in the defconfig."
    info "      Run './buildroot_setup.sh sd-card' for SD card assembly notes."
    echo ""
}

# ── Rebuild (kernel only) ──────────────────────────────────────────────────
do_rebuild() {
    if [ ! -f "${BUILDROOT_DIR}/.config" ]; then
        error "No .config found. Run './buildroot_setup.sh setup' first."
    fi

    cd "${BUILDROOT_DIR}"

    info "Rebuilding linux kernel..."
    make linux-rebuild -j"${JOBS}"

    info "Rebuilding rootfs..."
    make -j"${JOBS}"

    info "Rebuild complete."
}

# ── Clean ──────────────────────────────────────────────────────────────────
do_clean() {
    cd "${BUILDROOT_DIR}"
    info "Cleaning build artifacts..."
    make clean
    info "Clean complete. Run './buildroot_setup.sh build' to rebuild."
}

# ── SD Card Help ───────────────────────────────────────────────────────────
do_sd_card() {
    cat << 'EOF'

╔════════════════════════════════════════════════════════════════════════╗
║  SD Card Assembly Notes                                                ║
╠════════════════════════════════════════════════════════════════════════╣
║                                                                        ║
║  This tree does NOT produce a flashable sdcard.img: genimage is        ║
║  disabled in the defconfig. See external/board/zybo-revb/genimage.cfg  ║
║  for the partition layout template kept for later use.                 ║
║                                                                        ║
║  Buildroot output (output/images/):                                    ║
║    boot.bin         U-Boot SPL (rename to BOOT.BIN on the card)        ║
║    u-boot.img       U-Boot proper                                      ║
║    uImage           Linux kernel                                       ║
║    zybo-audio.dtb   device tree                                        ║
║    rootfs.ext2      ext4 root filesystem                               ║
║    rootfs.tar       root filesystem as a tar archive                   ║
║                                                                        ║
║  Manual assembly:                                                      ║
║    1. Create FAT32 (>=64MB) + ext4 (>=256MB) partitions                ║
║    2. Copy to FAT32: BOOT.BIN, u-boot.img, uImage, zybo-audio.dtb      ║
║    3. Extract to ext4:                                                 ║
║         sudo tar -xf rootfs.tar -C /mount/point                        ║
║                                                                        ║
║  The release sdcard.img is assembled by the zybo-debian repository.    ║
║                                                                        ║
║  On ZYBO Rev B:                                                        ║
║    Boot mode jumpers: JP4 -> SD boot (silkscreen 1-0-0-0)              ║
║                                                                        ║
╚════════════════════════════════════════════════════════════════════════╝

EOF
}

# ── Main ──────────────────────────────────────────────────────────────────
case "${1:-help}" in
    setup)
        check_deps
        clone_buildroot
        setup_defconfig
        info "Setup complete. Now run: ./buildroot_setup.sh build"
        ;;
    build)
        do_build
        ;;
    rebuild)
        do_rebuild
        ;;
    clean)
        do_clean
        ;;
    sd-card)
        do_sd_card
        ;;
    *)
        echo "Usage: $0 {setup|build|rebuild|clean|sd-card}"
        echo ""
        echo "  setup    — Clone Buildroot 2026.02.3 + create defconfig"
        echo "  build    — Full build (kernel + u-boot + rootfs)"
        echo "  rebuild  — Incremental rebuild (kernel + rootfs only)"
        echo "  clean    — Clean build artifacts"
        echo "  sd-card  — SD card assembly notes"
        echo ""
        echo "Workflow:"
        echo "  1. ./buildroot_setup.sh setup"
        echo "  2. ./buildroot_setup.sh build"
        echo "  3. ./buildroot_setup.sh sd-card"
        exit 1
        ;;
esac
