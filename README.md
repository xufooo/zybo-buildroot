# zybo-buildroot — ZYBO Rev B 音频 Linux 根文件系统（Buildroot）

用 **GitHub Actions** 构建 Buildroot 镜像（BR2_EXTERNAL 板级配置在本仓库根目录）。

## 内容

```
zybo-buildroot/
├── .github/workflows/build-rootfs.yml   # Actions：Buildroot 2026.02.3 全量构建
├── external/                            # BR2_EXTERNAL 树
│   ├── configs/zybo_revb_audio_defconfig
│   ├── board/zybo-revb/                 # linux.fragment、post-build.sh、rootfs_overlay
│   └── overlays/zybo-audio.dts          # 音频 PL overlay（DMA/PL330/i2s/iic/sound）
├── buildroot_setup.sh                   # 本地等价流程（setup/build/rebuild/clean）
├── make_bootbin.sh                      # 组装 SD 卡启动文件（需本地 bitstream）
└── README.md
```

## Actions 产物（artifact `linux-images`）

`boot.bin`（=BOOT.BIN，U-Boot SPL）、`u-boot.img`、`uImage`、`zybo-audio.dtb`、
`rootfs.ext4`、`rootfs.tar`

## 关键配置

| 项 | 值 |
|---|---|
| Buildroot | **2026.02.3**（LTS；要求宿主 tar ≥1.35，runner ubuntu-24.04 满足） |
| 工具链 | **Bootlin 预编译** `armv7-eabihf--glibc--stable`（跳过自建 gcc/glibc） |
| 内核 | linux-xlnx **tag** `xlnx_rebase_v6.6_LTS_2024.1_merge_6.6.80`（与 Vivado 2024.1 配套） |
| U-Boot | v2024.01，`xilinx_zynq_virt` + `DEVICE_TREE=zynq-zybo`，SPL（`spl/boot.bin`） |
| 音频 | 主线 ASoC：`adi,axi-i2s`(PL330) + `ssm2602/2603` + `simple-audio-card` |
| Phase-1 包 | `alsa-utils`(aplay/amixer/speaker-test) + `i2c-tools` |

## 组装 SD 卡

```bash
# 1) 下载 Actions artifact 到本地（解压出 images/）
# 2) 用 FPGA 侧 bitstream 组装启动文件
./make_bootbin.sh --bit /path/to/zybo_audio_wrapper.bit --images /path/to/images --out ./sdcard-boot
# → sdcard-boot/{BOOT.BIN,u-boot.img,uImage,zybo-audio.dtb,system.bit,uEnv.txt}
# 3) 拷入 SD 卡 FAT32 分区（rootfs.ext4 写到 ext4 分区）
```

## 上板验证顺序

`i2cdetect` 见 0x1A（codec）→ `aplay -l` 见声卡 → `speaker-test -r 48000` →
44.1k 素材 `aplay`（`plug` 重采样）→ `arecord`。
