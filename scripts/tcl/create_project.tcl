# =============================================================================
# create_project.tcl — Vivado Project Creation Script
# Project  : BLAZE NGFW
# Target   : AMD Xilinx Artix-7 XC7A200T (AX7203 board)
# Toolchain: Vivado 2023.x
# =============================================================================
# Usage: vivado -mode batch -source scripts/tcl/create_project.tcl
# =============================================================================

set PROJ_NAME   "blaze_ngfw"
set PROJ_DIR    "[file normalize ../../vivado]"
set PART        "xc7a200tfbg484-2"
set BOARD       ""
set TOP_MODULE  "blaze_top"

# Source root (relative to this script)
set SCRIPT_DIR  [file dirname [file normalize [info script]]]
set ROOT_DIR    [file normalize "$SCRIPT_DIR/../.."]

# Create project
create_project $PROJ_NAME $PROJ_DIR -part $PART -force

set_property target_language SystemVerilog [current_project]
set_property simulator_language Mixed      [current_project]
set_property default_lib work              [current_project]

# =============================================================================
# Add RTL Sources
# =============================================================================
proc add_rtl_dir {dir} {
  set files [glob -nocomplain -directory $dir "*.sv" "*.v"]
  if {[llength $files] > 0} {
    add_files -norecurse $files
  }
}

# Package files (compile first)
add_rtl_dir "$ROOT_DIR/rtl/pkg"

# Pipeline stages
foreach subdir {mac parser session acl dpi nat qos logging control} {
  add_rtl_dir "$ROOT_DIR/rtl/$subdir"
}

# Top level
set top_files [glob -nocomplain "$ROOT_DIR/rtl/*.sv" "$ROOT_DIR/rtl/*.v"]
if {[llength $top_files] > 0} {
  add_files -norecurse $top_files
}

# =============================================================================
# Add Constraints
# =============================================================================
set xdc_files [glob -nocomplain "$ROOT_DIR/constraints/*.xdc"]
if {[llength $xdc_files] > 0} {
  add_files -fileset constrs_1 -norecurse $xdc_files
}

# =============================================================================
# Add IP (verilog-ethernet)
# =============================================================================
set ip_files [glob -nocomplain "$ROOT_DIR/ip/verilog-ethernet/rtl/*.v"]
if {[llength $ip_files] > 0} {
  add_files -norecurse $ip_files
}

# =============================================================================
# Simulation Sources
# =============================================================================
set_property SOURCE_SET sources_1 [get_filesets sim_1]
set tb_files [glob -nocomplain -directory "$ROOT_DIR/tb" -type f "**/*.sv"]
if {[llength $tb_files] > 0} {
  add_files -fileset sim_1 -norecurse $tb_files
}

# =============================================================================
# Compile Order — package first
# =============================================================================
set_property file_type {SystemVerilog} [get_files -filter {FILE_TYPE == SystemVerilog}]

# Force package files to compile first
foreach pkg_file [glob -nocomplain "$ROOT_DIR/rtl/pkg/*.sv"] {
  set_property is_global_include true [get_files $pkg_file]
}

# =============================================================================
# Synthesis Settings
# =============================================================================
set_property strategy "Vivado Synthesis Defaults" [get_runs synth_1]
set_property STEPS.SYNTH_DESIGN.ARGS.FLATTEN_HIERARCHY rebuilt [get_runs synth_1]
set_property STEPS.SYNTH_DESIGN.ARGS.KEEP_EQUIVALENT_REGISTERS true [get_runs synth_1]
set_property STEPS.SYNTH_DESIGN.ARGS.RESOURCE_SHARING off [get_runs synth_1]

# =============================================================================
# Implementation Settings
# =============================================================================
set_property strategy "Performance_ExplorePostRoutePhysOpt" [get_runs impl_1]

# =============================================================================
# Top Module
# =============================================================================
# Will be set once blaze_top.sv is created
# set_property top $TOP_MODULE [current_fileset]

puts "INFO: Project $PROJ_NAME created at $PROJ_DIR"
puts "INFO: Part: $PART"
puts "INFO: RTL sources loaded from $ROOT_DIR/rtl"
