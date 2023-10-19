`timescale 1ns / 1ns

module tb_fifo();

parameter CYCLE = 10;

reg           fifo_clk;
reg           fifo_rst_n;

wire          fifo_wr_clk;
wire          fifo_wr_rst;
reg           fifo_wr_req;
reg  [15 : 0] fifo_wr_data;
wire [ 9 : 0] fifo_wr_num;
wire          fifo_wr_empty;
wire          fifo_wr_full;

wire          fifo_rd_clk;
wire          fifo_rd_rst;
reg           fifo_rd_req;
wire [15 : 0] fifo_rd_data;
wire [ 9 : 0] fifo_rd_num;
wire          fifo_rd_empty;
wire          fifo_rd_full;

reg           module_wr_ack;
wire [15 : 0] module_wr_data;

reg           module_rd_ack;
wire [15 : 0] module_rd_data;

initial begin
    fifo_clk   = 1'b1;
    fifo_rst_n = 1'b0;
    #(CYCLE * 10)
    fifo_rst_n = 1'b1;
end

always #(CYCLE / 2) fifo_clk = ~fifo_clk;

assign fifo_wr_clk = fifo_clk;
assign fifo_rd_clk = fifo_clk;

assign fifo_wr_rst = 1'b0;

always @(posedge fifo_wr_clk) begin
    if (!fifo_rst_n) begin
        fifo_wr_req  <= 1'b0;
        fifo_wr_data <= 16'h0000;
    end
    else begin
        if (!module_wr_ack) begin
            fifo_wr_req  <= 1'b1;
            fifo_wr_data <= fifo_wr_data + 1'b1;
        end
        else begin
            fifo_wr_req  <= 1'b0;
            fifo_wr_data <= fifo_wr_data;
        end
    end
end

always @(posedge fifo_clk) begin
    if (!fifo_rst_n) begin
        module_wr_ack  <= 1'b0;
    end
    else begin
        if (fifo_wr_full) begin
            module_wr_ack <= 1'b1;
        end
        else if (fifo_wr_empty) begin
            module_wr_ack <= 1'b0;
        end
        else begin
            module_wr_ack <= module_wr_ack;
        end
    end
end

fifo #(
    .DATA_WIDTH(16),
    .DATA_DEPTH(10)
)
fifo_wr_inst(
    .clr       (~fifo_rst_n || fifo_wr_rst),

    .wr_clk    (fifo_wr_clk),
    .wr_req    (fifo_wr_req),
    .wr_data   (fifo_wr_data),

    .rd_clk    (fifo_clk),
    .rd_req    (module_wr_ack),
    .rd_data   (module_wr_data),

    .wr_use_num(fifo_wr_num),
    .rd_use_num(),
    .wr_empty  (fifo_wr_empty),
    .rd_empty  (fifo_rd_empty),
    .wr_full   (fifo_wr_full),
    .rd_full   (fifo_rd_full)
);

// fifo #(
//     .DATA_WIDTH(16),
//     .DATA_DEPTH(10)
// )
// fifo_rd_inst (
//     .clr       (~fifo_clk || fifo_rd_rst),

//     .wr_clk    (fifo_clk),
//     .wr_req    (module_rd_ack),
//     .wr_data   (module_rd_data),

//     .rd_clk    (fifo_rd_clk),
//     .rd_req    (fifo_rd_req),
//     .rd_data   (fifo_rd_data),

//     .wr_use_num(),
//     .rd_use_num(fifo_rd_num)
// );

endmodule
