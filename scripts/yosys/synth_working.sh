#!/usr/bin/env bash
# =============================================================================
# synth_working.sh — Working synthesis script for BLAZE NGFW
# Uses Yosys-compatible simplified package definitions
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
SYNTH_DIR="$ROOT_DIR/synth_out"

log()  { echo "[SYNTH] $*"; }
die()  { echo "[ERROR] $*" >&2; exit 1; }

# Check for yosys
command -v yosys &>/dev/null || die "yosys not found. Install with: brew install yosys"

# Create output directory
mkdir -p "$SYNTH_DIR"
cd "$ROOT_DIR"

log "Starting BLAZE NGFW synthesis (Yosys-compatible mode)..."
log "Output directory: $SYNTH_DIR"
log ""

# Synthesize ACL Engine with simplified package
log "Synthesizing ACL Engine..."
if yosys -s scripts/yosys/synth_acl_simple.ys > "$SYNTH_DIR/acl_engine.log" 2>&1; then
    log "✓ ACL Engine synthesis complete"
else
    log "✗ ACL Engine synthesis failed - check $SYNTH_DIR/acl_engine.log"
fi

log ""
log "Synthesis complete!"
log "Results in: $SYNTH_DIR"
log ""

# Show statistics if available
if [ -f "$SYNTH_DIR/acl_engine_stats.txt" ]; then
    log "ACL Engine Statistics:"
    echo "=========================================="
    cat "$SYNTH_DIR/acl_engine_stats.txt"
    echo "=========================================="
else
    log "Statistics file not found. Check logs for errors."
fi

log ""
log "Generated files:"
ls -lh "$SYNTH_DIR"/*.{v,json,txt} 2>/dev/null || log "No output files generated"

log ""
log "Done!"
