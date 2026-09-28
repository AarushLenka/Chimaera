"""Dependency-free Verilog replay for compiler-emitted runtime programs."""

from __future__ import annotations

from collections.abc import Sequence
from pathlib import Path
import subprocess
import tempfile

from .backend import PackedProgram
from .errors import CompileError


# (synchronized inputs, rising edges, falling edges,
#  context 0 value, context 0 enable, context 1 value, context 1 enable)
ReplayCycle = tuple[int, int, int, int, int, int, int]


def _check_byte(value: int, name: str) -> int:
    if not 0 <= value <= 0xFF:
        raise ValueError(f"{name} must fit in 8 bits")
    return value


def _testbench(program: PackedProgram, trace: Sequence[ReplayCycle]) -> str:
    if not trace:
        raise ValueError("RTL replay requires at least one trace cycle")
    if len(program.context_entries) not in {1, 2}:
        raise ValueError("RTL replay supports one or two packed contexts")

    trace_rows: list[str] = []
    for index, row in enumerate(trace):
        if len(row) != 7:
            raise ValueError(f"trace cycle {index} must contain seven values")
        fields = (
            "inputs",
            "rising_edges",
            "falling_edges",
            "value_0",
            "enable_0",
            "value_1",
            "enable_1",
        )
        values = [_check_byte(value, f"trace[{index}][{field}]") for field, value in zip(fields, row)]
        trace_rows.append(
            "    trace_inputs[{index}] = 8'h{inputs:02x}; "
            "trace_rise[{index}] = 8'h{rising_edges:02x}; "
            "trace_fall[{index}] = 8'h{falling_edges:02x}; "
            "expected_value_0[{index}] = 8'h{value_0:02x}; "
            "expected_enable_0[{index}] = 8'h{enable_0:02x}; "
            "expected_value_1[{index}] = 8'h{value_1:02x}; "
            "expected_enable_1[{index}] = 8'h{enable_1:02x};".format(
                index=index,
                inputs=values[0],
                rising_edges=values[1],
                falling_edges=values[2],
                value_0=values[3],
                enable_0=values[4],
                value_1=values[5],
                enable_1=values[6],
            )
        )

    descriptor_rows = [
        f"    descriptor_memory[{index}] = 128'h{descriptor:032x};"
        for index, descriptor in enumerate(program.descriptors)
    ]
    entry_0 = program.context_entries[0]
    entry_1 = program.context_entries[1] if len(program.context_entries) == 2 else 0
    context_enable = 0x3 if len(program.context_entries) == 2 else 0x1
    trace_count = len(trace)
    return f'''`default_nettype none
`timescale 1ns / 1ps

module chimaera_generated_replay_tb;
  localparam integer TRACE_COUNT = {trace_count};
  reg clk = 1'b0;
  reg rst_n = 1'b0;
  reg execution_halted = 1'b1;
  reg [1:0] context_enable = 2'b{context_enable:02b};
  reg [4:0] context_entry_0 = 5'd{entry_0};
  reg [4:0] context_entry_1 = 5'd{entry_1};
  reg [7:0] sync_inputs = 8'h00;
  reg [7:0] rise_edges = 8'h00;
  reg [7:0] fall_edges = 8'h00;
  reg [15:0] fault_seed = 16'h{program.fault_seed:04x};
  reg [127:0] mutation_config_0 = 128'h{program.mutation_config[0]:032x};
  reg [127:0] mutation_config_1 = 128'h{program.mutation_config[1]:032x};
  reg [127:0] descriptor_memory [0:31];
  wire [4:0] descriptor_address;
  wire [127:0] descriptor_data = descriptor_memory[descriptor_address];
  wire [7:0] drive_value_0;
  wire [7:0] drive_enable_0;
  wire [7:0] drive_value_1;
  wire [7:0] drive_enable_1;
  wire fire_0;
  wire fire_1;
  reg [7:0] trace_inputs [0:TRACE_COUNT-1];
  reg [7:0] trace_rise [0:TRACE_COUNT-1];
  reg [7:0] trace_fall [0:TRACE_COUNT-1];
  reg [7:0] expected_value_0 [0:TRACE_COUNT-1];
  reg [7:0] expected_enable_0 [0:TRACE_COUNT-1];
  reg [7:0] expected_value_1 [0:TRACE_COUNT-1];
  reg [7:0] expected_enable_1 [0:TRACE_COUNT-1];
  integer cycle_index;

  chimaera_program_runtime dut (
      .clk(clk),
      .rst_n(rst_n),
      .execution_halted(execution_halted),
      .context_enable(context_enable),
      .context_entry_0(context_entry_0),
      .context_entry_1(context_entry_1),
      .descriptor_address(descriptor_address),
      .descriptor_data(descriptor_data),
      .sync_inputs(sync_inputs),
      .rise_edges(rise_edges),
      .fall_edges(fall_edges),
      .fault_seed(fault_seed),
      .mutation_config_0(mutation_config_0),
      .mutation_config_1(mutation_config_1),
      .drive_value_0(drive_value_0),
      .drive_enable_0(drive_enable_0),
      .drive_value_1(drive_value_1),
      .drive_enable_1(drive_enable_1),
      .fire_0(fire_0),
      .fire_1(fire_1)
  );

  always #5 clk = ~clk;

  initial begin
{chr(10).join(descriptor_rows)}
{chr(10).join(trace_rows)}

    repeat (3) @(posedge clk);
    rst_n = 1'b1;
    repeat (2) @(posedge clk);
    execution_halted = 1'b0;
    // One edge enters the running state and one edge services the entry load.
    repeat (2) @(posedge clk);

    for (cycle_index = 0; cycle_index < TRACE_COUNT; cycle_index = cycle_index + 1) begin
      @(negedge clk);
      sync_inputs = trace_inputs[cycle_index];
      rise_edges = trace_rise[cycle_index];
      fall_edges = trace_fall[cycle_index];
      @(posedge clk);
      #1;
      if (drive_value_0 !== expected_value_0[cycle_index] ||
          drive_enable_0 !== expected_enable_0[cycle_index] ||
          drive_value_1 !== expected_value_1[cycle_index] ||
          drive_enable_1 !== expected_enable_1[cycle_index]) begin
        $display("FAIL: RTL replay mismatch at cycle %0d", cycle_index);
        $display("  expected c0=%02h/%02h c1=%02h/%02h, got c0=%02h/%02h c1=%02h/%02h",
                 expected_value_0[cycle_index], expected_enable_0[cycle_index],
                 expected_value_1[cycle_index], expected_enable_1[cycle_index],
                 drive_value_0, drive_enable_0, drive_value_1, drive_enable_1);
        $fatal(1);
      end
    end

    $display("PASS: generated runtime replay, %0d cycles", TRACE_COUNT);
    $finish;
  end
endmodule

`default_nettype wire
'''


