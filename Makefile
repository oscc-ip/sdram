.PHONY: sim_init sim_aref sim_write sim_read sim_test clean

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
		../sim/tb_sdram_init.v
sim_aref:
	cd models && \
	ncverilog $(CMD_GUI_TEMP) +access+r +define+clk_133+x16 W989DxDB.nc.vp \
		../rtl/ctrl/modules/sdram_aref.v \
		../sim/tb_sdram_aref.v
sim_write:
	cd models && \
	ncverilog $(CMD_GUI_TEMP) +access+r +define+clk_133+x16 W989DxDB.nc.vp \
		../rtl/ctrl/modules/sdram_write.v \
		../sim/tb_sdram_write.v
sim_read:
	cd models && \
	ncverilog $(CMD_GUI_TEMP) +access+r +define+clk_133+x16 W989DxDB.nc.vp \
		../rtl/ctrl/modules/sdram_read.v \
		../sim/tb_sdram_read.v
sim_ctrl:
	cd models && \
	ncverilog $(CMD_GUI_TEMP) +access+r +define+clk_133+x16 W989DxDB.nc.vp \
		../rtl/ctrl/sdram_ctrl.v \
		../sim/ctrl/tb_sdram_ctrl.v
sim_model:
	cd models && \
	ncverilog $(CMD_GUI_TEMP) +access+r +define+clk_133+x16 W989DxDB.nc.vp \
		../sim/tb_sdram_model.v
clean:
	find -name "*.log" -o -name "*.history" -o -name "*.key" | xargs rm -f
	find -name ".simvision" | xargs rm -rf
	find -name "INCA_libs" | xargs rm -rf
	find -name "waves.shm" | xargs rm -rf
