.PHONY: sim clean

sim:
	cd models && \
	ncverilog +access+r +define+clk_133+x16 W989DxDB.nc.vp ../sim/sdram_test.v
clean:
	find -name "*.log" -o -name "*.history" -o -name "*.key" | xargs rm -f
	find -name "INCA_libs" | xargs rm -rf
