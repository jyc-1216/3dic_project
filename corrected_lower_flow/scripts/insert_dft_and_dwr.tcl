#=============================================================================
# insert_dft_and_dwr.tcl
#
# Purpose:
#   Single-file, two-phase Tessent Shell script that covers the FULL DFT
#   insertion flow for one die:
#
#     Phase 1 (RTL stage)   : Main TAP + HostIjtag + HostStap insertion
#                              (this is the flow you already validated)
#     Phase 2 (gate stage)  : IEEE 1838 DWR (Die Wrapper Register) insertion
#                              on top of the synthesized netlist
#
# Why this is ONE file but still TWO phases, not one combined step:
#   - HostIjtag/HostStap are described under the
#       IjtagNetwork/HostScanInterface/Tap(main)
#     configuration hierarchy and inserted at RTL via
#       create_dft_specification / read_config_data / process_dft_specification
#   - DWR is NOT part of that configuration hierarchy. It is built by
#     Tessent Scan's wrapper-cell analysis and scan insertion
#     (analyze_wrapper_cells + insert_test_logic), which only makes sense
#     on the SYNTHESIZED (gate-level) netlist.
#   - Between Phase 1 and Phase 2 you must run synthesis (Synopsys DC)
#     on the Phase-1 output netlist. That step happens OUTSIDE Tessent
#     Shell, so this script cannot literally run start-to-finish in one
#     `tessent_shell -file ...` call -- you run Phase 1, synthesize, then
#     run Phase 2. Keeping both phases in one file just means you no
#     longer maintain two separate scripts with two separate sets of
#     die/port/library variables that can drift out of sync.
#
# How to run:
#   tessent_shell -shell -file insert_dft_and_dwr.tcl   ;# with RUN_PHASE 1
#   ... run Synopsys DC synthesis on the Phase 1 output netlist ...
#   tessent_shell -shell -file insert_dft_and_dwr.tcl   ;# with RUN_PHASE 2
#
# Before running, verify the exact syntax of the following commands against
# your installed Tessent version (some arguments differ across releases):
#   help create_dft_specification
#   help read_config_data
#   help process_dft_specification
#   help set_wrapper_analysis_options
#   help set_dedicated_wrapper_cell_options
#   help analyze_wrapper_cells
#   help add_scan_mode
#   help analyze_scan_chains
#   help insert_test_logic
#=============================================================================


#-----------------------------------------------------------------------
# 0. USER CONFIGURATION -- the only section you should need to edit
#-----------------------------------------------------------------------

# 0-0) Which phase to run in THIS invocation of Tessent Shell.
#      1 = RTL-stage Main TAP + HostIjtag + HostStap insertion
#      2 = Gate-level DWR insertion (run only after Phase 1 output has
#          been synthesized by Synopsys DC)
set RUN_PHASE   1                                          ;# TODO: 1 or 2

# 0-1) Top-level design name (same die, both phases)
set TOP_DESIGN         "current_die"                        ;# TODO

# ---- Phase 1 (RTL) inputs/outputs ----
set RTL_SOURCES        [list "./rtl/current_die.v"]         ;# TODO: golden RTL file list
set MAIN_TAP_PATH_TAIL "IjtagNetwork/HostScanInterface(tap)/Tap(main)" \
                                                              ;# usually unchanged
set PHASE1_DESIGN_ID   "rtl2"                                ;# TODO: must match
                                                              ;# whatever Phase 2 expects
                                                              ;# in PREV_DESIGN_ID below
set PHASE1_TSDB_DIR    "./tsdb_rtl"

# ---- Phase 2 (gate) inputs/outputs ----
set LIB_PATH           "./lib/standard_cells.tcelllib"       ;# TODO: Tessent cell library
set NETLIST_PATH        "./netlist/current_die_synth.v"      ;# TODO: DC-synthesized netlist
set PREV_DESIGN_ID      $PHASE1_DESIGN_ID                     ;# must match Phase 1 output
set PHASE2_TSDB_DIR     "./tsdb_dwr"
set GATE_DESIGN_ID      "gate"

# Die-to-die functional ports that need a DWR wrapper cell.
# List ONLY true cross-die functional signals here -- do NOT include
# PTAP/STAP/TCK/TMS/reset or any other test pin; those are already
# handled by the Phase 1 HostIjtag/HostStap insertion.
set DWR_PORT_PATTERNS { \
    d2d_rx* \
    d2d_tx* \
}                                                             ;# TODO

# Dedicated vs shared wrapper cell:
#   on  = force a new dedicated wrapper cell on every D2D port
#         (best for combinational D2D outputs, or when there is no
#         nearby reusable flop)
#   off = try to reuse an existing nearby functional scan flop as a
#         shared DWR cell (saves area on designs that already have
#         pipeline/IO flops)
# If your D2D output is purely combinational (e.g. driven directly by
# an ALU), keep this at 1 (on) for the first working version.
set USE_DEDICATED_WRAPPER   1                                 ;# 1 = on, 0 = off


