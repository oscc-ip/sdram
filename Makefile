.PHONY: sim_init sim_ar sim_test clean

CMD_GUI ?=

ifeq ($(CMD_GUI), y)
    CMD_GUI_TEMP = -gui
else ifeq ($(CMD_GUI),)
    CMD_GUI_TEMP =
else ifeq ($(CMD_GUI), n)
    CMD_GUI_TEMP =
else
    $(error CMD_GUI is incorrect, optional values are y or n)
endif

sim_init:
	cd models && \
	ncverilog $(CMD_GUI_TEMP) +access+r +define+clk_133+x16 W989DxDB.nc.vp \
		../rtl/ctrl/modules/sdram_init.v \
		../sim/sdram_tb_init.v
sim_aref:
	cd models && \
	ncverilog $(CMD_GUI_TEMP) +access+r +define+clk_133+x16 W989DxDB.nc.vp \
		../rtl/ctrl/modules/sdram_aref.v \
		../sim/sdram_tb_aref.v
sim_test:
	cd models && \
	ncverilog $(CMD_GUI_TEMP) +access+r +define+clk_133+x16 W989DxDB.nc.vp \
		../sim/sdram_test.v
clean:
	find -name "*.log" -o -name "*.history" -o -name "*.key" | xargs rm -f
	find -name ".simvision" | xargs rm -rf
	find -name "INCA_libs" | xargs rm -rf
	find -name "waves.shm" | xargs rm -rf
