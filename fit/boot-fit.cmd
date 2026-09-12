# ZYBO Rev B audio player boot script (FIT form)
# Unlike the legacy form, the kernel and the device tree are no longer two files
# and the dtb address is no longer passed by hand: both live inside fit.itb
# (bootm relocates them using the load addresses recorded in the FIT).
echo "== ZYBO audio: loading FPGA bitstream =="
fatload mmc 0:1 0x100000 system.bit
fpga loadb 0 0x100000 ${filesize}

echo "== ZYBO audio: loading FIT (kernel + dtb) =="
fatload mmc 0:1 0x2000000 fit.itb
setenv bootargs console=ttyPS0,115200 root=/dev/mmcblk0p2 rootwait rw
bootm 0x2000000
