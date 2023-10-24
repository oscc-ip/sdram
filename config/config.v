`ifdef freq_50
    parameter CYCLE = 20;
`elsif freq_100
    parameter CYCLE = 10;
`elsif freq_125
    parameter CYCLE =  8;
`elsif freq_166
    parameter CYCLE =  6
`elsif freq_200
    parameter CYCLE =  5
`else
    parameter CYCLE = 10;
`endif
