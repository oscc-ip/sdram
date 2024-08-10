.PHONY: enter-dev gen-config gen-code

enter-dev:
	nix develop .#oscc

gen-config:
	mill sdramcontroller.run config --idWidth 4 --dataWidth 32 --addrWidth 32 --csWidth 4

gen-code:
	mill sdramcontroller.run design --run-firtool

gen-testbench:
	mill sdramcontroller.run testbench --run-firtool

vcs:
	@vcs -y ./ +libext+.v \
		-timescale=1ns/1ps \
		-full64 +v2k -sverilog -Mupdate +define+DUMP_FSDB \
		-debug_acc+all -debug_region+cell+encrypt \
		+lint=TFIPC-L -Mdir=out/ \
		-P ${NOVAS_HOME}/share/PLI/VCS/LINUX64/novas.tab ${NOVAS_HOME}/share/PLI/VCS/LINUX64/pli.a \
		./sdramcontroller/test/target/debug/libonline_dpi.a \
		SDRAMControllerTestbenchMain.sv

test: SDRAMControllerTestbenchMain.sv simv
	@./simv

SDRAMControllerTestbenchMain.sv:
	$(MAKE) gen-testbench

simv:
	$(MAKE) vcs

clean:
	rm -rf simv ucli.key vc_hdrs.h simv.daidir/ out/
