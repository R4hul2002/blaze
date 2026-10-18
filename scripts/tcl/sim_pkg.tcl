# =============================================================================
# sim_pkg.tcl — Simulate blaze_pkg testbench using Vivado xsim
# Project  : BLAZE NGFW
# Usage    : vivado -mode batch -source scripts/tcl/sim_pkg.tcl
# =============================================================================

set SCRIPT_DIR [file dirname [file normalize [info script]]]
set ROOT_DIR   [file normalize "$SCRIPT_DIR/../.."]
set SIM_DIR    "$ROOT_DIR/sim"

file mkdir $SIM_DIR

# Compile package files
set pkg_files [list \
  "$ROOT_DIR/rtl/pkg/blaze_pkg.sv" \
  "$ROOT_DIR/rtl/pkg/axis_if.sv"   \
  "$ROOT_DIR/rtl/pkg/axil_if.sv"   \
  "$ROOT_DIR/rtl/pkg/axi4_if.sv"   \
  "$ROOT_DIR/rtl/pkg/meta_if.sv"   \
  "$ROOT_DIR/tb/pkg/tb_blaze_pkg.sv" \
]

# xvlog compile
foreach f $pkg_files {
  exec xvlog --sv $f -work work 2>@stdout
}

# Elaborate
exec xelab -debug typical work.tb_blaze_pkg -s tb_blaze_pkg_sim 2>@stdout

# Simulate
exec xsim tb_blaze_pkg_sim --runall 2>@stdout

puts "INFO: Simulation complete. Check output above for PASS/FAIL."
