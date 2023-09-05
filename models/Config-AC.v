/*******************************************************************************
[Disclaimer]  
   This software code and all associated documentation,
   comments or other information (collectively "Software") is
   provided "AS IS" without warranty of any kind. Winbond Electronics
   Corporation ("WEC") hereby DISCLAIMS ALL WARRANTIES EXPRESS
   OR IMPLIED, INCLUDING BUT NOT LIMITED TO, NONINFRINGEMENT
   OF THIRD PARTY RIGHTS, AND ANY IMPLIED WARRANTIES OF MERCHANTABILITY
   OR FITNESS FOR ANY PARTICULAR PURPOSE. WEC DOES NOT
   WARRANT THAT THE SOFTWARE WILL MEET YOUR REQUIREMENTS, OR THAT
   THE OPERATION OF THE SOFTWARE WILL BE UNINTERRUPTED OR ERROR-FREE.
   FURTHERMORE, WEC DOES NOT MAKE ANY REPRESENTATIONS REGARDING
   THE USE OR THE RESULTS OF THE USE OF THE SOFTWARE IN
   TERMS OF ITS CORRECTNESS, ACCURACY, RELIABILITY, OR OTHERWISE.
   THE ENTIRE RISK ARISING OUT OF USE OR PERFORMANCE OF THE SOFTWARE
   SHALL REMAIN WITH YOU. IN NO EVENT SHALL WEC, ITS AFFILIATED
   COMPANIES OR THEIR SUPPLIERS BE LIABLE FOR ANY DIRECT,
   INDIRECT, CONSEQUENTIAL, INCIDENTAL, OR SPECIAL DAMAGES (INCLUDING,
   WITHOUT LIMITATION, DAMAGES FOR LOSS OF PROFITS, BUSINESS
   INTERRUPTION, OR LOSS OF INFORMATION) ARISING OUT OF YOUR
   USE OF OR INABILITY TO USE THE SOFTWARE, EVEN IF WEC HAS BEEN
   ADVISED OF THE POSSIBILITY OF SUCH DAMAGES.
   
   Copyright 2014 Winbond Electronics Corporation. All rights reserved
*******************************************************************************/

                                           // SYMBOL UNITS DESCRIPTION
                                           // ------ ----- -----------
