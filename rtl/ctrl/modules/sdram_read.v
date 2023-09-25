module sdram_read(
    input   wire          rd_clk,
    input   wire          rd_rst_n,
    input   wire          rd_en,
    input   wire [23 : 0] rd_addr,
    input   wire [15 : 0] rd_data,
    input   wire [ 9 : 0] rd_bst_len,
    input   wire          init_end,

    output  wire          rd_ack,
    output  wire          rd_end,
    output  reg  [ 3 : 0] rd_sdram_cmd,
    output  reg  [ 1 : 0] rd_sdram_bank,
    output  reg  [12 : 0] rd_sdram_addr,
    output  wire [15 : 0] rd_sdram_data
);

`include "Config-AC.v"

//-----------------------------------------------------------------------------

localparam TRCD = (tRCD / 1000 / 10 + 1),
           TCL  = (tCL  / 1000 / 10 + 1),
           TRP  = (tRP  / 1000 / 10 + 1);

localparam CMD_NOP      = 4'b0111,
           CMD_ACT      = 4'b0011,
           CMD_RD       = 4'b0101,
           CMD_BST_STOP = 4'b0110,
           CMD_PRE      = 4'b0010;

localparam STATE_IDLE = 4'b0000,
           STATE_ACT  = 4'b0001,
           STATE_TRCD = 4'b0011,
           STATE_RD   = 4'b0010,
           STATE_TCL  = 4'b0100,
           STATE_DATA = 4'b0101,
           STATE_PRE  = 4'b0111,
           STATE_TRP  = 4'b0110,
           STATE_END  = 4'b1100;

reg [ 3 : 0] state_curr;
reg [ 3 : 0] state_next;
reg [ 9 : 0] cnt_fsm;
reg          cnt_fsm_rst;
reg [15 : 0] rd_data_tmp;

wire flag_trcd_end;
wire flag_tcl_end;
wire flag_trp_end;
wire flag_rd_end;
wire flag_rd_bst_end;

//-----------------------------------------------------------------------------

assign flag_trcd_end   = ((state_curr == STATE_TRCD) &&
                          (cnt_fsm == TRCD)) ? 1'b1 : 1'b0;
assign flag_tcl_end    = ((state_curr == STATE_TCL)  &&
                          (cnt_fsm == TCL))  ? 1'b1 : 1'b0;
assign flag_trp_end    = ((staet_curr == STATE_TRP)  &&
                          (cnt_fsm == TRP))  ? 1'b1 : 1'b0;
assign flag_rd_end     = ((state_curr == STATE_RD)   &&
                          (cnt_fsm == rd_bst_len)) ? 1'b1 : 1'b0;
assign flag_rd_bst_end = ((state_curr == STATE_RD)   &&
                          (cnt_fsm == rd_bst_len - 4)) ? 1'b1 : 1'b0;

always @(posedge rd_clk or negedge rd_rst_n) begin
    if (!rd_rst_n) begin
        cnt_fsm <= 10'd0;
    end
    else if (cnt_fsm_rst) begin
        cnt_fsm <= 10'd0;
    end
    else begin
        cnt_fsm <= cnt_fsm + 1'b1;
    end
end

always @(*) begin
    case (staet_curr)
        STATE_IDLE: cnt_fsm_rst <= 1'b1;
        STATE_TRCD: cnt_fsm_rst <= (flag_trcd_end) ? 1'b1 : 1'b0;
        STATE_RD:   cnt_fsm_rst <= 1'b1;
        STATE_TCL:  cnt_fsm_rst <= (flag_tcl_end)  ? 1'b1 : 1'b0;
        STATE_DATA: cnt_fsm_rst <= (flag_rd_end)   ? 1'b1 : 1'b0;
        STATE_TRP:  cnt_fsm_rst <= (flag_trp_end)  ? 1'b1 : 1'b0;
        STATE_END:  cnt_fsm_rst <= 1'b1;
        default:    cnt_fsm_rst <= 1'b0;
    endcase
end

always @(posedge rd_clk or negedge rd_rst_n) begin
    if (!rd_rst_n) begin
        rd_data_tmp <= 16'd0;
    end
    else begin
        rd_data_tmp <= rd_data;
    end
end

assign rd_ack = (state_curr == STATE_RD) &&
                (cnt_fsm >= 10'd1) &&
                (cnt_fsm < (rd_bst_len + 2'd1));
assign rd_end = (state_curr == STATE_END) ? 1'b1 : 1'b0;
assign rd_sdram_data = (rd_ack == 1'b1) ? rd_data_tmp : 16'b0;

//-----------------------------------------------------------------------------

always @(posedge rd_clk or negedge rd_rst_n) begin
    if (!rd_rst_n) begin
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
            if (init_end && rd_en) begin
                state_next = STATE_ACT;
            end
            else begin
                state_next = STATE_IDLE;
            end
        end
        STATE_ACT: begin
            state_next = STATE_TRCD;
        end
        STATE_TRCD: begin
            if (flag_trcd_end) begin
                state_next = STATE_RD;
            end
            else begin
                state_next = STATE_TRCD;
            end
        end
        STATE_RD: begin
            state_next = STATE_TCL;
        end
        STATE_TCL: begin
            if (flag_tcl_end) begin
                state_next = STATE_DATA;
            end
            else begin
                state_next = STATE_TCL;
            end
        end
        STATE_DATA: begin
            if (flag_rd_end) begin
                state_next = STATE_PRE;
            end
            else begin
                state_next = STATE_DATA;
            end
        end
        STATE_PRE: begin
            state_next = STATE_TRP;
        end
        STATE_TRP: begin
            if (flag_trp_end) begin
                state_next = STATE_END;
            end
            else begin
                state_next = STATE_TRP;
            end
        end
        STATE_END: begin
            state_next = STATE_IDLE;
        end
        default: begin
            state_next = STATE_IDLE;
        end
    endcase
end

always @(posedge rd_clk or negedge rd_rst_n) begin
    if (!rd_rst_n) begin
        rd_sdram_cmd  <= CMD_NOP;
        rd_sdram_bank <= 2'b11;
        rd_sdram_addr <= 13'h1fff;
    end
    else begin
        case (state_curr)
            STATE_IDLE: begin
                rd_sdram_cmd  <= CMD_NOP;
                rd_sdram_bank <= 2'b11;
                rd_sdram_addr <= 13'h1fff;
            end
            STATE_ACT: begin
                rd_sdram_cmd  <= CMD_ACT;
                rd_sdram_bank <= rd_addr[23 : 22];
                rd_sdram_addr <= rd_addr[21 :  9];
            end
            STATE_TRCD: begin
                rd_sdram_cmd  <= CMD_NOP;
                rd_sdram_bank <= 2'b11;
                rd_sdram_addr <= 13'h1fff;
            end
            STATE_RD: begin
                rd_sdram_cmd  <= CMD_RD;
                rd_sdram_bank <= rd_addr[23 : 22];
                rd_sdram_addr <= { 4'b0000, rd_addr[8 : 0] };
            end
            STATE_TCL: begin
                rd_sdram_cmd  <= CMD_NOP;
                rd_sdram_bank <= 2'b11;
                rd_sdram_addr <= 13'h1fff;
            end
            STATE_DATA: begin
                rd_sdram_bank <= 2'b11;
                rd_sdram_addr <= 13'h1fff;
                if (flag_rd_bst_end) begin
                    rd_sdram_cmd <= CMD_BST_STOP;
                end
                else begin
                    rd_sdram_cmd <= CMD_NOP;
                end
            end
            STATE_PRE: begin
                rd_sdram_cmd  <= CMD_PRE;
                rd_sdram_bank <= rd_addr[23 : 22];
                rd_sdram_addr <= 13'h0400;
            end
            STATE_TRP: begin
                rd_sdram_cmd  <= CMD_NOP;
                rd_sdram_bank <= 2'b11;
                rd_sdram_addr <= 13'h1fff;
            end
            STATE_END: begin
                rd_sdram_cmd  <= CMD_NOP;
                rd_sdram_bank <= 2'b11;
                rd_sdram_addr <= 13'h1fff;
            end
            default: begin
                rd_sdram_cmd  <= CMD_NOP;
                rd_sdram_bank <= 2'b11;
                rd_sdram_addr <= 13'h1fff;
            end
        endcase
    end
end



endmodule
