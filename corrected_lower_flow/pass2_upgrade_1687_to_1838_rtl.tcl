# =============================================================================
# Tessent 2025.02 RTL Pass 2 template
# Upgrade an already inserted and verified IEEE 1687 design view to IEEE 1838.
#
# Required Pass 1 result:
#   - RTL insertion completed
#   - extract_icl completed
#   - write_design -tsdb completed
#   - PDL retargeting and RTL pattern simulation already passed
#
# Typical bottom-die run:
#   DIE_POSITION=bottom \
#   TOP_MODULE=basic_die_top \
#   TSDB_DIR=./tsdb_basic \
#   PASS1_DESIGN_ID=rtl_1687 \
#   PASS2_DESIGN_ID=rtl_1687_1838_bottom \
#   STAP_HOST_LIST="s1" \
#   tessent -shell -dofile pass2_upgrade_1687_to_1838_rtl.tcl
#
# Middle die:
#   DIE_POSITION=middle ... STAP_HOST_LIST="s1" tessent -shell -dofile ...
#
# Top die:
#   Tessent releases/support kits can differ in the PTAP-only creation switch.
#   First run with SPEC_ONLY=1.  After confirming that Tessent 2025.02 accepts
#   an empty STAP host list as PTAP-only, also set:
#     TOP_PTAP_STRATEGY=empty_stap_list
#
# This script never re-adds the Pass 1 HostIjtag/SIB/TDR and never reads golden
# RTL.  Its purpose is cumulative insertion into the Pass 1 RTL design view.
# =============================================================================

proc env_or {name default_value} {
    global env
    if {[info exists env($name)] && $env($name) ne ""} {
        return $env($name)
    }
    return $default_value
}

proc env_bool {name default_value} {
    set raw [string tolower [env_or $name $default_value]]
    if {$raw in [list 1 true yes on]} {
        return 1
    }
    if {$raw in [list 0 false no off]} {
        return 0
    }
    error "$name must be one of: 1/0, true/false, yes/no, on/off"
}

proc split_host_list {raw} {
    set normalized [string map [list "," " " ";" " "] $raw]
    set result [list]
    foreach item [split $normalized] {
        if {$item ne ""} {
            lappend result $item
        }
    }
    return $result
}

proc verify_or_repair_port_function {port_name expected_function allow_repair} {
    set objects [get_ports $port_name]
    set object_count [sizeof_collection $objects]

    if {$object_count != 1} {
        error "Expected exactly one top-level port '$port_name'; found $object_count"
    }

    if {[catch {
        set before [get_attribute_value_list $objects -name function]
    } read_error]} {
        set before "<unreadable: $read_error>"
    }

    puts "ATTRIBUTE_CHECK $port_name before='$before' expected='$expected_function'"

    if {$before ne $expected_function} {
        if {!$allow_repair} {
            error "Port '$port_name' did not retain function='$expected_function' from Pass 1. Set ALLOW_ATTRIBUTE_REPAIR=1 only after confirming the target object with get_ports/report_attributes."
        }

        set_attribute_value $objects \
            -name function \
            -value $expected_function

        set after [get_attribute_value_list $objects -name function]
        puts "ATTRIBUTE_CHECK $port_name after='$after'"

        if {$after ne $expected_function} {
            error "Attribute repair did not persist immediately on port '$port_name'"
        }
    }
}

set die_position [string tolower [env_or DIE_POSITION ""]]
if {$die_position ni [list bottom middle top]} {
    error "Set DIE_POSITION to bottom, middle, or top"
}

set top_module       [env_or TOP_MODULE basic_die_top]
set tsdb_dir         [file normalize [env_or TSDB_DIR ./tsdb_basic]]
set pass1_design_id  [env_or PASS1_DESIGN_ID rtl_1687]
set pass2_design_id  [env_or PASS2_DESIGN_ID rtl_1687_1838_${die_position}]
set output_dir       [file normalize [env_or OUTPUT_DIR ./generated_pass2]]
set allow_attr_fix   [env_bool ALLOW_ATTRIBUTE_REPAIR 0]
set spec_only        [env_bool SPEC_ONLY 0]
set write_flat_rtl   [env_bool WRITE_FLAT_RTL 1]

