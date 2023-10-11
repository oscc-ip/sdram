module sdram_init(
    input  wire          init_clk,   // Init clock
    input  wire          init_rst_n, // Init reset

    output reg           init_end,   // Init end flag
    output reg  [ 3 : 0] init_cmd,   // Init command: {CS#, RAS#, CAS#, WE#}
    output reg  [ 1 : 0] init_bank,  // Init bank address
    output reg  [12 : 0] init_addr   // Init data address
);

`include "Config-AC.v"

//-----------------------------------------------------------------------------

localparam CNT_WAIT = 16'd20000, // Wait counter, 100MHz = 10ns/cycle,
                                 // The number of times required to delay 200us
                                 // (>=100us): 200*10^3ns / 10ns = 20000
           CNT_AR   = 4'd2;      // Auto refresh counter, refresh 2 times

localparam TRP  = (tRP  / 1000 / 10 + 1), // The time required to wait for the
                                          // next operation after sending the
                                          // precharge command
           TRFC = (tRFC / 1000 / 10 + 1), // The time to wait for the next
                                          // operation after sending the auto
                                          // refresh command
           TMRD =  tMRD; // The time to wait for the next operation after
                         // sending the set mode register command

localparam CMD_PRE = 4'b0010, // Precharge command
           CMD_AR  = 4'b0001, // Auto refresh command
           CMD_NOP = 4'b0111, // NO operation command
           CMD_MRS = 4'b0000; // Mode register setting command

localparam STATE_IDLE = 3'b000, // Init state
           STATE_PRE  = 3'b001, // Precharge state
           STATE_TRP  = 3'b011, // Precharge waiting state
           STATE_AR   = 3'b010, // Auto refresh state
           STATE_TRFC = 3'b110, // Auto refresh waiting state
           STATE_MRS  = 3'b111, // Mode register setting state
           STATE_TMRD = 3'b101, // Mode register setting waiting state
           STATE_END  = 3'b100; // Init end state

reg [ 2 : 0] state_curr;  // State machine current state
reg [ 2 : 0] state_next;  // State machine next state
reg [15 : 0] cnt_wait;    // Delay waiting counter
reg [ 3 : 0] cnt_ar;      // Auto refresh counter
reg [ 3 : 0] cnt_fsm;     // State machine counter
reg          cnt_fsm_rst; // State machine reset counter

wire flag_wait; // Power-on waiting time flag
wire flag_trp;  // Precharge waiting time flag
wire flag_trfc; // Auto refresh waiting time flag
wire flag_tmrd; // Mode register configures wait time flag

//-----------------------------------------------------------------------------

// Because the state jump is sequential logic, the flag signal of the waiting
// parameter is raised in the previous cycle to make the state jump
assign flag_wait =  (cnt_wait == CNT_WAIT - 'd1) ?
                     1'b1 : 1'b0;
assign flag_trp  = ((state_curr == STATE_TRP ) && (cnt_fsm == TRP  - 1'b1)) ?
                     1'b1 : 1'b0;
assign flag_trfc = ((state_curr == STATE_TRFC) && (cnt_fsm == TRFC - 1'b1)) ?
                     1'b1 : 1'b0;
assign flag_tmrd = ((state_curr == STATE_TMRD) && (cnt_fsm == TMRD - 1'b1)) ?
                     1'b1 : 1'b0;

always @(posedge init_clk or negedge init_rst_n) begin
    if (!init_rst_n) begin
        cnt_wait <= 16'd0;
    end
    else if (cnt_wait == CNT_WAIT) begin
        cnt_wait <= cnt_wait;
    end
    else begin
        cnt_wait <= cnt_wait + 1'd1;
    end
end

always @(posedge init_clk or negedge init_rst_n) begin
    if (!init_rst_n) begin
        cnt_ar <= 4'd0;
    end
    else if (state_curr == STATE_IDLE) begin
        cnt_ar <= 4'd0;
    end
    else if (state_curr == STATE_AR) begin
        cnt_ar <= cnt_ar + 1'd1;
    end
    else begin
        cnt_ar <= cnt_ar;
    end
end

always @(posedge init_clk or negedge init_rst_n) begin
    if (!init_rst_n) begin
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
        STATE_TMRD: cnt_fsm_rst = (flag_tmrd) ? 1'b1 : 1'b0;
        STATE_END:  cnt_fsm_rst = 1'b1;
        default:    cnt_fsm_rst = 1'b0;
    endcase
end

always @(posedge init_clk or negedge init_rst_n) begin
    if (!init_rst_n) begin
        init_end <= 1'b0;
    end
    else if (state_curr == STATE_END) begin
        init_end <= 1'b1;
    end
    else begin
        init_end <= 1'b0;
    end
end

//-----------------------------------------------------------------------------

// State machine stage 1: Synchronous timing describes state transitions
always@(posedge init_clk or negedge init_rst_n) begin
    if (!init_rst_n) begin
        state_curr <= STATE_IDLE;
    end
    else begin
        state_curr <= state_next;
    end
end

// State machine stage 2: Combinational logic determines state transition
// conditions, describes state transition rules and outputs
always@(*) begin
    state_next = STATE_IDLE;
    case (state_curr)
        STATE_IDLE: begin
            // When the wait flag is pulled high, jump to the next state,
            // otherwise stay in this state
            if (flag_wait) begin
                state_next = STATE_PRE;
            end
            else begin
                state_next = STATE_IDLE;
            end
        end
        STATE_PRE: begin
            // Jump to TRP waiting state
            state_next = STATE_TRP;
        end
        STATE_TRP: begin
            // If the TRP wait flag is raised high, it will jump to the next
            // state, otherwise it will remain in this state.
            if (flag_trp) begin
                state_next = STATE_AR;
            end
            else begin
                state_next = STATE_TRP;
            end
        end
        STATE_AR: begin
            // Jump to TRFC wait state
            state_next = STATE_TRFC;
        end
        STATE_TRFC: begin
            if (flag_trfc) begin
                // The TRFC wait flag is pulled high and the number of
                // automatic refreshes meets the timing requirements, then jump
                //  to the next state
                if (cnt_ar == CNT_AR) begin
                    state_next = STATE_MRS;
                end
                else begin
                    state_next = STATE_AR;
                end
            end
            else begin
                state_next = STATE_TRFC;
            end
        end
        STATE_MRS: begin
            // Jump to STATE_TMRD wait state
            state_next = STATE_TMRD;
        end
        STATE_TMRD: begin
            // The STATE_TMRD waits for the flag to be raised high and the
            // number of automatic refreshes meets the timing requirements to
            // jump to the next state
            if (flag_tmrd) begin
                state_next = STATE_END;
            end
            else begin
                state_next = STATE_TMRD;
            end
        end
        STATE_END: begin
            state_next = STATE_END;
        end
        default: begin
            state_next = STATE_IDLE;
        end
    endcase
end

// State machine stage 3: Sequential logic description output
always@(posedge init_clk or negedge init_rst_n) begin
    // Reset output NOP command, don't care about bank address and data
    // address, just pull them all high
    if (!init_rst_n) begin
        init_cmd  <= CMD_NOP;
        init_bank <= 2'b11;
        init_addr <= 13'h1fff;
    end
    else begin
        case (state_curr)
            // Output NOP command, don't care about bank address and data
            // address, just pull them all high
            STATE_IDLE: begin
                init_cmd  <= CMD_NOP;
                init_bank <= 2'b11;
                init_addr <= 13'h1fff;
            end
            // Output Auto precharge command, A10 pulls up and selects all
            // bank, don't care about bank address and data address, just pull
            // them all high
            STATE_PRE: begin
                init_cmd  <= CMD_PRE;
                init_bank <= 2'b11;
                init_addr <= 13'h1fff;
            end
            // Output NOP command, don't care about bank address and data
            // address, just pull them all high
            STATE_TRP: begin
                init_cmd  <= CMD_NOP;
                init_bank <= 2'b11;
                init_addr <= 13'h1fff;
            end
            // Output Auto refresh command, don't care about bank address
            // and data address, just pull them all high
            STATE_AR: begin
                init_cmd  <= CMD_AR;
                init_bank <= 2'b11;
                init_addr <= 13'h1fff;
            end
            // Output NOP command, don't care about bank address and data
            // address, just pull them all high
            STATE_TRFC:begin
                init_cmd  <= CMD_NOP;
                init_bank <= 2'b11;
                init_addr <= 13'h1fff;
            end
            // Output mode register configuration command, A0~A12 address
            // for mode configuration, All bank addresses are pulled low
            STATE_MRS: begin
                init_cmd  <= CMD_MRS;
                init_bank <= 2'b00;
                init_addr <=
                {
                    3'b000, // A12-A10: Reserved
                    1'b0,   // A09: Single Write Model,
                            // [0]=Burst read & Burst write,
                            // [1]=Burst read and Single write
                    2'b00,  // A08-A07: Reserved
                    3'b011, // A06-A04: CAS Latency, [010]=2, [011]=3
                    1'b0,   // A03: Addressing Mode, [0]=Sequential,
                            //                       [1]=Interleave
                    3'b111  // A02-A00: Burst Length: [000]=1, [001]=2,
                            //                        [010]=4, [011]=8,
                            //                        [111]=Full Page
                };
            end
            // Output NOP command, don't care about bank address and data
            // address, just pull them all high
            STATE_TMRD: begin
                init_cmd  <= CMD_NOP;
                init_bank <= 2'b11;
                init_addr <= 13'h1fff;
            end
            // Output NOP command, don't care about bank address and data
            // address, just pull them all high
            STATE_END: begin
                init_cmd  <= CMD_NOP;
                init_bank <= 2'b11;
                init_addr <= 13'h1fff;
            end
            // Output NOP command, don't care about bank address and data
            // address, just pull them all high
            default: begin
                init_cmd  <= CMD_NOP;
                init_bank <= 2'b11;
                init_addr <= 13'h1fff;
            end
        endcase
    end
end

endmodule
