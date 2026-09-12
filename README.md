# zybo-buildroot

Buildroot rootfs for a ZYBO (Zynq-7000) audio player.

Builds a complete SD-card boot set — U-Boot SPL, U-Boot, kernel, device tree and
root filesystem — from the `BR2_EXTERNAL` tree in this repository. The PL
bitstream comes from Vivado and is added when the SD card is assembled.

## What it builds

| Item | Value |
|---|---|
| Buildroot | `2026.02.3` (LTS), cloned at build time |
| Toolchain | Bootlin prebuilt external toolchain, `armv7-eabihf--glibc--stable` |
| Kernel | Xilinx `linux-xlnx`, tag `xlnx_rebase_v6.6_LTS_2024.1_merge_6.6.80` |
| Kernel config | `xilinx_zynq_defconfig` + `external/board/zybo-revb/linux.fragment` |
| Device tree | `external/overlays/zybo-audio.dts` |
| U-Boot | `v2024.01`, board `xilinx_zynq_virt` with `DEVICE_TREE=zynq-zybo`, SPL enabled |
| Packages | `alsa-utils` (aplay, amixer, speaker-test) and `i2c-tools` |
| Root filesystem | ext4 (256 MB) and tar |

`BOOT.BIN` is the U-Boot SPL image (`spl/boot.bin`); no FSBL or bootgen is
required. The PL bitstream is loaded by U-Boot from the boot script
(`fpga loadb`).

## Layout

```
.github/workflows/build-rootfs.yml      # CI: Buildroot build + artifacts
buildroot_setup.sh                      # local setup/build helper
make_bootbin.sh                         # assemble the SD-card boot files
external/                               # BR2_EXTERNAL tree
  external.desc  Config.in  external.mk
  configs/zybo_revb_audio_defconfig     # defconfig
  board/zybo-revb/                      # linux.fragment, post-build.sh, genimage.cfg
  overlays/zybo-audio.dts               # audio device tree
```

`external/overlays/zybo-audio.dts` and `external/board/zybo-revb/linux.fragment`
are copies of the canonical files in `zybo-linux`; CI fails if they drift.

## Requirements

- Linux host with the Buildroot host dependencies: `bc`, `bison`,
  `build-essential`, `cpio`, `file`, `flex`, `git`, `libncurses-dev`,
  `libssl-dev`, `python3`, `rsync`, `unzip`, `wget`
- `tar` 1.35 or newer
- `mkimage` (`uboot-tools`) to generate the boot script
- A bitstream from Vivado (`*_wrapper.bit`) for the final boot set

## Build

```bash
./buildroot_setup.sh setup     # clone Buildroot + apply the defconfig
./buildroot_setup.sh build     # build kernel, U-Boot and root filesystem
./buildroot_setup.sh rebuild   # rebuild kernel + root filesystem only
./buildroot_setup.sh clean     # remove the build tree
```

Buildroot is cloned into `./buildroot` and images land in
`buildroot/output/images/`. The equivalent manual steps are:

```bash
git clone --depth 1 --branch 2026.02.3 https://github.com/buildroot/buildroot.git buildroot
cd buildroot
make BR2_EXTERNAL=../external zybo_revb_audio_defconfig
make -j"$(nproc)"
```

## CI

`.github/workflows/build-rootfs.yml` runs on `workflow_dispatch` and on pushes
that touch `external/**` or `buildroot_setup.sh`. The `linux-images` artifact
holds `output/images/`:

```
boot.bin        # BOOT.BIN — U-Boot SPL
u-boot.img      # U-Boot proper
uImage          # kernel
zybo-audio.dtb  # device tree with the audio nodes
rootfs.ext2     # ext4 root filesystem (rootfs.ext4 is a symlink to it)
rootfs.tar      # root filesystem as a tar archive
```

## Assembling an SD card

`make_bootbin.sh` copies the boot images next to a bitstream and generates the
U-Boot boot script:

```bash
./make_bootbin.sh --bit zybo_audio_wrapper.bit \
                  --images ./buildroot/output/images \
                  --out ./sdcard-boot
# sdcard-boot/
#   BOOT.BIN  u-boot.img  uImage  zybo-audio.dtb  system.bit  boot.scr  uEnv.txt
```

`boot.scr` is the script U-Boot's `distro_bootcmd` executes automatically: it
loads `system.bit` with `fpga loadb` and then boots `uImage` with
`zybo-audio.dtb`. `uEnv.txt` is written as a fallback for loaders that import it.

Write both partitions of the card:

1. FAT32 boot partition: copy everything from `sdcard-boot/`.
2. ext4 root partition: write `rootfs.ext4`, or unpack the tar with
   `sudo tar -xpf rootfs.tar -C /mnt/root`.

Boot arguments used by the script:

```
console=ttyPS0,115200 root=/dev/mmcblk0p2 rootwait rw
```

`external/board/zybo-revb/genimage.cfg` holds a two-partition layout template
(FAT32 boot + ext4 root); genimage is not currently enabled in the defconfig.

## Related repositories

- Kernel: [zybo-linux](https://github.com/xufooo/zybo-linux)
- Debian rootfs: [zybo-debian](https://github.com/xufooo/zybo-debian)
