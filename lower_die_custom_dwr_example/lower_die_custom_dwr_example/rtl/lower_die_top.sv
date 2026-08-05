`timescale 1ns/1ps

module lower_die_top (
    input  wire       tck,
    input  wire       tms,
    input  wire       tdi,
    output wire       tdo,
    input  wire       trst,

    input  wire [7:0] d2d_operand_a_in,
    input  wire [7:0] d2d_operand_b_in,
    input  wire [2:0] d2d_opcode_in,

    output wire [7:0] d2d_result_out,
    output wire       d2d_zero_flag_out,
    output wire       d2d_carry_flag_out,
    output wire       d2d_overflow_flag_out,

    input  wire       dwr_select,
    input  wire       dwr_capture_en,
    input  wire       dwr_shift_en,
    input  wire       dwr_update_en,
    input  wire       dwr_scan_in,
    output wire       dwr_scan_out,

    input  wire       dwr_enable,
    input  wire       dwr_intest_mode,
    input  wire       dwr_extest_mode,

    output wire [7:0] alu_operand_a,
    output wire [7:0] alu_operand_b,
    output wire [2:0] alu_opcode,
    output wire [7:0] alu_result,
    output wire       alu_zero_flag,
    output wire       alu_carry_flag,
    output wire       alu_overflow_flag
);

    lower_die_dwr_chain u_dwr_chain (
        .tck                  (tck),
        .trst_n               (trst),
        .dwr_select           (dwr_select),
        .dwr_capture_en       (dwr_capture_en),
        .dwr_shift_en         (dwr_shift_en),
        .dwr_update_en        (dwr_update_en),
        .dwr_scan_in          (dwr_scan_in),
        .dwr_scan_out         (dwr_scan_out),
        .dwr_enable           (dwr_enable),
        .dwr_intest_mode      (dwr_intest_mode),
        .dwr_extest_mode      (dwr_extest_mode),
        .d2d_operand_a_in     (d2d_operand_a_in),
        .d2d_operand_b_in     (d2d_operand_b_in),
        .d2d_opcode_in        (d2d_opcode_in),
        .core_operand_a       (alu_operand_a),
        .core_operand_b       (alu_operand_b),
        .core_opcode          (alu_opcode),
        .core_result          (alu_result),
        .core_zero_flag       (alu_zero_flag),
        .core_carry_flag      (alu_carry_flag),
        .core_overflow_flag   (alu_overflow_flag),
        .d2d_result_out       (d2d_result_out),
        .d2d_zero_flag_out    (d2d_zero_flag_out),
        .d2d_carry_flag_out   (d2d_carry_flag_out),
        .d2d_overflow_flag_out(d2d_overflow_flag_out)
    );

    lower_die_alu_core #(
        .DATA_WIDTH(8)
    ) u_alu (
        .operand_a    (alu_operand_a),
        .operand_b    (alu_operand_b),
        .opcode       (alu_opcode),
        .result       (alu_result),
        .zero_flag    (alu_zero_flag),
        .carry_flag   (alu_carry_flag),
        .overflow_flag(alu_overflow_flag)
    );

    // tms/tdi/tdo belong to the existing Tessent PTAP access root.  This
    // custom DWR chain must be connected behind its existing HostIJTAG/SIB;
    // it must not instantiate or decode a second TAP here.

endmodule
