module sdram_write(
    input               wr_clk,       // Write clock
    input               wr_rst_n,     // Write reset
    input               wr_en,        // Write enable
    input      [23 : 0] wr_addr,      // Write addr
    input      [15 : 0] wr_data,      // Write data
    input      [ 9 : 0] wr_bst_len,   // Write burst length
    input               init_end,     // Init end flag

    output              wr_ack,        // Write response
    output              wr_end,        // Write end flag
    output reg          wr_sdram_en,   // Write sdram enable, used for
                                       // subsequent arbitration module output
    output reg [ 3 : 0] wr_sdram_cmd,  // Write command: {CS#, RAS#, CAS#, WE#}
    output reg [ 1 : 0] wr_sdram_bank, // Write bank address
    output reg [12 : 0] wr_sdram_addr, // Write data address
    output reg [15 : 0] wr_sdram_data  // Write sdram data
);

`include "Config-AC.v"

//-----------------------------------------------------------------------------

localparam TRCD = (tRCD / 1000 / 10 + 1), // The time required to wait for the
                                          // next operation after sending the
                                          // active command
           TRP  = (tRP  / 1000 / 10 + 1); // The time required to wait for the
                                          // next operation after sending the
                                          // precharge command

localparam CMD_NOP      = 4'b0111, // NO operation command
           CMD_PRE      = 4'b0010, // Precharge command
           CMD_ACT      = 4'b0011, // Active command
           CMD_WR       = 4'b0100, // Write command
           CMD_BST_STOP = 4'b0110; // Write burst command

localparam STATE_IDLE = 3'b000, // Init state
           STATE_ACT  = 3'b001, // Row active state
           STATE_TRCD = 3'b011, // Row active waiting state
           STATE_WR   = 3'b010, // Write state
           STATE_DATA = 3'b100, // Write data state
           STATE_PRE  = 3'b101, // Precharge state
           STATE_TRP  = 3'b111, // Precharge waiting state
           STATE_END  = 3'b110; // Write end state

reg [2 : 0] state_curr;  // State machine current state
reg [2 : 0] state_next;  // State machine next state
reg [9 : 0] cnt_fsm;     // State machine counter
reg         cnt_fsm_rst; // State machine reset counter

wire flag_trcd_end; // Row active waiting time flag
wire flag_wr_end;   // Write end flag
wire flag_trp_end;  // Precharge waiting time flag

//-----------------------------------------------------------------------------

assign flag_trcd_end = ((state_curr == WR_TRCD) &&
                        (cnt_fsm == TRCD - 1'b1)) ? 1'b1 : 1'b0;
assign flag_wr_end   = ((state_curr == WR_DATA) &&
                        (cnt_fsm == wr_bst_len - 1'b1)) ? 1'b1 : 1'b0;
assign flag_trp_end  = ((state_curr == WR_TRP)  &&
                        (cnt_fsm == TRP - 1'b1)) ? 1'b1 : 1'b0;

always @(posedge wr_clk or negedge wr_rst_n) begin
    if (!wr_rst_n) begin
        cnt_fsm <= 10'd0;
    end
    else if (cnt_fsm_reset) begin
        cnt_fsm <= 10'd0;
    end
    else begin
        cnt_fsm <= cnt_fsm + 1'd1;
    end
end

always @(*) begin
    case (state_curr)
        STATE_IDLE: cnt_fsm_reset = 1'b1;
        STATE_TRCD: cnt_fsm_reset = (flag_trcd_end) ? 1'b1 : 1'b0;
        STATE_WR:   cnt_fsm_reset = 1'b1;
        STATE_DATA: cnt_fsm_reset = (flag_wr_end)   ? 1'b1 : 1'b0;
        STATE_TRP:  cnt_fsm_reset = (flag_trp_end)  ? 1'b1 : 1'b0;
        STATE_END:  cnt_fsm_reset = 1'b1;
        default:    cnt_fsm_reset = 1'b0;
    endcase
end

assign wr_ack = (state_curr == STATE_WR) ||
               ((state_curr == STATE_DATA) && (cnt_fsm <= wr_bst_len - 2'd2));
assign wr_end = (state_curr == STATE_END) ? 1'b1 : 1'b0;

always @(posedge wr_clk or negedge wr_rst_n) begin
    if (!wr_rst_n) begin
        wr_sdram_en <= 1'b0;
    end
    else begin
        wr_sdram_en <= wr_ack;
    end
end

assign wr_sdram_data = (wr_sdram_en == 1'b1) ? wr_data : 16'b0;

//-----------------------------------------------------------------------------

// State machine stage 1: Synchronous timing describes state transitions
always @(posedge wr_clk or negedge wr_rst_n) begin
    if (!wr_rst_n) begin
        state_curr <= STATE_IDLE;
    end
    else begin
        state_curr <= state_next;
    end
end

// State machine stage 2: Combinational logic determines state transition
// conditions, describes state transition rules and outputs
always @(*) begin
    state_next = STATE_IDLE;
    case (state_curr)
        STATE_IDLE: begin
            if (init_end && wr_en) begin
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
                state_next = STATE_WR;
            end
            else begin
                state_next = STATE_TRCD;
            end
        end
        STATE_WR: begin
            state_next = STATE_DATA;
        end
        STATE_DATA: begin
            if (flag_wr_end) begin
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

// State machine stage 3: Sequential logic description output
always @(posedge wr_clk or negedge wr_rst_n) begin
    if (!wr_rst_n) begin
        wr_sdram_cmd  <= CMD_NOP;
        wr_sdram_bank <= 2'b11;
        wr_sdram_addr <= 13'h1fff;
    end
    else begin
        case (state_curr)
            STATE_IDLE: begin
                wr_sdram_cmd  <= CMD_NOP;
                wr_sdram_bank <= 2'b11;
                wr_sdram_addr <= 13'h1fff;
            end
            STATE_ACT: begin
                wr_sdram_cmd  <= CMD_ACT;
                wr_sdram_bank <= wr_addr[23 : 22];
                wr_sdram_addr <= wr_addr[21 :  9];
            end
            STATE_TRCD: begin
                wr_sdram_cmd  <= CMD_NOP;
                wr_sdram_bank <= 2'b11;
                wr_sdram_addr <= 13'h1fff;
            end
            STATE_WR: begin
                wr_sdram_cmd  <= CMD_WR;
                wr_sdram_bank <= wr_addr[23 : 22];
                wr_sdram_addr <= { 4'b0000, wr_addr[8 : 0] };
            end
            STATE_DATA: begin
                wr_sdram_bank <= 2'b11;
                wr_sdram_addr <= 13'h1fff;
                if (flag_wr_end) begin
                    wr_sdram_cmd <= CMD_BST_STOP;
                end
                else begin
                    wr_sdram_cmd <= CMD_NOP;
                end
            end
            STATE_PRE: begin
                wr_sdram_cmd  <= CMD_PRE;
                wr_sdram_bank <= wr_addr[23 : 22];
                wr_sdram_addr <= 13'h0400;
            end
            STATE_TRP: begin
                wr_sdram_cmd  <= CMD_NOP;
                wr_sdram_bank <= 2'b11;
                wr_sdram_addr <= 13'h1fff;
            end
            STATE_END: begin
                wr_sdram_cmd  <= CMD_NOP;
                wr_sdram_bank <= 2'b11;
                wr_sdram_addr <= 13'h1fff;
            end
            default: begin
                wr_sdram_cmd  <= CMD_NOP;
                wr_sdram_bank <= 2'b11;
                wr_sdram_addr <= 13'h1fff;
            end
        endcase
    end
end

endmodule
