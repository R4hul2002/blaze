# BLAZE NGFW — Synthesis Setup Complete

**Date:** August 4, 2026  
**Synthesis Tool:** Yosys 0.68+post  
**Status:** Tools installed, scripts created

---

## Tools Installed

✅ **Yosys 0.68+post** - Open synthesis suite  
  - Location: `/opt/homebrew/bin/yosys`
  - Compiler: AppleClang clang++ 21.0.0
  - Features: SystemVerilog support, ABC optimization, LUT mapping

✅ **Dependencies**
  - libtommath 1.3.0
  - tcl-tk 9.0.4
  - tomlplusplus 3.4.0
  - yosys-abc (logic optimization)

---

## Synthesis Scripts Created

### 1. Master Synthesis Script
**Location:** `scripts/yosys/synth_all.sh`

Orchestrates synthesis of all major modules:
- ACL Engine
- Parser modules (frame, IPv4, TCP, etc.)
- Session modules (flow_hash, flow_table)

### 2. Module-Specific Scripts

#### ACL Engine (`scripts/yosys/synth_acl.ys`)
```tcl
read_verilog -sv rtl/pkg/blaze_pkg.sv
read_verilog -sv rtl/acl/acl_engine.sv
hierarchy -check -top acl_engine
proc; opt; fsm; opt; memory; opt;
techmap; opt;
alumacc; share; opt;
abc -lut 6; clean;
stat;
```

#### Parser Modules (`scripts/yosys/synth_parsers.ys`)
- frame_parser
- ipv4_parser  
- tcp_parser
- All L2/L3/L4 parsers

#### Session Modules (`scripts/yosys/synth_session.ys`)
- flow_hash (CRC32-based hash engine)
- flow_table (flow state management)

---

## Known Issues & Compatibility

### SystemVerilog Compatibility
Yosys has partial SystemVerilog support. Some constructs may require modification:

1. ✅ **Fixed:** `priority` keyword conflict in `rule_entry_t`
   - Changed `logic [31:0] priority` → `rule_priority`
   
2. ⚠️ **Limitation:** Complex packed structs with nested types
   - Yosys parser may have issues with deeply nested structures
   - Consider flattening for synthesis

3. ⚠️ **Limitation:** Some SystemVerilog-2012 features
   - Interfaces may need to be converted to port lists
   - `unique`/`priority` case statements may need simplification

---

## RTL Modules Available for Synthesis

### Core Modules
- ✓ `blaze_top.sv` - Top-level integration (complex, many dependencies)
- ✓ `acl_engine.sv` - Firewall rule engine (1024 rules, BRAM-based)

### Parser Chain  
- ✓ `frame_parser.sv` - Ethernet frame parsing
- ✓ `vlan_parser.sv` - VLAN tag extraction
- ✓ `ipv4_parser.sv` - IPv4 header parsing
- ✓ `ipv6_parser.sv` - IPv6 header parsing  
- ✓ `arp_parser.sv` - ARP packet handling
- ✓ `tcp_parser.sv` - TCP header + flags
- ✓ `udp_parser.sv` - UDP header
- ✓ `icmp_parser.sv` - ICMP parsing
- ✓ `dns_parser.sv` - DNS tunneling detection
- ✓ `http_parser.sv` - HTTP URL extraction
- ✓ `tls_parser.sv` - TLS SNI extraction

### Session & Flow
- ✓ `flow_hash.sv` - 5-tuple hash (CRC32, symmetric)
- ✓ `flow_table.sv` - Flow state table

### Control & Data Path
- ✓ `dos_protect.sv` - DoS/DDoS mitigation
- ✓ `nat_engine.sv` - NAT translation
- ✓ `qos_shaper.sv` - 16-queue token bucket QoS
- ✓ `stats_logger.sv` - Statistics collection

### MAC & PHY
- ✓ `blaze_mac_wrapper.sv` - MAC wrapper (uses verilog-ethernet IP)
- ✓ `rgmii_phy_if.sv` - RGMII PHY interface

---

## Synthesis Workflow

### Quick Start
```bash
cd /Users/rahul/Documents/sphericsx/blaze

# Make script executable
chmod +x scripts/yosys/synth_all.sh

# Run synthesis
./scripts/yosys/synth_all.sh
```

