module sdram_aref(
    input               ar_clk,   // Auto refresh clock
    input               ar_rst_n, // Auto refresh reset
    input               ar_en,    // Auto refresh enable
    input               init_end, // Auto refresh end flag

    output reg [ 3 : 0] ar_cmd,   // Auto refresh Command: {CS#, RAS#, CAS#, WE#}
    output reg [ 1 : 0] ar_bank,  // Auto refresh bank address
    output reg [12 : 0] ar_addr,  // Auto refresh data address
    output reg          ar_req,   // Auto refresh request, output to the
                                  // arbitration module and initiate an auto
                                  // refresh request
    output reg          ar_end    // Auto refresh end flag, After completion,
                                  // it is pulled high for one clock cycle and
                                  // notified to the arbitration module
);

`include "Config-AC.v"

//-----------------------------------------------------------------------------

localparam CNT_AR_TIME = 16'd800, // Auto refresh time counter, 100MHz = 10ns/cycle,
                                  // The time required to perform a refresh:
                                  // 64ms / 8192 = 7.8125us ≈ 8us,
                                  // The number of times to perform a refresh:
                                  // 8*10^3ns / 10ns = 800
           CNT_AR      = 4'd2;    // Auto refresh counter, refresh 2 times

localparam	TRP  = (tRP  / 1000 / 10 + 1), // The time required to wait for the
                                           // next operation after sending the
                                           // precharge command
            TRFC = (tRFC / 1000 / 10 + 1); // The time to wait for the next
                                           // operation after sending the auto
                                           // refresh command

localparam 	CMD_PRE = 4'b0010, // Precharge command
            CMD_AR  = 4'b0001, // Auto refresh command
            CMD_NOP = 4'b0111; // NO operation command

localparam	STATE_IDLE = 3'b000, // Initial state
            STATE_PRE  = 3'b001, // Precharge state
            STATE_TRP  = 3'b011, // Precharge waiting state
            STATE_AR   = 3'b010, // Auto refresh state
            STATE_TRFC = 3'b110, // Auto refresh waiting state
            STATE_END  = 3'b111; // Auto refresh end state

reg [ 2 : 0] state_curr;  // State machine current state
reg [ 2 : 0] state_next;  // State machine next state
reg [15 : 0] cnt_ar_time; // Auto refresh time counter
reg [ 1 : 0] cnt_ar;      // Auto refresh counter
reg [ 3 : 0] cnt_fsm;     // State machine counter
reg [ 3 : 0] cnt_fsm_rst; // State machine reset counter

wire flag_trp;    // Precharge waiting time flag
wire flag_trfc;   // Auto refresh waiting time flag
wire flag_ar_ack; // Auto refresh request flag, used to pull down the refresh
                  // response signal

//-----------------------------------------------------------------------------

// Because the state jump is sequential logic, the flag signal of the waiting
// parameter is raised in the previous cycle to make the state jump
assign flag_trp  = ((state_curr == STATE_TRP)  && (cnt_fsm == TRP  - 1'b1)) ?
                     1'b1 : 1'b0;
assign flag_trfc = ((state_curr == STATE_TRFC) && (cnt_fsm == TRFC - 1'b1)) ?
                     1'b1 : 1'b0;
// When sending precharge, it means that the auto refresh module responds to
// the auto refresh enable given by the arbitration module, so aref_ack is
// pulled high
assign flag_ar_ack = (state_curr == STATE_PRE) ? 1'b1 : 1'b0;

always @(posedge ar_clk or negedge ar_rst_n) begin
    if (!ar_rst_n) begin
        cnt_ar_time <= 16'd0;
    end
    else if (init_end) begin
        if (cnt_ar_time == CNT_AR_TIME) begin
            cnt_ar_time <= 16'd0;
        end
        else begin
            cnt_ar_time <= cnt_ar_time + 1;
        end
    end
    else begin
        cnt_ar_time <= cnt_ar_time;
    end
end

always @(posedge ar_clk or negedge ar_rst_n) begin
    if (!ar_rst_n) begin
        cnt_ar <= 2'b0;
    end
    else if (state_curr == STATE_IDLE) begin
        cnt_ar <= 2'b0;
    end
    else if (state_curr == STATE_AR) begin
        cnt_ar <= cnt_ar + 1'd1;
    end
    else begin
        cnt_ar <= cnt_ar;
    end
end

always @(posedge ar_clk or negedge ar_rst_n) begin
    if (!ar_rst_n) begin
        cnt_fsm <= 4'd0;
    end
    else if (cnt_fsm_rst) begin
        cnt_fsm <= 4'd0;
    end
    else begin
        cnt_fsm <= cnt_fsm + 1'd1;
    end
end

always @(*) begin
    case (state_curr)
        STATE_IDLE: cnt_fsm_rst = 1'b1;
        STATE_TRP:  cnt_fsm_rst = (flag_trp)  ? 1'b1 : 1'b0;
        STATE_TRFC: cnt_fsm_rst = (flag_trfc) ? 1'b1 : 1'b0;
        STATE_END:  cnt_fsm_rst = 1'b1;
        default:    cnt_fsm_rst = 1'b0;
    endcase
end

always @(posedge ar_clk or negedge ar_rst_n) begin
    if (!ar_rst_n) begin
        ar_req <= 1'b0;
    end
    else if (cnt_ar_time == CNT_AR_TIME - 1'b1) begin
        ar_req <= 1'b1;
    end
    else if (flag_ar_ack) begin
        ar_req <= 1'b0;
    end
    else begin
        ar_req <= ar_req;
    end
end

always @(posedge ar_clk or negedge ar_rst_n) begin
    if (!ar_rst_n) begin
        ar_end <= 1'b0;
    end
    else if (flag_trfc && cnt_ar == CNT_AR) begin
        ar_end <= 1'b1;
    end
    else begin
        ar_end <= 1'b0;
    end
end

//-----------------------------------------------------------------------------

always @(posedge ar_clk or negedge ar_rst_n) begin
    if (!ar_rst_n) begin
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
            if (init_end && ar_en) begin
                state_next = STATE_PRE;
            end
            else begin
                state_next = STATE_IDLE;
            end
        end
        STATE_PRE: begin
            state_next = STATE_TRP;
        end
        STATE_TRP: begin
            if (flag_trp) begin
                state_next = STATE_AR;
            end
            else begin
                state_next = STATE_TRP;
            end
        end
        STATE_AR: begin
            state_next = STATE_TRFC;
        end
        STATE_TRFC: begin
            if (flag_trfc) begin
                if (cnt_ar == CNT_AR) begin
                    state_next = STATE_END;
                end
                else begin
                    state_next = STATE_AR;
                end
            end
            else begin
                state_next = STATE_TRFC;
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

always @(posedge ar_clk or negedge ar_rst_n) begin
    if (!ar_rst_n) begin
        ar_cmd  <= CMD_NOP;
        ar_bank <= 2'b11;
        ar_addr <= 13'h1fff;
    end
    else begin
        case (state_curr)
            STATE_IDLE: begin
                ar_cmd  <= CMD_NOP;
                ar_bank <= 2'b11;
                ar_addr <= 13'h1fff;
            end
            STATE_PRE: begin
                ar_cmd  <= CMD_PRE;
                ar_bank <= 2'b11;
                ar_addr <= 13'h1fff;
            end
            STATE_TRP: begin
                ar_cmd  <= CMD_NOP;
                ar_bank <= 2'b11;
                ar_addr <= 13'h1fff;
            end
            STATE_AR: begin
                ar_cmd  <= CMD_AR;
                ar_bank <= 2'b11;
                ar_addr <= 13'h1fff;
            end
            STATE_TRFC: begin
                ar_cmd  <= CMD_NOP;
                ar_bank <= 2'b11;
                ar_addr <= 13'h1fff;
            end
            STATE_END: begin
                ar_cmd  <= CMD_NOP;
                ar_bank <= 2'b11;
                ar_addr <= 13'h1fff;
            end
            default: begin
                ar_cmd  <= CMD_NOP;
                ar_bank <= 2'b11;
                ar_addr <= 13'h1fff;
            end
        endcase
    end
end

endmodule
