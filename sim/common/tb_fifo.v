`timescale 1ns / 1ns

module tb_fifo();

parameter CYCLE = 10;

reg           clk;
reg           rst_n;

wire          fifo_clk;

wire          fifo_wr_clk;
wire          fifo_wr_rst;
wire          fifo_wr_req;
wire [15 : 0] fifo_wr_data;
wire [ 9 : 0] fifo_wr_num;

wire          fifo_rd_clk;
wire          fifo_rd_rst;
wire          fifo_rd_req;
wire [15 : 0] fifo_rd_data;
wire [ 9 : 0] fifo_rd_num;

wire          sdram_wr_ack;
wire [15 : 0] sdram_wr_data;

wire          sdram_rd_ack;
wire [15 : 0] sdram_rd_data;

initial begin
    clk   = 1'b1;
    rst_n = 1'b0;
    #(CYCLE * 10)
    rst_n = 1'b1;
end

always #(CYCLE / 2) clk = ~clk;

fifo fifo_wr_inst(
    .clr       (~fifo_clk || fifo_wr_rst),

    .wr_clk    (fifo_wr_clk),
    .wr_req    (fifo_wr_req),
    .wr_data   (fifo_wr_data),

    .rd_clk    (fifo_clk),
    .rd_req    (sdram_wr_ack),
    .rd_data   (sdram_wr_data),

    .wr_use_num(fifo_wr_num),
    .rd_use_num()
);

fifo fifo_rd_inst(
    .clr       (~fifo_clk || fifo_rd_rst),

    .wr_clk    (fifo_clk),
    .wr_req    (sdram_rd_ack),
    .wr_data   (sdram_rd_data),

    .rd_clk    (fifo_rd_clk),
    .rd_req    (fifo_rd_req),
    .rd_data   (fifo_rd_data),

    .wr_use_num(),
    .rd_use_num(fifo_rd_num)
);

endmodule
