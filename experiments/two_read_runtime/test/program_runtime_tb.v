`default_nettype none
`timescale 1ns / 1ps

module program_runtime_tb;
  reg clk = 1'b0;
  reg rst_n = 1'b0;
  reg execution_halted = 1'b1;
  reg [1:0] context_enable = 2'b01;
  reg [4:0] context_entry_0 = 5'd0;
  reg [4:0] context_entry_1 = 5'd1;
  reg [7:0] sync_inputs = 8'h00;
  reg [7:0] rise_edges = 8'h00;
  reg [7:0] fall_edges = 8'h00;
  reg [15:0] fault_seed = 16'h0001;
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

  wire [39:0] descriptor_candidates;
  wire [5:0] descriptor_decision;
  wire [255:0] descriptor_data;
  wire [31:0] select_row_0;
  wire [31:0] select_row_1;

  // This is the same two-context read topology used by the candidate loader,
  // kept explicit here so the runtime bench observes both independent buses.
  chimaera_context_selector selector_0 (
      .candidates(descriptor_candidates[19:0]),
      .pending(descriptor_decision[4]),
      .fire_timeout(descriptor_decision[2]),
      .branch_condition(descriptor_decision[0]),
      .select_row(select_row_0)
  );
  chimaera_context_selector selector_1 (
      .candidates(descriptor_candidates[39:20]),
      .pending(descriptor_decision[5]),
      .fire_timeout(descriptor_decision[3]),
      .branch_condition(descriptor_decision[1]),
      .select_row(select_row_1)
  );
  chimaera_descriptor_read_slice #(
      .READ_WIDTH(128), .USE_SHARED_SELECT(1)
  ) reader_0 (
      .candidates(40'b0), .decision(7'b0), .shared_select_row(select_row_0),
      .words(descriptor_words), .data(descriptor_data[127:0])
  );
  chimaera_descriptor_read_slice #(
      .READ_WIDTH(128), .USE_SHARED_SELECT(1)
  ) reader_1 (
      .candidates(40'b0), .decision(7'b0), .shared_select_row(select_row_1),
      .words(descriptor_words), .data(descriptor_data[255:128])
  );

  wire [7:0] drive_value_0;
  wire [7:0] drive_enable_0;
  wire [7:0] drive_value_1;
  wire [7:0] drive_enable_1;
  wire fire_0;
  wire fire_1;
  wire contract_trigger;
  wire [7:0] contract_violation_count;
  wire [3:0] contract_violation_id;
  wire [31:0] contract_violation_timestamp;
  wire contract_release_pulse;
  wire contract_trace_frozen;
  wire [31:0] contract_trace_latest;

  chimaera_program_runtime dut (
      .clk(clk),
      .rst_n(rst_n),
      .execution_halted(execution_halted),
      .context_enable(context_enable),
      .context_entry_0(context_entry_0),
      .context_entry_1(context_entry_1),
      .descriptor_candidates(descriptor_candidates),
      .descriptor_decision(descriptor_decision),
      .descriptor_data(descriptor_data),
      .sync_inputs(sync_inputs),
      .rise_edges(rise_edges),
      .fall_edges(fall_edges),
      .fault_seed(fault_seed),
      .mutation_config_0(mutation_config_0),
      .mutation_config_1(mutation_config_1),
      .contract_config_0(contract_config_0),
      .contract_config_1(contract_config_1),
      .drive_value_0(drive_value_0),
      .drive_enable_0(drive_enable_0),
      .drive_value_1(drive_value_1),
      .drive_enable_1(drive_enable_1),
      .fire_0(fire_0),
      .fire_1(fire_1),
      .contract_trigger(contract_trigger),
      .contract_violation_count(contract_violation_count),
      .contract_violation_id(contract_violation_id),
      .contract_violation_timestamp(contract_violation_timestamp),
      .contract_release_pulse(contract_release_pulse),
      .contract_trace_frozen(contract_trace_frozen),
      .contract_trace_latest(contract_trace_latest)
  );

  wire [4:0] expected_address_0 = dut.pending_0 ? dut.pending_state_0 :
      dut.fire_timeout_0 ? dut.active_control_0[14:10] :
      dut.branch_condition_0 ? dut.active_control_0[4:0] :
      dut.active_control_0[9:5];
  wire [4:0] expected_address_1 = dut.pending_1 ? dut.pending_state_1 :
      dut.fire_timeout_1 ? dut.active_control_1[14:10] :
      dut.branch_condition_1 ? dut.active_control_1[4:0] :
      dut.active_control_1[9:5];

  always #5 clk = ~clk;

  task check_buses;
    begin
      #1;
      if (descriptor_data[127:0] !== descriptor_memory[expected_address_0])
        $fatal(1, "context 0 read bus mismatch at row %0d", expected_address_0);
      if (descriptor_data[255:128] !== descriptor_memory[expected_address_1])
        $fatal(1, "context 1 read bus mismatch at row %0d", expected_address_1);
      if (dut.load_0 && descriptor_data[127:0] !== descriptor_memory[dut.request_state_0])
        $fatal(1, "context 0 consumed the wrong descriptor");
      if (dut.load_1 && descriptor_data[255:128] !== descriptor_memory[dut.request_state_1])
        $fatal(1, "context 1 consumed the wrong descriptor");
    end
  endtask

  task set_descriptor;
    input integer index;
    input [2:0] event_kind;
    input [7:0] event_mask;
    input [15:0] timeout;
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
      descriptor_memory[index][50:35] = timeout;
      descriptor_memory[index][10:3] = event_mask;
      descriptor_memory[index][2:0] = event_kind;
    end
  endtask

  integer index;
  initial begin
    for (index = 0; index < 32; index = index + 1)
      descriptor_memory[index] = 128'h0;

    // Context 0 fires on a rising edge, then its state-1 descriptor times out
    // back to state 0. Context 1 remains disabled for this phase.
    set_descriptor(0, 3'd1, 8'h01, 16'd4, 8'h02, 8'h02,
                   8'h02, 8'h02, 5'd1, 5'd1, 5'd1,
                   2'd0, 8'h00, 1'b0, 4'd0, 1'b0);
    set_descriptor(1, 3'd1, 8'h00, 16'd1, 8'h02, 8'h00,
                   8'h00, 8'h00, 5'd0, 5'd0, 5'd0,
                   2'd0, 8'h00, 1'b0, 4'd0, 1'b0);
    repeat (3) @(posedge clk);
    rst_n = 1'b1;
    @(negedge clk);
    execution_halted = 1'b0;
    repeat (3) begin
      @(negedge clk); check_buses();
      @(posedge clk);
    end

    @(negedge clk);
    sync_inputs = 8'h01;
    rise_edges = 8'h01;
    check_buses();
    if (!fire_0)
      $fatal(1, "context 0 rising event did not fire");
    @(posedge clk);
    #1;
    rise_edges = 8'h00;
    if (drive_value_0[1] !== 1'b1 || drive_enable_0[1] !== 1'b1)
      $fatal(1, "context 0 event action did not commit on its fire edge");

    // Descriptor 1 has a one-cycle timeout and returns to descriptor 0.
    @(negedge clk); check_buses();
    @(posedge clk); #1;
    if (drive_value_0[1] !== 1'b0 || drive_enable_0[1] !== 1'b1) begin
      $display("timeout mismatch value=%02h enable=%02h fire=%b timeout=%b state=%0d active=%b timer=%0d",
               drive_value_0, drive_enable_0, fire_0, dut.fire_timeout_0,
               dut.current_state_0, dut.reaction_cell_0.active,
               dut.reaction_cell_0.timer);
      $fatal(1, "context 0 timeout action did not commit");
    end

    // Restart both contexts. Their first descriptors fire together, while the
    // arbiter defers one reload; both private read buses remain valid.
    rst_n = 1'b0;
    execution_halted = 1'b1;
    context_enable = 2'b11;
    context_entry_0 = 5'd2;
    context_entry_1 = 5'd3;
    set_descriptor(2, 3'd1, 8'h01, 16'd16, 8'h04, 8'h04,
                   8'h04, 8'h04, 5'd4, 5'd4, 5'd4,
                   2'd2, 8'h02, 1'b1, 4'd1, 1'b1);
    set_descriptor(3, 3'd1, 8'h01, 16'd16, 8'h08, 8'h08,
                   8'h08, 8'h08, 5'd5, 5'd5, 5'd5,
                   2'd0, 8'h00, 1'b0, 4'd0, 1'b0);
    set_descriptor(4, 3'd1, 8'h00, 16'd1, 8'h04, 8'h00,
                   8'h04, 8'h00, 5'd2, 5'd2, 5'd2,
                   2'd0, 8'h00, 1'b0, 4'd0, 1'b0);
    set_descriptor(5, 3'd1, 8'h00, 16'd1, 8'h08, 8'h00,
                   8'h08, 8'h00, 5'd3, 5'd3, 5'd3,
                   2'd0, 8'h00, 1'b0, 4'd0, 1'b0);
    repeat (2) @(posedge clk);
    rst_n = 1'b1;
    @(negedge clk); execution_halted = 1'b0;
    repeat (4) begin
      @(negedge clk); check_buses();
      @(posedge clk);
    end
    // The arbiter loads context 0 first after restart; service context 1 once
    // before presenting the common edge so both cells are active together.
    @(negedge clk); check_buses();
    @(posedge clk);
    @(negedge clk);
    sync_inputs = 8'h01;
    rise_edges = 8'h01;
    check_buses();
    if (!fire_0 || !fire_1)
      $fatal(1, "both contexts did not fire on the shared rising edge");
    @(posedge clk); #1;
    if (drive_value_0[2] !== 1'b0 || drive_value_1[3] !== 1'b1 ||
        !dut.selected_dynamic_output_0) begin
      $display("simultaneous values c0=%02h/%02h c1=%02h/%02h action=%02h/%02h fire=%b%b",
               drive_value_0, drive_enable_0, drive_value_1, drive_enable_1,
               dut.reaction_cell_0.action_value, dut.reaction_cell_1.action_value,
               fire_1, fire_0);
      $fatal(1, "simultaneous actions did not commit");
    end
    rise_edges = 8'h00;

    // Context 1 must be serviced from its own pending bus on the next cycle.
    @(negedge clk); check_buses();
    if (!dut.pending_1 && !dut.load_1)
      $fatal(1, "deferred context did not retain a pending reload");
    @(posedge clk); #1;

    $display("PASS: two independent runtime buses, dynamic action, timeout, branch, and bounded rearm");
    $finish;
  end
endmodule

`default_nettype wire
