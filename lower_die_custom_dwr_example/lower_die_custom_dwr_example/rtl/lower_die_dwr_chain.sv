`timescale 1ns/1ps

module lower_die_dwr_chain (
    input  wire       tck,
    input  wire       trst_n,

    input  wire       dwr_select,
    input  wire       dwr_capture_en,
    input  wire       dwr_shift_en,
    input  wire       dwr_update_en,
    input  wire       dwr_scan_in,
    output wire       dwr_scan_out,

    input  wire       dwr_enable,
    input  wire       dwr_intest_mode,
    input  wire       dwr_extest_mode,

    input  wire [7:0] d2d_operand_a_in,
    input  wire [7:0] d2d_operand_b_in,
    input  wire [2:0] d2d_opcode_in,

    output wire [7:0] core_operand_a,
    output wire [7:0] core_operand_b,
    output wire [2:0] core_opcode,

    input  wire [7:0] core_result,
    input  wire       core_zero_flag,
    input  wire       core_carry_flag,
    input  wire       core_overflow_flag,

    output wire [7:0] d2d_result_out,
    output wire       d2d_zero_flag_out,
    output wire       d2d_carry_flag_out,
    output wire       d2d_overflow_flag_out
);

    localparam integer DWR_WIDTH = 30;
    localparam integer A_BASE    = 0;
    localparam integer B_BASE    = 8;
    localparam integer OP_BASE   = 16;
    localparam integer RES_BASE  = 19;
    localparam integer ZERO_BIT  = 27;
    localparam integer CARRY_BIT = 28;
    localparam integer OVF_BIT   = 29;

    wire [DWR_WIDTH:0] scan_link;

    wire input_apply;
    wire output_apply;

    assign input_apply = dwr_enable &&
                         dwr_intest_mode &&
                         !dwr_extest_mode;

    assign output_apply = dwr_enable &&
                          dwr_extest_mode &&
                          !dwr_intest_mode;

    assign scan_link[0] = dwr_scan_in;
    assign dwr_scan_out = scan_link[DWR_WIDTH];

    genvar i;
    generate
        for (i = 0; i < 8; i = i + 1) begin : gen_operand_a_dwr
            dwr_boundary_cell u_dwr_cell (
                .tck           (tck),
                .trst_n        (trst_n),
                .dwr_select    (dwr_select),
                .capture_en    (dwr_capture_en),
                .shift_en      (dwr_shift_en),
                .update_en     (dwr_update_en),
                .scan_in       (scan_link[A_BASE + i]),
                .scan_out      (scan_link[A_BASE + i + 1]),
                .functional_in (d2d_operand_a_in[i]),
                .functional_out(core_operand_a[i]),
                .test_apply    (input_apply)
            );
        end

        for (i = 0; i < 8; i = i + 1) begin : gen_operand_b_dwr
            dwr_boundary_cell u_dwr_cell (
                .tck           (tck),
                .trst_n        (trst_n),
                .dwr_select    (dwr_select),
                .capture_en    (dwr_capture_en),
                .shift_en      (dwr_shift_en),
                .update_en     (dwr_update_en),
                .scan_in       (scan_link[B_BASE + i]),
                .scan_out      (scan_link[B_BASE + i + 1]),
                .functional_in (d2d_operand_b_in[i]),
                .functional_out(core_operand_b[i]),
                .test_apply    (input_apply)
            );
        end

        for (i = 0; i < 3; i = i + 1) begin : gen_opcode_dwr
            dwr_boundary_cell u_dwr_cell (
                .tck           (tck),
                .trst_n        (trst_n),
                .dwr_select    (dwr_select),
                .capture_en    (dwr_capture_en),
                .shift_en      (dwr_shift_en),
                .update_en     (dwr_update_en),
                .scan_in       (scan_link[OP_BASE + i]),
                .scan_out      (scan_link[OP_BASE + i + 1]),
                .functional_in (d2d_opcode_in[i]),
                .functional_out(core_opcode[i]),
                .test_apply    (input_apply)
            );
        end

        for (i = 0; i < 8; i = i + 1) begin : gen_result_dwr
            dwr_boundary_cell u_dwr_cell (
                .tck           (tck),
                .trst_n        (trst_n),
                .dwr_select    (dwr_select),
                .capture_en    (dwr_capture_en),
                .shift_en      (dwr_shift_en),
                .update_en     (dwr_update_en),
                .scan_in       (scan_link[RES_BASE + i]),
                .scan_out      (scan_link[RES_BASE + i + 1]),
                .functional_in (core_result[i]),
                .functional_out(d2d_result_out[i]),
                .test_apply    (output_apply)
            );
        end
    endgenerate

    dwr_boundary_cell u_zero_flag_dwr (
        .tck           (tck),
        .trst_n        (trst_n),
        .dwr_select    (dwr_select),
        .capture_en    (dwr_capture_en),
        .shift_en      (dwr_shift_en),
        .update_en     (dwr_update_en),
        .scan_in       (scan_link[ZERO_BIT]),
        .scan_out      (scan_link[ZERO_BIT + 1]),
        .functional_in (core_zero_flag),
        .functional_out(d2d_zero_flag_out),
        .test_apply    (output_apply)
    );

    dwr_boundary_cell u_carry_flag_dwr (
        .tck           (tck),
        .trst_n        (trst_n),
        .dwr_select    (dwr_select),
        .capture_en    (dwr_capture_en),
        .shift_en      (dwr_shift_en),
        .update_en     (dwr_update_en),
        .scan_in       (scan_link[CARRY_BIT]),
        .scan_out      (scan_link[CARRY_BIT + 1]),
        .functional_in (core_carry_flag),
        .functional_out(d2d_carry_flag_out),
        .test_apply    (output_apply)
    );

    dwr_boundary_cell u_overflow_flag_dwr (
        .tck           (tck),
        .trst_n        (trst_n),
        .dwr_select    (dwr_select),
        .capture_en    (dwr_capture_en),
        .shift_en      (dwr_shift_en),
        .update_en     (dwr_update_en),
        .scan_in       (scan_link[OVF_BIT]),
        .scan_out      (scan_link[OVF_BIT + 1]),
        .functional_in (core_overflow_flag),
        .functional_out(d2d_overflow_flag_out),
        .test_apply    (output_apply)
    );

endmodule
