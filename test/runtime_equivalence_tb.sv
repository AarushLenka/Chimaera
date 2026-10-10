`default_nettype none
`timescale 1ns / 1ps

// The stimulus is class-based so directed edge phases and the long saturated
// run share one deterministic source without hiding coverage in a simulator
// seed. The DUT comparison remains a structural, cycle-by-cycle miter below.
class runtime_scenario;
  integer lfsr;

  function new(input integer seed);
    lfsr = seed & 16'hffff;
    if (lfsr == 0)
      lfsr = 16'h1;
  endfunction

  function [7:0] sample(input integer cycle);
    integer next_lfsr;
    begin
      case (cycle)
        0, 1, 2, 3, 4, 5: sample = 8'h00;
        6, 7:             sample = 8'h01;
        8:                sample = 8'h00;
        9, 10:            sample = 8'h01;
        11:               sample = 8'h00;
        12, 13:           sample = 8'h03;
        14:               sample = 8'h02;
        15:               sample = 8'h00;
        default: begin
          next_lfsr = ((lfsr << 1) ^
                       ((lfsr & 16'h8000) ? 16'h1021 : 16'h0000)) & 16'hffff;
          lfsr = next_lfsr;
          // Bias the saturated run toward event activity while retaining all
          // eight input bits for level/fall and sampled-shift behavior.
          sample = (lfsr[7:0] ^ {8{cycle[2]}}) |
                   ((cycle % 5 == 0) ? 8'h01 : 8'h00);
        end
      endcase
    end
  endfunction
endclass

module runtime_equivalence_tb;
  reg clk = 1'b0;
  reg rst_n = 1'b0;
  reg execution_halted = 1'b1;
  reg [1:0] context_enable = 2'b11;
  reg [4:0] context_entry_0 = 5'd0;
  reg [4:0] context_entry_1 = 5'd1;
  reg [7:0] sync_inputs = 8'h00;
  reg [7:0] rise_edges = 8'h00;
  reg [7:0] fall_edges = 8'h00;
  reg [15:0] fault_seed = 16'hACE1;
  reg [127:0] mutation_config_0 = 128'h0;
  reg [127:0] mutation_config_1 = 128'h0;
  reg [127:0] contract_config_0 = 128'h0;
  reg [127:0] contract_config_1 = 128'h0;

  reg [127:0] descriptor_memory [0:31];
  wire [4095:0] descriptor_words;
  genvar row;
  generate
    for (row = 0; row < 32; row = row + 1) begin : pack_descriptors
      assign descriptor_words[row*128 +: 128] = descriptor_memory[row];
    end
  endgenerate

  wire [39:0] production_candidates;
  wire [6:0] production_decision;
  wire [127:0] production_data;
  wire [255:0] candidate_data;
  wire [5:0] candidate_decision;
  wire [39:0] candidate_candidates;
  wire [31:0] candidate_select_row_0;
  wire [31:0] candidate_select_row_1;

  // Production reference: one shared selector/read bus.
  chimaera_descriptor_read_slice #(
      .READ_WIDTH(128), .USE_SHARED_SELECT(0)
  ) production_reader (
      .candidates(production_candidates),
      .decision(production_decision),
      .shared_select_row(32'b0),
      .words(descriptor_words),
      .data(production_data)
  );

  // Candidate integration: independent context selectors and buses. This is
  // functionally the loader's two-bank topology, represented at full width so
  // the miter checks every descriptor field consumed by the runtime.
  chimaera_context_selector candidate_selector_0 (
      .candidates(candidate_candidates[19:0]),
      .pending(candidate_decision[4]),
      .fire_timeout(candidate_decision[2]),
      .branch_condition(candidate_decision[0]),
      .select_row(candidate_select_row_0)
  );
  chimaera_context_selector candidate_selector_1 (
      .candidates(candidate_candidates[39:20]),
      .pending(candidate_decision[5]),
      .fire_timeout(candidate_decision[3]),
      .branch_condition(candidate_decision[1]),
      .select_row(candidate_select_row_1)
  );
  chimaera_descriptor_read_slice #(
      .READ_WIDTH(128), .USE_SHARED_SELECT(1)
  ) candidate_reader_0 (
      .candidates(40'b0), .decision(7'b0),
      .shared_select_row(candidate_select_row_0),
      .words(descriptor_words), .data(candidate_data[127:0])
  );
  chimaera_descriptor_read_slice #(
      .READ_WIDTH(128), .USE_SHARED_SELECT(1)
  ) candidate_reader_1 (
      .candidates(40'b0), .decision(7'b0),
      .shared_select_row(candidate_select_row_1),
      .words(descriptor_words), .data(candidate_data[255:128])
  );

  wire [7:0] production_drive_value_0;
  wire [7:0] production_drive_enable_0;
  wire [7:0] production_drive_value_1;
  wire [7:0] production_drive_enable_1;
  wire production_fire_0;
  wire production_fire_1;
  wire production_contract_trigger;
  wire [7:0] production_contract_count;
  wire [3:0] production_contract_id;
  wire [31:0] production_contract_timestamp;
  wire production_contract_release;
  wire production_contract_frozen;
  wire [31:0] production_contract_latest;

  wire [7:0] candidate_drive_value_0;
  wire [7:0] candidate_drive_enable_0;
  wire [7:0] candidate_drive_value_1;
  wire [7:0] candidate_drive_enable_1;
  wire candidate_fire_0;
  wire candidate_fire_1;
  wire candidate_contract_trigger;
  wire [7:0] candidate_contract_count;
  wire [3:0] candidate_contract_id;
  wire [31:0] candidate_contract_timestamp;
  wire candidate_contract_release;
  wire candidate_contract_frozen;
  wire [31:0] candidate_contract_latest;

  chimaera_program_runtime production_runtime (
      .clk(clk), .rst_n(rst_n), .execution_halted(execution_halted),
      .context_enable(context_enable), .context_entry_0(context_entry_0),
      .context_entry_1(context_entry_1),
      .descriptor_address(),
      .descriptor_candidates(production_candidates),
      .descriptor_decision(production_decision),
      .descriptor_data(production_data),
      .sync_inputs(sync_inputs), .rise_edges(rise_edges), .fall_edges(fall_edges),
      .fault_seed(fault_seed), .mutation_config_0(mutation_config_0),
      .mutation_config_1(mutation_config_1), .contract_config_0(contract_config_0),
      .contract_config_1(contract_config_1),
      .drive_value_0(production_drive_value_0),
      .drive_enable_0(production_drive_enable_0),
      .drive_value_1(production_drive_value_1),
      .drive_enable_1(production_drive_enable_1),
      .fire_0(production_fire_0), .fire_1(production_fire_1),
      .contract_trigger(production_contract_trigger),
      .contract_violation_count(production_contract_count),
      .contract_violation_id(production_contract_id),
      .contract_violation_timestamp(production_contract_timestamp),
      .contract_release_pulse(production_contract_release),
      .contract_trace_frozen(production_contract_frozen),
      .contract_trace_latest(production_contract_latest)
  );

  // The candidate runtime is compiled under a private name by the runner;
  // its default source-tree build remains named chimaera_program_runtime.
  chimaera_program_runtime_two_read candidate_runtime (
      .clk(clk), .rst_n(rst_n), .execution_halted(execution_halted),
      .context_enable(context_enable), .context_entry_0(context_entry_0),
      .context_entry_1(context_entry_1),
      .descriptor_candidates(candidate_candidates),
      .descriptor_decision(candidate_decision),
      .descriptor_data(candidate_data),
      .sync_inputs_0(sync_inputs), .rise_edges_0(rise_edges), .fall_edges_0(fall_edges),
      .sync_inputs_1(sync_inputs), .rise_edges_1(rise_edges), .fall_edges_1(fall_edges),
      .contract_sync_inputs(sync_inputs), .contract_rise_edges(rise_edges),
      .contract_fall_edges(fall_edges),
      .fault_seed(fault_seed), .mutation_config_0(mutation_config_0),
      .mutation_config_1(mutation_config_1), .contract_config_0(contract_config_0),
      .contract_config_1(contract_config_1),
      .drive_value_0(candidate_drive_value_0),
      .drive_enable_0(candidate_drive_enable_0),
      .drive_value_1(candidate_drive_value_1),
      .drive_enable_1(candidate_drive_enable_1),
      .fire_0(candidate_fire_0), .fire_1(candidate_fire_1),
      .contract_trigger(candidate_contract_trigger),
      .contract_violation_count(candidate_contract_count),
      .contract_violation_id(candidate_contract_id),
      .contract_violation_timestamp(candidate_contract_timestamp),
      .contract_release_pulse(candidate_contract_release),
      .contract_trace_frozen(candidate_contract_frozen),
      .contract_trace_latest(candidate_contract_latest)
  );

  `define CHECK_EQ(lhs, rhs, label) \
    if ((lhs) !== (rhs)) begin \
      $display("FAIL: %s production=%h candidate=%h at t=%0t", label, lhs, rhs, $time); \
      $fatal(1); \
    end

  task compare_preedge;
    begin
      `CHECK_EQ(production_candidates, candidate_candidates, "candidate addresses")
      `CHECK_EQ(production_decision[5:0], candidate_decision, "local decisions")
      `CHECK_EQ(production_decision[6],
                (!production_runtime.pending_0 &&
                 (production_runtime.pending_1 ||
                  (!production_runtime.fire_0 && production_runtime.fire_1))),
                "shared grant")
      if (production_decision[6]) begin
        `CHECK_EQ(production_data, candidate_data[255:128], "selected context-1 read")
      end else begin
        `CHECK_EQ(production_data, candidate_data[127:0], "selected context-0 read")
      end
      if (production_runtime.load_0) begin
        `CHECK_EQ(production_data, descriptor_memory[production_runtime.request_state_0],
                  "production context-0 consumed read")
        `CHECK_EQ(candidate_data[127:0], descriptor_memory[candidate_runtime.request_state_0],
                  "candidate context-0 consumed read")
      end
      if (production_runtime.load_1) begin
        `CHECK_EQ(production_data, descriptor_memory[production_runtime.request_state_1],
                  "production context-1 consumed read")
        `CHECK_EQ(candidate_data[255:128], descriptor_memory[candidate_runtime.request_state_1],
                  "candidate context-1 consumed read")
      end
      `CHECK_EQ(production_runtime.load_0, candidate_runtime.load_0, "load_0")
      `CHECK_EQ(production_runtime.load_1, candidate_runtime.load_1, "load_1")
    end
  endtask

  task compare_postedge;
    begin
      `CHECK_EQ(production_drive_value_0, candidate_drive_value_0, "drive value 0")
      `CHECK_EQ(production_drive_enable_0, candidate_drive_enable_0, "drive enable 0")
      `CHECK_EQ(production_drive_value_1, candidate_drive_value_1, "drive value 1")
      `CHECK_EQ(production_drive_enable_1, candidate_drive_enable_1, "drive enable 1")
      `CHECK_EQ(production_fire_0, candidate_fire_0, "fire 0")
      `CHECK_EQ(production_fire_1, candidate_fire_1, "fire 1")
      `CHECK_EQ(production_contract_trigger, candidate_contract_trigger, "contract trigger")
      `CHECK_EQ(production_contract_count, candidate_contract_count, "contract count")
      `CHECK_EQ(production_contract_id, candidate_contract_id, "contract id")
      `CHECK_EQ(production_contract_timestamp, candidate_contract_timestamp, "contract timestamp")
      `CHECK_EQ(production_contract_release, candidate_contract_release, "contract release")
      `CHECK_EQ(production_contract_frozen, candidate_contract_frozen, "contract frozen")
      `CHECK_EQ(production_contract_latest, candidate_contract_latest, "contract trace")
      `CHECK_EQ(production_runtime.pending_0, candidate_runtime.pending_0, "pending 0")
      `CHECK_EQ(production_runtime.pending_1, candidate_runtime.pending_1, "pending 1")
      `CHECK_EQ(production_runtime.pending_state_0, candidate_runtime.pending_state_0, "pending state 0")
      `CHECK_EQ(production_runtime.pending_state_1, candidate_runtime.pending_state_1, "pending state 1")
      `CHECK_EQ(production_runtime.active_control_0, candidate_runtime.active_control_0, "active control 0")
      `CHECK_EQ(production_runtime.active_control_1, candidate_runtime.active_control_1, "active control 1")
      `CHECK_EQ(production_runtime.was_running, candidate_runtime.was_running, "running state")
      `CHECK_EQ(production_runtime.fault_lfsr, candidate_runtime.fault_lfsr, "fault lfsr")
      `CHECK_EQ(production_runtime.reaction_cell_0.active, candidate_runtime.reaction_cell_0.active, "cell 0 active")
      `CHECK_EQ(production_runtime.reaction_cell_1.active, candidate_runtime.reaction_cell_1.active, "cell 1 active")
      `CHECK_EQ(production_runtime.reaction_cell_0.state_id, candidate_runtime.reaction_cell_0.state_id, "cell 0 state")
      `CHECK_EQ(production_runtime.reaction_cell_1.state_id, candidate_runtime.reaction_cell_1.state_id, "cell 1 state")
      `CHECK_EQ(production_runtime.reaction_cell_0.timer, candidate_runtime.reaction_cell_0.timer, "cell 0 timer")
      `CHECK_EQ(production_runtime.reaction_cell_1.timer, candidate_runtime.reaction_cell_1.timer, "cell 1 timer")
      `CHECK_EQ(production_runtime.reaction_cell_0.action_value, candidate_runtime.reaction_cell_0.action_value, "cell 0 action")
      `CHECK_EQ(production_runtime.reaction_cell_1.action_value, candidate_runtime.reaction_cell_1.action_value, "cell 1 action")
      `CHECK_EQ(production_runtime.reaction_cell_0.drive_value, candidate_runtime.reaction_cell_0.drive_value, "cell 0 stored value")
      `CHECK_EQ(production_runtime.reaction_cell_1.drive_value, candidate_runtime.reaction_cell_1.drive_value, "cell 1 stored value")
      `CHECK_EQ(production_runtime.reaction_cell_0.drive_enable, candidate_runtime.reaction_cell_0.drive_enable, "cell 0 stored enable")
      `CHECK_EQ(production_runtime.reaction_cell_1.drive_enable, candidate_runtime.reaction_cell_1.drive_enable, "cell 1 stored enable")
      `CHECK_EQ(production_runtime.execution_engine.shift_0, candidate_runtime.execution_engine.shift_0, "shift 0")
      `CHECK_EQ(production_runtime.execution_engine.shift_1, candidate_runtime.execution_engine.shift_1, "shift 1")
      `CHECK_EQ(production_runtime.execution_engine.count_0, candidate_runtime.execution_engine.count_0, "count 0")
      `CHECK_EQ(production_runtime.execution_engine.count_1, candidate_runtime.execution_engine.count_1, "count 1")
    end
  endtask

  task set_descriptor;
    input integer index;
    input [2:0] event_kind;
    input [7:0] event_mask;
    input [7:0] event_value;
    input [7:0] level_mask;
    input [7:0] level_value;
    input [15:0] timeout;
    input [7:0] sample_mask;
    input [7:0] action_mask;
    input [7:0] action_value;
    input [7:0] oe_mask;
    input [7:0] oe_value;
    input [4:0] branch_state;
    input [4:0] alternate_state;
    input [4:0] timeout_state;
    input [1:0] serial_mode;
    input [7:0] shift_literal;
    input use_shift_load;
    input [3:0] count_target;
    input use_count;
    begin
      descriptor_memory[index] = 128'h0;
      descriptor_memory[index][125:124] = serial_mode;
      descriptor_memory[index][123] = use_shift_load;
      descriptor_memory[index][119:112] = shift_literal;
      descriptor_memory[index][110:107] = count_target;
      descriptor_memory[index][106] = use_count;
      descriptor_memory[index][105:101] = timeout_state;
      descriptor_memory[index][100:96] = alternate_state;
      descriptor_memory[index][95:91] = branch_state;
      descriptor_memory[index][90:83] = oe_value;
      descriptor_memory[index][82:75] = oe_mask;
      descriptor_memory[index][74:67] = action_value;
      descriptor_memory[index][66:59] = action_mask;
      descriptor_memory[index][58:51] = sample_mask;
      descriptor_memory[index][50:35] = timeout;
      descriptor_memory[index][34:27] = level_value;
      descriptor_memory[index][26:19] = level_mask;
      descriptor_memory[index][18:11] = event_value;
      descriptor_memory[index][10:3] = event_mask;
      descriptor_memory[index][2:0] = event_kind;
    end
  endtask

  integer index;
  integer cycle;
  integer simultaneous_fires;
  integer deferred_reloads;
  integer timeout_fires;
  integer branch_true_fires;
  integer branch_false_fires;
  integer dynamic_fires;
  integer saturated_cycles;
  reg [7:0] previous_input;
  reg [7:0] next_input;
  runtime_scenario scenario;

  always #5 clk = ~clk;

  task record_coverage;
    begin
      if (cycle >= 16)
        saturated_cycles = saturated_cycles + 1;
      if (production_fire_0 && production_fire_1) begin
        simultaneous_fires = simultaneous_fires + 1;
        if (!production_runtime.load_1)
          deferred_reloads = deferred_reloads + 1;
      end
      if (production_runtime.fire_timeout_0 || production_runtime.fire_timeout_1)
        timeout_fires = timeout_fires + 1;
      if (production_fire_0) begin
        if (production_runtime.branch_condition_0)
          branch_true_fires = branch_true_fires + 1;
        else
          branch_false_fires = branch_false_fires + 1;
        if (production_runtime.selected_dynamic_output)
          dynamic_fires = dynamic_fires + 1;
      end
      if (production_fire_1) begin
        if (production_runtime.branch_condition_1)
          branch_true_fires = branch_true_fires + 1;
        else
          branch_false_fires = branch_false_fires + 1;
        if (production_runtime.selected_dynamic_output)
          dynamic_fires = dynamic_fires + 1;
      end
    end
  endtask

  initial begin
    for (index = 0; index < 32; index = index + 1) begin
      set_descriptor(index, 3'd1, 8'h01, 8'h00, 8'h00, 8'h00,
                     16'd1, 8'hff, (8'h01 << (index & 3)),
                     (8'h01 << (index & 3)), (8'h01 << (index & 3)),
                     (8'h01 << (index & 3)), index[4:0],
                     (index + 1) & 31, (index + 2) & 31,
                     2'd0, 8'h00, 1'b0, 4'd0, 1'b0);
    end
    // Directed topology cases: simultaneous self-looping fires, a branch
    // false path into a dynamic descriptor, and explicit timeout successors.
    set_descriptor(0, 3'd1, 8'h01, 8'h00, 8'h00, 8'h00,
                   16'd2, 8'h01, 8'h01, 8'h01, 8'h01, 8'h01,
                   5'd0, 5'd1, 5'd2, 2'd0, 8'h00, 1'b0, 4'd0, 1'b0);
    set_descriptor(1, 3'd1, 8'h01, 8'h00, 8'h00, 8'h00,
                   16'd2, 8'h01, 8'h02, 8'h02, 8'h02, 8'h02,
                   5'd1, 5'd0, 5'd3, 2'd0, 8'h00, 1'b0, 4'd0, 1'b0);
    set_descriptor(2, 3'd1, 8'h00, 8'h00, 8'h00, 8'h00,
                   16'd1, 8'hff, 8'h04, 8'h00, 8'h04, 8'h04,
                   5'd4, 5'd5, 5'd6, 2'd2, 8'h02, 1'b1, 4'd1, 1'b1);
    set_descriptor(3, 3'd2, 8'h01, 8'h00, 8'h00, 8'h00,
                   16'd2, 8'hff, 8'h08, 8'h08, 8'h08, 8'h08,
                   5'd7, 5'd4, 5'd0, 2'd0, 8'h00, 1'b0, 4'd0, 1'b0);
    set_descriptor(4, 3'd3, 8'h04, 8'h04, 8'h04, 8'h04,
                   16'd1, 8'hff, 8'h10, 8'h10, 8'h10, 8'h10,
                   5'd0, 5'd1, 5'd0, 2'd0, 8'h00, 1'b0, 4'd0, 1'b0);
    set_descriptor(5, 3'd1, 8'h00, 8'h00, 8'h00, 8'h00,
                   16'd1, 8'hff, 8'h20, 8'h00, 8'h20, 8'h00,
                   5'd0, 5'd1, 5'd0, 2'd0, 8'h00, 1'b0, 4'd0, 1'b0);
    set_descriptor(6, 3'd6, 8'h02, 8'h02, 8'h02, 8'h02,
                   16'd1, 8'hff, 8'h40, 8'h40, 8'h40, 8'h40,
                   5'd0, 5'd1, 5'd0, 2'd1, 8'h01, 1'b1, 4'd0, 1'b0);
    set_descriptor(7, 3'd7, 8'h04, 8'h04, 8'h04, 8'h04,
                   16'd1, 8'hff, 8'h80, 8'h80, 8'h80, 8'h80,
                   5'd0, 5'd1, 5'd0, 2'd0, 8'h00, 1'b0, 4'd0, 1'b0);

    // Nonzero mutation records exercise the shared fault LFSR and mutation
    // fanout in both implementations without relying on a particular hit.
    mutation_config_0 = 128'h0000_0000_0101_0000_0000_0000_0000_0000;
    mutation_config_1 = 128'h0000_0000_0201_0000_0000_0000_0000_0000;
    scenario = new(16'h5a3c);
    previous_input = 8'h00;
    simultaneous_fires = 0;
    deferred_reloads = 0;
    timeout_fires = 0;
    branch_true_fires = 0;
    branch_false_fires = 0;
    dynamic_fires = 0;
    saturated_cycles = 0;

    repeat (3) @(posedge clk);
    rst_n = 1'b1;
    @(negedge clk);
    execution_halted = 1'b0;

    for (cycle = 0; cycle < 260; cycle = cycle + 1) begin
      @(negedge clk);
      if (cycle >= 140 && cycle < 144)
        execution_halted = 1'b1;
      else
        execution_halted = 1'b0;
      next_input = scenario.sample(cycle);
      sync_inputs = next_input;
      rise_edges = (~previous_input & next_input);
      fall_edges = (previous_input & ~next_input);
      previous_input = next_input;
      record_coverage();
      compare_preedge();
      @(posedge clk);
      #1;
      compare_postedge();
    end

    if (simultaneous_fires == 0 || deferred_reloads == 0 || timeout_fires == 0 ||
        branch_true_fires == 0 || branch_false_fires == 0 || dynamic_fires == 0 ||
        saturated_cycles == 0)
      $fatal(1, "equivalence coverage incomplete: simultaneous=%0d deferred=%0d timeout=%0d branch_true=%0d branch_false=%0d dynamic=%0d saturated=%0d",
             simultaneous_fires, deferred_reloads, timeout_fires,
             branch_true_fires, branch_false_fires, dynamic_fires,
             saturated_cycles);
    $display("PASS: runtime equivalence for 260 cycles; simultaneous=%0d deferred=%0d timeout=%0d branch_true=%0d branch_false=%0d dynamic=%0d saturated=%0d",
             simultaneous_fires, deferred_reloads, timeout_fires,
             branch_true_fires, branch_false_fires, dynamic_fires,
             saturated_cycles);
    $finish;
  end
endmodule

`default_nettype wire