### Individual Module Synthesis
```bash
# ACL Engine only
yosys -s scripts/yosys/synth_acl.ys

# Parsers only
yosys -s scripts/yosys/synth_parsers.ys

# Session modules only
yosys -s scripts/yosys/synth_session.ys
```

### Output Files
All synthesis outputs go to `synth_out/`:
- `*_synth.v` - Synthesized Verilog netlist
- `*_synth.json` - JSON netlist (for nextpnr, etc.)
- `*_stats.txt` - Resource utilization statistics
- `*.log` - Full synthesis logs

---

## Target FPGAs

### Primary Target
**Artix-7 XC7A200T** (AX7203 board)
- 215,360 logic cells
- 13,140 Kbit block RAM
- 740 DSP slices
- Max 450 MHz performance

### Yosys Synthesis Options

#### Generic FPGA (default)
```tcl
abc -lut 6  # 6-input LUT mapping
```

#### Xilinx 7-Series Specific
```tcl
synth_xilinx -top module_name
```

#### Intel/Altera
```tcl
synth_intel -top module_name
```

#### ECP5 (Lattice)
```tcl
synth_ecp5 -top module_name
```

---

## Next Steps for Full Synthesis

### 1. Resolve SystemVerilog Compatibility
- Test individual modules with current Yosys
- Convert interfaces to explicit port connections if needed
- Flatten complex packed structs if parser fails

### 2. Use Vivado for Full Artix-7 Synthesis
Since the target is Xilinx Artix-7, Vivado provides:
- Full SystemVerilog-2012 support
- Xilinx-specific optimizations (BRAM, DSP, carry chains)
- Timing analysis and constraints
- Bitstream generation

```bash
# Vivado synthesis (if available)
vivado -mode batch -source scripts/tcl/synth_vivado.tcl
```

### 3. Hybrid Approach
- Use Yosys for logic optimization and exploration
- Use Vivado for final FPGA-specific synthesis
- Compare results for optimization opportunities

---

## Alternative: Verilator for RTL Verification

If full synthesis encounters issues, use Verilator for RTL lint/simulation:

```bash
# Install Verilator
brew install verilator

# Lint check
verilator --lint-only -Wall \
  -Irtl/pkg \
  rtl/pkg/blaze_pkg.sv \
  rtl/acl/acl_engine.sv

# Generate C++ testbench
verilator --cc --exe --build \
  -Irtl/pkg \
  rtl/acl/acl_engine.sv \
  tb/acl_engine_tb.cpp
```

---

## Resource Estimation (Preliminary)

Based on RTL analysis and similar designs:

### ACL Engine (1024 rules)
- LUTs: ~2,500
- FFs: ~1,200  
- BRAMs: 16 (rule storage)
- Max freq: ~250 MHz

### Parser Chain (all parsers)
- LUTs: ~8,000
- FFs: ~4,000
- BRAMs: 4 (packet buffer)
- Max freq: ~200 MHz

### Flow Table (16K entries)
- LUTs: ~3,000
- FFs: ~2,500
- BRAMs: 64
- Max freq: ~300 MHz

### Total Estimated (full BLAZE)
- LUTs: ~45,000 (21% of XC7A200T)
- FFs: ~25,000 (6% of XC7A200T)
- BRAMs: 120 (43% of XC7A200T)
- DSPs: 8 (for CRC, hash)
- Target Freq: 125 MHz (8ns period)

---

## Synthesis Optimization Flags

### For Area
```tcl
opt -full
opt_clean -purge
```

### For Speed
```tcl
abc -fast
opt -fast
```

### For Power
```tcl
opt_clean
memory_map -mode regs  # Use regs instead of BRAM where beneficial
```

---

## References

- Yosys Manual: http://yosyshq.net/yosys/documentation.html
- Yosys Commands: http://yosyshq.net/yosys/cmd_ref.html
- SystemVerilog Synthesis: https://github.com/YosysHQ/yosys#SystemVerilog-support
- Xilinx 7-Series Libraries: UG953 (Vivado Synthesis Guide)

---

*Setup completed: August 4, 2026*  
*Yosys version: 0.68+post*  
*Ready for synthesis workflow integration*
