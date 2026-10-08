# Sample testbench for a Tiny Tapeout project

This is a sample testbench for a Tiny Tapeout project. It uses [cocotb](https://docs.cocotb.org/en/stable/) to drive the DUT and check the outputs.
See below to get started or for more information, check the [website](https://tinytapeout.com/hdl/testing/).

## Setting up

1. Edit [Makefile](Makefile) and modify `PROJECT_SOURCES` to point to your Verilog files.
2. Edit [tb.v](tb.v) and instantiate the Chimaera top-level module.

## How to run

The production RTL gate is `bash scripts/local-verify.sh` from the repository
root. It includes all five demos, loader and runtime benches, strict lint,
synthesis, hybrid-read topology checks, and the descriptor-read SAT proof.
It also checks that both branch-lookahead modules depend only on registered
state and proves their predicates equivalent for arbitrary samples and all four
mutation records.
`make -C test phase5` runs the standalone benches, including the 260-cycle
runtime comparison against the frozen `dc22871` shared-read runtime and
pre-lookahead execution logic under `test/reference/`. These references are
simulation-only and are excluded from
`info.yaml` and the production Verilog source list.

To run the RTL simulation:

```sh
make -B
```

To run gatelevel simulation, first harden your project and copy `../runs/wokwi/results/final/verilog/gl/{your_module_name}.v` to `gate_level_netlist.v`.

Then run:

```sh
make -B GATES=yes
```

If you wish to save the waveform in VCD format instead of FST format, edit tb.v to use `$dumpfile("tb.vcd");` and then run:

```sh
make -B FST=
```

This will generate `tb.vcd` instead of `tb.fst`.

## How to view the waveform file

Using GTKWave

```sh
gtkwave tb.fst tb.gtkw
```

Using Surfer

```sh
surfer tb.fst
```
