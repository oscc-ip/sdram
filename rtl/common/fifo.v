`timescale 1ns / 1ns

module fifo #(
    parameter WIDTH = 8,
    parameter DEPTH = 8
) (
    input  wire                 i_wr_clk,
    input  wire                 i_wr_rst_n,
    input  wire                 i_wr_en,
    input  wire [WIDTH - 1 : 0] i_wr_data,
    output wire                 o_wr_full,
    output reg  [DEPTH - 1 : 0] o_wr_use,

    input  wire                 i_rd_clk,
    input  wire                 i_rd_rst_n,
    input  wire                 i_rd_en,
    output reg  [WIDTH - 1 : 0] o_rd_data,
    output wire                 o_rd_empty,
    output reg  [DEPTH - 1 : 0] o_rd_use
);

reg [$clog2(DEPTH) : 0] wr_ptr, rd_ptr;
reg [WIDTH - 1 : 0] fifo[DEPTH - 1 : 0];

// Write operation
always @(posedge i_wr_clk or negedge i_wr_rst_n) begin
    if (!i_wr_rst_n) begin
        wr_ptr <= 0;
    end
    else if (i_wr_en && !o_wr_full) begin
        fifo[wr_ptr] <= i_wr_data;
        wr_ptr <= wr_ptr + 1;
    end
    else begin
        wr_ptr <= wr_ptr;
    end
end

// Read operation
always @(posedge i_rd_clk or negedge i_rd_rst_n) begin
    if (!i_rd_rst_n) begin
        o_rd_data <= 0;
        rd_ptr    <= 0;
    end
    else if (i_rd_en && !o_rd_empty) begin
        o_rd_data <= fifo[rd_ptr];
        rd_ptr    <= rd_ptr + 1;
    end
    else begin
        rd_ptr <= rd_ptr;
    end
end

//-----------------------------------------------------------------------------

wire [$clog2(DEPTH) : 0] wr_ptr_grey, rd_ptr_grey;

assign wr_ptr_grey = wr_ptr ^ (wr_ptr >>> 1);
assign rd_ptr_grey = rd_ptr ^ (rd_ptr >>> 1);

reg [$clog2(DEPTH) : 0] wr_ptr_grey_d1, rd_ptr_grey_d1,
                        wr_ptr_grey_d2, rd_ptr_grey_d2;

// Write pointer synchronization to read clock domain
always @(posedge i_rd_clk or negedge i_rd_rst_n) begin
    if (!i_rd_rst_n) begin
        wr_ptr_grey_d1 <= 0;
        wr_ptr_grey_d2 <= 0;
    end
    else begin
        wr_ptr_grey_d1 <= wr_ptr_grey;
        wr_ptr_grey_d2 <= wr_ptr_grey_d1;
    end
end

// Read pointer synchronization to write clock domain
always @(posedge i_wr_clk or negedge i_wr_rst_n) begin
    if (!i_wr_rst_n) begin
        rd_ptr_grey_d1 <= 0;
        rd_ptr_grey_d2 <= 0;
    end
    else begin
        rd_ptr_grey_d1 <= rd_ptr_grey;
        rd_ptr_grey_d2 <= rd_ptr_grey_d1;
    end
end

//-----------------------------------------------------------------------------

// Write full judgment
assign o_wr_full = (!i_wr_rst_n) ? 0 :
                   ((wr_ptr_grey   [$clog2(DEPTH)]         !=
                     rd_ptr_grey_d2[$clog2(DEPTH)])        &&
                    (wr_ptr_grey   [$clog2(DEPTH) - 1]     !=
                     rd_ptr_grey_d2[$clog2(DEPTH) - 1])    &&
                    (wr_ptr_grey   [$clog2(DEPTH) - 2 : 0] ==
                     rd_ptr_grey_d2[$clog2(DEPTH) - 2 : 0])) ? 1 : 0;

// Read empty judgment
assign o_rd_empty = (!i_rd_rst_n) ? 0 :
                    (wr_ptr_grey_d2[$clog2(DEPTH) : 0] ==
                     rd_ptr_grey   [$clog2(DEPTH) : 0]) ? 1 : 0;

// Write clock domain used space
reg [$clog2(DEPTH) : 0] rd_ptr_grey_d2_bin;

integer i;
always @(rd_ptr_grey_d2) begin
    for (i = 0; i < $clog2(DEPTH) + 1; i++)
        rd_ptr_grey_d2_bin[i] = ^(rd_ptr_grey_d2 >> i);
end

always @(posedge i_wr_clk or negedge i_wr_rst_n) begin
    if (!i_wr_rst_n) begin
        o_wr_use <= 0;
    end
    else begin
        o_wr_use <= wr_ptr - rd_ptr_grey_d2_bin;
    end
end

reg [$clog2(DEPTH) : 0] wr_ptr_grey_d2_bin;

integer j;
always @(wr_ptr_grey_d2) begin
    for (j = 0; j < $clog2(DEPTH) + 1; j++)
        wr_ptr_grey_d2_bin[j] = ^(wr_ptr_grey_d2 >> j);
end

// Read clock domain used space
always @(posedge i_rd_clk or negedge i_rd_rst_n) begin
    if (!i_rd_rst_n) begin
        o_rd_use <= 0;
    end
    else begin
        o_rd_use <= wr_ptr_grey_d2_bin - rd_ptr;
    end
end

endmodule



// module fifo #(
//     parameter WIDTH = 16,
//     parameter DEPTH = 10
// ) (
//     input  wire                      clr,

//     input  wire                      wr_clk,
//     input  wire                      wr_req,
//     input  wire [WIDTH - 1 : 0] wr_data,

//     input  wire                      rd_clk,
//     input  wire                      rd_req,
//     output wire [WIDTH - 1 : 0] rd_data,

//     output reg  [DEPTH - 1 : 0] wr_use_num,
//     output reg  [DEPTH - 1 : 0] rd_use_num,
//     output reg                       wr_empty,
//     output reg                       rd_empty,
//     output reg                       wr_full,
//     output reg                       rd_full
// );

// //-----------------------------------------------------------------------------

// reg [WIDTH - 1 : 0] fifo[DEPTH - 1 : 0];
// reg [DEPTH - 1 : 0] cnt;

// wire wr_valid;
// wire rd_valid;

// //-----------------------------------------------------------------------------

// always @(clr) begin
//     if (clr) begin
//         cnt <= { (DEPTH){1'b0} };
//     end
// end

// always @(posedge wr_clk) begin
//     if (clr) begin
//         wr_use_num <= { (DEPTH){1'b0} };
//         wr_empty   <= 1'b0;
//         wr_full    <= 1'b0;
//     end
//     else if (wr_req & wr_valid) begin
//         if (cnt == 1'b0) begin
//             wr_use_num <= { (DEPTH){1'b0} };
//         end
//         fifo[cnt] <= wr_data;
//         if (~(rd_req & rd_valid)) begin
//             cnt        <= cnt + 1'd1;
//             wr_use_num <= wr_use_num + 1'd1;
//         end
//     end

//     if (cnt == 1'b0) begin
//         wr_empty <= 1'b1;
//         if (!wr_req) begin
//             wr_use_num <= { (DEPTH){1'b0} };
//         end
//     end
//     else begin
//         wr_empty <= 1'b0;
//     end

//     if (cnt == DEPTH - 1'b1) begin
//         wr_full <= 1'b1;
//     end
//     else begin
//         wr_full <= 1'b0;
//     end
// end

// always @(posedge rd_clk) begin
//     if (clr) begin
//         rd_use_num <= { (DEPTH){1'b0} };
//         rd_empty   <= 1'b0;
//         rd_full    <= 1'b0;
//     end
//     else if (rd_req & rd_valid) begin
//         if (~(wr_req & wr_valid)) begin
//             cnt        <= cnt - 1'd1;
//             rd_use_num <= rd_use_num + 1'd1;
//         end
//     end

//     if (cnt == 1'b0) begin
//         rd_empty   <= 1'b1;
//         rd_use_num <= { (DEPTH){1'b0} };
//     end
//     else begin
//         rd_empty <= 1'b0;
//     end

//     if (cnt == DEPTH - 1'b1) begin
//         rd_full <= 1'b1;
//     end
//     else begin
//         rd_full <= 1'b0;
//     end
// end

// assign wr_valid = (cnt != DEPTH);
// assign rd_valid = (cnt != 1'b0);

// assign rd_data  = (clr) ?                  { (WIDTH){1'b0} } :
//                   (~(rd_req & rd_valid)) ? { (WIDTH){1'b0} } :
//                   fifo[rd_use_num];

// endmodule
