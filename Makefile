PWD = $(shell pwd)
BUILDDIR = build
SRCDIR = src
VLOGDIR = $(BUILDDIR)/generated
LIST_VLOG = script/listVlogFiles.tcl

TOP ?= mkSdramController
FILE = $(SRCDIR)/SdramController.bsv


TRANSFLAGS = -aggressive-conditions # -lift -split-if
RECOMPILEFLAGS = -u -show-compiles
SCHEDFLAGS = -show-schedule -sched-dot # -show-rule-rel dMemInit_request_put doExecute
#	-show-elab-progress
DEBUGFLAGS = -check-assert \
	-continue-after-errors \
	-keep-fires \
	-keep-inlined-boundaries \
	-show-method-bvi \
	-show-method-conf \
	-show-module-use \
	-show-range-conflict \
	-show-stats \
	-warn-action-shadowing \
	-warn-method-urgency \
	-promote-warnings ALL
VERILOGFLAGS = -verilog -remove-dollar -remove-unused-modules # -use-dpi -verilog-filter cmd
BLUESIMFLAGS = -parallel-sim-link 16 # -systemc
OUTDIR = -bdir $(BUILDDIR) -info-dir $(BUILDDIR) -simdir $(BUILDDIR) -vdir $(BUILDDIR)
WORKDIR = -fdir $(abspath .)
LIBDIR = $(abspath ./lib/BlueAXI/src):$(abspath ./lib/BlueLib/src)
# LIBDIR = %/Libraries/AMBA_TLM3/Axi4:%/Libraries/AMBA_TLM3/TLM3:%/Libraries/AMBA_TLM3/Axi:%/Libraries/Bus
BSVSRCDIR = -p +:$(abspath $(SRCDIR)):$(LIBDIR)
DIRFLAGS = $(BSVSRCDIR) $(OUTDIR) $(WORKDIR)
MISCFLAGS = -show-timestamps -show-version # -steps 1000000000000000 -D macro
RUNTIMEFLAGS = +RTS -K256M -RTS
SIMEXE = $(BUILDDIR)/out

build:
	@mkdir -p $(BUILDDIR)
	@bsc -elab $(VERILOGFLAGS) $(DIRFLAGS) $(MISCFLAGS) $(RECOMPILEFLAGS) $(RUNTIMEFLAGS) $(TRANSFLAGS) -g $(TOP) $(FILE)
	@mkdir -p $(VLOGDIR)
	@bluetcl $(LIST_VLOG) $(BSVSRCDIR) -bdir $(BUILDDIR) -vdir $(BUILDDIR) $(TOP) $(TOP) | grep -i '\.v' | xargs -I {} cp {} $(VLOGDIR)

clean:
	@rm -rf $(BUILDDIR)

.PHONY: build clean
.DEFAULT_GOAL := build
