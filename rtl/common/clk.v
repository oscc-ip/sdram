`timescale 1ns / 1ns

module clk #(
    parameter NUM_FREQ_DIV_EVEN = 2,
    parameter NUM_FREQ_DIV_ODD  = 3,
    parameter NUM_FREQ_MUL      = 2
) (
    input  wire i_clk,
    input  wire i_rst_n,

    output reg  o_clk_div_even,
    output wire o_clk_div_odd,
    output wire o_clk_mul_dly_2x
);

//-----------------------------------------------------------------------------
// Even Frequency Division

reg [7 : 0] cnt_div_even;

parameter FREQ_REF     = 50_000_000; // 50MHz
parameter CNT_DIV_EVEN = NUM_FREQ_DIV_EVEN / 2 - 1;

always @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        cnt_div_even   <= 8'b0;
        o_clk_div_even <= 1'b0;
    end
    else begin
        if (cnt_div_even == CNT_DIV_EVEN) begin
            cnt_div_even   <= 8'b0;
            o_clk_div_even <= ~o_clk_div_even;
        end
        else begin
            cnt_div_even <= cnt_div_even + 1'b1;
        end
    end
end

//-----------------------------------------------------------------------------
// Odd Frequency Division

reg [7 : 0] cnt_div_odd_pos;
reg [7 : 0] cnt_div_odd_neg;
reg         clk_div_odd_pos;
reg         clk_div_odd_neg;

always @(negedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        cnt_div_odd_pos <= 8'b0;
        clk_div_odd_pos <= 1'b0;
    end
    else begin
        if (cnt_div_odd_pos == ((NUM_FREQ_DIV_ODD - 1) / 2) - 1) begin
            clk_div_odd_pos <= 1'b1;
        end
        else if (cnt_div_odd_pos == NUM_FREQ_DIV_ODD - 2) begin
            clk_div_odd_pos <= 1'b0;
        end
        else begin
        end

        if (cnt_div_odd_pos == NUM_FREQ_DIV_ODD - 1) begin
            cnt_div_odd_pos <= 8'b0;
        end
        else begin
            cnt_div_odd_pos <= cnt_div_odd_pos + 1'b1;
        end
    end
end

always @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        cnt_div_odd_neg <= 8'b0;
        clk_div_odd_neg <= 1'b0;
    end
    else begin
        if (cnt_div_odd_neg == ((NUM_FREQ_DIV_ODD - 1) / 2) - 1) begin
            clk_div_odd_neg <= 1'b1;
        end
        else if (cnt_div_odd_neg == NUM_FREQ_DIV_ODD - 2) begin
            clk_div_odd_neg <= 1'b0;
        end
        else begin
        end

        if (cnt_div_odd_neg == NUM_FREQ_DIV_ODD - 1) begin
            cnt_div_odd_neg <= 8'b0;
        end
        else begin
            cnt_div_odd_neg <= cnt_div_odd_neg + 1'b1;
        end
    end
end

assign o_clk_div_odd = clk_div_odd_pos | clk_div_odd_neg;

//-----------------------------------------------------------------------------
// Frequency Multiplier (Delay way)

parameter CYCLE_REF = 20; // 50MHz

reg clk_mul_dly_2x;

always @(posedge i_clk or negedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        clk_mul_dly_2x <= 1'b0;
    end
    else begin
        clk_mul_dly_2x <= #(CYCLE_REF / 2 / 2) ~clk_mul_dly_2x;
    end
end

assign o_clk_mul_dly_2x = i_clk ^ clk_mul_dly_2x;

endmodule
