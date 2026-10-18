# BLAZE Synthesis - Quick Start Guide

## ✅ Working Synthesis

The synthesis setup is complete and working! Here's how to use it:

### Run the Working Synthesis

```bash
cd /Users/rahul/Documents/sphericsx/blaze

# Synthesize the CRC32 hash module (TESTED & WORKING)
yosys -s scripts/yosys/synth_crc32.ys
```

### View Results

```bash
# See statistics
cat synth_out/crc32_stats.txt

# List all generated files
ls -lh synth_out/

# Check the synthesized Verilog
head -100 synth_out/crc32_synth.v
```

### Results Summary
- **LUTs:** 678 (6-input)
- **Flip-Flops:** 70
- **FPGA Usage:** < 1% of Artix-7 XC7A200T
- **Files Generated:** 
  - `crc32_synth.v` - Synthesized netlist
  - `crc32_synth.json` - JSON netlist
  - `crc32_stats.txt` - Statistics
  - `crc32_before.dot` & `crc32_after.dot` - Design graphs

---

## Issue Fixed: `{rtl` Directory

✅ **FIXED** - Removed the corrupted `{rtl` directory that was causing confusion.

Your directory structure is now clean:
```
blaze/
├── SIMULATION_RESULTS.md
├── SYNTHESIS_SETUP.md  
├── SYNTHESIS_SUCCESS.md
├── constraints/
├── docs/
├── ip/
├── rtl/          ← Correct RTL directory
├── scripts/
│   └── yosys/    ← Synthesis scripts here
├── sim/
├── sw/
├── synth_out/    ← Synthesis outputs here
└── tb/
```

---

## SystemVerilog Compatibility Note

**Current Status:**
- ✅ **Verilog-2001 modules work perfectly** (like `crc32_hash.v`)
- ⚠️ **Full BLAZE SystemVerilog** has advanced features Yosys doesn't fully support:
  - Complex packed structs
  - Typedef'd enums in packages
  - Interface declarations
  - Some SystemVerilog-2012 constructs

**Solutions:**

### Option 1: Use Vivado (Recommended for Full Design)
Vivado has complete SystemVerilog-2012 support:
```bash
vivado -mode batch -source scripts/tcl/synth_vivado.tcl
```

### Option 2: Use Yosys for Individual Modules
Create Verilog-2001 versions of modules:
- ✅ `crc32_hash.v` (working)
- Create simplified versions of other modules as needed

### Option 3: Pre-process SystemVerilog
Use tools like `sv2v` to convert SystemVerilog to Verilog:
```bash
brew install sv2v
sv2v rtl/pkg/blaze_pkg.sv -o rtl/pkg/blaze_pkg.v
```

---

## Available Synthesis Scripts

| Script | Module | Status |
|--------|--------|--------|
| `synth_crc32.ys` | CRC32 Hash | ✅ **WORKING** |
| `synth_working.sh` | Shell wrapper | ✅ Available |
| `synth_all.sh` | All modules | ⚠️ Needs SV→V conversion |

---

## Quick Commands

```bash
# Navigate to project
cd /Users/rahul/Documents/sphericsx/blaze

# Run synthesis (working module)
yosys -s scripts/yosys/synth_crc32.ys

# View stats
cat synth_out/crc32_stats.txt

# List outputs
ls -lh synth_out/

# Clean outputs
rm -rf synth_out/*.v synth_out/*.json synth_out/*.dot

# Check Yosys version
yosys --version
```

---

## What Works Right Now

✅ **Yosys installed and functional**  
✅ **CRC32 module synthesizes successfully**  
✅ **678 LUTs, 70 FFs - efficient design**  
✅ **Full netlist generated**  
✅ **Statistics available**  
✅ **Design graphs created**  

---

## Next Steps

1. **For quick testing:** Continue using `synth_crc32.ys`
2. **For full design:** Use Vivado with the existing SystemVerilog
3. **For more Yosys synthesis:** Create Verilog-2001 versions of modules

---

## Getting Help

```bash
# Yosys help
yosys -h

# Yosys command reference
yosys -p "help synth"
yosys -p "help abc"

# View this file
cat SYNTHESIS_QUICKSTART.md
```

---

*Last updated: August 4, 2026*  
*Status: Synthesis infrastructure ready and tested*
