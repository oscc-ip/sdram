module sdram_arbit(
    input  wire          arb_clk,
    input  wire          arb_rst_n,

    input  wire          init_end,
    input  wire [ 3 : 0] init_cmd,
    input  wire [ 1 : 0] init_bank,
    input  wire [12 : 0] init_addr,

    input  wire          ar_req,
    input  wire          ar_end,
    input  wire [ 3 : 0] ar_cmd,
    input  wire [ 1 : 0] ar_bank,
    input  wire [12 : 0] ar_addr,

    input  wire          wr_req,
    input  wire          wr_end,
    input  wire [ 3 : 0] wr_cmd,
    input  wire [ 1 : 0] wr_bank,
    input  wire [12 : 0] wr_addr,
    input  wire          wr_sdram_en,
    input  wire [15 : 0] wr_sdram_data,

    input  wire          rd_req,
    input  wire          rd_end,
    input  wire [ 3 : 0] rd_cmd,
    input  wire [ 1 : 0] rd_bank,
    input  wire [12 : 0] rd_addr,

    output reg           ar_en,
    output reg           wr_en,
    output reg           rd_en,

    output wire          sdram_cke,
    output wire          sdram_cs_n,
    output wire          sdram_ras_n,
    output wire          sdram_cas_n,
    output wire          sdram_we_n,
    output reg  [ 1 : 0] sdram_bank,
    output reg  [12 : 0] sdram_addr,
    output wire [15 : 0] sdram_dq
);

`include "Config-AC.v"

//-----------------------------------------------------------------------------

localparam CMD_NOP = 4'b0111;

localparam STATE_IDLE = 3'b000,
           STATE_ARB  = 3'b001,
           STATE_AR   = 3'b011,
           STATE_WR   = 3'b010,
           STATE_RD   = 3'b100;

reg [3 : 0] sdram_cmd;
reg [2 : 0] state_curr;
reg [2 : 0] state_next;

//-----------------------------------------------------------------------------

always @(posedge arb_clk or negedge arb_rst_n) begin
    if (!arb_rst_n) begin
        ar_en <= 1'b0;
    end
    else if ((state_curr == STATE_ARB) && ar_req) begin
        ar_en <= 1'b1;
    end
    else if (ar_end) begin
        ar_en <= 1'b0;
    end
    else begin
        ar_en <= ar_en;
    end
end

always @(posedge arb_clk or negedge arb_rst_n) begin
    if (!arb_rst_n) begin
        wr_en <= 1'b0;
    end
    else if ((state_curr == STATE_ARB) && !ar_req && wr_req) begin
        wr_en <= 1'b1;
    end
    else if (wr_end) begin
        wr_en <= 1'b0;
    end
    else begin
        wr_en <= wr_en;
    end
end

always @(posedge arb_clk or negedge arb_rst_n) begin
    if (!arb_rst_n) begin
        rd_en <= 1'b0;
    end
    else if ((state_curr == STATE_ARB) && !ar_req && !wr_req && rd_req) begin
        rd_en <= 1'b1;
    end
    else if (rd_end) begin
        rd_en <= 1'b0;
    end
    else begin
        rd_en <= rd_en;
    end
end

assign sdram_cke = 1'b1;
assign { sdram_cs_n, sdram_ras_n, sdram_cas_n, sdram_we_n } = sdram_cmd;
assign sdram_dq  = (wr_sdram_en) ? wr_sdram_data : 16'bz;

always @(posedge arb_clk or negedge arb_rst_n) begin
    if (!arb_rst_n) begin
        state_curr <= STATE_IDLE;
    end
    else begin
        state_curr <= state_next;
    end
end

always @(*) begin
    state_next = STATE_IDLE;
    case (state_curr)
        STATE_IDLE: begin
            if (init_end) begin
                state_curr <= STATE_ARB;
            end
            else begin
                state_curr <= STATE_IDLE;
            end
        end
        STATE_ARB: begin
            if (ar_req) begin
                state_next = STATE_AR;
            end
            else if (wr_req) begin
                state_next = STATE_WR;
            end
            else if (rd_req) begin
                state_next = STATE_RD;
            end
            else begin
                state_next = STATE_ARB;
            end
        end
        STATE_AR: begin
            if (ar_end) begin
                state_next = STATE_ARB;
            end
            else begin
                state_next = STATE_AR;
            end
        end
        STATE_WR: begin
            if (wr_end) begin
                state_next = STATE_ARB;
            end
            else begin
                state_next = STATE_WR;
            end
        end
        STATE_RD: begin
            if (rd_end) begin
                state_next = STATE_ARB;
            end
            else begin
                state_next = STATE_RD;
            end
        end
        default: begin
            state_next = STATE_IDLE;
        end
    endcase
end

always @(*) begin
    case (state_curr)
        STATE_IDLE: begin
            sdram_cmd  <= init_cmd;
            sdram_bank <= init_bank;
            sdram_addr <= init_addr;
        end
        STATE_AR: begin
            sdram_cmd  <= ar_cmd;
            sdram_bank <= ar_bank;
            sdram_addr <= ar_addr;
        end
        STATE_WR: begin
            sdram_cmd  <= wr_cmd;
            sdram_bank <= wr_bank;
            sdram_addr <= wr_addr;
        end
        STATE_RD: begin
            sdram_cmd  <= rd_cmd;
            sdram_bank <= rd_bank;
            sdram_addr <= rd_addr;
        end
        default: begin
            sdram_cmd  <= CMD_NOP;
            sdram_bank <= 2'b11;
            sdram_addr <= 13'h1fff;
        end
    endcase
end

endmodule
