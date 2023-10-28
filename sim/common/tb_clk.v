`timescale 1ns / 1ns

module tb_clk();

parameter CYCLE = 20;

reg sys_clk;
reg sys_rst_n;

wire sys_clk_div_even;
wire sys_clk_div_odd;
wire sys_clk_mul_dly_2x;

initial begin
    sys_clk   = 1'b1;
    sys_rst_n = 1'b0;
    #(CYCLE * 10)
    sys_rst_n = 1'b1;
end

always #(CYCLE / 2) sys_clk = ~sys_clk;

clk clk_inst(
    .i_clk           d(sys_clk),
    .i_rst_n         (sys_rst_n),

    .o_clk_div_even  (sys_clk_div_even),
    .o_clk_div_odd   (sys_clk_div_odd),
    .o_clk_mul_dly_2x(sys_clk_mul_dly_2x)
);

endmodule
