# Lower-die ALU custom DWR example

This project converts the original ALU IJTAG-style example into a 30-bit,
fully provisioned custom die-wrapper-register chain.

## Architecture

The existing Tessent access root remains unchanged:

```text
Package TAP pins -> existing PTAP -> existing HostIJTAG -> SIB_DWR
                                                        -> custom DWR chain
```

The custom RTL does not instantiate a TAP and does not decode `TMS`.  The
generated PTAP remains the only primary access root.  The final Tessent
integration must connect the existing SIB segment to these ports:

```text
dwr_select
dwr_capture_en
dwr_shift_en
dwr_update_en
dwr_scan_in
dwr_scan_out
```

A separate Tessent-generated mode TDR should drive:

```text
dwr_enable
dwr_intest_mode
dwr_extest_mode
```

The `dwr_*` ports are explicit top-level hooks only for the pilot and
testbench.  They should become internal connections below the existing
HostIJTAG/SIB in the final inserted design, rather than additional package
pins.

## Why the original port list was changed

The original `alu_operand_a`, `alu_operand_b`, and `alu_opcode` ports were
top-level outputs but were also ALU inputs, and had no functional driver.  That
is appropriate for a TDR-controlled ALU instrument, but it does not provide a
CFI-to-CFO functional boundary for a DWR.

The example therefore adds functional die-to-die ports:

```text
d2d_operand_*_in -> input-side DWR -> ALU
ALU result/flags -> output-side DWR -> d2d_*_out
```

The original `alu_*` outputs are retained as core-side observation points.

## DWR scan order

`dwr_scan_in` enters bit 0. `dwr_scan_out` leaves bit 29.

| DWR bit | Wrapped signal | Direction |
|---:|---|---|
| 0-7 | `d2d_operand_a_in[0:7]` | Die boundary to core |
| 8-15 | `d2d_operand_b_in[0:7]` | Die boundary to core |
| 16-18 | `d2d_opcode_in[0:2]` | Die boundary to core |
| 19-26 | `core_result[0:7]` | Core to die boundary |
| 27 | `core_zero_flag` | Core to die boundary |
| 28 | `core_carry_flag` | Core to die boundary |
| 29 | `core_overflow_flag` | Core to die boundary |

To load a 30-bit vector with this implementation, shift bit 29 first and bit 0
last.  Capture data leaves in the order bit 29 down to bit 0.

## Mode behavior

| Mode | Input-side DWR | Output-side DWR | Intended use |
|---|---|---|---|
| Mission | Functional pass-through | Functional pass-through | Normal ALU operation |
| INTEST | Apply update-stage data to ALU inputs | Capture core response; output remains functional | Test lower-die core logic |
| EXTEST | Capture incoming link data; input remains functional | Apply update-stage data to D2D outputs | Launch/capture link test |

If both `dwr_intest_mode` and `dwr_extest_mode` are asserted, the RTL falls
back to functional pass-through.  This avoids applying contradictory modes.

## Cell timing

- Capture and shift occur on the rising edge of `tck`.
- Update occurs on the falling edge of `tck`.
- `dwr_select` gates Capture, Shift, and Update.
- Reset clears both the shift and update stages.
- The example assumes the existing `trst` port is active low.  Change the
  connection to `trst_n` if the generated design uses another polarity.

## Files

- `rtl/dwr_boundary_cell.sv`: one fully provisioned wrapper cell.
- `rtl/lower_die_dwr_chain.sv`: 30-cell serial DWR chain.
- `rtl/lower_die_top.sv`: modified version of the supplied ALU top.
- `tb/lower_die_alu_core_model.sv`: simulation-only ALU model; replace it with
  the real `lower_die_alu_core` for project use.
- `tb/lower_die_top_dwr_tb.sv`: mission, capture/shift, INTEST, EXTEST, and
  mission-return checks.

Example simulation command:

```bash
iverilog -g2012 -o lower_die_dwr_sim \
  rtl/dwr_boundary_cell.sv \
  rtl/lower_die_dwr_chain.sv \
  rtl/lower_die_top.sv \
  tb/lower_die_alu_core_model.sv \
  tb/lower_die_top_dwr_tb.sv
vvp lower_die_dwr_sim
```

Expected final line:

```text
PASS: lower_die custom DWR example
```

## Tessent handoff boundary

This RTL is deliberately a user-defined DWR instrument, not a second TAP and
not a claim that `analyze_wrapper_cells` will report native ScanPro wrapper
cells.  Keep the already working PTAP/STAP/HostIJTAG hierarchy, place this
chain below a new SIB, and use extracted ICL plus retargeted readback to prove
the complete access path.
