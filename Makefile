.PHONY: sim-verilog sim-launch clean

GUI               ?=
MODULE            ?=
MODULE_TYPE       := init aref write read ctrl model
MODULE_RTL_PREFIX := ../rtl/ctrl/modules/sdram_
MODULE_SIM_PREFIX := ../sim/ctrl/modules/tb_sdram_
CTRL_RTL_PREFIX   := ../rtl/ctrl/sdram_
CTRL_SIM_PREFIX   := ../sim/ctrl/tb_sdram_
BUILD_OPT         := +access+r +define+clk_133+x16

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
    ifeq ($(MODULE), init)
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
                     $(CTRL_RTL_PREFIX)ctrl.v
        MODULE_SIM = $(CTRL_SIM_PREFIX)ctrl.v
    else ifeq ($(MODULE), model)
        MODULE_RTL =
        MODULE_SIM = ../sim/tb_sdram_model.v
    endif
endif

sim-verilog:
	cd models &&                                      \
	ncverilog $(GUI_TEMP) $(BUILD_OPT) W989DxDB.nc.vp \
		$(MODULE_RTL)                                 \
		$(MODULE_SIM)
sim-launch:
	cd models &&                         \
	nclaunch $(BUILD_OPT) W989DxDB.nc.vp \
		$(MODULE_RTL)                    \
		$(MODULE_SIM)
clean:
	find ./models -not -name "*.vp" -not -name "*.v" | \
		tail -n +2 |                                   \
		xargs rm -rf
