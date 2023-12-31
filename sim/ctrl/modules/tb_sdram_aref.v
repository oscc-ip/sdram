`timescale 1ns / 1ns

module tb_sdram_aref();

`include "Config-AC.v"
`include "../config/config.v"

reg           clk;        // Clock
reg           rst_n;      // Reset

wire [ 3 : 0] sdram_cmd;  // Command
wire [ 1 : 0] sdram_bank; // Bank address
wire [12 : 0] sdram_addr; // Data address

wire          init_end;   // End flag
wire [ 3 : 0] init_cmd;   // Command
wire [ 1 : 0] init_bank;  // Bank address
wire [12 : 0] init_addr;  // Data address

reg           ar_en;      // Enable
wire          ar_req;     // Request
wire          ar_end;     // End flag
wire [ 3 : 0] ar_cmd;     // Command
wire [ 1 : 0] ar_bank;    // Bank address
wire [12 : 0] ar_addr;    // Data address

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

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        ar_en <= 1'b0;
    end
    else if (init_end && ar_req) begin
        ar_en <= 1'b1;
    end
    else if (ar_end) begin
        ar_en <= 1'b0;
    end
    else begin
        ar_en <= ar_en;
    end
end

assign sdram_cmd  = (init_end) ? ar_cmd  : init_cmd;
assign sdram_bank = (init_end) ? ar_bank : init_bank;
assign sdram_addr = (init_end) ? ar_addr : init_addr;

sdram_init sdram_init_inst(
    .init_clk  (clk),
    .init_rst_n(rst_n),

    .init_end  (init_end),
    .init_cmd  (init_cmd),
    .init_bank (init_bank),
    .init_addr (init_addr)
);

sdram_aref sdram_aref_inst(
    .ar_clk  (clk),
    .ar_rst_n(rst_n),
    .ar_en   (ar_en),
    .init_end(init_end),

    .ar_req  (ar_req),
    .ar_end  (ar_end),
    .ar_cmd  (ar_cmd),
    .ar_bank (ar_bank),
    .ar_addr (ar_addr)
);

W989DxDB sdram_inst(
    .clk  (clk),
    .cke  (1'b1),
    .addr (sdram_addr),
    .ba   (sdram_bank),
    .cs_n (sdram_cmd[3]),
    .ras_n(sdram_cmd[2]),
    .cas_n(sdram_cmd[1]),
    .we_n (sdram_cmd[0]),
    .dq   (),
    .dqm  (2'b0)
);

// Store 10 characters(Each character is 8 bits wide)
reg [79 : 0] state_curr;

always @(*) begin
    case (sdram_aref_inst.state_curr)
        3'b000:  state_curr = "STATE_IDLE";
        3'b001:  state_curr = "STATE_PRE ";
        3'b011:  state_curr = "STATE_TRP ";
        3'b010:  state_curr = "STATE_AR  ";
        3'b110:  state_curr = "STATE_TRFC";
        3'b111:  state_curr = "STATE_END ";
        default: state_curr = "STATE_IDLE";
    endcase
end

initial begin
    $monitor("Command Display %s at the time %t", sdram_inst.command_display,
                                                  $time);
end

endmodule
