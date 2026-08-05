# =============================================================================
# Tessent 2025.02 RTL insertion pilot
# Existing PTAP/STAP/HostIJTAG -> SIB_DWR -> custom 30-bit DWR instrument
#                                    \-> 3-bit mode TDR
#
# This is a project template, not a claim of native ScanPro DWR insertion.
# The custom DWR is described to Tessent as a non-Tessent IJTAG instrument.
# Edit USER CONFIGURATION and the HostStap(s1) body to match the configuration
# that already passes report_config_data in the local Tessent 2025.02 setup.
# =============================================================================

# -----------------------------------------------------------------------------
# USER CONFIGURATION
# -----------------------------------------------------------------------------

set TARGET_TESSENT_RELEASE 2025.02
set DESIGN_NAME            lower_die_top
set DESIGN_ID              rtl_1838_custom_dwr
set DWR_INSTANCE_PATH      u_dwr_chain
set DWR_SCAN_INTERFACE     dwr_client

set script_dir  [file dirname [file normalize [info script]]]
set project_dir [file dirname $script_dir]

# The integration top is intentionally different from the simulation pilot.
# In this file, u_dwr_chain must exist, but its dwr_select/capture/shift/update,
# dwr_scan_in/out and three mode pins must be left unconnected at the parent
# level so process_dft_specification can connect them.  They must not remain
# package-level ports.
if {[info exists env(DWR_TOP_RTL)] && $env(DWR_TOP_RTL) ne ""} {
    set top_rtl [file normalize $env(DWR_TOP_RTL)]
} else {
    set top_rtl ${project_dir}/rtl/lower_die_top_tessent.sv
}

set rtl_files [list \
    ${project_dir}/rtl/dwr_boundary_cell.sv \
    ${project_dir}/rtl/lower_die_dwr_chain.sv \
    ${project_dir}/rtl/lower_die_alu_core.sv \
    $top_rtl \
]

set generated_dir ${project_dir}/generated/custom_dwr_1838
set report_dir    ${project_dir}/reports/custom_dwr_1838
set pattern_dir   ${project_dir}/patterns/custom_dwr_1838
set tsdb_dir      ${project_dir}/tsdb_custom_dwr_1838

set dwr_icl_file  ${generated_dir}/lower_die_dwr_chain.icl
set inserted_rtl  ${generated_dir}/lower_die_1838_custom_dwr_inserted.v
set extracted_icl ${generated_dir}/lower_die_1838_custom_dwr_extracted.icl
set dc_import_tcl ${generated_dir}/lower_die_1838_custom_dwr_dc_import.tcl

foreach directory [list $generated_dir $report_dir $pattern_dir $tsdb_dir] {
    file mkdir $directory
}

foreach rtl_file $rtl_files {
    if {![file exists $rtl_file]} {
        error "Missing RTL file: $rtl_file"
    }
}

# -----------------------------------------------------------------------------
# SELF-CONTAINED ICL MODEL FOR THE HAND-WRITTEN DWR CHAIN
# -----------------------------------------------------------------------------
# RTL scan direction:
#   dwr_scan_in -> DWR[0] -> ... -> DWR[29] -> dwr_scan_out
# Therefore the ascending ICL range DWR[0:29] is intentional.

set dwr_icl_text {
Module lower_die_dwr_chain {
    TCKPort       tck;
    ResetPort     trst_n { ActivePolarity 0; }

    ScanInPort    dwr_scan_in;
    ScanOutPort   dwr_scan_out { Source DWR[29]; }
    SelectPort    dwr_select;
    CaptureEnPort dwr_capture_en;
    ShiftEnPort   dwr_shift_en;
    UpdateEnPort  dwr_update_en;

    DataInPort dwr_enable;
    DataInPort dwr_intest_mode;
    DataInPort dwr_extest_mode;

    DataInPort d2d_operand_a_in[7:0];
    DataInPort d2d_operand_b_in[7:0];
    DataInPort d2d_opcode_in[2:0];
    DataInPort core_result[7:0];
    DataInPort core_zero_flag;
    DataInPort core_carry_flag;
    DataInPort core_overflow_flag;

    ScanInterface dwr_client {
        Port dwr_scan_in;
        Port dwr_scan_out;
        Port dwr_select;
        Port dwr_capture_en;
        Port dwr_shift_en;
        Port dwr_update_en;
        Port tck;
        Port trst_n;
    }

    ScanRegister DWR[0:29] {
        ScanInSource dwr_scan_in;
        CaptureSource
            d2d_operand_a_in[0], d2d_operand_a_in[1],
            d2d_operand_a_in[2], d2d_operand_a_in[3],
            d2d_operand_a_in[4], d2d_operand_a_in[5],
            d2d_operand_a_in[6], d2d_operand_a_in[7],
            d2d_operand_b_in[0], d2d_operand_b_in[1],
            d2d_operand_b_in[2], d2d_operand_b_in[3],
            d2d_operand_b_in[4], d2d_operand_b_in[5],
            d2d_operand_b_in[6], d2d_operand_b_in[7],
            d2d_opcode_in[0], d2d_opcode_in[1], d2d_opcode_in[2],
            core_result[0], core_result[1], core_result[2], core_result[3],
            core_result[4], core_result[5], core_result[6], core_result[7],
            core_zero_flag, core_carry_flag, core_overflow_flag;
        ResetValue 30'b000000000000000000000000000000;
    }
}
}

set icl_handle [open $dwr_icl_file w]
puts $icl_handle $dwr_icl_text
close $icl_handle

