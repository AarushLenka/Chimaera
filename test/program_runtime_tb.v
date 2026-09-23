`default_nettype none
`timescale 1ns / 1ps

module program_runtime_tb;
  reg clk = 1'b0;
  reg rst_n = 1'b0;
  reg execution_halted = 1'b1;
  reg [1:0] context_enable = 2'b01;
  reg [4:0] context_entry_0 = 5'd0;
  reg [4:0] context_entry_1 = 5'd0;
  reg [7:0] sync_inputs = 8'h00;
  reg [7:0] rise_edges = 8'h00;
  reg [7:0] fall_edges = 8'h00;
  wire [4:0] descriptor_address;
  reg [127:0] descriptor_memory [0:3];
  wire [127:0] descriptor_data = descriptor_memory[descriptor_address[1:0]];
  wire [7:0] drive_value_0;
  wire [7:0] drive_enable_0;
  wire [7:0] drive_value_1;
  wire [7:0] drive_enable_1;
  wire fire_0;
  wire fire_1;

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
      .drive_value_0(drive_value_0),
      .drive_enable_0(drive_enable_0),
      .drive_value_1(drive_value_1),
      .drive_enable_1(drive_enable_1),
      .fire_0(fire_0),
      .fire_1(fire_1)
  );

  always #5 clk = ~clk;

  initial begin
    descriptor_memory[0] = 128'h0100_0001_0810_1010_1000_0000_0000_0009;
    descriptor_memory[1] = 128'h0000_0000_0010_1000_1000_0020_0000_000a;

    repeat (3) @(posedge clk);
    rst_n = 1'b1;
    repeat (2) @(posedge clk);
    execution_halted = 1'b0;
    repeat (4) @(posedge clk);

    // A synchronized request rising edge commits the predecoded response-high
    // action without waiting for shared bookkeeping.
    @(negedge clk);
    sync_inputs = 8'h01;
    rise_edges = 8'h01;
    @(posedge clk);
    #1;
    rise_edges = 8'h00;
    if (drive_value_0[1] !== 1'b1 || drive_enable_0[1] !== 1'b1) begin
      $display("FAIL: loaded descriptor did not fire response high");
      $fatal(1);
    end

    // wait_release has a four-cycle timeout whose predecoded action drives low.
    repeat (3) @(posedge clk);
    @(posedge clk);
    #1;
    if (drive_value_0[1] !== 1'b0 || drive_enable_0[1] !== 1'b1) begin
      $display("FAIL: timeout did not return response low");
      $fatal(1);
    end

    execution_halted = 1'b1;
    @(posedge clk);
    #1;
    if (drive_enable_0 != 8'h00 || drive_enable_1 != 8'h00 || fire_1) begin
      $display("FAIL: halt did not release runtime outputs");
      $fatal(1);
    end

    // Restart with two contexts that see the same edge. Both predecoded output
    // actions must commit on the fire edge; context 1's deferred descriptor
    // reload must then outrank any new context-0 request.
    rst_n = 1'b0;
    execution_halted = 1'b1;
    context_enable = 2'b11;
    context_entry_0 = 5'd0;
    context_entry_1 = 5'd1;
    sync_inputs = 8'h00;
    rise_edges = 8'h00;
    descriptor_memory[0] = 128'h0000_0000_0020_2020_2000_0000_0000_0009;
    descriptor_memory[1] = 128'h0000_0021_0840_4040_4000_0000_0000_0009;
    repeat (2) @(posedge clk);
    rst_n = 1'b1;
    repeat (2) @(posedge clk);
    execution_halted = 1'b0;
    repeat (4) @(posedge clk);

    @(negedge clk);
    sync_inputs = 8'h01;
    rise_edges = 8'h01;
    #1;
    if (!fire_0 || !fire_1) begin
      $display("FAIL: simultaneous edge did not match both active descriptors");
      $fatal(1);
    end
    @(posedge clk);
    #1;
    if (drive_value_0[2] !== 1'b1 || drive_value_1[3] !== 1'b1 ||
        descriptor_address != 5'd1 ||
        dut.pending_1 !== 1'b1) begin
      $display("FAIL: simultaneous actions or deferred-context arbitration mismatch");
      $display("fire=%b%b value0=%02h value1=%02h address=%0d pending1=%b",
               fire_1, fire_0, drive_value_0, drive_value_1,
               descriptor_address, dut.pending_1);
      $fatal(1);
    end
    // Keep the synthetic rise request asserted for one more edge. Context 0
    // fires again, but context 1's older pending reload must win the read port.
    @(posedge clk);
    #1;
    if (dut.pending_1 !== 1'b0 || dut.pending_0 !== 1'b1 ||
        dut.active_control_1[4:0] != 5'd1) begin
      $display("FAIL: pending context did not outrank a new context-0 fire");
      $fatal(1);
    end
    rise_edges = 8'h00;
    @(posedge clk);
    #1;
    if (dut.pending_0 !== 1'b0) begin
      $display("FAIL: newly deferred context was not rearmed next");
      $fatal(1);
    end

    $display("PASS: packed execution timing, halt release, and bounded two-context arbitration");
    $finish;
  end
endmodule

`default_nettype wire
