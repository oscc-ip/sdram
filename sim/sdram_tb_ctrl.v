`timescale 1ns / 1ns

module sdram_tb_ctrl();

`include "Config-AC.v"

parameter CYCLE = 10;

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
wire          sdram_wr_ack;
wire          sdram_rd_ack;

reg           wr_en;
reg           rd_en;
reg  [15 : 0] wr_data_in;
wire [15 : 0] rd_data_out;

initial begin
    clk   = 1'b1;
    rst_n = 1'b0;
    #(CYCLE * 10)
    rst_n = 1'b1;
end

always #(CYCLE / 2) clk = ~clk;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        wr_en <= 1'b1;
    end
    else if (wr_data_in == 10'd10) begin
        wr_en <= 1'b0;
    end
    else begin
        wr_en <= wr_en;
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        rd_en <= 1'b0;
    end
    else if (!wr_en) begin
        rd_en <= 1'b1;
    end
    else begin
        rd_en <= rd_en;
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        wr_data_in <= 16'd0;
    end
    else if (wr_data_in == 16'd10) begin
        wr_data_in <= 16'd0;
    end
    else if (sdram_wr_ack) begin
        wr_data_in <= wr_data_in + 1'b1;
    end
    else begin
        wr_data_in <= wr_data_in;
    end
end

sdram_ctrl sdram_ctrl_inst(
    .sdram_clk       (clk),
    .sdram_rst_n     (rst_n),
    .init_end        (init_end)

    .sdram_wr_req    (wr_en),
    .sdram_wr_bst_len(10'd10),
    .sdram_wr_addr   (24'h000000),
    .sdram_wr_data   (wr_data_in),
    .sdram_wr_ack    (sdram_wr_ack),

    .sdram_rd_req    (rd_en),
    .sdram_rd_bst_len(10'd10),
    .sdram_rd_addr   (24'h000000),
    .sdram_rd_ack    (sdram_rd_ack),
    .sdram_rd_data   (rd_data_out),

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