# -----------------------------------------------------------------------------
# READ RTL + ICL BEFORE set_current_design
# -----------------------------------------------------------------------------

puts "TARGET TESSENT RELEASE: $TARGET_TESSENT_RELEASE"
set_context dft -rtl -design_id $DESIGN_ID
set_tsdb_output_directory $tsdb_dir

foreach rtl_file $rtl_files {
    read_verilog $rtl_file
}
read_icl $dwr_icl_file

set_current_design $DESIGN_NAME
set_design_level chip

set_attribute_value tck  -name function -value tck
set_attribute_value tms  -name function -value tms
set_attribute_value tdi  -name function -value tdi
set_attribute_value tdo  -name function -value tdo
set_attribute_value trst -name function -value trst

set_dft_specification_requirements -host_scan_interface_type tap
check_design_rules
report_module_matching -icl

# Fail closed if the simulation-only DWR hooks are still package ports.  The
# final PTAP/SIB network cannot safely drive pins that are already driven by
# top-level ports.
set forbidden_top_hooks [list \
    dwr_select dwr_capture_en dwr_shift_en dwr_update_en \
    dwr_scan_in dwr_scan_out \
    dwr_enable dwr_intest_mode dwr_extest_mode \
]

set exposed_hooks [get_ports -quiet $forbidden_top_hooks]
if {[sizeof_collection $exposed_hooks] != 0} {
    error "DWR pilot hooks are still top-level ports: [get_object_name $exposed_hooks]. Use lower_die_top_tessent.sv and leave these u_dwr_chain pins unconnected for Tessent insertion."
}

# -----------------------------------------------------------------------------
# ONE PTAP ROOT, ONE LOCAL HostIjtag, ONE DOWNSTREAM STAP
# -----------------------------------------------------------------------------

# Do not add -stap_host_list here.  In the local 2025.02 flow that was already
# debugged, HostIjtag(1) and HostStap(s1) must be created/edited together by one
# read_config_data block below.
set spec [create_dft_specification]
set main_tap_path $spec/IjtagNetwork/HostScanInterface(tap)/Tap(main)

# Keep HostIjtag(1) and HostStap(s1) in the same Tap(main) edit.  This follows
# the already-debugged Tessent 2025.02 organization and avoids a second local
# TAP.  If the validated company HostStap body contains release-specific
# fields, paste those fields inside HostStap(s1) below before running.
set combined_host_config [format {
    HostIjtag(1) {
        Sib(dwr) {
            DesignInstance(%s) {
                scan_interface : %s;
            }

            Tdr(dwr_mode) {
                length : 3;
                DataOutPorts {
                    Connection(0) : %s/dwr_enable;
                    Connection(1) : %s/dwr_intest_mode;
                    Connection(2) : %s/dwr_extest_mode;
                }
            }
        }
    }

    HostStap(s1) {
        # Paste only the already-validated 2025.02 HostStap(s1) fields here.
        # Do not create another HostScanInterface or Tap.
    }
} $DWR_INSTANCE_PATH $DWR_SCAN_INTERFACE \
  $DWR_INSTANCE_PATH $DWR_INSTANCE_PATH $DWR_INSTANCE_PATH]

read_config_data \
    -in $main_tap_path \
    -from_string $combined_host_config

redirect -file ${report_dir}/config_data.rpt {
    report_config_data $spec
}

if {[llength [info commands report_config_syntax]] != 0} {
    redirect -file ${report_dir}/config_syntax.rpt {
        report_config_syntax $spec
    }
}

process_dft_specification -validate_only
process_dft_specification
extract_icl

# -----------------------------------------------------------------------------
# SAVE INSERTED RTL, TSDB, EXTRACTED ICL, AND DC IMPORT SCRIPT
# -----------------------------------------------------------------------------

write_design -tsdb -verbose
write_design -output_file $inserted_rtl -replace
write_design_import_script \
    $dc_import_tcl \
    -replace \
    -use_relative_path_to $project_dir

set_system_mode analysis
write_icl \
    -output_file $extracted_icl \
    -modules [get_single_name [get_current_design]] \
    -hierarchical \
    -replace

# -----------------------------------------------------------------------------
# ACCESS-NETWORK VERIFICATION PATTERNS
# -----------------------------------------------------------------------------
# These patterns prove PTAP -> HostIjtag -> SIB -> DWR connectivity and scan
# length.  They do not, by themselves, prove INTEST/EXTEST functional behavior;
# run the RTL and post-synthesis GLS tests listed in the companion PDF.

if {[llength [info commands create_icl_verification_patterns]] == 0} {
    error "create_icl_verification_patterns is unavailable in this session"
}

open_pattern_set dwr_icl_connectivity
create_icl_verification_patterns
close_pattern_set

redirect -file ${report_dir}/icl_verification_pattern.rpt {
    report_pattern_set dwr_icl_connectivity
}

write_patterns \
    ${pattern_dir}/lower_die_dwr_icl_connectivity.v \
    -verilog \
    -replace

puts ""
puts "CUSTOM DWR IJTAG INSERTION PILOT COMPLETED"
puts "Inserted RTL : $inserted_rtl"
puts "Extracted ICL: $extracted_icl"
puts "DC import Tcl: $dc_import_tcl"
puts "TSDB         : $tsdb_dir"
puts "Reports      : $report_dir"
puts "Patterns     : $pattern_dir"
puts ""
puts "Required next gate: simulate mission, capture, shift, update, INTEST and EXTEST on both RTL and post-synthesis netlists."
exit
