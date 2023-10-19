`timescale 1ns / 1ns

module fifo #(
    parameter DATA_WIDTH = 16,
    parameter DATA_DEPTH = 10
) (
    input  wire                      clr,

    input  wire                      wr_clk,
    input  wire                      wr_req,
    input  wire [DATA_WIDTH - 1 : 0] wr_data,

    input  wire                      rd_clk,
    input  wire                      rd_req,
    output wire [DATA_WIDTH - 1 : 0] rd_data,

    output reg  [DATA_DEPTH - 1 : 0] wr_use_num,
    output reg  [DATA_DEPTH - 1 : 0] rd_use_num,
    output reg                       wr_empty,
    output reg                       rd_empty,
    output reg                       wr_full,
    output reg                       rd_full
);

//-----------------------------------------------------------------------------

reg [DATA_WIDTH - 1 : 0] fifo[DATA_DEPTH - 1 : 0];
reg [DATA_DEPTH - 1 : 0] cnt;

wire wr_valid;
wire rd_valid;

//-----------------------------------------------------------------------------

always @(clr) begin
    if (clr) begin
        cnt <= { (DATA_DEPTH){1'b0} };
    end
end

always @(posedge wr_clk) begin
    if (clr) begin
        wr_use_num <= { (DATA_DEPTH){1'b0} };
        wr_empty   <= 1'b0;
        wr_full    <= 1'b0;
    end
    else if (wr_req & wr_valid) begin
        fifo[wr_use_num] <= wr_data;
        wr_use_num       <= wr_use_num + 1'd1;
        if (~(rd_req & rd_valid)) begin
            cnt <= cnt + 1'd1;
        end
    end

    if (cnt == 1'b0) begin
        wr_empty <= 1'b1;
    end
    else begin
        wr_empty <= 1'b0;
    end

    if (cnt == DATA_DEPTH) begin
        wr_full <= 1'b1;
    end
    else begin
        wr_full <= 1'b0;
    end
end

always @(posedge rd_clk) begin
    if (clr) begin
        rd_use_num <= { (DATA_DEPTH){1'b0} };
        rd_empty   <= 1'b0;
        rd_full    <= 1'b0;
    end
    else if (rd_req & rd_valid) begin
        rd_use_num <= rd_use_num + 1'd1;
        if (~(wr_req & wr_valid)) begin
            cnt <= cnt - 1'd1;
        end
    end

    if (cnt == 1'b0) begin
        rd_empty <= 1'b1;
    end
    else begin
        rd_empty <= 1'b0;
    end

    if (cnt == DATA_DEPTH) begin
        rd_full <= 1'b1;
    end
    else begin
        rd_full <= 1'b0;
    end
end

assign wr_valid = (cnt != DATA_DEPTH);
assign rd_valid = (cnt != 1'b0);

assign rd_data  = (clr) ? { (DATA_WIDTH){1'b0} } : fifo[rd_use_num];

endmodule
