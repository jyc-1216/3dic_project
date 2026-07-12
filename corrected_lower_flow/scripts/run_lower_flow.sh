#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

"$SCRIPT_DIR/check_environment.sh"

mkdir -p \
    "$PROJECT_DIR/logs" \
    "$PROJECT_DIR/generated" \
    "$PROJECT_DIR/reports/dc_lower"

echo "[1/3] Tessent RTL IJTAG insertion"
tessent -shell -dofile "$SCRIPT_DIR/lower_die_insert_ijtag.tcl" \
    2>&1 | tee "$PROJECT_DIR/logs/lower_tessent_insert.log"

test -f "$PROJECT_DIR/generated/lower_die_ijtag_inserted.v"
test -f "$PROJECT_DIR/generated/lower_die_dc_import.tcl"

echo "[2/3] Synopsys Design Compiler synthesis"
dc_shell -f "$PROJECT_DIR/dc/lower_die_synthesis.tcl" \
    2>&1 | tee "$PROJECT_DIR/logs/lower_dc_synthesis.log"

test -f "$PROJECT_DIR/generated/lower_die_ijtag_synthesized.v"
test -f "$PROJECT_DIR/generated/lower_die_ijtag_synthesized.ddc"

echo "[3/3] Tessent gate-level import and ICL update"
tessent -shell -dofile "$SCRIPT_DIR/lower_die_gate_import.tcl" \
    2>&1 | tee "$PROJECT_DIR/logs/lower_gate_import.log"

echo "Lower-die insertion, synthesis, and gate import completed"
