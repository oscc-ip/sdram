`timescale 1ns / 1ns

module fifo(
    input wire           clr,

    input  wire          wr_clk,
    input  wire          wr_req,
    input  wire [15 : 0] wr_data,

    input  wire          rd_clk,
    input  wire          rd_req,
    output wire [15 : 0] rd_data,

    output reg  [ 9 : 0] wr_use_num,
    output reg  [ 9 : 0] rd_use_num
);

assign rd_data = 16'h0000;

always @(posedge wr_clk) begin
    wr_use_num <= 16'h0000;
end

always @(posedge rd_clk) begin
    rd_use_num <= 16'h0000;
end

endmodule
