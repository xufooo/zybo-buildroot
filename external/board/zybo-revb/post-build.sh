#!/bin/sh
# ============================================================================
# post-build.sh — ZYBO Rev B 音频：写入 ALSA 默认设备配置
# ============================================================================
# Buildroot 调用约定：$1 = TARGET_DIR（rootfs 的 target 目录）
# 只做一件必要的事：写 /etc/asound.conf（44.1k 素材靠 plug 重采样到 48k，
# 因为 codec MCLK 固定 12.288MHz = 256×48kHz）。
# ============================================================================
set -e

TARGET_DIR="${1:?usage: post-build.sh TARGET_DIR}"

mkdir -p "${TARGET_DIR}/etc"
cat > "${TARGET_DIR}/etc/asound.conf" << 'EOF'
# 默认 PCM：软件重采样到 48kHz / S24_LE / 2ch（MCLK 固定 12.288MHz）
pcm.!default {
    type plug
    slave {
        pcm "hw:0,0"
        rate 48000
        format S24_LE
        channels 2
    }
}

ctl.!default {
    type hw
    card 0
}
EOF
