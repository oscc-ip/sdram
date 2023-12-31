`timescale 1ns / 1ns

module tb_sdram_init();

`include "Config-AC.v"
`include "../config/config.v"

reg           clk;       // Clock
reg           rst_n;     // Reset

wire          init_end;  // End flag
wire [ 3 : 0] init_cmd;  // Command
wire [ 1 : 0] init_bank; // Bank address
wire [12 : 0] init_addr; // Data address

// Initialization
initial begin
    clk   = 1'b1;
    rst_n = 1'b0;
    #(CYCLE * 10)
    rst_n = 1'b1;
end

// Generate 100MHz Clock
// 10ns = 100MHz
always #(CYCLE / 2) clk = ~clk;

sdram_init  sdram_init_inst(
    .init_clk  (clk),
    .init_rst_n(rst_n),

    .init_end  (init_end),
    .init_cmd  (init_cmd),
    .init_bank (init_bank),
    .init_addr (init_addr)
);

W989DxDB sdram_inst(
    .clk  (clk),
    .cke  (1'b1),
    .addr (init_addr),
    .ba   (init_bank),
    .cs_n (init_cmd[3]),
    .ras_n(init_cmd[2]),
    .cas_n(init_cmd[1]),
    .we_n (init_cmd[0]),
    .dq   (),
    .dqm  (2'b0)
);

// Store 10 characters(Each character is 8 bits wide)
reg [79 : 0] state_curr;

always @(*) begin
    case (sdram_init_inst.state_curr)
        3'b000:  state_curr = "STATE_IDLE";
        3'b001:  state_curr = "STATE_PRE ";
        3'b011:  state_curr = "STATE_TRP ";
        3'b010:  state_curr = "STATE_AR  ";
        3'b110:  state_curr = "STATE_TRFC";
        3'b111:  state_curr = "STATE_MRS ";
        3'b101:  state_curr = "STATE_TMRD";
        3'b100:  state_curr = "STATE_END ";
        default: state_curr = "STATE_IDLE";
    endcase
end

initial begin
    $monitor("Command Display %s at the time %t", sdram_inst.command_display,
                                                  $time);
end

endmodule
