# zybo-buildroot

Buildroot rootfs for a ZYBO (Zynq-7000) audio player.

Builds a complete SD-card boot set on GitHub Actions from a `BR2_EXTERNAL`
tree kept in this repository.

## What it builds

| Item | Value |
|---|---|
| Buildroot | `2026.02.3` (LTS) |
| Toolchain | Bootlin prebuilt `armv7-eabihf--glibc--stable` (no self-built toolchain) |
| Kernel | Xilinx `linux-xlnx`, tag `xlnx_rebase_v6.6_LTS_2024.1_merge_6.6.80` |
| Device tree | `external/overlays/zybo-audio.dts` |
| U-Boot | v2024.01, `xilinx_zynq_virt` + `DEVICE_TREE=zynq-zybo`, SPL (`spl/boot.bin`) |
| Packages (phase 1) | `alsa-utils` (aplay / amixer / speaker-test), `i2c-tools` |
| Rootfs | ext4 + tar, rootfs overlay under `external/board/zybo-revb/` |

`BOOT.BIN` is the U-Boot SPL image (`boot.bin`); no FSBL/bootgen is required.
The PL bitstream is loaded by U-Boot from `uEnv.txt` via `fpga loadb`.

## CI artifacts

Artifact `linux-images`:

```
boot.bin        # = BOOT.BIN (U-Boot SPL)
u-boot.img      # U-Boot proper (SPL payload)
uImage          # kernel
zybo-audio.dtb  # device tree with audio nodes
rootfs.ext4     # root filesystem
rootfs.tar
```

## Layout

```
zybo-buildroot/
├── .github/workflows/build-rootfs.yml
├── external/                            # BR2_EXTERNAL tree
│   ├── configs/zybo_revb_audio_defconfig
│   ├── board/zybo-revb/                 # linux.fragment, post-build.sh
│   └── overlays/zybo-audio.dts
├── buildroot_setup.sh                   # local equivalent (setup / build / rebuild / clean)
└── make_bootbin.sh                      # assemble SD-card boot files (needs a bitstream)
```

## Assembling an SD card

```bash
# 1) download the CI artifact and unpack images/
# 2) combine the boot files with the PL bitstream from Vivado
./make_bootbin.sh --bit zybo_audio_wrapper.bit --images ./images --out ./sdcard-boot
# → sdcard-boot/{BOOT.BIN,u-boot.img,uImage,zybo-audio.dtb,system.bit,uEnv.txt}
# 3) copy the boot files to the FAT32 partition, write rootfs.ext4 to the ext4 partition
```

`make_bootbin.sh` generates `boot.scr` (a U-Boot script that `distro_bootcmd`
executes automatically): it loads `system.bit` with `fpga loadb`, then boots
`uImage` with `zybo-audio.dtb`. A minimal `uEnv.txt` is also written for
loaders that import it. `mkimage` is required (`uboot-tools`).

## Related

- Kernel build: [zybo-linux](https://github.com/xufooo/zybo-linux)
