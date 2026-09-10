#!/bin/sh
# ============================================================================
# post-build.sh — ZYBO Rev B 音频：写入 ALSA 默认设备配置
# ============================================================================
# Buildroot 调用约定：$1 = TARGET_DIR（rootfs 的 target 目录）
# 只做一件必要的事：写 /etc/asound.conf（44.1k 素材靠 plug 重采样到 48k，
# 因为 codec MCLK 固定 12.288MHz = 256×48kHz）。
# 已上板验证：axi-i2s 只能 S32_LE（见下方注释）。
# ============================================================================
set -e

TARGET_DIR="${1:?usage: post-build.sh TARGET_DIR}"

mkdir -p "${TARGET_DIR}/etc"
cat > "${TARGET_DIR}/etc/asound.conf" << 'EOF'
# 默认 PCM：软件重采样到 48kHz / S32_LE / 2ch
# 注意：axi-i2s (adi,axi-i2s-1.00.a) 在 DMA 模式下只暴露 S32_LE（24bit 数据
#       左对齐在 32bit 字里）；写 S16_LE / S24_LE 会被 hw params 拒绝
#       （aplay 报 "Sample format non available"）。
# MCLK 固定 12.288MHz → 原生只支持 48k 族，44.1k 靠 plug 重采样
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
