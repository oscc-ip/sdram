# SDRAM

# Dev Guide
1. Install Nix
2. Enter development environment:
```bash
nix develop .#oscc
```
3. Setup Mill BSP
```bash
mill mill.bsp.BSP/install
```
4. Open your favorite IDE

# Elaborate Verilog

Use this line to generate a json config at `PWD`, you can config the parameter on the command-line.
```bash
mill sdramcontroller.run config --idWidth 4 --dataWidth 32 --addrWidth 32 --csWidth 4
```

Use this line to generate the Verilog at `PWD`, based on the config just generated.
```bash
mill sdramcontroller.run design --run-firtool
```

Generated Verilog will be placed at `PWD`

# Elaborate Testbench

Use this line to generate the Verilog at `PWD`, based on the config just generated.

```bash
mill sdramcontroller.run testbench --run-firtool
```

Generated Verilog will be placed at `PWD`

# Update dependency

## Build from source dependencies
```bash
pushd nix && nix run nixpkgs#nvfetcher && popd
```

## Other dependencies
```bash
nix flake update
```
