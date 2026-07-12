module lower_die_top (
    input  wire       tck,
    input  wire       tms,
    input  wire       tdi,
    output wire       tdo,
    input  wire       trst,

    output wire [7:0] alu_operand_a,
    output wire [7:0] alu_operand_b,
    output wire [2:0] alu_opcode,
    output wire [7:0] alu_result,
    output wire       alu_zero_flag,
    output wire       alu_carry_flag,
    output wire       alu_overflow_flag
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

endmodule
