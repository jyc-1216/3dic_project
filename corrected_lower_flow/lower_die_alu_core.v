module lower_die_alu_core #(
    parameter DATA_WIDTH = 8
) (
    input  wire [DATA_WIDTH-1:0] operand_a,
    input  wire [DATA_WIDTH-1:0] operand_b,
    input  wire [2:0]            opcode,

    output reg  [DATA_WIDTH-1:0] result,
    output reg                   zero_flag,
    output reg                   carry_flag,
    output reg                   overflow_flag
);

    reg [DATA_WIDTH:0] extended_result;

    always @(*) begin
        result          = {DATA_WIDTH{1'b0}};
        extended_result = {(DATA_WIDTH+1){1'b0}};
        carry_flag      = 1'b0;
        overflow_flag   = 1'b0;

        case (opcode)
            3'b000: begin
                extended_result = {1'b0, operand_a} + {1'b0, operand_b};
                result          = extended_result[DATA_WIDTH-1:0];
                carry_flag      = extended_result[DATA_WIDTH];
                overflow_flag   = ~(operand_a[DATA_WIDTH-1] ^ operand_b[DATA_WIDTH-1]) &
                                  (result[DATA_WIDTH-1] ^ operand_a[DATA_WIDTH-1]);
            end

            3'b001: begin
                extended_result = {1'b0, operand_a} - {1'b0, operand_b};
                result          = extended_result[DATA_WIDTH-1:0];
                carry_flag      = (operand_a >= operand_b);
                overflow_flag   = (operand_a[DATA_WIDTH-1] ^ operand_b[DATA_WIDTH-1]) &
                                  (result[DATA_WIDTH-1] ^ operand_a[DATA_WIDTH-1]);
            end

            3'b010: result = operand_a & operand_b;
            3'b011: result = operand_a | operand_b;
            3'b100: result = operand_a ^ operand_b;
            3'b101: result = operand_a << 1;
            3'b110: result = operand_a >> 1;
            3'b111: result = {{(DATA_WIDTH-1){1'b0}},
                              ($signed(operand_a) < $signed(operand_b))};

            default: result = {DATA_WIDTH{1'b0}};
        endcase

        zero_flag = (result == {DATA_WIDTH{1'b0}});
    end

endmodule
