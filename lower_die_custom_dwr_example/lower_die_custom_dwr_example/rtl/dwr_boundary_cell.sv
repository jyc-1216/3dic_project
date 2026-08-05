`timescale 1ns/1ps

module dwr_boundary_cell (
    input  wire tck,
    input  wire trst_n,

    input  wire dwr_select,
    input  wire capture_en,
    input  wire shift_en,
    input  wire update_en,

    input  wire scan_in,
    output wire scan_out,

    input  wire functional_in,
    output wire functional_out,
    input  wire test_apply
);

    reg shift_stage;
    reg update_stage;

    always @(posedge tck or negedge trst_n) begin
        if (!trst_n) begin
            shift_stage <= 1'b0;
        end
        else if (dwr_select) begin
            if (capture_en)
                shift_stage <= functional_in;
            else if (shift_en)
                shift_stage <= scan_in;
        end
    end

    always @(negedge tck or negedge trst_n) begin
        if (!trst_n)
            update_stage <= 1'b0;
        else if (dwr_select && update_en)
            update_stage <= shift_stage;
    end

    assign scan_out      = shift_stage;
    assign functional_out = test_apply ? update_stage : functional_in;

endmodule
