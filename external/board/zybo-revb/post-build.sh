#!/bin/sh
# ============================================================================
# post-build.sh — ZYBO Rev B audio: install the default ALSA device configuration
# ============================================================================
# Buildroot calling convention: $1 = TARGET_DIR (the rootfs target directory)
# It does one necessary thing: write /etc/asound.conf (44.1k material is resampled
# to 48k through plug, because the codec MCLK is fixed at 12.288MHz = 256 x 48kHz).
# Verified on the board: axi-i2s only exposes S32_LE (see the comments below).
# ============================================================================
set -e

TARGET_DIR="${1:?usage: post-build.sh TARGET_DIR}"

mkdir -p "${TARGET_DIR}/etc"
cat > "${TARGET_DIR}/etc/asound.conf" << 'EOF'
# Default PCM: software resample to 48kHz / S32_LE / 2ch
# Note: in DMA mode axi-i2s (adi,axi-i2s-1.00.a) exposes only S32_LE (24-bit data
#       left-aligned in a 32-bit word); requesting S16_LE / S24_LE is rejected by
#       hw params (aplay reports "Sample format non available").
# MCLK is fixed at 12.288MHz -> only the 48k family is native; 44.1k goes through plug resampling
pcm.!default {
    type plug
    slave {
        pcm "hw:0,0"
        rate 48000
        format S32_LE
        channels 2
    }
}

ctl.!default {
    type hw
    card 0
}
EOF
