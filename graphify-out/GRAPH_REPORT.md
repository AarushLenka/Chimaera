# Graph Report - .  (2026-09-22)

## Corpus Check
- Corpus is ~25,012 words - fits in a single context window. You may not need a graph.

## Summary
- 101 nodes · 140 edges · 16 communities (9 shown, 7 thin omitted)
- Extraction: 82% EXTRACTED · 18% INFERRED · 0% AMBIGUOUS · INFERRED: 25 edges (avg confidence: 0.89)
- Token cost: 0 input · 0 output

## Community Hubs (Navigation)
- Architecture & DSL Spec
- Dev Flow & Graphify Pipeline
- Project Docs & UART Slice
- Python Testbench
- RTL Source Modules
- CI Workflows & Platform
- Smoke UART Testbench
- Test Tooling & Deps
- Runtime Contracts & Replay
- Verilog Testbench
- Dev Container Setup
- Execution Engine RTL
- Input Frontend RTL
- Reaction Cell RTL
- UART Program RTL
- Graphify Steering

## God Nodes (most connected - your core abstractions)
1. `SPEC.md — Chimaera Functional Specification` - 15 edges
2. `ARCHITECTURE.md — Chimaera Hardware Architecture` - 14 edges
3. `Graphify Skill` - 11 edges
4. `DSL_SPEC.md — Chimaera Protocol Description Language` - 10 edges
5. `IMPLEMENTATION.md — Chimaera Implementation Guide` - 7 edges
6. `Reaction Cell — fixed-latency per-context state holder` - 7 edges
7. `uart_receive_and_echo_has_exact_bit_timing()` - 6 edges
8. `AGENTS.md — Operating Instructions for the Coding Agent` - 6 edges
9. `PIN_MAP.md — Tiny Tapeout Pin Assignment` - 6 edges
10. `decisions.md — Design Decision Log` - 6 edges

## Surprising Connections (you probably didn't know these)
- `SPEC.md — Chimaera Functional Specification` --conceptually_related_to--> `Tiny Tapeout — shared-die ASIC fabrication platform`  [INFERRED]
  agent-docs/SPEC.md → README.md
- `CI Workflow: gds (ASIC GDS build + precheck + GL test + viewer)` --conceptually_related_to--> `IMPLEMENTATION.md — Chimaera Implementation Guide`  [INFERRED]
  .github/workflows/gds.yaml → agent-docs/IMPLEMENTATION.md
- `CI Workflow: test (cocotb simulation)` --conceptually_related_to--> `IMPLEMENTATION.md — Chimaera Implementation Guide`  [INFERRED]
  .github/workflows/test.yaml → agent-docs/IMPLEMENTATION.md
- `Event-Driven Programmable Protocol Transducer` --semantically_similar_to--> `Chimaera Tiny Tapeout Project Config`  [INFERRED] [semantically similar]
  docs/info.md → info.yaml
- `Repository Commit and Attribution Policy` --semantically_similar_to--> `Graphify Post-Commit Hook`  [INFERRED] [semantically similar]
  flow.md → .kiro/skills/graphify/references/hooks.md

## Import Cycles
- None detected.

## Hyperedges (group relationships)
- **Static Safety Triangle: Proof-Carrying Microcode enforces Open-Drain Safety and Pin Ownership via DSL compiler checks** — concept_proof_carrying_microcode, concept_open_drain_safety, concept_pin_ownership [EXTRACTED 0.95]
- **Fast Reaction Path: Input Synchronizer → Reaction Cell → Fixed-Latency Output** — concept_input_synchronizer, concept_reaction_cell, concept_fixed_latency_guarantee [EXTRACTED 0.95]
- **DSL Compiler Pipeline: protocol/mutation/contract blocks compile to proof-carrying microcode** — concept_dsl_protocol_block, concept_dsl_mutation_block, concept_dsl_contract_block, concept_proof_carrying_microcode [EXTRACTED 0.95]
- **UART Slice Verification Cluster** — docs_info_phase2_uart_slice, docs_info_cocotb_tests, docs_info_smoke_uart_test, test_requirements_cocotb, flow_phase2_uart_start [INFERRED 0.85]
- **Graphify Graph Build Pipeline** — kiro_skills_graphify_skill_knowledge_graph_pipeline, kiro_skills_graphify_references_extraction_spec_subagent, kiro_skills_graphify_references_update_incremental, kiro_skills_graphify_skill_community_detection [EXTRACTED 0.95]
- **Chimaera Project Identity** — docs_info_chimaera_project, info_yaml_chimaera_project, flow_chimaera_dev_flow, docs_info_event_driven_transducer [INFERRED 0.85]

## Communities (16 total, 7 thin omitted)

