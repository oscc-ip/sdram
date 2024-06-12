.PHONY: enter-dev gen-config gen-code

enter-dev:
	nix develop .#oscc

gen-config:
	mill sdramcontroller.run config --idWidth 4 --dataWidth 32 --addrWidth 32 --csWidth 4

gen-code:
	mill sdramcontroller.run design --run-firtool
