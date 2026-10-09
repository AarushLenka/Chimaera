#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_dir"

echo "== host compiler tests =="
python3 -m unittest discover -s phase5_tests -v

echo "== Phase 6 demo simulations =="
python3 scripts/phase6_demos.py

echo "== standalone RTL tests =="
make -C test phase5

echo "== Phase 4 smoke simulation =="
smoke_binary="$(mktemp /tmp/chimaera-smoke.XXXXXX)"
trap 'rm -f "$smoke_binary"' EXIT
iverilog -g2012 -s smoke_phase4 -o "$smoke_binary" src/*.v test/smoke_phase4.v
vvp "$smoke_binary"

echo "== Verilator lint =="
verilator --lint-only -Wall --top-module tt_um_chimaera src/*.v

echo "== Yosys generic synthesis =="
yosys_log="$(mktemp /tmp/chimaera-yosys.XXXXXX)"
yosys_netlist="$(mktemp /tmp/chimaera-yosys-netlist.XXXXXX)"
trap 'rm -f "$smoke_binary" "$yosys_log" "$yosys_netlist"' EXIT
if ! yosys -Q -T -l "$yosys_log" -p \
  "read_verilog -sv src/*.v; hierarchy -top tt_um_chimaera; proc; opt; memory_map; opt; techmap; opt; stat; flatten; opt_clean; check -assert; write_json $yosys_netlist" \
  >/dev/null 2>&1; then
  cat "$yosys_log"
  exit 1
fi
grep -m1 -A12 '^=== design hierarchy ===' "$yosys_log"

echo "== descriptor read topology and equivalence =="
python3 scripts/check_descriptor_read.py "$yosys_netlist"

echo "== branch lookahead topology and equivalence =="
python3 scripts/check_branch_lookahead.py "$yosys_netlist"

echo "== event matcher topology and equivalence =="
python3 scripts/check_event_matcher.py "$yosys_netlist"

if [[ "${RUN_COCOTB:-0}" == "1" ]]; then
  echo "== cocotb simulation =="
  if ! command -v cocotb-config >/dev/null 2>&1; then
    echo "RUN_COCOTB=1 requires cocotb-config on PATH" >&2
    exit 2
  fi
  make -C test clean
  make -C test
  if grep -Eq '<(failure|error)([[:space:]>])' test/results.xml; then
    echo "cocotb reported failures in test/results.xml" >&2
    exit 1
  fi
else
  echo "== cocotb simulation skipped (set RUN_COCOTB=1 to require it) =="
fi

echo "Local verification completed."
