`timescale 1ps / 1ps

module tb_sdram_model;

`include "Config-AC.v"

reg                      clk;
reg                      cke;
reg                      cs_n;
reg                      ras_n;
reg                      cas_n;
reg                      we_n;
reg  [BA_BITS   - 1 : 0] ba;
reg  [ADDR_BITS - 1 : 0] addr;
reg  [DM_BITS   - 1 : 0] dqm;
reg  [DQ_BITS   - 1 : 0] dq;

wire [DQ_BITS   - 1 : 0] DQ = dq;

parameter hi_z = { DQ_BITS{1'bz} };
parameter t200us = 2000000000;

W989DxDB sdram_inst(
    .clk  (clk),
    .cke  (cke),
    .addr (addr),
    .ba   (ba),
    .cs_n (cs_n),
    .ras_n(ras_n),
    .cas_n(cas_n),
    .we_n (we_n),
    .dq   (DQ),
    .dqm  (dqm)
);

initial begin
    clk  = 1;
    cke  = 1;
    cs_n = 1;
    dq   = hi_z;
end

always #(tCK / 2) clk = ~clk;

task CMD_NOP;
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

task CMD_PRECHARGE_ALL;
    input [DM_BITS - 1 : 0] dqm_in;
    input [DQ_BITS - 1 : 0] dq_in;
    begin
        cke   = 1;
        cs_n  = 0;
        ras_n = 0;
        cas_n = 1;
        we_n  = 0;
        ba    = 0;
        addr  = 1024; // A10 = 1
        dqm   = dqm_in;
        dq    = dq_in;
    end
endtask

task CMD_AUTO_REFRESH;
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

task CMD_LOAD_MODE_REG;
    input [ADDR_BITS - 1 : 0] op_code;
    begin
        cke   = 1;
        cs_n  = 0;
        ras_n = 0;
        cas_n = 0;
        we_n  = 0;
        ba    = 0;
        addr  = op_code;
        dqm   = 0;
        dq    = hi_z;
    end
endtask

task CMD_ACTIVATE;
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

task CMD_READ_AUTO_PRECHARGE;
    input   [BA_BITS - 1 : 0] bank;
    input [ADDR_BITS - 1 : 0] column;
    input   [DM_BITS - 1 : 0] dqm_in;
    input   [DQ_BITS - 1 : 0] dq_in;
    begin
        cke   = 1;
        cs_n  = 0;
        ras_n = 1;
        cas_n = 0;
        we_n  = 1;
        ba    = bank;
        addr  = column;
        dqm   = dqm_in;
        dq    = dq_in;
    end
endtask

task CMD_WRITE_AUTO_PRECHARGE;
    input   [BA_BITS - 1 : 0] bank;
    input [ADDR_BITS - 1 : 0] column;
    input   [DM_BITS - 1 : 0] dqm_in;
    input   [DQ_BITS - 1 : 0] dq_in;
    begin
        cke   = 1;
        cs_n  = 0;
        ras_n = 1;
        cas_n = 0;
        we_n  = 0;
        ba    = bank;
        addr  = column;
        dqm   = dqm_in;
        dq    = dq_in;
    end
endtask

task CMD_PRECHARGE_BANK_0;
    input [DM_BITS - 1 : 0] dqm_in;
    input [DQ_BITS - 1 : 0] dq_in;
    begin
        cke   = 1;
        cs_n  = 0;
        ras_n = 0;
        cas_n = 1;
        we_n  = 0;
        ba    = 0;
        addr  = 0;
        dqm   = dqm_in;
        dq    = dq_in;
    end
endtask

task CMD_PRECHARGE_BANK_1;
    input [DM_BITS - 1 : 0] dqm_in;
    input [DQ_BITS - 1 : 0] dq_in;
    begin
        cke   = 1;
        cs_n  = 0;
        ras_n = 0;
        cas_n = 1;
        we_n  = 0;
        ba    = 1;
        addr  = 0;
        dqm   = dqm_in;
        dq    = dq_in;
    end
endtask

task CMD_PRECHARGE_BANK_2;
    input [DM_BITS - 1 : 0] dqm_in;
    input [DQ_BITS - 1 : 0] dq_in;
    begin
        cke   = 1;
        cs_n  = 0;
        ras_n = 0;
        cas_n = 1;
        we_n  = 0;
        ba    = 2;
        addr  = 0;
        dqm   = dqm_in;
        dq    = dq_in;
    end
endtask

task CMD_PRECHARGE_BANK_3;
    input [DM_BITS - 1 : 0] dqm_in;
    input [DQ_BITS - 1 : 0] dq_in;
    begin
        cke   = 1;
        cs_n  = 0;
        ras_n = 0;
        cas_n = 1;
        we_n  = 0;
        ba    = 3;
        addr  = 0;
        dqm   = dqm_in;
        dq    = dq_in;
    end
endtask

initial begin
    begin
        // Initialize
        #t200us;
        #tCK; CMD_NOP          (0, hi_z); // NOP
        #tCK; CMD_PRECHARGE_ALL(0, hi_z); // Precharge ALL Bank
        #tCK; CMD_NOP          (0, hi_z); // NOP
        #tCK; CMD_NOP          (0, hi_z); // NOP
        #tCK; CMD_AUTO_REFRESH;           // Auto Refresh
        #tCK; CMD_NOP          (0, hi_z); // NOP
        #tCK; CMD_NOP          (0, hi_z); // NOP
        #tCK; CMD_NOP          (0, hi_z); // NOP
        #tCK; CMD_NOP          (0, hi_z); // NOP
        #tCK; CMD_NOP          (0, hi_z); // NOP
        #tCK; CMD_NOP          (0, hi_z); // NOP
        #tCK; CMD_NOP          (0, hi_z); // NOP
        #tCK; CMD_NOP          (0, hi_z); // NOP
        #tCK; CMD_NOP          (0, hi_z); // NOP
        #tCK; CMD_AUTO_REFRESH;           // Auto Refresh
        #tCK; CMD_NOP          (0, hi_z); // NOP
        #tCK; CMD_NOP          (0, hi_z); // NOP
        #tCK; CMD_NOP          (0, hi_z); // NOP
        #tCK; CMD_NOP          (0, hi_z); // NOP
        #tCK; CMD_NOP          (0, hi_z); // NOP
        #tCK; CMD_NOP          (0, hi_z); // NOP
        #tCK; CMD_NOP          (0, hi_z); // NOP
        #tCK; CMD_NOP          (0, hi_z); // NOP
        #tCK; CMD_NOP          (0, hi_z); // NOP
        #tCK; CMD_LOAD_MODE_REG(50);      // Load Mode: Lat = 3, BL = 4, Seq
        #tCK; CMD_NOP          (0, hi_z); // NOP

        // Write with auto precharge to bank 0 (non-interrupt)
        #tCK; CMD_ACTIVATE            (0, 0, hi_z);          // Active: Bank = 0, Row = 0
        #tCK; CMD_NOP                 (0, hi_z);             // NOP
        #tCK; CMD_NOP                 (0, hi_z);             // NOP
        #tCK; CMD_WRITE_AUTO_PRECHARGE(0, 1024, $random, 0); // Write : Bank = 0, Col = 0, Dqm = 0, Auto Precharge
        #tCK; CMD_NOP                 (0, $random);          // NOP
        #tCK; CMD_NOP                 (0, $random);          // NOP
        #tCK; CMD_NOP                 (0, $random);          // NOP
        #tCK; CMD_NOP                 (0, hi_z);             // NOP

        // Write with auto precharge to bank 1 (non-interrupt)
        #tCK; CMD_ACTIVATE            (1, 0, hi_z);          // Active: Bank = 1, Row = 0
        #tCK; CMD_NOP                 (0, hi_z);             // NOP
        #tCK; CMD_NOP                 (0, hi_z);             // NOP
        #tCK; CMD_WRITE_AUTO_PRECHARGE(1, 1024, $random, 0); // Write : Bank = 1, Col = 0, Dqm = 0, Auto precharge
        #tCK; CMD_NOP                 (0, $random);          // NOP
        #tCK; CMD_NOP                 (0, $random);          // NOP
        #tCK; CMD_NOP                 (0, $random);          // NOP
        #tCK; CMD_NOP                 (0, hi_z);             // NOP

        // Write with auto precharge to bank 2 (non-interrupt)
        #tCK; CMD_ACTIVATE            (2, 0, hi_z);          // Active: Bank = 2, Row = 0
        #tCK; CMD_NOP                 (0, hi_z);             // NOP
        #tCK; CMD_NOP                 (0, hi_z);             // NOP
        #tCK; CMD_WRITE_AUTO_PRECHARGE(2, 1024, $random, 0); // Write : Bank = 2, Col = 0, Dqm = 0, Auto Precharge
        #tCK; CMD_NOP                 (0, $random);          // NOP
        #tCK; CMD_NOP                 (0, $random);          // NOP
        #tCK; CMD_NOP                 (0, $random);          // NOP
        #tCK; CMD_NOP                 (0, hi_z);             // NOP

        // Write with auto precharge to bank 3 (non-interrupt)
        #tCK; CMD_ACTIVATE            (3, 0, hi_z);          // Active: Bank = 3, Row = 0
        #tCK; CMD_NOP                 (0, hi_z);             // NOP
        #tCK; CMD_NOP                 (0, hi_z);             // NOP
        #tCK; CMD_WRITE_AUTO_PRECHARGE(3, 1024, $random, 0); // Write:  Bank = 3, Col = 0, Dqm = 0, Auto precharge
        #tCK; CMD_NOP                 (0, $random);          // NOP
        #tCK; CMD_NOP                 (0, $random);          // NOP
        #tCK; CMD_NOP                 (0, $random);          // NOP
        #tCK; CMD_NOP                 (0, hi_z);             // NOP

        // Read with auto precharge to bank 0 (non-interrupt)
        #tCK; CMD_ACTIVATE           (0, 0, hi_z);       // Active: Bank = 0, Row = 0
        #tCK; CMD_NOP                (0, hi_z);          // NOP
        #tCK; CMD_NOP                (0, hi_z);          // NOP
        #tCK; CMD_READ_AUTO_PRECHARGE(0, 1024, 0, hi_z); // Read:   Bank = 0, Col = 0, Dqm = 0, Auto precharge
        #tCK; CMD_NOP                (0, hi_z);          // NOP
        #tCK; CMD_NOP                (0, hi_z);          // NOP
        #tCK; CMD_NOP                (0, hi_z);          // NOP
        #tCK; CMD_NOP                (0, hi_z);          // NOP

        // Read with auto precharge to bank 1 (non-interrupt)
        #tCK; CMD_ACTIVATE           (1, 0, hi_z);       // Active: Bank = 1, Row = 0
        #tCK; CMD_NOP                (0, hi_z);          // NOP
        #tCK; CMD_NOP                (0, hi_z);          // NOP
        #tCK; CMD_READ_AUTO_PRECHARGE(1, 1024, 0, hi_z); // Read:   Bank = 1, Col = 0, Dqm = 0, Auto precharge
        #tCK; CMD_NOP                (0, hi_z);          // NOP
        #tCK; CMD_NOP                (0, hi_z);          // NOP
        #tCK; CMD_NOP                (0, hi_z);          // NOP
        #tCK; CMD_NOP                (0, hi_z);          // NOP

        // Read with auto precharge to bank 2 (non-interrupt)
        #tCK; CMD_ACTIVATE           (2, 0, hi_z);       // Active: Bank = 2, Row = 0
        #tCK; CMD_NOP                (0, hi_z);          // NOP
        #tCK; CMD_NOP                (0, hi_z);          // NOP
        #tCK; CMD_READ_AUTO_PRECHARGE(2, 1024, 0, hi_z); // Read:   Bank = 2, Col = 0, Dqm = 0, Auto precharge
        #tCK; CMD_NOP                (0, hi_z);          // NOP
        #tCK; CMD_NOP                (0, hi_z);          // NOP
        #tCK; CMD_NOP                (0, hi_z);          // NOP
        #tCK; CMD_NOP                (0, hi_z);          // NOP

        // Read with auto precharge to bank 3 (non-interrupt)
        #tCK; CMD_ACTIVATE           (3, 0, hi_z);       // Active: Bank = 3, Row = 0
        #tCK; CMD_NOP                (0, hi_z);          // NOP
        #tCK; CMD_NOP                (0, hi_z);          // NOP
        #tCK; CMD_READ_AUTO_PRECHARGE(3, 1024, 0, hi_z); // Read:   Bank = 3, Col = 0, Dqm = 0, Auto precharge
        #tCK; CMD_NOP                (0, hi_z);          // NOP
        #tCK; CMD_NOP                (0, hi_z);          // NOP
        #tCK; CMD_NOP                (0, hi_z);          // NOP
        #tCK; CMD_NOP                (0, hi_z);          // NOP

        #tCK; CMD_NOP(0, hi_z); // NOP
        #tCK; CMD_NOP(0, hi_z); // NOP
        #tCK; CMD_NOP(0, hi_z); // NOP
        #tCK;
    end
    $stop;
    $finish;
end

endmodule
