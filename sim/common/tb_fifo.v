`timescale 1ns / 1ns

module tb_fifo();

parameter WIDTH = 8;
parameter DEPTH = 8;

reg wr_clk, wr_rst_n, wr_en;
reg rd_clk, rd_rst_n, rd_en;

reg  [WIDTH - 1 : 0] wr_data;
wire [WIDTH - 1 : 0] rd_data;

wire wr_full, rd_empty;
wire [DEPTH - 1 : 0] wr_use, rd_use;

fifo fifo_inst(
    .i_wr_clk  (wr_clk),
    .i_wr_rst_n(wr_rst_n),
    .i_wr_en   (wr_en),
    .i_wr_data (wr_data),
    .o_wr_full (wr_full),
    .o_wr_use  (),

    .i_rd_clk  (rd_clk),
    .i_rd_rst_n(rd_rst_n),
    .i_rd_en   (rd_en),
    .o_rd_data (rd_data),
    .o_rd_empty(rd_empty),
    .o_rd_use  ()
);

initial begin
    wr_clk = 0;
    forever #(10 / 2) wr_clk = ~wr_clk; // 100MHz
end

initial begin
    rd_clk = 0;
    forever #(20 / 2) rd_clk = ~rd_clk; // 50MHz
end

initial begin
    $dumpfile("wave.vcd");
    $dumpvars(0, tb_fifo);
end

initial begin
    wr_en = 0;
    rd_en = 0;
    wr_rst_n = 1;
    rd_rst_n = 1;

    #10;
    wr_rst_n = 0;
    rd_rst_n = 0;

    #20
    wr_rst_n = 1;
    rd_rst_n = 1;

    @(negedge wr_clk)
    wr_data = {$random} % 30;
    wr_en = 1;

    repeat(7) begin
        @(negedge wr_clk)
        wr_data = {$random} % 30;
    end

    @(negedge wr_clk)
    wr_en = 0;

    @(negedge rd_clk)
    rd_en = 1;

    repeat(7) begin
        @(negedge rd_clk);
    end

    @(negedge rd_clk)
    rd_en = 0;

    #150;

    @(negedge wr_clk)
    wr_en = 1;
    wr_data = {$random} % 30;

    repeat(15) begin
        @(negedge wr_clk)
        wr_data = {$random} % 30;
    end

    @(negedge wr_clk)
    wr_en = 0;

    #50;
    $finish;
end

endmodule



// module tb_fifo();

// `include "../config/config.v"

// reg           fifo_clk;
// reg           fifo_rst_n;

// wire          fifo_wr_clk;
// wire          fifo_wr_rst;
// reg           fifo_wr_req;
// reg  [15 : 0] fifo_wr_data;
// wire [ 9 : 0] fifo_wr_num;
// wire          fifo_wr_empty;
// wire          fifo_wr_full;

// wire          fifo_rd_clk;
// wire          fifo_rd_rst;
// reg           fifo_rd_req;
// wire [15 : 0] fifo_rd_data;
// wire [ 9 : 0] fifo_rd_num;
// wire          fifo_rd_empty;
// wire          fifo_rd_full;

// reg           module_wr_ack;
// wire [15 : 0] module_wr_data;

// reg           module_rd_ack;
// wire [15 : 0] module_rd_data;

// initial begin
//     fifo_clk   = 1'b1;
//     fifo_rst_n = 1'b0;
//     #(CYCLE * 10)
//     fifo_rst_n = 1'b1;
// end

// always #(CYCLE / 2) fifo_clk = ~fifo_clk;

// assign fifo_wr_clk = fifo_clk;
// assign fifo_rd_clk = fifo_clk;

// assign fifo_wr_rst = 1'b0;

// always @(posedge fifo_wr_clk) begin
//     if (!fifo_rst_n) begin
//         fifo_wr_req  <= 1'b0;
//         fifo_wr_data <= 16'h0000;
//     end
//     else begin
//         if (!module_wr_ack) begin
//             fifo_wr_req  <= 1'b1;
//             fifo_wr_data <= fifo_wr_data + 1'b1;
//         end
//         else begin
//             fifo_wr_req  <= 1'b0;
//             fifo_wr_data <= fifo_wr_data;
//         end
//     end
// end

// always @(posedge fifo_clk) begin
//     if (!fifo_rst_n) begin
//         module_wr_ack  <= 1'b0;
//     end
//     else begin
//         if (fifo_wr_full) begin
//             module_wr_ack <= 1'b1;
//         end
//         else if (fifo_wr_empty) begin
//             module_wr_ack <= 1'b0;
//         end
//         else begin
//             module_wr_ack <= module_wr_ack;
//         end
//     end
// end

// fifo #(
//     .DATA_WIDTH(16),
//     .DATA_DEPTH(10)
// )
// fifo_wr_inst(
//     .clr       (~fifo_rst_n || fifo_wr_rst),

//     .wr_clk    (fifo_wr_clk),
//     .wr_req    (fifo_wr_req),
//     .wr_data   (fifo_wr_data),

//     .rd_clk    (fifo_clk),
//     .rd_req    (module_wr_ack),
//     .rd_data   (module_wr_data),

//     .wr_use_num(fifo_wr_num),
//     .rd_use_num(),
//     .wr_empty  (fifo_wr_empty),
//     .rd_empty  (fifo_rd_empty),
//     .wr_full   (fifo_wr_full),
//     .rd_full   (fifo_rd_full)
// );

// endmodule
