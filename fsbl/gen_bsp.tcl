# ============================================================================
# gen_bsp.tcl — Generate the FSBL BSP from our own XSA with the official
# Xilinx HSI built into xsdb.
# ============================================================================
# Rationale: the FSBL xparameters.h is **hardware dependent** (UART/SDIO clocks,
# SD card detect pin, DDR ranges, ...). Borrowing the BSP of another board
# (zc702/zc706/zed) pulls in that board's parameters — e.g. a 50 MHz
# UART/SDIO clock where our hardware runs at 100 MHz.
# The HSI built into xsdb can generate a correct standalone BSP from the XSA
# without a Vitis installation.
#
# Generate only, never compile (-compile would run the HSI's own make, which
# does not pass the toolchain variables and fails); compilation is left to the
# official Xilinx BSP makefile shipped with embeddedsw
# (sw_apps/zynq_fsbl/misc/makefile).
#
# Inputs (environment variables): ZYBO_XSA=XSA path, ZYBO_BSP_OUT=output dir
# Output: <ZYBO_BSP_OUT>/ps7_cortexa9_0/{include,libsrc,...}
# ============================================================================
set xsa $::env(ZYBO_XSA)
set out $::env(ZYBO_BSP_OUT)

puts "== HSI: open_hw_design $xsa"
hsi::open_hw_design $xsa

puts "== HSI: create_sw_design zynq_fsbl_bsp (ps7_cortexa9_0 / standalone)"
hsi::create_sw_design zynq_fsbl_bsp -proc ps7_cortexa9_0 -os standalone

puts "== HSI: generate_bsp -> $out"
hsi::generate_bsp -dir $out

puts "== HSI: done (BSP generated; the official makefile compiles it next)"