#=============================================================================
# PHASE 1 -- RTL stage: Main TAP + HostIjtag + HostStap insertion
#=============================================================================
if {$RUN_PHASE == 1} {

    puts "INFO: Running PHASE 1 (RTL-stage TAP/HostIjtag/HostStap insertion)"

    set_context dft -rtl

    set_tsdb_output_directory $PHASE1_TSDB_DIR

    foreach f $RTL_SOURCES {
        read_verilog $f
    }

    set_current_design $TOP_DESIGN

    check_design_rules

    #-------------------------------------------------------------------
    # 1-1. Create the DFT specification and describe HostIjtag/HostStap
    #      under the Main TAP. This is the flow you already validated;
    #      it is reproduced here unchanged so the whole die flow lives
    #      in one file.
    #-------------------------------------------------------------------
    set spec [create_dft_specification]

    set main_tap_path "$spec/$MAIN_TAP_PATH_TAIL"

    read_config_data \
        -in $main_tap_path \
        -from_string {
            HostIjtag(1) {
            }

            HostStap(s1) {
            }
        }

    report_config_data $spec

    #-------------------------------------------------------------------
    # 1-2. Validate, then actually process the specification
    #-------------------------------------------------------------------
    process_dft_specification -validate_only
    process_dft_specification

    puts "INFO: Main TAP + HostIjtag + HostStap have been inserted at RTL."
    puts "NOTE: Do NOT add a HostDwr(...) entry above -- DWR is not part of"
    puts "      the IjtagNetwork/HostScanInterface/Tap configuration"
    puts "      hierarchy. DWR is handled separately in PHASE 2, after"
    puts "      synthesis."

    #-------------------------------------------------------------------
    # 1-3. Extract ICL and save the design database for Phase 2 to read
    #      back (this is what PREV_DESIGN_ID / PHASE1_DESIGN_ID refers to)
    #-------------------------------------------------------------------
    extract_icl
    write_design -tsdb -design_id $PHASE1_DESIGN_ID -verbose

    puts "INFO: PHASE 1 complete."
    puts "NEXT STEP: synthesize this RTL output with Synopsys DC using your"
    puts "           existing standard-cell .db, then re-run this script"
    puts "           with RUN_PHASE set to 2."

    return
}