### Community 0 - "Architecture & DSL Spec"
Cohesion: 0.23
Nodes (22): AGENTS.md — Operating Instructions for the Coding Agent, ARCHITECTURE.md — Chimaera Hardware Architecture, DSL_SPEC.md — Chimaera Protocol Description Language, IMPLEMENTATION.md — Chimaera Implementation Guide, PIN_MAP.md — Tiny Tapeout Pin Assignment, SPEC.md — Chimaera Functional Specification, Deterministic Fault Injection — LFSR-seeded reproducible faults, DSL mutation block — conditional fault-injection descriptor (+14 more)

### Community 1 - "Dev Flow & Graphify Pipeline"
Cohesion: 0.12
Nodes (18): Chimaera Development Flow Log, Repository Commit and Attribution Policy, Phase 0/1 Repository Setup, Graphify URL Ingest and Folder Watch, Graphify Neo4j/FalkorDB/SVG/GraphML Exports, Graphify Extraction Subagent Spec, Graphify GitHub Clone and Cross-Repo Merge, Graphify Post-Commit Hook (+10 more)

### Community 2 - "Project Docs & UART Slice"
Cohesion: 0.29
Nodes (11): Chimaera Project Overview, Cocotb Test Suite, Event-Driven Programmable Protocol Transducer, Phase 2 UART Reaction Cell Slice, Dependency-Free Verilog Smoke Test, UART 8-N-1 Program, Phase 2 UART Slice Development Start, Chimaera Tiny Tapeout Project Config (+3 more)

### Community 3 - "Python Testbench"
Cohesion: 0.42
Nodes (8): decode_uart_tx(), drive_uart_byte(), pin(), Receive 0xA5, expose it on uo_out, and transmit the same 8-N-1 frame., A low pulse shorter than half a bit must not become a received byte., reset_dut(), uart_false_start_is_rejected(), uart_receive_and_echo_has_exact_bit_timing()

### Community 4 - "RTL Source Modules"
Cohesion: 0.33
Nodes (5): chimaera_execution_engine, chimaera_input_frontend, chimaera_reaction_cell, chimaera_uart_program, tt_um_chimaera

### Community 5 - "CI Workflows & Platform"
Cohesion: 0.33
Nodes (6): Tiny Tapeout — shared-die ASIC fabrication platform, CI Workflow: docs (documentation build), CI Workflow: fpga (ICE40UP5K bitstream), CI Workflow: gds (ASIC GDS build + precheck + GL test + viewer), CI Workflow: test (cocotb simulation), README — Chimaera Project Overview

### Community 6 - "Smoke UART Testbench"
Cohesion: 0.33
Nodes (5): smoke_uart, send_uart_byte, wait_clocks, tt_um_chimaera, wait_clocks

### Community 7 - "Test Tooling & Deps"
Cohesion: 0.40
Nodes (5): Cocotb DUT Driver, Gate-Level Netlist Simulation, GTKWave Waveform Viewer, Tiny Tapeout Sample Testbench, cocotb 2.0.1

### Community 8 - "Runtime Contracts & Replay"
Cohesion: 0.50
Nodes (4): Capture → Compile → Replay — host-side waveform-to-microcode tooling, DSL contract block — temporal assertion descriptor, Runtime Protocol Contracts — temporal assertion checker, Trace Buffer — small contract-violation + capture buffer

## Knowledge Gaps
- **33 isolated node(s):** `copy_tt_support_tools.sh script`, `chimaera_execution_engine`, `chimaera_input_frontend`, `chimaera_reaction_cell`, `chimaera_uart_program` (+28 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **7 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `Chimaera Development Flow Log` connect `Dev Flow & Graphify Pipeline` to `Project Docs & UART Slice`?**
  _High betweenness centrality (0.058) - this node is a cross-community bridge._
- **Why does `Phase 2 UART Slice Development Start` connect `Project Docs & UART Slice` to `Dev Flow & Graphify Pipeline`?**
  _High betweenness centrality (0.056) - this node is a cross-community bridge._
- **Are the 2 inferred relationships involving `IMPLEMENTATION.md — Chimaera Implementation Guide` (e.g. with `CI Workflow: gds (ASIC GDS build + precheck + GL test + viewer)` and `CI Workflow: test (cocotb simulation)`) actually correct?**
  _`IMPLEMENTATION.md — Chimaera Implementation Guide` has 2 INFERRED edges - model-reasoned connections that need verification._
- **What connects `copy_tt_support_tools.sh script`, `chimaera_execution_engine`, `chimaera_input_frontend` to the rest of the system?**
  _33 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Dev Flow & Graphify Pipeline` be split into smaller, more focused modules?**
  _Cohesion score 0.11764705882352941 - nodes in this community are weakly interconnected._