`ifdef clk_133                             //              Timing Parameters for -75 (CL = 3)
    parameter tCK              =     7500; // tCK    ps    Nominal Clock Cycle Time
    parameter tCK3_min         =     7500; // tCK    ps    Nominal Clock Cycle Time
    parameter tCK2_min         =     9600; // tCK    ps    Nominal Clock Cycle Time
    parameter tCK1_min         =     0000; // tCK    ps    Nominal Clock Cycle Time
    parameter tAC3             =     5400; // tAC3   ps    Access time from CLK (pos edge) CL = 3
    parameter tAC2             =     8000; // tAC2   ps    Access time from CLK (pos edge) CL = 2
    parameter tAC1             =     0000; // tAC1   ps    Parameter definition for compilation - CL = 1 illegal for 133
    parameter tHZ3             =     5400; // tHZ3   ps    Data Out High Z time - CL = 3
    parameter tHZ2             =     6000; // tHZ2   ps    Data Out High Z time - CL = 2
    parameter tHZ1             =     0000; // tHZ1   ps    Parameter definition for compilation - CL = 1 illegal for 133
    parameter tOH              =     2500; // tOH    ps    Data Out Hold time
    parameter tMRD             =        2; // tMRD   tCK   Load Mode Register command cycle time (2 * tCK)
    parameter tRAS             =    45000; // tRAS   ps    Active to Precharge command time
    parameter tRC              =    67500; // tRC    ps    Active to Active/Auto Refresh command time
    parameter tRFC             =    72000; // tRFC   ps    Refresh to Refresh Command interval time
    parameter tRCD             =    18000; // tRCD   ps    Active to Read/Write command time
    parameter tRP              =    18000; // tRP    ps    Precharge command period
    parameter tRRD             =        2; // tRRD   tCK   Active bank a to Active bank b command time
    parameter tWRa             =    15000; // tWR    ps    Write recovery time (auto-precharge mode - must add 1 CLK)
    parameter tWRm             =    15000; // tWR    ps    Write recovery time
    parameter tCH              =     2500; // tCH    ps    Clock high level width
    parameter tCL              =     2500; // tCL    ps    Clock low level width
    parameter tXSR             =   115000; // tXSR   ps    Clock low level width
`else `ifdef clk_166                       //              Timing Parameters for -6 (CL = 3)
    parameter tCK              =     6000; // tCK    ps    Nominal Clock Cycle Time
    parameter tCK3_min         =     6000; // tCK    ps    Nominal Clock Cycle Time
    parameter tCK2_min         =     9600; // tCK    ps    Nominal Clock Cycle Time
    parameter tCK1_min         =        0; // tCK    ps    Nominal Clock Cycle Time
    parameter tAC3             =     5000; // tAC3   ps    Access time from CLK (pos edge) CL = 3
    parameter tAC2             =     6000; // tAC2   ps    Access time from CLK (pos edge) CL = 2
    parameter tAC1             =        0; // tAC1   ps    Access time from CLK (pos edge) CL = 1
    parameter tHZ3             =     5000; // tHZ3   ps    Data Out High Z time - CL = 3
    parameter tHZ2             =     8000; // tHZ2   ps    Data Out High Z time - CL = 2
    parameter tHZ1             =        0; // tHZ1   ps    Data Out High Z time - CL = 1
    parameter tOH              =     2500; // tOH    ps    Data Out Hold time
    parameter tMRD             =        2; // tMRD   tCK   Load Mode Register command cycle time (2 * tCK)
    parameter tRAS             =    42000; // tRAS   ps    Active to Precharge command time
    parameter tRC              =    60000; // tRC    ps    Active to Active/Auto Refresh command time
    parameter tRFC             =    72000; // tRFC   ps    Refresh to Refresh Command interval time
    parameter tRCD             =    18000; // tRCD   ps    Active to Read/Write command time
    parameter tRP              =    18000; // tRP    ps    Precharge command period
    parameter tRRD             =       2; // tRRD   tCK   Active bank a to Active bank b command time
    parameter tWRa             =    15000; // tWR    ps    Write recovery time (auto-precharge mode - must add 1 CLK)
    parameter tWRm             =    15000; // tWR    ps    Write recovery time
    parameter tCH              =     2500; // tCH    ps    Clock high level width
    parameter tCL              =     2500; // tCL    ps    Clock low level width
    parameter tXSR             =   120000; // tXSR   ps       
`else `define clk_166                    //          Timing Parameters for -6
    parameter tCK              =     6000; // tCK    ps    Nominal Clock Cycle Time
    parameter tCK3_min         =     6000; // tCK    ps    Nominal Clock Cycle Time
    parameter tCK2_min         =     9600; // tCK    ps    Nominal Clock Cycle Time
    parameter tCK1_min         =        0; // tCK    ps    Nominal Clock Cycle Time
    parameter tAC3             =     5000; // tAC3   ps    Access time from CLK (pos edge) CL = 3
    parameter tAC2             =     6000; // tAC2   ps    Access time from CLK (pos edge) CL = 2
    parameter tAC1             =        0; // tAC1   ps    Access time from CLK (pos edge) CL = 1
    parameter tHZ3             =     5000; // tHZ3   ps    Data Out High Z time - CL = 3
    parameter tHZ2             =     8000; // tHZ2   ps    Data Out High Z time - CL = 2
    parameter tHZ1             =        0; // tHZ1   ps    Data Out High Z time - CL = 1
    parameter tOH              =     2500; // tOH    ps    Data Out Hold time
    parameter tMRD             =        2; // tMRD   tCK   Load Mode Register command cycle time (2 * tCK)
    parameter tRAS             =    42000; // tRAS   ps    Active to Precharge command time
    parameter tRC              =    60000; // tRC    ps    Active to Active/Auto Refresh command time
    parameter tRFC             =    72000; // tRFC   ps    Refresh to Refresh Command interval time
    parameter tRCD             =    18000; // tRCD   ps    Active to Read/Write command time
    parameter tRP              =    18000; // tRP    ps    Precharge command period
    parameter tRRD             =       2; // tRRD   tCK   Active bank a to Active bank b command time
    parameter tWRa             =     15000; // tWR    ps    Write recovery time (auto-precharge mode - must add 1 CLK)
    parameter tWRm             =    15000; // tWR    ps    Write recovery time
    parameter tCH              =     2500; // tCH    ps    Clock high level width
    parameter tCL              =     2500; // tCL    ps    Clock low level width
    parameter tXSR             =   120000; // tXSR   ps      
`endif  `endif

    // Size Parameters based on Part Width

`ifdef x32
    parameter ADDR_BITS        =      13; // Set this parameter to control how many Address bits are used
    parameter ROW_BITS         =      13; // Set this parameter to control how many Row bits are used
    parameter DQ_BITS          =      32; // Set this parameter to control how many Data bits are used
    parameter DM_BITS          =       4; // Set this parameter to control how many DM bits are used
    parameter COL_BITS         =       9; // Set this parameter to control how many Column bits are used
    parameter BA_BITS          =       2; // Bank bits
