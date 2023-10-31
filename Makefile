.PHONY: sim-ivlog sim-ncvlog sim-nclaunch clean

GUI               ?=
MODULE            ?=
MODULE_COMM       := axi4 clk fifo
MODULE_TYPE       := model $(MODULE_COMM) init aref write read ctrl top
MODULE_RTL_PREFIX := ../rtl/ctrl/modules/sdram_
MODULE_SIM_PREFIX := ../sim/ctrl/modules/tb_sdram_
CTRL_RTL_PREFIX   := ../rtl/ctrl/sdram_
CTRL_SIM_PREFIX   := ../sim/ctrl/tb_sdram_
COMM_RTL_PREFIX   := ../rtl/common/
COMM_SIM_PREFIX   := ../sim/common/tb_
SIM_MODEL         := W989DxDB.nc.vp
SIM_CONFIG        := ../config/config.v
BUILD_OPT         := +access+r +define+clk_133+freq_100+dumpfile+x16

ifeq ($(GUI), y)
    GUI_TEMP = -gui
else ifeq ($(GUI),)
    GUI_TEMP =
else ifeq ($(GUI), n)
    GUI_TEMP =
else
    $(error $$GUI is incorrect, optional values are [y] or [n])
endif

ifeq ($(filter $(MODULE_TYPE), $(MODULE)), )
    ifneq ($(MAKECMDGOALS), clean)
        $(error $$MODULE is incorrect, optional values in [$(MODULE_TYPE)])
    endif
else
    ifeq ($(MODULE), model)
        MODULE_RTL =
        MODULE_SIM = ../sim/tb_sdram_model.v
    else ifneq ($(filter $(MODULE_COMM), $(MODULE)), )
        SIM_MODEL  =
        MODULE_RTL = $(COMM_RTL_PREFIX)$(MODULE).v
        MODULE_SIM = $(COMM_SIM_PREFIX)$(MODULE).v
    else ifeq ($(MODULE), init)
        MODULE_RTL = $(MODULE_RTL_PREFIX)init.v
        MODULE_SIM = $(MODULE_SIM_PREFIX)init.v
    else ifeq ($(MODULE), aref)
        MODULE_RTL = $(MODULE_RTL_PREFIX)init.v  \
                     $(MODULE_RTL_PREFIX)aref.v
        MODULE_SIM = $(MODULE_SIM_PREFIX)aref.v
    else ifeq ($(MODULE), write)
        MODULE_RTL = $(MODULE_RTL_PREFIX)init.v  \
                     $(MODULE_RTL_PREFIX)write.v
        MODULE_SIM = $(MODULE_SIM_PREFIX)write.v
    else ifeq ($(MODULE), read)
        MODULE_RTL = $(MODULE_RTL_PREFIX)init.v  \
                     $(MODULE_RTL_PREFIX)write.v \
                     $(MODULE_RTL_PREFIX)read.v
        MODULE_SIM = $(MODULE_SIM_PREFIX)read.v
    else ifeq ($(MODULE), ctrl)
        MODULE_RTL = $(MODULE_RTL_PREFIX)init.v  \
                     $(MODULE_RTL_PREFIX)aref.v  \
                     $(MODULE_RTL_PREFIX)write.v \
                     $(MODULE_RTL_PREFIX)read.v  \
                     $(MODULE_RTL_PREFIX)arbit.v \
                     $(CTRL_RTL_PREFIX)ctrl.v
        MODULE_SIM = $(CTRL_SIM_PREFIX)ctrl.v
    else
        MODULE_RTL =
        MODULE_SIM =
    endif
endif

sim-ivlog:
	mkdir -p build &&                                       \
	cd build &&                                             \
	iverilog -g2005-sv -o $(MODULE) $(MODULE_RTL) $(MODULE_SIM) && \
	vvp -v $(MODULE) -lxt2 &&                               \
	gtkwave wave.vcd
sim-ncvlog:
	cd models &&                                    \
	ncverilog $(GUI_TEMP) $(BUILD_OPT) $(SIM_MODEL) \
		$(MODULE_RTL)                               \
		$(MODULE_SIM)
sim-nclaunch:
	cd models &&                                    \
	nclaunch              $(BUILD_OPT) $(SIM_MODEL) \
		$(MODULE_RTL)                               \
		$(MODULE_SIM)
clean:
	rm -rf build &&                                    \
	find ./models -not -name "*.vp" -not -name "*.v" | \
		tail -n +2 |                                   \
		xargs rm -rf
