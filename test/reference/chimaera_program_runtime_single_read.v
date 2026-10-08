// Frozen shared-read runtime from dc2287144c0042ecdfc21a243ac17d616a9dcac0.
// Simulation reference only; excluded from the production source manifest.
/*
 * Two reaction cells executing compiler-loaded 128-bit descriptors.
 *
 * One descriptor read port uses pending-first bounded arbitration. Simultaneous
 * cell fires commit both predecoded actions immediately; one cell rearms on that
 * edge and the other is guaranteed service on the following edge, ahead of new
 * requests. The compiler budgets a two-cycle inclusive worst-case rearm.
 */

`default_nettype none
`timescale 1ns / 1ps

module chimaera_program_runtime (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         execution_halted,
    input  wire [1:0]   context_enable,
    input  wire [4:0]   context_entry_0,
    input  wire [4:0]   context_entry_1,

    output wire [4:0]   descriptor_address,
    output wire [39:0]  descriptor_candidates,
    output wire [6:0]   descriptor_decision,
    input  wire [127:0] descriptor_data,

    input  wire [7:0]   sync_inputs,
    input  wire [7:0]   rise_edges,
    input  wire [7:0]   fall_edges,
    input  wire [15:0]  fault_seed,
    input  wire [127:0] mutation_config_0,
    input  wire [127:0] mutation_config_1,
    input  wire [127:0] contract_config_0,
    input  wire [127:0] contract_config_1,
    output wire [7:0]   drive_value_0,
    output wire [7:0]   drive_enable_0,
    output wire [7:0]   drive_value_1,
    output wire [7:0]   drive_enable_1,
    output wire         fire_0,
    output wire         fire_1,
    output wire         contract_trigger,
    output wire [7:0]   contract_violation_count,
    output wire [3:0]   contract_violation_id,
    output wire [31:0]  contract_violation_timestamp,
    output wire         contract_release_pulse,
    output wire         contract_trace_frozen,
    output wire [31:0]  contract_trace_latest
);

  wire running = !execution_halted;
  wire runtime_rst_n = rst_n && running;

  reg pending_0;
  reg pending_1;
  reg [4:0] pending_state_0;
  reg [4:0] pending_state_1;
  reg was_running;
  reg [15:0] fault_lfsr;
  reg [34:0] active_control_0;
  reg [34:0] active_control_1;

  wire fire_timeout_0;
  wire fire_timeout_1;
  wire [7:0] fire_sample_0;
  wire [7:0] fire_sample_1;
  wire [4:0] current_state_0;
  wire [4:0] current_state_1;
  wire [7:0] cell_drive_value_0;
  wire [7:0] cell_drive_enable_0;
  wire [7:0] cell_drive_value_1;
  wire [7:0] cell_drive_enable_1;
  wire [4:0] next_state_0;
  wire [4:0] next_state_1;
  wire branch_condition_0;
  wire branch_condition_1;
  wire [7:0] current_shift_0;
  wire [7:0] current_shift_1;
  wire [7:0] post_shift_0;
  wire [7:0] post_shift_1;
  wire [7:0] mutation_delay_0;
  wire [7:0] mutation_delay_1;
  wire mutation_suppress_0;
  wire mutation_suppress_1;
  wire [7:0] mutation_hold_mask_0;
  wire [7:0] mutation_hold_mask_1;
  wire [7:0] mutation_hold_cycles_0;
  wire [7:0] mutation_hold_cycles_1;
  wire [7:0] mutation_duplicate_mask_0;
  wire [7:0] mutation_duplicate_mask_1;
  wire [7:0] mutation_late_release_mask_0;
  wire [7:0] mutation_late_release_mask_1;
  wire [7:0] mutation_late_release_cycles_0;
  wire [7:0] mutation_late_release_cycles_1;

  function [15:0] next_lfsr;
    input [15:0] current;
    begin
      next_lfsr = {
          current[14:0],
          current[15] ^ current[13] ^ current[12] ^ current[10]
      };
    end
  endfunction

  wire [4:0] request_state_0 = pending_0 ? pending_state_0 : next_state_0;
  wire [4:0] request_state_1 = pending_1 ? pending_state_1 : next_state_1;
  // Pending reloads outrank new fires so a context cannot be starved by the
  // other context firing every cycle. With no pending work, cell 0 breaks ties.
  wire service_0 = running &&
      (pending_0 || (!pending_1 && fire_0));
  wire select_request_1 = !pending_0 &&
      (pending_1 || (!fire_0 && fire_1));
  wire service_1 = running && select_request_1;
  wire load_0 = service_0;
  wire load_1 = service_1;

  // The read data is consumed only on a load. Keep a candidate selected while
  // idle so running/service_0 do not add another gate to every address bit.
  assign descriptor_address = select_request_1 ? request_state_1 : request_state_0;
  // These addresses come only from registered control/pending state. The memory
  // decodes all eight before event matching and pending-first arbitration finish.
  assign descriptor_candidates = {
      pending_state_1, active_control_1[14:10],
      active_control_1[9:5], active_control_1[4:0],
      pending_state_0, active_control_0[14:10],
      active_control_0[9:5], active_control_0[4:0]
  };
  assign descriptor_decision = {
      select_request_1, pending_1, pending_0,
      fire_timeout_1, fire_timeout_0, branch_condition_1, branch_condition_0
  };

  wire [2:0] selected_serial_mode = {1'b0, descriptor_data[125:124]};
  wire selected_dynamic_output = selected_serial_mode == 3'd2;
  wire selected_dynamic_bit_0 = fire_0 ? post_shift_0[0] : current_shift_0[0];
  wire selected_dynamic_bit_1 = fire_1 ? post_shift_1[0] : current_shift_1[0];
  wire [7:0] selected_action_value_0 = selected_dynamic_output ?
      ((descriptor_data[74:67] & ~descriptor_data[66:59]) |
       (selected_dynamic_bit_0 ? descriptor_data[66:59] : 8'h00)) :
      descriptor_data[74:67];
  wire [7:0] selected_action_value_1 = selected_dynamic_output ?
      ((descriptor_data[74:67] & ~descriptor_data[66:59]) |
       (selected_dynamic_bit_1 ? descriptor_data[66:59] : 8'h00)) :
      descriptor_data[74:67];

  assign drive_value_0 = cell_drive_value_0;
  assign drive_value_1 = cell_drive_value_1;
  assign drive_enable_0 = (running && !contract_release_pulse) ? cell_drive_enable_0 : 8'h00;
  assign drive_enable_1 = (running && !contract_release_pulse) ? cell_drive_enable_1 : 8'h00;

  chimaera_contract_monitor contract_monitor (
      .clk                  (clk),
      .rst_n                (rst_n),
      .enabled              (running),
      .contract_config_0    (contract_config_0),
      .contract_config_1    (contract_config_1),
      .sync_inputs          (sync_inputs),
      .rise_edges           (rise_edges),
      .fall_edges           (fall_edges),
      .trigger              (contract_trigger),
      .violation_count      (contract_violation_count),
      .violation_id         (contract_violation_id),
      .violation_timestamp  (contract_violation_timestamp),
      .trace_frozen         (contract_trace_frozen),
      .trace_latest         (contract_trace_latest),
      .release_pulse        (contract_release_pulse)
  );

  always @(posedge clk) begin
    if (!rst_n || !running) begin
      pending_0 <= 1'b0;
      pending_1 <= 1'b0;
      pending_state_0 <= 5'd0;
      pending_state_1 <= 5'd0;
      was_running <= 1'b0;
      fault_lfsr <= (fault_seed == 16'h0000) ? 16'h0001 : fault_seed;
      active_control_0 <= 35'd0;
      active_control_1 <= 35'd0;
    end else begin
      was_running <= 1'b1;
      if (!was_running) begin
        pending_0 <= context_enable[0];
        pending_1 <= context_enable[1];
        pending_state_0 <= context_entry_0;
        pending_state_1 <= context_entry_1;
      end else begin
        if (service_0 && pending_0)
          pending_0 <= 1'b0;
        if (service_1 && pending_1)
          pending_1 <= 1'b0;
        if (fire_0 && !service_0) begin
          pending_0 <= 1'b1;
          pending_state_0 <= next_state_0;
        end
        if (fire_1 && !service_1) begin
          pending_1 <= 1'b1;
          pending_state_1 <= next_state_1;
        end
      end
      if (load_0)
        active_control_0 <= descriptor_data[125:91];
      if (load_1)
        active_control_1 <= descriptor_data[125:91];
      if (fire_0 || fire_1)
        fault_lfsr <= next_lfsr(fault_lfsr);
    end
  end

  chimaera_generic_execution_engine_reference execution_engine (
      .clk(clk),
      .rst_n(runtime_rst_n),
      .fire_0(fire_0),
      .fire_timeout_0(fire_timeout_0),
      .fire_sample_0(fire_sample_0),
      .control_0(active_control_0),
      .mutation_config_0(mutation_config_0),
      .fault_lfsr(fault_lfsr),
      .next_state_0(next_state_0),
      .branch_condition_0(branch_condition_0),
      .current_shift_0(current_shift_0),
      .post_shift_0(post_shift_0),
      .mutation_delay_0(mutation_delay_0),
      .mutation_suppress_0(mutation_suppress_0),
      .mutation_hold_mask_0(mutation_hold_mask_0),
      .mutation_hold_cycles_0(mutation_hold_cycles_0),
      .mutation_duplicate_mask_0(mutation_duplicate_mask_0),
      .mutation_late_release_mask_0(mutation_late_release_mask_0),
      .mutation_late_release_cycles_0(mutation_late_release_cycles_0),
      .fire_1(fire_1),
      .fire_timeout_1(fire_timeout_1),
      .fire_sample_1(fire_sample_1),
      .control_1(active_control_1),
      .mutation_config_1(mutation_config_1),
      .next_state_1(next_state_1),
      .branch_condition_1(branch_condition_1),
      .current_shift_1(current_shift_1),
      .post_shift_1(post_shift_1),
      .mutation_delay_1(mutation_delay_1),
      .mutation_suppress_1(mutation_suppress_1),
      .mutation_hold_mask_1(mutation_hold_mask_1),
      .mutation_hold_cycles_1(mutation_hold_cycles_1),
      .mutation_duplicate_mask_1(mutation_duplicate_mask_1),
      .mutation_late_release_mask_1(mutation_late_release_mask_1),
      .mutation_late_release_cycles_1(mutation_late_release_cycles_1)
  );

  chimaera_reaction_cell #(
      .STATE_WIDTH(5),
      .TIMER_WIDTH(16),
      .RESET_DRIVE_VALUE(8'h00),
      .RESET_DRIVE_ENABLE(8'h00)
  ) reaction_cell_0 (
      .clk(clk),
      .rst_n(runtime_rst_n),
      .sync_inputs(sync_inputs),
      .rise_edges(rise_edges),
      .fall_edges(fall_edges),
      .load(load_0),
      .load_state(request_state_0),
      .load_event_kind({1'b0, descriptor_data[2:0]}),
      .load_event_mask(descriptor_data[10:3]),
      .load_event_value(descriptor_data[18:11]),
      .load_level_mask(descriptor_data[26:19]),
      .load_level_value(descriptor_data[34:27]),
      .load_timeout(descriptor_data[50:35]),
      .load_sample_mask(descriptor_data[58:51]),
      .load_action_mask(descriptor_data[66:59]),
      .load_action_value(selected_action_value_0),
      .load_oe_mask(descriptor_data[82:75]),
      .load_oe_value(descriptor_data[90:83]),
      .fault_delay(mutation_delay_0),
      .fault_suppress(mutation_suppress_0),
      .fault_hold_mask(mutation_hold_mask_0),
      .fault_hold_cycles(mutation_hold_cycles_0),
      .fault_duplicate_mask(mutation_duplicate_mask_0),
      .fault_late_release_mask(mutation_late_release_mask_0),
      .fault_late_release_cycles(mutation_late_release_cycles_0),
      .fire(fire_0),
      .fire_from_timeout(fire_timeout_0),
      .fire_sample(fire_sample_0),
      .current_state(current_state_0),
      .drive_value(cell_drive_value_0),
      .drive_enable(cell_drive_enable_0)
  );

  chimaera_reaction_cell #(
      .STATE_WIDTH(5),
      .TIMER_WIDTH(16),
      .RESET_DRIVE_VALUE(8'h00),
      .RESET_DRIVE_ENABLE(8'h00)
  ) reaction_cell_1 (
      .clk(clk),
      .rst_n(runtime_rst_n),
      .sync_inputs(sync_inputs),
      .rise_edges(rise_edges),
      .fall_edges(fall_edges),
      .load(load_1),
      .load_state(request_state_1),
      .load_event_kind({1'b0, descriptor_data[2:0]}),
      .load_event_mask(descriptor_data[10:3]),
      .load_event_value(descriptor_data[18:11]),
      .load_level_mask(descriptor_data[26:19]),
      .load_level_value(descriptor_data[34:27]),
      .load_timeout(descriptor_data[50:35]),
      .load_sample_mask(descriptor_data[58:51]),
      .load_action_mask(descriptor_data[66:59]),
      .load_action_value(selected_action_value_1),
      .load_oe_mask(descriptor_data[82:75]),
      .load_oe_value(descriptor_data[90:83]),
      .fault_delay(mutation_delay_1),
      .fault_suppress(mutation_suppress_1),
      .fault_hold_mask(mutation_hold_mask_1),
      .fault_hold_cycles(mutation_hold_cycles_1),
      .fault_duplicate_mask(mutation_duplicate_mask_1),
      .fault_late_release_mask(mutation_late_release_mask_1),
      .fault_late_release_cycles(mutation_late_release_cycles_1),
      .fire(fire_1),
      .fire_from_timeout(fire_timeout_1),
      .fire_sample(fire_sample_1),
      .current_state(current_state_1),
      .drive_value(cell_drive_value_1),
      .drive_enable(cell_drive_enable_1)
  );

  wire _unused = &{
      current_state_0, current_state_1,
      current_shift_0[7:1], current_shift_1[7:1],
      post_shift_0[7:1], post_shift_1[7:1],
      descriptor_data[127:126], 1'b0
  };

endmodule

`default_nettype wire