file mkdir $output_dir

set inserted_rtl  ${output_dir}/${top_module}_${die_position}_1687_1838_inserted.v
set dc_import_tcl ${output_dir}/${top_module}_${die_position}_1687_1838_dc_import.tcl

puts "PASS2_CONFIG die_position=$die_position"
puts "PASS2_CONFIG top_module=$top_module"
puts "PASS2_CONFIG tsdb_dir=$tsdb_dir"
puts "PASS2_CONFIG pass1_design_id=$pass1_design_id"
puts "PASS2_CONFIG pass2_design_id=$pass2_design_id"

set_context dft -rtl -design_id $pass2_design_id
set_tsdb_output_directory $tsdb_dir

# Critical: load the cumulative Pass 1 design view.  Do not read golden RTL.
read_design $top_module \
    -design_id $pass1_design_id \
    -verbose

set_current_design $top_module
set_design_level chip

# Pass 1 should already contain these attributes.  By default this is a
# verification gate, not a second blind set_attribute_value operation.
foreach {port_name function_name} {
    tck  tck
    tms  tms
    tdi  tdi
    tdo  tdo
    trst trst
} {
    verify_or_repair_port_function \
        $port_name \
        $function_name \
        $allow_attr_fix
}

# This report can be release/license dependent, so failure is informative.
# The final acceptance gate is still the generated specification plus the
# extracted ICL and retargeted pattern.
if {[catch {report_module_matching -icl} matching_error]} {
    puts "WARNING: report_module_matching -icl was unavailable or failed: $matching_error"
}

set_dft_specification_requirements -host_scan_interface_type tap
check_design_rules

switch -- $die_position {
    bottom -
    middle {
        set stap_hosts [split_host_list [env_or STAP_HOST_LIST s1]]
        if {[llength $stap_hosts] == 0} {
            error "$die_position die must name at least one downstream STAP host"
        }

        # Multi-die augmentation request: reuse/augment the existing Pass 1 TAP
        # and create the STAP connection(s) to the next die(s).
        set spec [create_dft_specification \
            -stap_host_list $stap_hosts]
    }

    top {
        set top_strategy [string tolower [env_or TOP_PTAP_STRATEGY ""]]
        if {$top_strategy ne "empty_stap_list"} {
            help create_dft_specification
            error "Top die requires a PTAP but no downstream STAP. Tessent 2025.02/support-kit syntax must be confirmed locally. If help confirms an empty -stap_host_list creates PTAP-only, rerun with TOP_PTAP_STRATEGY=empty_stap_list. The script stopped before insertion."
        }

        # Candidate supported by some Multi-die flows.  SPEC_ONLY=1 is
        # strongly recommended on the first run for this top-die branch.
        set spec [create_dft_specification \
            -stap_host_list [list]]
    }
}

puts "PASS2_SPEC_BEGIN"
report_config_data $spec
puts "PASS2_SPEC_END"

puts "PASS2_CHECKPOINT:"
puts "  1. The Pass 1 TAP is augmented/reused as the PTAP."
puts "  2. The existing HostIjtag/SIB/TDR is not created again."
puts "  3. bottom/middle: STAP host count = downstream-die count."
puts "  4. top: PTAP exists and STAP count is zero."

process_dft_specification -validate_only

if {$spec_only} {
    puts "SPEC_ONLY=1: validation completed; no RTL or TSDB write was performed"
    exit
}

process_dft_specification
extract_icl

# Save the cumulative RTL + ICL + PDL + DFT metadata as the Pass 2 view.
write_design -tsdb -verbose

if {$write_flat_rtl} {
    write_design \
        -output_file $inserted_rtl \
        -replace
}

write_design_import_script \
    $dc_import_tcl \
    -replace \
    -use_relative_path_to [pwd]

puts "PASS2_COMPLETED"
puts "Inserted RTL : $inserted_rtl"
puts "DC import Tcl: $dc_import_tcl"
puts "TSDB         : $tsdb_dir"
puts "Design ID    : $pass2_design_id"
exit
