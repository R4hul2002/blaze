#!/usr/bin/env bash
# =============================================================================
# build.sh — Top-level build orchestration script
# Project  : BLAZE NGFW
# =============================================================================
# Usage:
#   ./scripts/build/build.sh [sim|synth|impl|all]
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

VIVADO="${VIVADO_BIN:-vivado}"
PYTHON="${PYTHON_BIN:-python3}"

TARGET="${1:-sim}"

log()  { echo "[BLAZE] $*"; }
die()  { echo "[ERROR] $*" >&2; exit 1; }

# ---------------------------------------------------------------------------
check_tools() {
  command -v "$VIVADO" &>/dev/null || die "vivado not found. Set VIVADO_BIN."
  command -v "$PYTHON"  &>/dev/null || die "python3 not found."
}

# ---------------------------------------------------------------------------
run_python_verify() {
  log "Running Python verification..."
  "$PYTHON" "$ROOT_DIR/scripts/python/verify_pkg.py"
}

# ---------------------------------------------------------------------------
run_sim() {
  log "Running package simulation..."
  cd "$ROOT_DIR/sim"
  "$VIVADO" -mode batch -source "$ROOT_DIR/scripts/tcl/sim_pkg.tcl" \
            -log sim_pkg.log -journal sim_pkg.jou
}

# ---------------------------------------------------------------------------
run_synth() {
  log "Running synthesis..."
  "$VIVADO" -mode batch -source "$ROOT_DIR/scripts/tcl/create_project.tcl" \
            -log synth.log -journal synth.jou
}

# ---------------------------------------------------------------------------
case "$TARGET" in
  verify)
    run_python_verify
    ;;
  sim)
    check_tools
    run_python_verify
    run_sim
    ;;
  synth)
    check_tools
    run_synth
    ;;
  all)
    check_tools
    run_python_verify
    run_sim
    run_synth
    ;;
  *)
    die "Unknown target: $TARGET. Use: verify|sim|synth|all"
    ;;
esac

log "Done: $TARGET"
