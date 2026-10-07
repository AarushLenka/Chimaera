#!/usr/bin/env bash
set -euo pipefail

candidate_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$candidate_root/../.." && pwd)"
cd "$repo_root"

echo "== host compiler tests =="
python3 -m unittest discover -s phase5_tests -v

echo "== Phase 6 demos against isolated candidate =="
python3 scripts/phase6_demos.py --source-root "$candidate_root"

echo "== candidate standalone RTL tests =="
iverilog -g2012 -s descriptor_two_read_sel_tb \
  -o /tmp/chimaera-two-read-selector.vvp \
  "$candidate_root/src/chimaera_program_loader.v" \
  "$candidate_root/test/descriptor_two_read_sel_tb.v"
vvp /tmp/chimaera-two-read-selector.vvp

iverilog -g2012 -s program_loader_tb \
  -o /tmp/chimaera-two-read-loader.vvp \
  "$candidate_root/src/chimaera_program_loader.v" \
  "$candidate_root/test/program_loader_tb.v"
vvp /tmp/chimaera-two-read-loader.vvp

iverilog -g2012 -s fault_loader_tb \
  -o /tmp/chimaera-two-read-fault.vvp \
  "$candidate_root/src/chimaera_program_loader.v" \
  "$candidate_root/test/fault_loader_tb.v"
vvp /tmp/chimaera-two-read-fault.vvp

iverilog -g2012 -s host_interface_tb \
  -o /tmp/chimaera-two-read-host.vvp \
  "$candidate_root/src/chimaera_config_spi.v" \
  "$candidate_root/src/chimaera_program_loader.v" \
  "$candidate_root/src/chimaera_host_interface.v" \
  "$candidate_root/test/host_interface_tb.v"
vvp /tmp/chimaera-two-read-host.vvp

iverilog -g2012 -s program_runtime_tb \
  -o /tmp/chimaera-two-read-runtime.vvp \
  "$candidate_root/src/chimaera_reaction_cell.v" \
  "$candidate_root/src/chimaera_generic_execution_engine.v" \
  "$candidate_root/src/chimaera_contract_monitor.v" \
  "$candidate_root/src/chimaera_program_runtime.v" \
  "$candidate_root/src/chimaera_program_loader.v" \
  "$candidate_root/test/program_runtime_tb.v"
vvp /tmp/chimaera-two-read-runtime.vvp

echo "== production/candidate runtime equivalence miter =="
iverilog -g2012 \
  -DCHIMAERA_RUNTIME_MODULE=chimaera_program_runtime_two_read \
  -s runtime_equivalence_tb \
  -o /tmp/chimaera-two-read-equivalence.vvp \
  "$repo_root/src/chimaera_reaction_cell.v" \
  "$repo_root/src/chimaera_generic_execution_engine.v" \
  "$repo_root/src/chimaera_contract_monitor.v" \
  "$repo_root/src/chimaera_program_runtime.v" \
  "$candidate_root/src/chimaera_program_loader.v" \
  "$candidate_root/src/chimaera_program_runtime.v" \
  "$candidate_root/test/runtime_equivalence_tb.sv"
vvp /tmp/chimaera-two-read-equivalence.vvp

echo "== candidate Phase 4 smoke =="
iverilog -g2012 -s smoke_phase4 -o /tmp/chimaera-two-read-smoke.vvp \
  "$candidate_root/src/"*.v "$repo_root/test/smoke_phase4.v"
vvp /tmp/chimaera-two-read-smoke.vvp

echo "== candidate Verilator lint =="
verilator --lint-only -Wall --top-module tt_um_chimaera "$candidate_root/src/"*.v

echo "== candidate generic synthesis and topology/SAT gate =="
netlist="$(mktemp /tmp/chimaera-two-read-netlist.XXXXXX.json)"
trap 'rm -f "$netlist"' EXIT
yosys -Q -T -p \
  "read_verilog -sv $candidate_root/src/*.v; hierarchy -top tt_um_chimaera; proc; opt; memory_map; opt; techmap; opt; stat; flatten; opt_clean; check -assert; write_json $netlist" \
  >/tmp/chimaera-two-read-yosys.log 2>&1
grep -m1 -A12 '^=== design hierarchy ===' /tmp/chimaera-two-read-yosys.log
python3 "$candidate_root/check_two_read_topology.py" "$netlist" "$candidate_root"

echo "== matched full-top Yosys+ABC screen =="
python3 "$candidate_root/measure_area.py"

echo "Candidate local verification completed. No production RTL or workflow files were changed by this runner."
