module sdram_fifo(
    input  wire          fifo_clk,
    input  wire          fifo_rst_n,

    input  wire          fifo_wr_clk,
    input  wire          fifo_wr_rst,
    input  wire          fifo_wr_req,
    input  wire [15 : 0] fifo_wr_data,
    input  wire [23 : 0] sdram_wr_addr_start,
    input  wire [23 : 0] sdram_wr_addr_end,
    input  wire [ 9 : 0] sdram_wr_bst_len,
    output wire [ 9 : 0] fifo_wr_num,

    input  wire          fifo_rd_clk,
    input  wire          fifo_rd_rst,
    input  wire          fifo_rd_req,
    input  wire [23 : 0] sdram_rd_addr_start,
    input  wire [23 : 0] sdram_rd_addr_end,
    input  wire [ 9 : 0] sdram_rd_bst_len,
    output wire [15 : 0] fifo_rd_data,
    output wire [ 9 : 0] fifo_rd_num,

    input  wire          sdram_rd_valid,
    input  wire          init_end,

    input  wire          sdram_wr_ack,
    output reg           sdram_wr_req,
    output reg  [23 : 0] sdram_wr_addr,
    output wire [15 : 0] sdram_wr_data,

    input  wire          sdram_rd_ack,
    input  wire [15 : 0] sdram_rd_data,
    output reg           sdram_rd_req,
    output reg  [23 : 0] sdram_rd_addr
);

`include "fifo.v"

//-----------------------------------------------------------------------------

reg sdram_wr_ack_beat_1;
reg sdram_wr_ack_beat_2;
reg sdram_rd_ack_beat_1;
reg sdram_rd_ack_beat_2;

wire sdram_wr_ack_fall_edge;
wire sdram_rd_ack_fall_dege;

//-----------------------------------------------------------------------------

always @(posedge sdram_clk or negedge sdram_rst_n) begin
    if (!sdram_rst_n) begin
        sdram_wr_ack_beat_1 <= 1'b0;
        sdram_wr_ack_beat_2 <= 1'b0;
    end
    else begin
        sdram_wr_ack_beat_1 <= sdram_wr_ack;
        sdram_wr_ack_beat_2 <= sdram_wr_ack_beat_1;
    end
end

always @(posedge sdram_clk or negedge sdram_rst_n) begin
    if (!sdram_rst_n) begin
        sdram_rd_ack_beat_1 <= 1'b0;
        sdram_rd_ack_beat_2 <= 1'b0;
    end
    else begin
        sdram_rd_ack_beat_1 <= sdram_rd_ack;
        sdram_rd_ack_beat_2 <= sdram_rd_ack_beat_1;
    end
end

assign sdram_wr_ack_fall_edge = (sdram_wr_ack_beat_2 & ~sdram_wr_ack_beat_1);
assign sdram_rd_ack_fall_dege = (sdram_rd_ack_beat_2 & ~sdram_rd_ack_beat_1);

always @(posedge sdram_clk or negedge sdram_rst_n) begin
    if (!sdram_rst_n) begin
        sdram_wr_addr <= 24'h000000;
    end
    else if (fifo_wr_rst) begin
        sdram_wr_addr <= sdram_wr_addr_start;
    end
    else if (sdram_wr_ack_fall_edge) begin
        if (sdram_wr_addr < (sdram_wr_addr_end - sdram_wr_bst_len)) begin
            sdram_wr_addr <= sdram_wr_addr + sdram_wr_bst_len;
        end
        else begin
            sdram_wr_addr <= sdram_wr_addr_start;
        end
    end
end

always @(posedge sdram_clk or negedge sdram_rst_n) begin
    if (!sdram_rst_n) begin
        sdram_rd_addr <= 24'h000000;
    end
    else if (fifo_rd_rst) begin
        sdram_rd_addr <= sdram_rd_addr_start;
    end
    else if (sdram_rd_ack_fall_edge) begin
        if (sdram_rd_addr < (sdram_rd_addr_end - sdram_rd_bst_len)) begin
            sdram_rd_addr <= sdram_rd_addr + sdram_rd_bst_len;
        end
        else begin
            sdram_rd_addr <= sdram_rd_addr_start;
        end
    end
end

always @(posedge sdram_clk or negedge sdram_rst_n) begin
    if (!sdram_rst_n) begin
        sdram_wr_req <= 1'b0;
        sdram_rd_req <= 1'b0;
    end
    else if (init_end) begin
        if (fifo_wr_num >= sdram_wr_bst_len) begin
            sdram_wr_req <= 1'b1;
            sdram_rd_req <= 1'b0;
        end
        else if ((fifo_rd_num < sdram_rd_bst_len) && sdram_rd_valid) begin
            sdram_wr_req <= 1'b0;
            sdram_rd_req <= 1'b1;
        end
        else begin
            sdram_wr_req <= 1'b0;
            sdram_rd_req <= 1'b0;
        end
    end
    else begin
        sdram_wr_req <= 1'b0;
        sdram_rd_req <= 1'b0;
    end
end

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
