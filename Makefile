PWD = $(shell pwd)
BUILD_DIR = build
SRC_DIR = src
VLOG_DIR = $(BUILD_DIR)/generated
LIST_VLOG = script/listVlogFiles.tcl

TOP ?= mkSdramController
FILE = $(SRC_DIR)/SdramController.bsv

ifndef CLK_FREQ_MHZ
    export CLK_FREQ_MHZ := 200
endif

TRANSFLAGS = -aggressive-conditions # -lift -split-if
RECOMPILE_FLAG = -u -show-compiles
SCHED_FLAG = -show-schedule -sched-dot # -show-rule-rel dMemInit_request_put doExecute
#	-show-elab-progress
DEBUG_FLAG = -check-assert \
	-continue-after-errors \
	-keep-fires \
	-keep-inlined-boundaries \
	-show-method-bvi \
	-show-method-conf \
	-show-module-use \
	-show-range-conflict \
	-show-stats \
	-warn-action-shadowing \
	-warn-method-urgency
VERILOG_FLAG = -verilog -remove-dollar -remove-unused-modules # -use-dpi -verilog-filter cmd
BLUESIM_FLAG = -parallel-sim-link 16 # -systemc
OUT_DIR = -bdir $(BUILD_DIR) -info-dir $(BUILD_DIR) -simdir $(BUILD_DIR) -vdir $(BUILD_DIR)
WORK_DIR = -fdir $(abspath .)
LIB_DIR = $(abspath ./lib/BlueAXI/src):$(abspath ./lib/BlueLib/src)
# LIB_DIR = %/Libraries/AMBA_TLM3/Axi4:%/Libraries/AMBA_TLM3/TLM3:%/Libraries/AMBA_TLM3/Axi:%/Libraries/Bus
BSVSRC_DIR = -p +:$(abspath $(SRC_DIR)):$(LIB_DIR)
DIR_FLAG = $(BSVSRC_DIR) $(OUT_DIR) $(WORK_DIR)
MISCFLAGS = -show-timestamps -show-version \
	-promote-warnings ALL \
	-suppress-warnings ALL \
	# -steps 1000000000000000 -D macro
RUNTIME_FLAG = +RTS -K256M -RTS
SIM_EXE = $(BUILD_DIR)/out

# STA
SDC_FILE ?= $(PWD)/script/top.sdc
RTL_FILES ?= $(shell find $(VLOG_DIR) -name "*.v")
REPORT_DIR = $(BUILD_DIR)/report
SCRIPT_DIR = $(PWD)/script
NETLIST_SYN_V   = $(BUILD_DIR)/$(TOP).netlist.syn.v
NETLIST_FIXED_V = $(BUILD_DIR)/$(TOP).netlist.fixed.v

build:
	@mkdir -p $(BUILD_DIR)
	@bsc -elab $(VERILOG_FLAG) $(DIR_FLAG) $(MISCFLAGS) $(RECOMPILE_FLAG) $(RUNTIME_FLAG) $(TRANSFLAGS) -g $(TOP) $(FILE)
	@mkdir -p $(VLOG_DIR)
	@bluetcl $(LIST_VLOG) $(BSVSRC_DIR) -bdir $(BUILD_DIR) -vdir $(BUILD_DIR) $(TOP) $(TOP) | grep -i '\.v' | xargs -I {} cp {} $(VLOG_DIR)

test:
	@mkdir -p $(BUILD_DIR)
	@bsc -elab -sim $(BLUESIM_FLAG) $(DEBUG_FLAG) $(DIR_FLAG) $(MISCFLAGS) $(RECOMPILE_FLAG) $(RUNTIME_FLAG) -g mkTb $(FILE)
	@bsc -sim $(BLUESIM_FLAG) $(DIR_FLAG) $(RECOMPILE_FLAG) -e mkTb -o $(SIM_EXE)
	$(SIM_EXE)

sta: build
	@echo "Using $(CLK_FREQ_MHZ)MHz for sta."
	mkdir -p $(REPORT_DIR)
	echo tcl $(SCRIPT_DIR)/yosys.tcl $(TOP) \"$(RTL_FILES)\" $(NETLIST_SYN_V) | yosys -l $(REPORT_DIR)/yosys.log -s -
	iEDA -script $(SCRIPT_DIR)/fix-fanout.tcl $(SDC_FILE) $(NETLIST_SYN_V) $(TOP) $(NETLIST_FIXED_V) 2>&1 | tee $(REPORT_DIR)/fix-fanout.log
	iEDA -script $(SCRIPT_DIR)/sta.tcl $(SDC_FILE) $(NETLIST_FIXED_V) $(TOP) $(REPORT_DIR) 2>&1 | tee $(REPORT_DIR)/sta.log

clean:
	@rm -rf $(BUILD_DIR)

.PHONY: build test clean sta
.DEFAULT_GOAL := build
