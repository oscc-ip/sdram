SIM_TOOL    ?= iverilog
RUN_TOOL    ?= vvp
WAVE_FORMAT ?=

SIM_APP  ?= {{$$IP_NAME$$}}
SIM_TOP   := $(SIM_APP)_tb
TEST_ARGS ?= default_args

ifeq ($(TEST_ARGS), dump_fst_wave)
WAVE_FORMAT := -fst
endif
ifeq ($(TEST_ARGS), dump_vcd_wave)
WAVE_FORMAT := -vcd
endif
# WARN_OPTIONS := -Wanachronisms -Wimplicit -Wportbind -Wselect-range -Winfloop
# WARN_OPTIONS += -Wsensitivity-entire-vector -Wsensitivity-entire-array
WARN_OPTIONS := -Wall -Winfloop -Wno-timescale
SIM_OPTIONS  := -g2012 -s $(SIM_TOP) $(WARN_OPTIONS)
INC_LIST     :=
FILE_LIST    :=
SIMV_PROG    := simv

INC_LIST += -I ../rtl
INC_LIST += -I ../tb

comp:
	@mkdir -p build
	cd build && ($(SIM_TOOL) $(SIM_OPTIONS) $(FILE_LIST) $(INC_LIST) ../rtl/$(SIM_APP).sv ../tb/$(SIM_TOP).sv -o $(SIMV_PROG) || exit -1) 2>&1 | tee compile.log

run: comp
	cd build && $(RUN_TOOL) -l run.log -n $(SIMV_PROG) +$(TEST_ARGS) $(WAVE_FORMAT)

clean:
	rm -rf build

.PHONY: comp run
