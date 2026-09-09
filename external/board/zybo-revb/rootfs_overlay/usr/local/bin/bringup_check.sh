#!/bin/sh
# ============================================================================
# bringup_check.sh — ZYBO Rev B 音频上板自检（在板子上运行）
# ============================================================================
# 用法：把本脚本拷到 SD 卡 rootfs（或 scp）后执行：
#   sh /root/bringup_check.sh
# 作用：按"先出声"顺序逐项检查，输出 PASS/FAIL 与关键日志。
# ============================================================================

PASS=0; FAIL=0
ok()   { echo "[PASS] $*"; PASS=$((PASS+1)); }
bad()  { echo "[FAIL] $*"; FAIL=$((FAIL+1)); }
sec()  { echo; echo "===== $* ====="; }

sec "1. 内核与平台"
uname -a
cat /proc/device-tree/model 2>/dev/null; echo

sec "2. 内核音频驱动/模块"
for m in snd_soc_adi_axi_i2s snd_soc_ssm2602 snd_soc_simple_card; do
    if grep -q "^$m " /proc/modules 2>/dev/null || grep -q "$m" /lib/modules/$(uname -r)/modules.builtin 2>/dev/null; then
        ok "驱动存在: $m"
    else
        # 内置(=y)时 /proc/modules 里没有，属于正常，提示即可
        echo "[INFO] $m 未作为模块出现（可能已编译进内核）"
    fi
done
ls /sys/bus/platform/drivers/ 2>/dev/null | grep -iE 'adi|ssm|simple' || echo "[INFO] 无对应 platform driver 目录（内置驱动时常见）"

sec "3. I2C：codec SSM2603 @0x1A"
I2CBUS=$(i2cdetect -l 2>/dev/null | grep -iE 'xiic|i2c' | head -1 | awk '{print $1}' | sed 's/i2c-//')
if [ -n "$I2CBUS" ]; then
    echo "使用 I2C bus $I2CBUS"; i2cdetect -y "$I2CBUS" | tee /tmp/i2cdetect.out
    if grep -qE '(^| )1a( |$)' /tmp/i2cdetect.out; then ok "codec 0x1A 应答"; else bad "未见 0x1A（检查 BD I2C 连线/上拉/供电）"; fi
else
    bad "未找到 I2C 总线（axi_iic 驱动未加载？）"
fi

sec "4. 声卡与 PCM 设备"
aplay -l 2>&1 | tee /tmp/aplayl.out
if grep -qE 'card [0-9]' /tmp/aplayl.out; then ok "声卡已注册"; else bad "无 ALSA 声卡（检查 simple-card/DAI 绑定）"; fi
cat /proc/asound/cards 2>/dev/null
ls -l /dev/snd/ 2>/dev/null

sec "5. 播放测试（48kHz）"
if command -v speaker-test >/dev/null 2>&1; then
    echo "speaker-test 2 秒（48kHz 正弦，注意音量）..."
    timeout 5 speaker-test -D default -t sine -f 440 -r 48000 -c 2 -l 1 2>&1 | tail -8
    ok "speaker-test 已执行（听是否有声）"
else
    echo "[INFO] 无 speaker-test，改用 aplay"
fi

sec "6. 混音器"
amixer scontrols 2>&1 | head -8
amixer sget Master 2>&1 | head -4

sec "7. 录音测试（可选，5 秒）"
if command -v arecord >/dev/null 2>&1; then
    timeout 8 arecord -D default -f S16_LE -r 48000 -c 2 -d 5 /tmp/test.wav 2>&1 | tail -4
    [ -s /tmp/test.wav ] && ok "录音文件已生成: $(ls -l /tmp/test.wav | awk '{print $5}') bytes" || bad "录音失败"
else
    echo "[INFO] 无 arecord"
fi

sec "8. 内核日志要点"
dmesg 2>/dev/null | grep -iE 'ssm2602|axi-i2s|i2s|simple-card|asoc|xiic|i2c' | tail -15

sec "结果"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && echo ">>> 基本检查通过；若 speaker-test 无声，请检查耳机/音量与 ac_muten" \
                  || echo ">>> 有失败项，请把上面输出贴回排查"
