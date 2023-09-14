.PHONY: sim_init sim_test clean

sim_init:
	cd models && \
	ncverilog -gui +access+r +define+clk_133+x16+dumpfile W989DxDB.nc.vp ../rtl/modules/sdram_init.v ../sim/sdram_tb_init.v
sim_test:
	cd models && \
	ncverilog +access+r +define+clk_133+x16 W989DxDB.nc.vp ../sim/sdram_test.v
clean:
	find -name "*.log" -o -name "*.history" -o -name "*.key" | xargs rm -f
	find -name ".simvision" | xargs rm -rf
	find -name "INCA_libs" | xargs rm -rf
	find -name "waves.shm" | xargs rm -rf
