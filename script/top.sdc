set clk_port_name CLK
set CLK_FREQ_MHZ 200
set clk_io_pct 0.2

set clk_port [get_ports $clk_port_name]
create_clock -name core_clock -period [expr 1000.0 / $CLK_FREQ_MHZ] $clk_port
