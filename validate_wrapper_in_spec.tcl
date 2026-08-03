#=============================================================================
# validate_wrapper_in_spec.tcl
#
# Purpose:
#   NOT a production insertion script. This is a small, throwaway test to
#   answer ONE specific question before you commit to the single-pass
#   insert_dft_with_dwr.tcl flow:
#
#     Does DWR wrapper-cell analysis actually survive being combined into
#     the SAME process_dft_specification call as HostIjtag/HostStap, or
#     does it get reset / ignored / thrown away?
#
#   Run this once on your smallest available test design (ideally the
#   1-bit-in / 1-bit-out basic_die_top mentioned in your success
#   criteria). It writes two reports, before and after
#   process_dft_specification, so you can diff them directly.
#
# How to read the result:
#   - Compare pre_spec_wrapper.rpt and post_spec_wrapper.rpt.
#   - If both D2D ports still show "dedicated wrapper" in the AFTER
#     report, with the same instance names as the BEFORE report:
#       -> combining wrapper analysis + HostIjtag/HostStap into one
#          process_dft_specification call WORKS. Proceed with
#          insert_dft_with_dwr.tcl as-is.
#   - If the AFTER report shows the D2D ports as excluded/optimized/
#     missing, or process_dft_specification throws an error:
#       -> the combination does NOT work on your version. Fall back to
#          the two-phase approach (RTL: TAP+HostIjtag+HostStap only,
#          then gate-level: analyze_wrapper_cells + insert_test_logic
#          after synthesis).
#   - Also check dwr_grep_check.txt at the end -- it greps the written
#     RTL for the wrapper instance names found in the reports, so you
#     can confirm the cells are physically present in the output RTL,
#     not just claimed in a report.
#=============================================================================


#-----------------------------------------------------------------------
# 0. Minimal test configuration -- point this at your smallest test die
#-----------------------------------------------------------------------

set TOP_DESIGN          "basic_die_top"                        ;# TODO: your smallest test die
set RTL_SOURCES         [list "./rtl/basic_die_top.v"]          ;# TODO
set MAIN_TAP_PATH_TAIL  "IjtagNetwork/HostScanInterface(tap)/Tap(main)"
set TSDB_DIR            "./tsdb_validate_wrapper"

# Use a single 1-bit in / 1-bit out D2D pair for this test, per your
# own success-criteria recommendation -- keeps the report small and easy
# to read by eye.
set D2D_PORTS_LIST { \
    d2d_test_in \
    d2d_test_out \
}                                                                ;# TODO: your real 1-bit test pair


#-----------------------------------------------------------------------
# 1. Load design, run wrapper analysis FIRST (baseline)
#-----------------------------------------------------------------------

set_context dft -rtl
set_tsdb_output_directory $TSDB_DIR

foreach f $RTL_SOURCES {
    read_verilog $f
}

set_current_design $TOP_DESIGN
set_dft_specification_requirements -logic_test on

set d2d_ports [get_ports $D2D_PORTS_LIST]

if {[sizeof_collection $d2d_ports] == 0} {
    puts "ERROR: no ports matched D2D_PORTS_LIST -- fix section 0 and retry"
    return -code error "no matching D2D ports"
}

set non_d2d_ports [remove_from_collection [get_ports *] $d2d_ports]

set_wrapper_analysis_options -exclude_ports $non_d2d_ports
set_dedicated_wrapper_cell_options on -ports $d2d_ports

check_design_rules
set_system_mode analysis
analyze_wrapper_cells

report_wrapper_cells -verbose > pre_spec_wrapper.rpt
puts "INFO: wrote pre_spec_wrapper.rpt -- this is the BEFORE baseline."


#-----------------------------------------------------------------------
# 2. Now create the spec and add HostIjtag/HostStap, in the same session
#-----------------------------------------------------------------------

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

set fh [open "spec_report_before_process.rpt" w]
puts $fh [report_config_data $spec]
close $fh
puts "INFO: wrote spec_report_before_process.rpt -- check whether any"
puts "      wrapper-related entries appear here at all (they may not --"
puts "      that alone does not mean failure, since wrapper settings may"
puts "      simply live outside the spec's config-data tree)."


