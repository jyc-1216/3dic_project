# ============================================================
# Lower-die Tessent RTL IJTAG insertion flow
# ============================================================

set script_dir  [file dirname [file normalize [info script]]]
set project_dir [file dirname $script_dir]

set generated_dir ${project_dir}/generated
set tsdb_dir      ${project_dir}/tsdb_lower
set inserted_rtl  ${generated_dir}/lower_die_ijtag_inserted.v
set dc_import_tcl ${generated_dir}/lower_die_dc_import.tcl

file mkdir $generated_dir
file mkdir $tsdb_dir
file mkdir ${project_dir}/logs

if {![info exists env(TESSENT_CELL_LIBRARY)]} {
    error "Set TESSENT_CELL_LIBRARY to the technology .tcelllib file"
}

# Load the golden Verilog-2001 RTL.
set_context dft -rtl -design_id rtl1
set_tsdb_output_directory $tsdb_dir

read_cell_library $env(TESSENT_CELL_LIBRARY)
read_verilog ${project_dir}/lower_die_alu_core.v
read_verilog ${project_dir}/lower_die_top.v

set_current_design lower_die_top
set_design_level chip

# Identify the external TAP ports.
set_attribute_value tck  -name function -value tck
set_attribute_value tms  -name function -value tms
set_attribute_value tdi  -name function -value tdi
set_attribute_value tdo  -name function -value tdo
set_attribute_value trst -name function -value trst

check_design_rules

# Insert one TAP, one ALU SIB, and one 30-bit ALU TDR.
set spec [create_dft_specification]

read_config_data -in $spec -from_string {
    IjtagNetwork {
        HostScanInterface(ijtag) {
            Interface {
                tck : tck;
            }

            Tap(single) {
                HostIjtag(1) {
                    Sib(alu) {
                        Tdr(alu_tdr) {
                            length : 30;

                            DataOutPorts {
                                connection(7:0)   : u_alu/operand_a[7:0];
                                connection(15:8)  : u_alu/operand_b[7:0];
                                connection(18:16) : u_alu/opcode[2:0];
                            }

                            DataInPorts {
                                connection(26:19) : u_alu/result[7:0];
                                connection(27)    : u_alu/zero_flag;
                                connection(28)    : u_alu/carry_flag;
                                connection(29)    : u_alu/overflow_flag;
                            }
                        }
                    }
                }
            }
        }
    }
}

report_config_data $spec
process_dft_specification
extract_icl

# Save the RTL-stage ICL/DFT metadata as design view rtl1.
puts "Saving rtl1 design view into TSDB: $tsdb_dir"
write_design -tsdb -verbose

# Write a readable post-DFT Verilog netlist.
puts "Writing post-DFT RTL: $inserted_rtl"
write_design -output_file $inserted_rtl -replace

# Generate the Synopsys DC design-loading script.
puts "Writing DC import script: $dc_import_tcl"
write_design_import_script \
    $dc_import_tcl \
    -replace \
    -use_relative_path_to $project_dir

puts "Lower-die Tessent RTL IJTAG insertion completed"
exit
