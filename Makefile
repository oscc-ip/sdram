sim-nc:
	ncverilog +access+r +define+clk_133 models/W989DxDB.nc.vp sim/sdram_test.v
clean:
	find -name "*.log" -o -name "*.history" | xargs rm -f
