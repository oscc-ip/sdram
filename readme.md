# SDRAM

## Dev Guide

1. Install Nix
2. Enter development environment:

    ```bash
    nix develop .#sdram.<target>
    ```

3. Setup Mill BSP

    ```bash
    mill mill.bsp.BSP/install
    ```

4. Open your favorite IDE

## Elaborate Verilog

Use this line to generate a json config at `PWD`, you can config the parameter on the command-line.

```bash
# rtl config
nix run .#sdram.sdram-compiled.elaborator -- config --idWidth 4 --dataWidth 32 --addrWidth 32 --csWidth 4

# testbench config
nix run .#sdram.tb-compiled.elaborator -- config --idWidth 4 --dataWidth 32 --addrWidth 32 --csWidth 4 --useAsyncReset false --initFunctionName cosim_init --dumpFunctionName dump_wave --clockFlipTick 1 --resetFlipTick 100 --timeout 10000
```

Use this line to generate the Verilog at `result`, based on the config in `configs` directory.

```bash
nix build .#sdram.rtl
```

or elaborate design with testbench:

```bash
nix build .#sdram.tb-rtl
```

Generated Verilog will be placed at `result` by default, which can be specified with `-O`

## Run VCS Simulation

```bash
nix run .#sdram.vcs-trace --impure -- +dump-range=0,10000 +wave-path=trace +fsdb+sva_success
```

## Update dependency

### Build from source dependencies

```bash
pushd nix/pkgs/dependencies && nix run nixpkgs#nvfetcher && popd
```

### Other dependencies

```bash
nix flake update
```