#-----------------------------------------------------------------------
# 3. Validate, then actually process
#-----------------------------------------------------------------------

if {[catch {process_dft_specification -validate_only} err]} {
    puts "RESULT: process_dft_specification -validate_only FAILED:"
    puts "        $err"
    puts "RESULT: this points to the combined single-pass approach NOT"
    puts "        working on your version -- use the two-phase flow."
    return
} else {
    puts "INFO: process_dft_specification -validate_only passed."
}

if {[catch {process_dft_specification} err]} {
    puts "RESULT: process_dft_specification FAILED:"
    puts "        $err"
    puts "RESULT: this points to the combined single-pass approach NOT"
    puts "        working on your version -- use the two-phase flow."
    return
} else {
    puts "INFO: process_dft_specification completed without error."
}


#-----------------------------------------------------------------------
# 4. Re-check wrapper cells AFTER process_dft_specification
#-----------------------------------------------------------------------

report_wrapper_cells -verbose > post_spec_wrapper.rpt
puts "INFO: wrote post_spec_wrapper.rpt -- this is the AFTER result."
puts "INFO: now run, outside Tessent Shell:"
puts "        diff pre_spec_wrapper.rpt post_spec_wrapper.rpt"
puts "      Both D2D ports should still show dedicated wrapper status,"
puts "      with the same instance names, in both files."

set dft_info [get_dft_info_dictionary]
if {[dict exists $dft_info dedicated_wrapper_cells]} {
    set fh [open "post_spec_dedicated_wrapper_cells.rpt" w]
    puts $fh [format_dictionary [dict get $dft_info dedicated_wrapper_cells]]
    close $fh
    puts "INFO: wrote post_spec_dedicated_wrapper_cells.rpt -- instance"
    puts "      names here should match post_spec_wrapper.rpt."
} else {
    puts "RESULT: dedicated_wrapper_cells key is MISSING from"
    puts "        dft_info_dictionary after process_dft_specification."
    puts "RESULT: this is a strong signal the wrapper analysis was reset"
    puts "        or discarded -- use the two-phase flow instead."
}


#-----------------------------------------------------------------------
# 5. Confirm the wrapper cells are physically present in the written RTL,
#    not just claimed in a report
#-----------------------------------------------------------------------

extract_icl
write_design -tsdb -design_id validate1 -verbose

# Pull instance names out of the AFTER report and grep for them in the
# design_source_dictionary's RTL files. Adjust the grep pattern if your
# report format differs.
set fh [open "post_spec_wrapper.rpt" r]
set report_text [read $fh]
close $fh

set instance_names {}
foreach line [split $report_text "\n"] {
    if {[regexp {(\S+d2d\S*)} $line -> match]} {
        lappend instance_names $match
    }
}

set fh [open "dwr_grep_check.txt" w]
puts $fh "Instance-like tokens found in post_spec_wrapper.rpt:"
puts $fh $instance_names
puts $fh ""
puts $fh "Run this manually against the written RTL to confirm physical presence:"
puts $fh "  grep -iE \"[join $instance_names |]\" $TSDB_DIR/dft_inserted_designs/*/*.v"
close $fh

puts "INFO: wrote dwr_grep_check.txt -- follow the grep command inside it"
puts "      to confirm the wrapper cell instances are physically present"
puts "      in the written RTL, not just listed in a report."

puts ""
puts "=== VALIDATION COMPLETE ==="
puts "Review, in order:"
puts "  1. pre_spec_wrapper.rpt vs post_spec_wrapper.rpt (diff them)"
puts "  2. post_spec_dedicated_wrapper_cells.rpt instance names"
puts "  3. dwr_grep_check.txt -- confirm instances exist in written RTL"
puts "If all three agree, the combined single-pass approach is safe to"
puts "use for real. If any of them disagree or process_dft_specification"
puts "errored above, use the two-phase (RTL then gate-level) flow."
