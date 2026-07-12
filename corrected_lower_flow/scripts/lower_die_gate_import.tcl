# ============================================================
# Lower-die gate-level import and ICL post-synthesis update
# ============================================================

set script_dir  [file dirname [file normalize [info script]]]
set project_dir [file dirname $script_dir]

set tsdb_dir    ${project_dir}/tsdb_lower
set gate_netlist ${project_dir}/generated/lower_die_ijtag_synthesized.v

if {![info exists env(TESSENT_CELL_LIBRARY)]} {
    error "Environment variable TESSENT_CELL_LIBRARY is not set"
}

if {![file exists $gate_netlist]} {
    error "Gate-level netlist does not exist: $gate_netlist"
}

set_context dft -no_rtl -design_id gate
set_tsdb_output_directory $tsdb_dir

read_cell_library $env(TESSENT_CELL_LIBRARY)
read_verilog $gate_netlist

# Load rtl1 metadata without reloading the old RTL netlist.
read_design \
    lower_die_top \
    -design_id rtl1 \
    -no_hdl \
    -verbose

set_current_design lower_die_top
set_design_level chip

# Explicitly report any RTL-to-gate ICL name-mapping failures.
update_icl_attributes_from_design -verbose
check_design_rules

# Save the new gate design view into the same TSDB.
write_design -tsdb -verbose

puts "Lower-die gate-level import and ICL update completed"
exit
