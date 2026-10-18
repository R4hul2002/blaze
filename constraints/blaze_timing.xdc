# =============================================================================
# blaze_timing.xdc — Master Timing Constraints
# Project  : BLAZE NGFW
# Target   : AMD Xilinx Artix-7 XC7A200T (AX7203)
# =============================================================================

# =============================================================================
# Primary Clocks
# =============================================================================

# 200 MHz differential system clock (AX7203 onboard oscillator)
create_clock -period 5.000 -name clk_200m \
  [get_ports sys_clk_p]

# RGMII RX clock from PHY (125 MHz for 1G, 25 MHz for 100M, 2.5 MHz for 10M)
create_clock -period 8.000 -name rgmii_rxc \
  [get_ports {rgmii_rxc[*]}]

# =============================================================================
# Generated Clocks (MMCM outputs — defined after MMCM instantiation)
# =============================================================================

# 125 MHz core clock (datapath)
# create_generated_clock -name clk_125m -source [get_pins mmcm_inst/CLKIN1] \
#   -multiply_by 5 -divide_by 8 [get_pins mmcm_inst/CLKOUT0]

# 200 MHz reference clock for IDELAYCTRL
# create_generated_clock -name clk_200m_ref -source [get_pins mmcm_inst/CLKIN1] \
#   -multiply_by 1 -divide_by 1 [get_pins mmcm_inst/CLKOUT1]

# =============================================================================
# RGMII Input Timing (relative to RGMII RX clock)
# =============================================================================
# RGMII spec: data valid 1.0 ns before and 1.0 ns after clock edge
set_input_delay -clock rgmii_rxc -max  1.8 [get_ports {rgmii_rxd[*] rgmii_rx_ctl}]
set_input_delay -clock rgmii_rxc -min -0.8 [get_ports {rgmii_rxd[*] rgmii_rx_ctl}]
set_input_delay -clock rgmii_rxc -max  1.8 -clock_fall \
  [get_ports {rgmii_rxd[*] rgmii_rx_ctl}] -add_delay
set_input_delay -clock rgmii_rxc -min -0.8 -clock_fall \
  [get_ports {rgmii_rxd[*] rgmii_rx_ctl}] -add_delay

# =============================================================================
# RGMII Output Timing
# =============================================================================
set_output_delay -clock rgmii_rxc -max  1.0 [get_ports {rgmii_txd[*] rgmii_tx_ctl rgmii_txc}]
set_output_delay -clock rgmii_rxc -min -1.0 [get_ports {rgmii_txd[*] rgmii_tx_ctl rgmii_txc}]

# =============================================================================
# Clock Domain Crossings
# =============================================================================
# RGMII RX -> Core clock (handled by async FIFOs in MAC)
set_false_path -from [get_clocks rgmii_rxc] -to [get_clocks clk_125m]
set_false_path -from [get_clocks clk_125m]  -to [get_clocks rgmii_rxc]

# =============================================================================
# I/O Standards (AX7203 specific)
# =============================================================================
# RGMII pins use HSTL_I_18 or LVCMOS18 depending on PHY VDD
# Uncomment and adjust after pin assignment:
# set_property IOSTANDARD LVCMOS33 [get_ports {rgmii_rxd[*]}]
# set_property IOSTANDARD LVCMOS33 [get_ports {rgmii_txd[*]}]
# set_property IOSTANDARD LVCMOS33 [get_ports rgmii_rxc]
# set_property IOSTANDARD LVCMOS33 [get_ports rgmii_txc]
# set_property IOSTANDARD LVCMOS33 [get_ports rgmii_rx_ctl]
# set_property IOSTANDARD LVCMOS33 [get_ports rgmii_tx_ctl]

# =============================================================================
# Multicycle Paths (pipeline registers with known latency)
# =============================================================================
# ACL TCAM lookup: 2-cycle path
# set_multicycle_path 2 -setup -from [get_cells acl_engine/tcam_*] \
#   -to [get_cells acl_engine/result_reg*]

# =============================================================================
# False Paths
# =============================================================================
# Configuration registers written by MicroBlaze (slow path)
set_false_path -from [get_cells -hierarchical -filter {NAME =~ *axil_reg*}]

# =============================================================================
# Timing Exceptions for Reset
# =============================================================================
set_false_path -from [get_ports rst_n]

# =============================================================================
# Max Delay on Async Signals
# =============================================================================
set_max_delay 5.0 -datapath_only \
  -from [get_cells -hierarchical -filter {NAME =~ *cdc_sync*}]