#=============================================================================
# PHASE 2 -- Gate stage: IEEE 1838 DWR insertion
#            (run only after Synopsys DC synthesis of the Phase 1 output)
#=============================================================================
if {$RUN_PHASE == 2} {

    puts "INFO: Running PHASE 2 (gate-level DWR insertion)"

    #-------------------------------------------------------------------
    # 2-1. Load the synthesized design
    #-------------------------------------------------------------------
    set_context dft -scan -design_id $GATE_DESIGN_ID

    set_tsdb_output_directory $PHASE2_TSDB_DIR

    read_cell_library  $LIB_PATH
    read_verilog       $NETLIST_PATH

    # Read back the Phase 1 database so PTAP/STAP/IJTAG logic is already
    # known and will not be mistaken for D2D functional ports.
    read_design $TOP_DESIGN -design_id $PREV_DESIGN_ID -no_hdl

    set_current_design $TOP_DESIGN

    check_design_rules
    report_clocks

    #-------------------------------------------------------------------
    # 2-2. Identify D2D functional ports and exclude everything else
    #-------------------------------------------------------------------
    set dwr_ports [get_ports $DWR_PORT_PATTERNS]

    if {[sizeof_collection $dwr_ports] == 0} {
        puts "ERROR: no ports matched DWR_PORT_PATTERNS -- check section 0"
        return -code error "no matching D2D ports"
    }

    puts "INFO: the following ports are treated as D2D functional ports"
    puts "      for DWR analysis:"
    report_collection $dwr_ports

    set_wrapper_analysis_options \
        -exclude_ports [remove_from_collection [get_ports *] $dwr_ports]

    #-------------------------------------------------------------------
    # 2-3. Choose dedicated vs shared wrapper cell
    #-------------------------------------------------------------------
    if {$USE_DEDICATED_WRAPPER} {
        puts "INFO: using dedicated wrapper cell mode (on)"
        set_dedicated_wrapper_cell_options on -ports $dwr_ports
    } else {
        puts "INFO: using shared wrapper cell mode (off) -- reusing"
        puts "      existing functional flops where possible"
        set_dedicated_wrapper_cell_options off -ports $dwr_ports
    }

    #-------------------------------------------------------------------
    # 2-4. Analyze wrapper / DWR cells
    #-------------------------------------------------------------------
    check_design_rules
    analyze_wrapper_cells
    report_wrapper_cells -verbose > report_wrapper_cells_before_insertion.rpt

    puts "INFO: wrote report_wrapper_cells_before_insertion.rpt -- confirm"
    puts "      every D2D port shows as dedicated (or shared) wrapper,"
    puts "      not excluded or optimized."

    #-------------------------------------------------------------------
    # 2-5. Define internal / external scan modes
    #-------------------------------------------------------------------

    # Internal mode: tests logic inside the die (same idea as ordinary
    # core-level scan).
    add_scan_mode int_mode \
        -chain_count 1

    # External mode: uses ONLY the wrapper cells, to test die-to-die
    # interconnect. This is the IEEE 1838 external test mode -- the
    # whole reason DWR exists.
    add_scan_mode ext_mode \
        -chain_count 1

    #-------------------------------------------------------------------
    # 2-6. Analyze scan chains, then actually insert
    #      (insert_test_logic is the step that changes the circuit)
    #-------------------------------------------------------------------
    analyze_scan_chains
    report_scan_chains > report_scan_chains_before_insertion.rpt

    insert_test_logic

    puts "INFO: insert_test_logic complete -- DWR/scan chains are now"
    puts "      physically present in the design."

    #-------------------------------------------------------------------
    # 2-7. Post-insertion verification and output
    #-------------------------------------------------------------------
    report_wrapper_cells -verbose > report_wrapper_cells_after_insertion.rpt
    report_scan_chains            > report_scan_chains_after_insertion.rpt
    report_scan_cells              > dwr_scan_cells.list

    set dft_info [get_dft_info_dictionary]
    if {[dict exists $dft_info dedicated_wrapper_cells]} {
        set fh [open "dwr_dedicated_wrapper_cells.rpt" w]
        puts $fh [format_dictionary [dict get $dft_info dedicated_wrapper_cells]]
        close $fh
    }

    write_design -tsdb -design_id $GATE_DESIGN_ID -verbose

    #-------------------------------------------------------------------
    # 2-8. Completion checklist
    #      (check against report_wrapper_cells_after_insertion.rpt and
    #      dwr_scan_cells.list)
    #-------------------------------------------------------------------
    #   [ ] every D2D port appears in report_wrapper_cells
    #   [ ] each D2D port shows dedicated (or shared, per your choice)
    #       wrapper status -- not excluded or optimized
    #   [ ] wrapper cell instances appear in the gate-level netlist after
    #       insert_test_logic
    #   [ ] dwr_dedicated_wrapper_cells.rpt instance names match the
    #       report above
    #   [ ] the Phase 1 PTAP/STAP/IJTAG wrapper instance count did not
    #       decrease
    #   [ ] no unresolved modules near the D2D ports
    #   [ ] mission-mode functional simulation still matches the golden
    #       RTL
    #   [ ] ext_mode can control/observe capture, shift, and update
    #       behavior on at least one wrapper cell
    #
    #   Once all of the above are confirmed, you can move on to
    #   external-mode die-to-die ATPG at stack_top.

    puts "INFO: PHASE 2 complete. Review the checklist in the comments"
    puts "      above before moving to stack-level ATPG."

    return
}

puts "ERROR: RUN_PHASE must be set to 1 or 2 (see section 0)."
return -code error "invalid RUN_PHASE"


#=============================================================================
# APPENDIX -- Advanced SSN/EDT version (reference only, not executed)
#
# For a full multi-die stack that needs to move large volumes of
# scan/DWR data through SSN/FPP instead of the simple chain_count 1
# scan modes used above, the external-mode scan setup from the Tessent
# Multi-die manual looks more like this:
#
#   set dwr_ports [get_ports {left_* right_*}]
#
#   set_wrapper_analysis_options \
#       -exclude_ports [remove_from_collection [get_ports *] $dwr_ports]
#
#   set_dedicated_wrapper_cell_options off -ports $dwr_ports
#
#   check_design_rules
#   analyze_wrapper_cells
#   report_wrapper_cells -verbose
#
#   # Die internal test mode
#   set_attribute_value {core_a core_b} \
#       -name active_child_scan_mode \
#       -value ext_edt_mode
#
#   add_scan_mode int_edt_mode \
#       -edt_instance <internal_edt_instance>
#
#   # Die external mode: the actual DWR/die-to-die test mode
#   set_attribute_value {core_a core_b} \
#       -name active_child_scan_mode \
#       -value parent_ext_edt_mode
#
#   add_scan_mode ext_edt_mode \
#       -edt_instance <external_edt_instance> \
#       -include_elements [get_scan_elements *occ*] \
#       -associate_chains [get_scan_elements -type chain]
#
#   analyze_scan_chains
#   insert_test_logic
#
# Note: IEEE 1838 defines FPP as optional, but Tessent's full 3D flow
# needs SSN to implement FPP before it can run stack-level external-mode
# ATPG. If your current goal is just to prove out the DWR architecture
# itself, you do not need this section yet.
#=============================================================================
