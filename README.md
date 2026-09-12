# zybo-buildroot

Buildroot **external tree** plus the boot-set/FSBL scripts for a ZYBO (Zynq-7000)
audio player. This repository does **not** contain Buildroot or U-Boot source (CI
clones them at pinned commits), and no PL bitstream or built image is tracked
here. It builds the kernel, device tree, U-Boot and root filesystem from
`external/`; the boot set is published in the **FSBL** form, and the U-Boot SPL
route (`boot.bin`) is kept as an optional/historical path.

## What it builds

| Item | Value |
|---|---|
| Buildroot | `2026.02.3` (commit `679b9ead7620bbf193620d1ebf56f53c1764d37a`), cloned at build time |
| Toolchain | Bootlin prebuilt external toolchain, `armv7-eabihf--glibc--stable` |
| Kernel | Xilinx `linux-xlnx`, commit `e29e392a451244a11aa3559738b6617536fde460` (tag `xlnx_rebase_v6.6_LTS_2024.1_merge_6.6.80`) |
| Kernel config | `xilinx_zynq_defconfig` + `external/board/zybo-revb/linux.fragment` |
| Device tree | `external/overlays/zybo-audio.dts` |
| U-Boot | commit `866ca972d6c3cabeaf6dbac431e8e08bb30b3c8e` (tag `v2024.01`), board `xilinx_zynq_virt` with `DEVICE_TREE=zynq-zybo`, SPL enabled |
| Packages | `alsa-utils` (aplay, amixer, speaker-test) and `i2c-tools` |
| Root filesystem | ext4 (256 MB) and tar |

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
git init --quiet buildroot
git -C buildroot remote add origin https://github.com/buildroot/buildroot.git
git -C buildroot fetch --depth 1 origin 679b9ead7620bbf193620d1ebf56f53c1764d37a
git -C buildroot checkout --detach FETCH_HEAD
cd buildroot
make BR2_EXTERNAL=../external zybo_revb_audio_defconfig
make -j"$(nproc)"
```

## CI

`.github/workflows/build-rootfs.yml` runs on `workflow_dispatch` and on pushes
that touch `external/**` or `buildroot_setup.sh`. The `linux-images` artifact
holds `output/images/`:

```
boot.bin        # U-Boot SPL image (used by the SPL boot route)
u-boot.img      # U-Boot proper
uImage          # kernel
zybo-audio.dtb  # device tree with the audio nodes
rootfs.ext2     # ext4 root filesystem (rootfs.ext4 is a symlink to it)
rootfs.tar      # root filesystem as a tar archive
```

## Assembling an SD card

`make_bootbin.sh` assembles the SPL-route boot set: it copies the boot images next
to a bitstream and generates the U-Boot boot script. The published FSBL form puts
`BOOT.BIN` (FSBL + bitstream + U-Boot), `uImage` and `boot.scr` on the boot
partition instead.

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

## License

This repository is licensed under the **GNU General Public License, version 2**
(GPL-2.0); see [LICENSE](LICENSE) for the full text. The components it builds
(U-Boot, the Linux kernel, Buildroot and the rootfs packages) keep their own
licenses, and their corresponding source is documented in
[THIRD-PARTY.md](THIRD-PARTY.md).

## Related repositories

- Kernel: [zybo-linux](https://github.com/xufooo/zybo-linux)
- Debian rootfs: [zybo-debian](https://github.com/xufooo/zybo-debian)
