# Third-party components (THIRD-PARTY)

This repository holds the Buildroot `BR2_EXTERNAL` tree and build scripts for a
ZYBO (Zynq-7000) audio-player root filesystem. No binary images, kernels or
U-Boot builds are stored here; they are produced by
`.github/workflows/build-rootfs.yml` (or locally by `buildroot_setup.sh`) from
the pinned upstream sources below.

## Components

| Component | Version / ref | License | Source |
|---|---|---|---|
| Buildroot | `2026.02.3` (commit `679b9ead7620bbf193620d1ebf56f53c1764d37a`) | GPL-2.0-or-later | <https://github.com/buildroot/buildroot> |
| U-Boot | `v2024.01` (commit `866ca972d6c3cabeaf6dbac431e8e08bb30b3c8e`) | GPL-2.0-or-later | <https://source.denx.de/u-boot/u-boot.git> |
| Linux kernel (`Xilinx/linux-xlnx`) | tag `xlnx_rebase_v6.6_LTS_2024.1_merge_6.6.80` (commit `e29e392a451244a11aa3559738b6617536fde460`) | GPL-2.0-only, with the Linux syscall note | <https://github.com/Xilinx/linux-xlnx> |
| Bootlin external toolchain | `armv7-eabihf--glibc--stable` | toolchain licenses (GPL/LGPL with the usual toolchain exceptions) | <https://toolchains.bootlin.com/> |
| Root-filesystem packages (`busybox`, `alsa-utils`, `i2c-tools`, ...) | as selected by `external/configs/zybo_revb_audio_defconfig` in Buildroot 2026.02.3 | per package (mostly GPL-2.0-or-later, LGPL-2.1-or-later, MIT/BSD) | upstream projects; Buildroot records the exact tarball URLs and hashes |
| FSBL (built with the scripts in `fsbl/`) | Vivado 2024.1 `embeddedsw` | MIT (per-file SPDX) | <https://github.com/Xilinx/embeddedsw> |
| This repository (external tree, defconfig, kernel fragment, DTS, scripts) | — | GPL-2.0 (see `LICENSE`) | this repository |
| PL bitstream | — | **not distributed** | see below |

Buildroot, U-Boot and the kernel are pinned to the commit SHAs above, not to
tags: a tag can be re-pointed or deleted upstream, a commit SHA cannot. The
mapping was resolved with `git ls-remote` (the tags are annotated, so the
`refs/tags/<tag>^{}` line gives the commit):

```
git ls-remote https://github.com/buildroot/buildroot.git 'refs/tags/2026.02.3^{}'
git ls-remote https://source.denx.de/u-boot/u-boot.git  'refs/tags/v2024.01^{}'
git ls-remote https://github.com/Xilinx/linux-xlnx.git \
    'refs/tags/xlnx_rebase_v6.6_LTS_2024.1_merge_6.6.80^{}'
```

`BR2_TARGET_UBOOT_CUSTOM_REPO_VERSION` and
`BR2_LINUX_KERNEL_CUSTOM_REPO_VERSION` accept any git revision, a commit SHA
included (`boot/uboot/Config.in`, `linux/Config.in`).

## Corresponding source (GPL-2.0 / GPL-2.0-or-later)

Binaries produced from this repository (U-Boot inside `BOOT.BIN`, the kernel
inside `uImage`, and the root filesystem built by Buildroot) contain
GPL-licensed programs. The complete corresponding source is:

1. the upstream sources at the pinned commits above; Buildroot
   `679b9ead7620bbf193620d1ebf56f53c1764d37a` records the exact tarball URL and
   hash of every package it downloads (into `br2-dl/`), and the resolved
   configuration is `output/.config`;
2. every file in this repository (`external/**`, `buildroot_setup.sh`,
   `make_bootbin.sh`, `fsbl/**`, `fit/**`), which includes the U-Boot `.config`
   generated from `external/configs/zybo_revb_audio_defconfig`;
3. for the kernel, the `zybo-linux` repository together with the linux-xlnx
   commit above.

Written offers for the corresponding source, as allowed by GPL-2.0 section 3(b),
can be requested through the repository issue tracker.

Buildroot itself is a build tool: it is cloned at build time and is not
redistributed by this repository.

## Not distributed

The PL bitstream, `BOOT.BIN`, the kernel/U-Boot images and the root-filesystem
image are not stored in this repository and are not published as releases.
Building the FSBL requires a valid Vivado 2024.1 installation; Vivado and bootgen
are proprietary (Xilinx EULA) and are not redistributed. Distributing a bitstream
is additionally subject to the Xilinx EULA device restrictions and to the
licenses of the HDL it contains.
