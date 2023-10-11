.PHONY: sim clean

GUI ?=
MODULES = init aref write read arbit ctrl model
MODULE ?=

ifeq ($(GUI), y)
    GUI_TEMP = -gui
else ifeq ($(GUI),)
    GUI_TEMP =
else ifeq ($(GUI), n)
    GUI_TEMP =
else
    $(error $$GUI is incorrect, optional values are [y] or [n])
endif

ifeq ($(filter $(MODULES), $(MODULE)), )
    $(error $$MODULE is incorrect, optional values in [$(MODULES)])
else
    MODULE_RTL = ../rtl/ctrl/modules/sdram_$(MODULE).v
    MODULE_SIM = ../sim/ctrl/modules/tb_sdram_$(MODULE).v
    ifeq ($(MODULE), ctrl)
        MODULE_RTL = ../rtl/ctrl/sdram_ctrl.v
        MODULE_SIM = ../sim/ctrl/tb_sdram_ctrl.v
    else ifeq ($(MODULE), model)
        MODULE_RTL =
        MODULE_SIM = ../sim/tb_sdram_model.v
    endif
    $(info $(MODULE_RTL))
    $(info $(MODULE_SIM))
endif

sim:
	cd models && \
	ncverilog $(GUI_TEMP) +access+r +define+clk_133+x16 W989DxDB.nc.vp \
		$(MODULE_RTL) \
		$(MODULE_SIM)
clean:
	find -name "*.log" -o -name "*.history" -o -name "*.key" | xargs rm -f
	find -name ".simvision" | xargs rm -rf
	find -name "INCA_libs" | xargs rm -rf
	find -name "waves.shm" | xargs rm -rf
