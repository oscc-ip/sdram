`timescale 1ps / 1ps

module sdram_test;

`include "Config-AC.v"

reg                     clk;
reg                     cke;
reg                     cs_n;
reg                     ras_n;
reg                     cas_n;
reg                     we_n;
reg [ADDR_BITS - 1 : 0] addr;
reg   [BA_BITS - 1 : 0] ba;
reg   [DQ_BITS - 1 : 0] dq;
reg   [DM_BITS - 1 : 0] dqm;

wire  [DQ_BITS - 1 : 0] DQ = dq;

parameter hi_z = {DQ_BITS{1'bz}};
parameter t100us = 1000000000;

W989DxDB sdram(clk, cke, addr, ba, cs_n, ras_n, cas_n, we_n, DQ, dqm);

initial begin
    clk  = 1'b0;
    cke  = 1'b0;
    cs_n = 1'b1;
    dq   = hi_z;
end

always #(tCK / 2) clk = ~clk;

task NOP;
    input [DM_BITS - 1 : 0] dqm_in;
    input [DQ_BITS - 1 : 0] dq_in;
    begin
        cke   = 1;
        cs_n  = 0;
        ras_n = 1;
        cas_n = 1;
        we_n  = 1;
        dqm   = dqm_in;
        dq    = dq_in;
    end
endtask

task PERA;
    input [DM_BITS - 1 : 0] dqm_in;
    input [DQ_BITS - 1 : 0] dq_in;
    begin
        cke   = 1;
        cs_n  = 0;
        ras_n = 0;
        cas_n = 1;
        we_n  = 0;
        addr  = 1024; // A10 = 1
        ba    = 0;
        dqm   = dqm_in;
        dq    = dq_in;
    end
endtask

task AREF;
    begin
        cke   = 1;
        cs_n  = 0;
        ras_n = 0;
        cas_n = 0;
        we_n  = 1;
        dqm   = 0;
        dq    = hi_z;
    end
endtask

task LMR;
    input [ADDR_BITS - 1 : 0] op_code;
    begin
        cke   = 1;
        cs_n  = 0;
        ras_n = 0;
        cas_n = 0;
        we_n  = 0;
        addr  = op_code;
        ba    = 0;
        dqm   = 0;
        dq    = hi_z;
    end
endtask


task active;
    input [ADDR_BITS - 1 : 0] bank;
    input  [ROW_BITS - 1 : 0] row;
    input   [DQ_BITS - 1 : 0] dq_in;
    begin
        cke   = 1;
        cs_n  = 0;
        ras_n = 0;
        cas_n = 1;
        we_n  = 1;
        ba    = bank;
        addr  = row;
        dqm   = 0;
        dq    = dq_in;
    end
endtask



task burst_term;
    input [DQ_BITS - 1 : 0] dq_in;
    begin
        cke   = 1;
        cs_n  = 0;
        ras_n = 1;
        cas_n = 1;
        we_n  = 0;
        dqm   = 0;
        //ba    = 0;
        //addr  = 0;
        dq    = dq_in;
    end
endtask



task precharge_bank_0;
    input [DM_BITS - 1 : 0] dqm_in;
    input [DQ_BITS - 1 : 0] dq_in;
    begin
        cke   = 1;
        cs_n  = 0;
        ras_n = 0;
        cas_n = 1;
        we_n  = 0;
        dqm   = dqm_in;
        ba    = 0;
        addr  = 0;
        dq    = dq_in;
    end
endtask

task precharge_bank_1;
    input [DM_BITS - 1 : 0] dqm_in;
    input [DQ_BITS - 1 : 0] dq_in;
    begin
        cke   = 1;
        cs_n  = 0;
        ras_n = 0;
        cas_n = 1;
        we_n  = 0;
        dqm   = dqm_in;
        ba    = 1;
        addr  = 0;
        dq    = dq_in;
    end
endtask

task precharge_bank_2;
    input [DM_BITS - 1 : 0] dqm_in;
    input [DQ_BITS - 1 : 0] dq_in;
    begin
        cke   = 1;
        cs_n  = 0;
        ras_n = 0;
        cas_n = 1;
        we_n  = 0;
        dqm   = dqm_in;
        ba    = 2;
        addr  = 0;
        dq    = dq_in;
    end
endtask

task precharge_bank_3;
    input [DM_BITS - 1 : 0] dqm_in;
    input [DQ_BITS - 1 : 0] dq_in;
    begin
        cke   = 1;
        cs_n  = 0;
        ras_n = 0;
        cas_n = 1;
        we_n  = 0;
        dqm   = dqm_in;
        ba    = 3;
        addr  = 0;
        dq    = dq_in;
    end
endtask



task read;
    input   [BA_BITS - 1 : 0] bank;
    input [ADDR_BITS - 1 : 0] column;
    input   [DQ_BITS - 1 : 0] dq_in;
    input   [DM_BITS - 1 : 0] dqm_in;
    begin
        cke   = 1;
        cs_n  = 0;
        ras_n = 1;
        cas_n = 0;
        we_n  = 1;
        dqm   = dqm_in;
        ba    = bank;
        addr  = column;
        dq    = dq_in;
    end
endtask

task write;
    input   [BA_BITS - 1 : 0] bank;
    input [ADDR_BITS - 1 : 0] column;
    input   [DQ_BITS - 1 : 0] dq_in;
    input   [DM_BITS - 1 : 0] dqm_in;
    begin
        cke   = 1;
        cs_n  = 0;
        ras_n = 1;
        cas_n = 0;
        we_n  = 0;
        dqm   = dqm_in;
        ba    = bank;
        addr  = column;
        dq    = dq_in;
    end
endtask

initial begin
    begin
        // Initialize
        #t100us;
        #tCK; NOP    (0, hi_z);                 // Nop
        #tCK; PERA(0, hi_z);                    // Precharge ALL Bank
        #tCK; NOP    (0, hi_z);                 // Nop
        #tCK; NOP    (0, hi_z);                 // Nop
        #tCK; AREF;                             // Auto Refresh
        #tCK; NOP    (0, hi_z);                 // Nop
        #tCK; NOP    (0, hi_z);                 // Nop
        #tCK; NOP    (0, hi_z);                 // Nop
        #tCK; NOP    (0, hi_z);                 // Nop
        #tCK; NOP    (0, hi_z);                 // Nop
        #tCK; NOP    (0, hi_z);                 // Nop
        #tCK; NOP    (0, hi_z);                 // Nop
        #tCK; NOP    (0, hi_z);                 // Nop
        #tCK; NOP    (0, hi_z);                 // Nop
        #tCK; AREF;                             // Auto Refresh
        #tCK; NOP    (0, hi_z);                 // Nop
        #tCK; NOP    (0, hi_z);                 // Nop
        #tCK; NOP    (0, hi_z);                 // Nop
        #tCK; NOP    (0, hi_z);                 // Nop
        #tCK; NOP    (0, hi_z);                 // Nop
        #tCK; NOP    (0, hi_z);                 // Nop
        #tCK; NOP    (0, hi_z);                 // Nop
        #tCK; NOP    (0, hi_z);                 // Nop
        #tCK; NOP    (0, hi_z);                 // Nop
        #tCK; LMR (50);                         // Load Mode: Lat = 3, BL = 4, Seq
        #tCK; NOP    (0, hi_z);                 // Nop

        // Write with auto precharge to bank 0 (non-interrupt)
        #tCK; active (0, 0, hi_z);              // Active: Bank = 0, Row = 0
        #tCK; NOP    (0, hi_z);                 // Nop
        #tCK; NOP    (0, hi_z);                 // Nop
        #tCK; write  (0, 1024, $random, 0);     // Write : Bank = 0, Col = 0, Dqm = 0, Auto Precharge
        #tCK; NOP    (0, $random);              // Nop
        #tCK; NOP    (0, $random);              // Nop
        #tCK; NOP    (0, $random);              // Nop
        #tCK; NOP    (0, hi_z);                 // Nop

        // // Write with auto precharge to bank 1 (non-interrupt)
        // #tCK; active (1, 0, hi_z);              // Active: Bank = 1, Row = 0
        // #tCK; NOP    (0, hi_z);                 // Nop
        // #tCK; NOP    (0, hi_z);                 // Nop
        // #tCK; write  (1, 1024, $random, 0);     // Write : Bank = 1, Col = 0, Dqm = 0, Auto precharge
        // #tCK; NOP    (0, $random);              // Nop
        // #tCK; NOP    (0, $random);              // Nop
        // #tCK; NOP    (0, $random);              // Nop
        // #tCK; NOP    (0, hi_z);                 // Nop

        // // Write with auto precharge to bank 2 (non-interrupt)
        // #tCK; active (2, 0, hi_z);              // Active: Bank = 2, Row = 0
        // #tCK; NOP    (0, hi_z);                 // Nop
        // #tCK; NOP    (0, hi_z);                 // Nop
        // #tCK; write  (2, 1024, $random, 0);     // Write : Bank = 2, Col = 0, Dqm = 0, Auto Precharge
        // #tCK; NOP    (0, $random);              // Nop
        // #tCK; NOP    (0, $random);              // Nop
        // #tCK; NOP    (0, $random);              // Nop
        // #tCK; NOP    (0, hi_z);                 // Nop

        // // Write with auto precharge to bank 3 (non-interrupt)
        // #tCK; active (3, 0, hi_z);              // Active: Bank = 3, Row = 0
        // #tCK; NOP    (0, hi_z);                 // Nop
        // #tCK; NOP    (0, hi_z);                 // Nop
        // #tCK; write  (3, 1024, $random, 0);     // Write : Bank = 3, Col = 0, Dqm = 0, Auto precharge
        // #tCK; NOP    (0, $random);              // Nop
        // #tCK; NOP    (0, $random);              // Nop
        // #tCK; NOP    (0, $random);              // Nop
        // #tCK; NOP    (0, hi_z);                 // Nop

        // // Read with auto precharge to bank 0 (non-interrupt)
        // #tCK; active (0, 0, hi_z);              // Active: Bank = 0, Row = 0
        // #tCK; NOP    (0, hi_z);                 // Nop
        // #tCK; NOP    (0, hi_z);                 // Nop
        // #tCK; read   (0, 1024, hi_z, 0);        // Read  : Bank = 0, Col = 0, Dqm = 0, Auto precharge
        // #tCK; NOP    (0, hi_z);                 // Nop
        // #tCK; NOP    (0, hi_z);                 // Nop
        // #tCK; NOP    (0, hi_z);                 // Nop
        // #tCK; NOP    (0, hi_z);                 // Nop

        // // Read with auto precharge to bank 1 (non-interrupt)
        // #tCK; active (1, 0, hi_z);              // Active: Bank = 1, Row = 0
        // #tCK; NOP    (0, hi_z);                 // Nop
        // #tCK; NOP    (0, hi_z);                 // Nop
        // #tCK; read   (1, 1024, hi_z, 0);        // Read  : Bank = 1, Col = 0, Dqm = 0, Auto precharge
        // #tCK; NOP    (0, hi_z);                 // Nop
        // #tCK; NOP    (0, hi_z);                 // Nop
        // #tCK; NOP    (0, hi_z);                 // Nop
        // #tCK; NOP    (0, hi_z);                 // Nop

        // // Read with auto precharge to bank 2 (non-interrupt)
        // #tCK; active (2, 0, hi_z);              // Active: Bank = 2, Row = 0
        // #tCK; NOP    (0, hi_z);                 // Nop
        // #tCK; NOP    (0, hi_z);                 // Nop
        // #tCK; read   (2, 1024, hi_z, 0);        // Read  : Bank = 2, Col = 0, Dqm = 0, Auto precharge
        // #tCK; NOP    (0, hi_z);                 // Nop
        // #tCK; NOP    (0, hi_z);                 // Nop
        // #tCK; NOP    (0, hi_z);                 // Nop
        // #tCK; NOP    (0, hi_z);                 // Nop

        // // Read with auto precharge to bank 3 (non-interrupt)
        // #tCK; active (3, 0, hi_z);              // Active: Bank = 3, Row = 0
        // #tCK; NOP    (0, hi_z);                 // Nop
        // #tCK; NOP    (0, hi_z);                 // Nop
        // #tCK; read   (3, 1024, hi_z, 0);        // Read  : Bank = 3, Col = 0, Dqm = 0, Auto precharge
        // #tCK; NOP    (0, hi_z);                 // Nop
        // #tCK; NOP    (0, hi_z);                 // Nop
        // #tCK; NOP    (0, hi_z);                 // Nop
        // #tCK; NOP    (0, hi_z);                 // Nop

        // #tCK; NOP    (0, hi_z);                 // Nop
        // #tCK; NOP    (0, hi_z);                 // Nop
        // #tCK; NOP    (0, hi_z);                 // Nop
        // #tCK;
    end
$stop;
$finish;
end

endmodule
