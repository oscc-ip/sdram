`timescale 1ns / 1ns

module tb_sdram_ctrl();

`include "Config-AC.v"
`include "../config/config.v"

reg           clk;
reg           rst_n;

wire          sdram_cke;
wire          sdram_cs_n;
wire          sdram_ras_n;
wire          sdram_cas_n;
wire          sdram_we_n;
wire [ 1 : 0] sdram_bank;
wire [12 : 0] sdram_addr;
wire [15 : 0] sdram_dq;

wire          init_end;
wire          wr_ack;
wire          rd_ack;

reg           wr_req;
reg           rd_req;
reg  [15 : 0] wr_data;
wire [15 : 0] rd_data;

initial begin
    clk   = 1'b1;
    rst_n = 1'b0;
    #(CYCLE * 10)
    rst_n = 1'b1;
end

always #(CYCLE / 2) clk = ~clk;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        wr_req <= 1'b1;
    end
    else if (wr_data == 10'd10) begin
        wr_req <= 1'b0;
    end
    else begin
        wr_req <= wr_req;
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        rd_req <= 1'b0;
    end
    else if (!wr_req) begin
        rd_req <= 1'b1;
    end
    else begin
        rd_req <= rd_req;
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        wr_data <= 16'd0;
    end
    else if (wr_data == 16'd10) begin
        wr_data <= 16'd0;
    end
    else if (wr_ack) begin
        wr_data <= wr_data + 1'b1;
    end
    else begin
        wr_data <= wr_data;
    end
end

sdram_ctrl sdram_ctrl_inst(
    .sdram_clk       (clk),
    .sdram_rst_n     (rst_n),
    .sdram_init_end  (init_end),

    .sdram_wr_req    (wr_req),
    .sdram_wr_addr   (24'h000000),
    .sdram_wr_data   (wr_data),
    .sdram_wr_bst_len(10'd10),
    .sdram_wr_ack    (wr_ack),

    .sdram_rd_req    (rd_req),
    .sdram_rd_addr   (24'h000000),
    .sdram_rd_bst_len(10'd10),
    .sdram_rd_ack    (rd_ack),
    .sdram_rd_data   (rd_data),

    .sdram_cke       (sdram_cke),
    .sdram_cs_n      (sdram_cs_n),
    .sdram_ras_n     (sdram_ras_n),
    .sdram_cas_n     (sdram_cas_n),
    .sdram_we_n      (sdram_we_n),
    .sdram_bank      (sdram_bank),
    .sdram_addr      (sdram_addr),
    .sdram_dq        (sdram_dq)
);

W989DxDB sdram_inst(
    .clk  (clk),
    .cke  (sdram_cke),
    .addr (sdram_addr),
    .ba   (sdram_bank),
    .cs_n (sdram_cs_n),
    .ras_n(sdram_ras_n),
    .cas_n(sdram_cas_n),
    .we_n (sdram_we_n),
    .dq   (sdram_dq),
    .dqm  (2'b0)
);

endmodule
