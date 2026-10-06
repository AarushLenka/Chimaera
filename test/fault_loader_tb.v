`default_nettype none
`timescale 1ns / 1ps

module fault_loader_tb;
  reg clk = 1'b0;
  reg rst_n = 1'b0;
  reg frame_strobe = 1'b0;
  reg [31:0] frame_data = 32'h00000000;
  reg [4:0] descriptor_address = 5'd0;
  wire [127:0] descriptor_data;
  wire [4:0] context_entry_0;
  wire [4:0] context_entry_1;
  wire [1:0] context_enable;
  wire [7:0] open_drain_mask;
  wire program_valid;
  wire execution_halted;
  wire load_error;
  wire load_in_progress;
  wire [5:0] loaded_descriptor_count;
  wire [15:0] computed_crc;
  wire [15:0] fault_seed;
  wire [127:0] mutation_config_0;
  wire [127:0] mutation_config_1;
  wire [127:0] contract_config_0;
  wire [127:0] contract_config_1;

  chimaera_program_loader dut (
      .clk(clk),
      .rst_n(rst_n),
      .frame_strobe(frame_strobe),
      .frame_data(frame_data),
      .descriptor_candidates({8{descriptor_address}}),
      .descriptor_decision(7'd0),
      .descriptor_data(descriptor_data),
      .context_entry_0(context_entry_0),
      .context_entry_1(context_entry_1),
      .context_enable(context_enable),
      .open_drain_mask(open_drain_mask),
      .program_valid(program_valid),
      .execution_halted(execution_halted),
      .load_error(load_error),
      .load_in_progress(load_in_progress),
      .loaded_descriptor_count(loaded_descriptor_count),
      .computed_crc(computed_crc),
      .fault_seed(fault_seed),
      .mutation_config_0(mutation_config_0),
      .mutation_config_1(mutation_config_1),
      .contract_config_0(contract_config_0),
      .contract_config_1(contract_config_1)
  );

  always #5 clk = ~clk;

  task automatic send_frame;
    input [31:0] value;
    begin
      @(negedge clk);
      frame_data = value;
      frame_strobe = 1'b1;
      @(negedge clk);
      frame_strobe = 1'b0;
      @(posedge clk);
    end
  endtask

  initial begin
    repeat (2) @(posedge clk);
    rst_n = 1'b1;
    repeat (2) @(posedge clk);

    send_frame(32'h00000000); // BEGIN
    send_frame(32'h5000ace1); // SET_FAULT_SEED 0xace1
    send_frame(32'h60009101); // mutation 0 word 0
    send_frame(32'h600801ff); // mutation 0 word 1
    send_frame(32'h7000b100); // contract 0 word 0: high-width maximum
    send_frame(32'h70080004); // contract 0 word 1: four cycles

    if (load_error || fault_seed !== 16'hace1 ||
        mutation_config_0[31:16] !== 16'h9101 ||
        mutation_config_0[15:0] !== 16'h01ff || mutation_config_1 !== 128'h0 ||
        contract_config_0[31:16] !== 16'hb100 ||
        contract_config_0[15:0] !== 16'h0004 || contract_config_1 !== 128'h0) begin
      $display("FAIL: fault/contract records were not loaded: error=%b seed=%04h mutation=%032h contract=%032h",
               load_error, fault_seed, mutation_config_0, contract_config_0);
      $fatal(1);
    end

    send_frame(32'h00000000); // BEGIN clears the separate fault table.
    if (fault_seed !== 16'h0001 || mutation_config_0 !== 128'h0 ||
        contract_config_0 !== 128'h0 || load_error) begin
      $display("FAIL: BEGIN did not clear fault configuration");
      $fatal(1);
    end

    send_frame(32'h50000000); // Zero is not a legal maximal-length seed.
    if (!load_error) begin
      $display("FAIL: zero fault seed was accepted");
      $fatal(1);
    end

    $display("PASS: seeded fault, mutation, and contract records load through the frame ABI");
    $finish;
  end
endmodule

`default_nettype wire