`else  `ifdef x16
    parameter ADDR_BITS        =      13; // Set this parameter to control how many Address bits are used
    parameter ROW_BITS         =      13; // Set this parameter to control how many Row bits are used
    parameter DQ_BITS          =      16; // Set this parameter to control how many Data bits are used
    parameter DM_BITS          =       2; // Set this parameter to control how many DM bits are used
    parameter COL_BITS         =      10; // Set this parameter to control how many Column bits are used
    parameter BA_BITS          =       2; // Bank bits
`else `define x32
    parameter ADDR_BITS        =      13; // Set this parameter to control how many Address bits are used
    parameter ROW_BITS         =      9; // Set this parameter to control how many Row bits are used
    parameter DQ_BITS          =      32; // Set this parameter to control how many Data bits are used
    parameter DM_BITS          =       4; // Set this parameter to control how many DM bits are used
    parameter COL_BITS         =       9; // Set this parameter to control how many Column bits are used
    parameter BA_BITS          =       2; // Bank bits
    
`endif `endif

    // Other Parameters

    parameter full_mem_bits    = BA_BITS+ADDR_BITS+COL_BITS; // Set this parameter to control how many unique addresses are used
    parameter part_mem_bits    = 10;                         // For fast sim load
    parameter part_size        = 512;                        // Set this parameter to indicate part size(512Mb, 256Mb, 128Mb)

//-------------------------------------------------------------------------------------------------------


    
    parameter MRS              = 2'b00;                 // Standard Mode Register Definition BA1=0, BA0=0
    parameter EMRS             = 2'b10;                 // Extended Mode Register Definition BA1=1, BA0=0    
    
    parameter A10_1            = 1'b1;                  // A10 = 1 PRECHARGE ALL BANK      
    parameter A10_0            = 1'b0;                  // A10 = 0 PRECHARGE ONE BANK 
    
    parameter Bank0            = 2'b00;                 // PRECHARGE BANK 0       
    parameter Bank1            = 2'b01;                 // PRECHARGE BANK 1         
    parameter Bank2            = 2'b10;                 // PRECHARGE BANK 2       
    parameter Bank3            = 2'b11;                 // PRECHARGE BANK 3   
    
    parameter Full_array       = 3'b000;                // EMRS Full array    [A2:A0]    
    parameter Half_array       = 3'b001;                // EMRS Half array    [A2:A0]
    parameter Quarter_array    = 3'b010;                // EMRS Quarter array [A2:A0] 
    
    parameter TCSR             = 2'b00;                 // TCSR [A4:A3]   

    parameter Full_Drive       = 2'b00;                 // EMRS DS Full     [A6:A5]     
    parameter Half_Drive       = 2'b01;                 // EMRS DS Half     [A6:A5]
    parameter Quarter_Drive    = 2'b10;                 // EMRS DS Quarter  [A6:A5]
    parameter Eigth_Drive      = 2'b11;                 // EMRS DS Eigth    [A6:A5]

    parameter Rev_Bit          = ADDR_BITS-7;           // Reserved Bit
    parameter Rev              = {Rev_Bit{1'b0}};       // Reserved

    parameter Reserved_Bit     = ADDR_BITS-10;           // Reserved Bit
    parameter Reserved         = {Reserved_Bit{1'b0}};   // Reserved
    
    parameter Burst_Length_1   = 3'b000;                 // MRS Burst Length 1  [A2:A0]
    parameter Burst_Length_2   = 3'b001;                 // MRS Burst Length 2  [A2:A0]
    parameter Burst_Length_4   = 3'b010;                 // MRS Burst Length 4  [A2:A0]
    parameter Burst_Length_8   = 3'b011;                 // MRS Burst Length 8  [A2:A0] 
    parameter Burst_Full       = 3'b111;                 // MRS Burst Full-Page [A2:A0]

    parameter BT_Seq           = 1'b0;                   // MRS Burst Type Sequential [A3] 
    parameter BT_Inter         = 1'b1;                   // MRS Burst Type Interleaved [A3]

    parameter CAS_Lat_2        = 3'b010;                 // MRS CAS Latency 2  [A6:A4]
    parameter CAS_Lat_3        = 3'b011;                 // MRS CAS Latency 3  [A6:A4]
    
    parameter REV              = 2'b00 ;                 // Reserved bit  [A8:A7]
    
    parameter B_Write          = 1'b0;                   // MRS Write Burst Mode [A9] 
    parameter S_Write          = 1'b1;                   // MRS Write Burst Mode [A9]