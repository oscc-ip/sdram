module sdram_ctrl(
    input  wire          sdram_clk,
    input  wire          sdram_rst_n,
    output wire          sdram_init_end,

    input  wire          sdram_wr_req,
    input  wire [23 : 0] sdram_wr_addr,
    input  wire [15 : 0] sdram_wr_data,
    input  wire [ 9 : 0] sdram_wr_bst_len,
    output wire          sdram_wr_ack,

    input  wire          sdram_rd_req,
    input  wire [23 : 0] sdram_rd_addr,
    input  wire [ 9 : 0] sdram_rd_bst_len,
    output wire          sdram_rd_ack,
    output wire [15 : 0] sdram_rd_data,

    output wire          sdram_cke,
    output wire          sdram_cs_n,
    output wire          sdram_ras_n,
    output wire          sdram_cas_n,
    output wire          sdram_we_n,
    output wire [ 1 : 0] sdram_bank,
    output wire [12 : 0] sdram_addr,
    inout  wire [15 : 0] sdram_dq
);

wire [ 3 : 0] init_cmd;
wire [ 1 : 0] init_bank;
wire [12 : 0] init_addr;

wire          ar_en;
wire          ar_req;
wire          ar_end;
wire [ 3 : 0] ar_cmd;
wire [ 1 : 0] ar_bank;
wire [12 : 0] ar_addr;

wire          wr_en;
wire          wr_end;
wire          wr_sdram_en;
wire [ 3 : 0] wr_sdram_cmd;
wire [ 1 : 0] wr_sdram_bank;
wire [12 : 0] wr_sdram_addr;
wire [15 : 0] wr_sdram_data;

wire          rd_en;
wire          rd_end;
wire [ 3 : 0] rd_sdram_cmd;
wire [ 1 : 0] rd_sdram_bank;
wire [12 : 0] rd_sdram_addr;

sdram_arbit sdram_arbit_inst(
    .arb_clk      (sdram_clk),
    .arb_rst_n    (sdram_rst_n),

    .init_end     (sdram_init_end),
    .init_cmd     (init_cmd),
    .init_bank    (init_bank),
    .init_addr    (init_addr),

    .ar_req       (ar_req),
    .ar_end       (ar_end),
    .ar_cmd       (ar_cmd),
    .ar_bank      (ar_bank),
    .ar_addr      (ar_addr),

    .wr_req       (sdram_wr_req),
    .wr_end       (wr_end),
    .wr_cmd       (wr_sdram_cmd),
    .wr_bank      (wr_sdram_bank),
    .wr_addr      (wr_sdram_addr),
    .wr_sdram_en  (wr_sdram_en),
    .wr_sdram_data(wr_sdram_data),

    .rd_req       (sdram_rd_req),
    .rd_end       (rd_end),
    .rd_cmd       (rd_sdram_cmd),
    .rd_bank      (rd_sdram_bank),
    .rd_addr      (rd_sdram_addr),

    .ar_en        (ar_en),
    .wr_en        (wr_en),
    .rd_en        (rd_en),

    .sdram_cke    (sdram_cke),
    .sdram_cs_n   (sdram_cs_n),
    .sdram_ras_n  (sdram_rst_n),
    .sdram_cas_n  (sdram_cas_n),
    .sdram_we_n   (sdram_we_n),
    .sdram_bank   (sdram_bank),
    .sdram_addr   (sdram_addr),
    .sdram_dq     (sdram_dq)
);

sdram_init sdram_init_inst(
    .init_clk  (sdram_clk),
    .init_rst_n(sdram_rst_n),

    .init_end  (sdram_init_end),
    .init_cmd  (init_cmd),
    .init_bank (init_bank),
    .init_addr (init_addr)
);

sdram_aref sdram_aref_inst(
    .ar_clk  (sdram_clk),
    .ar_rst_n(sdram_rst_n),
    .ar_en   (ar_en),
    .init_end(sdram_init_end),

    .ar_req  (ar_req),
    .ar_end  (ar_end),
    .ar_cmd  (ar_cmd),
    .ar_bank (ar_bank),
    .ar_addr (ar_addr)
);

sdram_write sdram_write_inst(
    .wr_clk       (sdram_clk),
    .wr_rst_n     (sdram_rst_n),
    .wr_en        (wr_en),
    .wr_addr      (sdram_wr_addr),
    .wr_data      (sdram_wr_data),
    .wr_bst_len   (sdram_wr_bst_len),
    .init_end     (sdram_init_end),

    .wr_ack       (sdram_wr_ack),
    .wr_end       (wr_end),
    .wr_sdram_en  (wr_sdram_en),
    .wr_sdram_cmd (wr_sdram_cmd),
    .wr_sdram_bank(wr_sdram_bank),
    .wr_sdram_addr(wr_sdram_addr),
    .wr_sdram_data(wr_sdram_data)
);

sdram_read sdram_read_inst(
    .rd_clk       (sdram_clk),
    .rd_rst_n     (sdram_rst_n),
    .rd_en        (rd_en),
    .rd_addr      (sdram_rd_addr),
    .rd_data      (sdram_dq),
    .rd_bst_len   (sdram_rd_bst_len),
    .init_end     (sdram_init_end),

    .rd_ack       (sdram_rd_ack),
    .rd_end       (rd_end),
    .rd_sdram_cmd (rd_sdram_cmd),
    .rd_sdram_bank(rd_sdram_bank),
    .rd_sdram_addr(rd_sdram_addr),
    .rd_sdram_data(sdram_rd_data)
);

endmodule
