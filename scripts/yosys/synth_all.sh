#!/usr/bin/env bash
# =============================================================================
# synth_all.sh — Master synthesis script for BLAZE NGFW
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

log "Starting BLAZE NGFW synthesis..."
log "Output directory: $SYNTH_DIR"

# Synthesize ACL Engine
log "Synthesizing ACL Engine..."
yosys -q -s scripts/yosys/synth_acl.ys 2>&1 | tee "$SYNTH_DIR/acl_engine.log"

# Synthesize Parsers
log "Synthesizing Parser modules..."
yosys -q -s scripts/yosys/synth_parsers.ys 2>&1 | tee "$SYNTH_DIR/parsers.log"

# Synthesize Session modules
log "Synthesizing Session modules..."
yosys -q -s scripts/yosys/synth_session.ys 2>&1 | tee "$SYNTH_DIR/session.log"

log "Synthesis complete!"
log "Results in: $SYNTH_DIR"
log ""
log "Summary:"
echo "=========================================="
cat "$SYNTH_DIR"/acl_engine_stats.txt 2>/dev/null || echo "ACL stats not found"
echo "=========================================="
cat "$SYNTH_DIR"/frame_parser_stats.txt 2>/dev/null || echo "Parser stats not found"
echo "=========================================="
cat "$SYNTH_DIR"/flow_hash_stats.txt 2>/dev/null || echo "Session stats not found"
echo "=========================================="

log "Done!"