def run_runtime_replay(
    program: PackedProgram,
    trace: Sequence[ReplayCycle],
    *,
    source_root: Path | None = None,
) -> str:
    """Compile and run a packed program against the RTL runtime.

    The replay drives ``sync_inputs`` and its edge masks directly. This compares
    the compiler/model/runtime contract at the synchronized clock boundary while
    keeping asynchronous pin synchronization outside this host-side test.
    """

    root = source_root or Path(__file__).resolve().parents[1]
    source_dir = root / "src"
    sources = [
        source_dir / "chimaera_reaction_cell.v",
        source_dir / "chimaera_generic_execution_engine.v",
        source_dir / "chimaera_program_runtime.v",
    ]
    missing = [str(path) for path in sources if not path.is_file()]
    if missing:
        raise CompileError("RTL replay source file(s) missing: " + ", ".join(missing))

    try:
        with tempfile.TemporaryDirectory(prefix="chimaera-rtl-replay-") as directory:
            temp_dir = Path(directory)
            testbench = temp_dir / "replay_tb.v"
            simulator = temp_dir / "replay.vvp"
            testbench.write_text(_testbench(program, trace), encoding="utf-8")
            compile_result = subprocess.run(
                [
                    "iverilog",
                    "-g2012",
                    "-s",
                    "chimaera_generated_replay_tb",
                    "-o",
                    str(simulator),
                    *(str(path) for path in sources),
                    str(testbench),
                ],
                cwd=root,
                capture_output=True,
                text=True,
                check=False,
            )
            if compile_result.returncode:
                raise CompileError(
                    "RTL replay compile failed:\n"
                    + compile_result.stdout
                    + compile_result.stderr
                )
            run_result = subprocess.run(
                ["vvp", str(simulator)],
                cwd=root,
                capture_output=True,
                text=True,
                check=False,
            )
            if run_result.returncode:
                raise CompileError(
                    "RTL replay failed:\n" + run_result.stdout + run_result.stderr
                )
            return run_result.stdout
    except FileNotFoundError as error:
        raise CompileError(f"RTL replay requires {error.filename!r} on PATH") from error
