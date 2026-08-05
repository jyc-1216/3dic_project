`timescale 1ns/1ps

module lower_die_top_dwr_tb;

    localparam integer DWR_WIDTH = 30;

    reg        tck;
    reg        tms;
    reg        tdi;
    wire       tdo;
    reg        trst;

    reg  [7:0] d2d_operand_a_in;
    reg  [7:0] d2d_operand_b_in;
    reg  [2:0] d2d_opcode_in;

    wire [7:0] d2d_result_out;
    wire       d2d_zero_flag_out;
    wire       d2d_carry_flag_out;
    wire       d2d_overflow_flag_out;

    reg        dwr_select;
    reg        dwr_capture_en;
    reg        dwr_shift_en;
    reg        dwr_update_en;
    reg        dwr_scan_in;
    wire       dwr_scan_out;

    reg        dwr_enable;
    reg        dwr_intest_mode;
    reg        dwr_extest_mode;

    wire [7:0] alu_operand_a;
    wire [7:0] alu_operand_b;
    wire [2:0] alu_opcode;
    wire [7:0] alu_result;
    wire       alu_zero_flag;
    wire       alu_carry_flag;
    wire       alu_overflow_flag;

    reg [DWR_WIDTH-1:0] shift_input;
    reg [DWR_WIDTH-1:0] shift_output;
    reg [DWR_WIDTH-1:0] expected_capture;
    integer errors;

    lower_die_top dut (
        .tck                  (tck),
        .tms                  (tms),
        .tdi                  (tdi),
        .tdo                  (tdo),
        .trst                 (trst),
        .d2d_operand_a_in     (d2d_operand_a_in),
        .d2d_operand_b_in     (d2d_operand_b_in),
        .d2d_opcode_in        (d2d_opcode_in),
        .d2d_result_out       (d2d_result_out),
        .d2d_zero_flag_out    (d2d_zero_flag_out),
        .d2d_carry_flag_out   (d2d_carry_flag_out),
        .d2d_overflow_flag_out(d2d_overflow_flag_out),
        .dwr_select           (dwr_select),
        .dwr_capture_en       (dwr_capture_en),
        .dwr_shift_en         (dwr_shift_en),
        .dwr_update_en        (dwr_update_en),
        .dwr_scan_in          (dwr_scan_in),
        .dwr_scan_out         (dwr_scan_out),
        .dwr_enable           (dwr_enable),
        .dwr_intest_mode      (dwr_intest_mode),
        .dwr_extest_mode      (dwr_extest_mode),
        .alu_operand_a        (alu_operand_a),
        .alu_operand_b        (alu_operand_b),
        .alu_opcode           (alu_opcode),
        .alu_result           (alu_result),
        .alu_zero_flag        (alu_zero_flag),
        .alu_carry_flag       (alu_carry_flag),
        .alu_overflow_flag    (alu_overflow_flag)
    );

    always #5 tck = ~tck;

    task check_equal_8;
        input [8*40-1:0] name;
        input [7:0] actual;
        input [7:0] expected;
        begin
            if (actual !== expected) begin
                $display("FAIL: %0s actual=%02h expected=%02h", name, actual, expected);
                errors = errors + 1;
            end
        end
    endtask

    task check_equal_3;
        input [8*40-1:0] name;
        input [2:0] actual;
        input [2:0] expected;
        begin
            if (actual !== expected) begin
                $display("FAIL: %0s actual=%01h expected=%01h", name, actual, expected);
                errors = errors + 1;
            end
        end
    endtask

    task check_equal_1;
        input [8*40-1:0] name;
        input actual;
        input expected;
        begin
            if (actual !== expected) begin
                $display("FAIL: %0s actual=%0b expected=%0b", name, actual, expected);
                errors = errors + 1;
            end
        end
    endtask

    task pulse_capture;
        begin
            @(negedge tck);
            dwr_shift_en   = 1'b0;
            dwr_update_en  = 1'b0;
            dwr_capture_en = 1'b1;
            @(posedge tck);
            #1;
            dwr_capture_en = 1'b0;
        end
    endtask

    task shift_chain;
        input  [DWR_WIDTH-1:0] serial_input_value;
        output [DWR_WIDTH-1:0] serial_output_value;
        integer bit_index;
        begin
            dwr_capture_en = 1'b0;
            dwr_update_en  = 1'b0;
            for (bit_index = DWR_WIDTH - 1;
                 bit_index >= 0;
                 bit_index = bit_index - 1) begin
                @(negedge tck);
                dwr_shift_en = 1'b1;
                dwr_scan_in  = serial_input_value[bit_index];
                #1;
                serial_output_value[bit_index] = dwr_scan_out;
                @(posedge tck);
                #1;
            end
            @(negedge tck);
            dwr_shift_en = 1'b0;
            dwr_scan_in  = 1'b0;
        end
    endtask

    task pulse_update;
        begin
            @(posedge tck);
            #1;
            dwr_update_en = 1'b1;
            @(negedge tck);
            #1;
            dwr_update_en = 1'b0;
        end
    endtask

    initial begin
        tck              = 1'b0;
        tms              = 1'b0;
        tdi              = 1'b0;
        trst             = 1'b0;
        d2d_operand_a_in = 8'h00;
        d2d_operand_b_in = 8'h00;
        d2d_opcode_in    = 3'b000;
        dwr_select       = 1'b0;
        dwr_capture_en   = 1'b0;
        dwr_shift_en     = 1'b0;
        dwr_update_en    = 1'b0;
        dwr_scan_in      = 1'b0;
        dwr_enable       = 1'b0;
        dwr_intest_mode  = 1'b0;
        dwr_extest_mode  = 1'b0;
        shift_input      = {DWR_WIDTH{1'b0}};
        shift_output     = {DWR_WIDTH{1'b0}};
        expected_capture = {DWR_WIDTH{1'b0}};
        errors           = 0;

        repeat (2) @(negedge tck);
        trst       = 1'b1;
        dwr_select = 1'b1;

        d2d_operand_a_in = 8'h12;
        d2d_operand_b_in = 8'h34;
        d2d_opcode_in    = 3'b000;
        #1;

        check_equal_8("mission operand A", alu_operand_a, 8'h12);
        check_equal_8("mission operand B", alu_operand_b, 8'h34);
        check_equal_3("mission opcode", alu_opcode, 3'b000);
        check_equal_8("mission result", d2d_result_out, 8'h46);

        expected_capture[7:0]   = d2d_operand_a_in;
        expected_capture[15:8]  = d2d_operand_b_in;
        expected_capture[18:16] = d2d_opcode_in;
        expected_capture[26:19] = alu_result;
        expected_capture[27]    = alu_zero_flag;
        expected_capture[28]    = alu_carry_flag;
        expected_capture[29]    = alu_overflow_flag;

        pulse_capture();
        shift_chain({DWR_WIDTH{1'b0}}, shift_output);
        if (shift_output !== expected_capture) begin
            $display("FAIL: capture/shift actual=%08h expected=%08h",
                     shift_output, expected_capture);
            errors = errors + 1;
        end

        shift_input          = {DWR_WIDTH{1'b0}};
        shift_input[7:0]     = 8'h05;
        shift_input[15:8]    = 8'h03;
        shift_input[18:16]   = 3'b000;
        shift_output         = {DWR_WIDTH{1'b0}};
        shift_chain(shift_input, shift_output);
        pulse_update();

        dwr_enable      = 1'b1;
        dwr_intest_mode = 1'b1;
        dwr_extest_mode = 1'b0;
        #1;

        check_equal_8("INTEST operand A", alu_operand_a, 8'h05);
        check_equal_8("INTEST operand B", alu_operand_b, 8'h03);
        check_equal_3("INTEST opcode", alu_opcode, 3'b000);
        check_equal_8("INTEST core response", alu_result, 8'h08);
        check_equal_8("INTEST output pass-through", d2d_result_out, 8'h08);

        shift_input        = {DWR_WIDTH{1'b0}};
        shift_input[26:19] = 8'hA5;
        shift_input[27]    = 1'b1;
        shift_input[28]    = 1'b0;
        shift_input[29]    = 1'b1;
        shift_output       = {DWR_WIDTH{1'b0}};
        shift_chain(shift_input, shift_output);
        pulse_update();

        dwr_intest_mode = 1'b0;
        dwr_extest_mode = 1'b1;
        #1;

        check_equal_8("EXTEST result launch", d2d_result_out, 8'hA5);
        check_equal_1("EXTEST zero launch", d2d_zero_flag_out, 1'b1);
        check_equal_1("EXTEST carry launch", d2d_carry_flag_out, 1'b0);
        check_equal_1("EXTEST overflow launch", d2d_overflow_flag_out, 1'b1);

        dwr_enable      = 1'b0;
        dwr_extest_mode = 1'b0;
        d2d_operand_a_in = 8'h01;
        d2d_operand_b_in = 8'h02;
        #1;

        check_equal_8("return to mission operands", alu_operand_a, 8'h01);
        check_equal_8("return to mission output", d2d_result_out, 8'h03);

        if (errors == 0)
            $display("PASS: lower_die custom DWR example");
        else
            $display("FAIL: lower_die custom DWR example errors=%0d", errors);

        $finish;
    end

endmodule
