`default_nettype none
`timescale 1ns / 1ps

module program_loader_tb;
  reg clk = 1'b0;
  reg rst_n = 1'b0;
  reg frame_strobe = 1'b0;
  reg [31:0] frame_data = 32'd0;
  reg [4:0] descriptor_address = 5'd0;
  wire [255:0] descriptor_data;
  wire [127:0] descriptor_data_0 = descriptor_data[127:0];
  wire [127:0] descriptor_data_1 = descriptor_data[255:128];
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

  integer index;
  integer pass;
  integer address_index;
  reg [15:0] words [0:15];
  reg [15:0] readback_pattern = 16'hace1;
  reg [127:0] expected_memory [0:31];

  chimaera_program_loader dut (
      .clk(clk),
      .rst_n(rst_n),
      .frame_strobe(frame_strobe),
      .frame_data(frame_data),
      .descriptor_candidates({8{descriptor_address}}),
      .descriptor_decision(6'd0),
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
      .computed_crc(computed_crc)
  );

  always #5 clk = ~clk;

  function [31:0] make_frame;
    input [3:0] opcode;
    input context_id;
    input [4:0] address;
    input [2:0] word_index;
    input [15:0] payload;
    begin
      make_frame = {opcode, context_id, address, word_index, 3'b000, payload};
    end
  endfunction

  task automatic send_frame;
    input [31:0] value;
    begin
      @(negedge clk);
      frame_data = value;
      frame_strobe = 1'b1;
      @(negedge clk);
      frame_strobe = 1'b0;
      frame_data = 32'd0;
    end
  endtask

  initial begin
    // Compiler-emitted loader_pulse descriptors, word 0 first.
    words[0]  = 16'h0009;
    words[1]  = 16'h0000;
    words[2]  = 16'h0000;
    words[3]  = 16'h1000;
    words[4]  = 16'h1010;
    words[5]  = 16'h0810;
    words[6]  = 16'h0001;
    words[7]  = 16'h0100;
    words[8]  = 16'h000a;
    words[9]  = 16'h0000;
    words[10] = 16'h0020;
    words[11] = 16'h1000;
    words[12] = 16'h1000;
    words[13] = 16'h0010;
    words[14] = 16'h0000;
    words[15] = 16'h0000;

    repeat (3) @(posedge clk);
    rst_n = 1'b1;

    // An out-of-order word is rejected, and BEGIN recovers cleanly.
    send_frame(make_frame(4'h0, 1'b0, 5'd0, 3'd0, 16'd0));
    send_frame(make_frame(4'h1, 1'b0, 5'd0, 3'd1, words[1]));
    if (!load_error) begin
      $display("FAIL: out-of-order write was accepted");
      $fatal(1);
    end
    send_frame(make_frame(4'h0, 1'b0, 5'd0, 3'd0, 16'd0));

    // A stream with a valid checksum but an out-of-range successor is rejected
    // structurally. BEGIN remains the recovery point after any loader error.
    words[5] = 16'hf810;
    for (index = 0; index < 16; index = index + 1)
      send_frame(make_frame(4'h1, 1'b0, index[4:3], index[2:0], words[index]));
    send_frame(make_frame(4'h2, 1'b0, 5'd0, 3'd0, 16'h0020));
    send_frame(make_frame(4'he, 1'b0, 5'd1, 3'd0, 16'h722c));
    if (program_valid || !load_error) begin
      $display("FAIL: out-of-range descriptor target was accepted");
      $fatal(1);
    end

    words[5] = 16'h0810;
    send_frame(make_frame(4'h0, 1'b0, 5'd0, 3'd0, 16'd0));
    for (index = 0; index < 16; index = index + 1)
      send_frame(make_frame(4'h1, 1'b0, index[4:3], index[2:0], words[index]));

    send_frame(make_frame(4'h2, 1'b0, 5'd0, 3'd0, 16'h0020));
    send_frame(make_frame(4'h4, 1'b0, 5'd0, 3'd0, 16'h0010));
    send_frame(make_frame(4'he, 1'b0, 5'd1, 3'd0, 16'hca08));

    if (!program_valid || load_error || !execution_halted ||
        loaded_descriptor_count != 6'd2 || computed_crc != 16'hca08 ||
        context_enable != 2'b01 || context_entry_0 != 5'd0 ||
        open_drain_mask != 8'h10) begin
      $display("FAIL: valid program commit status mismatch");
      $fatal(1);
    end

    descriptor_address = 5'd0;
    #1;
    if (descriptor_data_0 !== 128'h0100_0001_0810_1010_1000_0000_0000_0009 ||
        descriptor_data_1 !== 128'h0100_0001_0810_1010_1000_0000_0000_0009) begin
      $display("FAIL: descriptor 0 readback c0=%032h c1=%032h", descriptor_data_0, descriptor_data_1);
      $fatal(1);
    end
    descriptor_address = 5'd1;
    #1;
    if (descriptor_data_0 !== 128'h0000_0000_0010_1000_1000_0020_0000_000a ||
        descriptor_data_1 !== 128'h0000_0000_0010_1000_1000_0020_0000_000a) begin
      $display("FAIL: descriptor 1 readback c0=%032h c1=%032h", descriptor_data_0, descriptor_data_1);
      $fatal(1);
    end

    send_frame(make_frame(4'h3, 1'b0, 5'd0, 3'd0, 16'h0001));
    if (execution_halted) begin
      $display("FAIL: committed program did not resume");
      $fatal(1);
    end

    // Exercise all rows and all eight word slices through the real write port,
    // including rewrites. Unwritten words in other rows are still unknown on
    // the first pass and must not contaminate the selected known word.
    for (pass = 0; pass < 2; pass = pass + 1) begin
      send_frame(make_frame(4'h0, 1'b0, 5'd0, 3'd0, 16'd0));
      for (index = 0; index < 256; index = index + 1) begin
        readback_pattern = {readback_pattern[14:0],
            readback_pattern[15] ^ readback_pattern[13] ^
            readback_pattern[12] ^ readback_pattern[10]};
        expected_memory[index/8][(index%8)*16 +: 16] = readback_pattern;
        descriptor_address = index[7:3];
        send_frame(make_frame(4'h1, 1'b0, index[7:3], index[2:0], readback_pattern));
        #1;
        if (load_error ||
            descriptor_data_0[(index%8)*16 +: 16] !== readback_pattern ||
            descriptor_data_1[(index%8)*16 +: 16] !== readback_pattern)
          $fatal(1, "word readback mismatch pass=%0d row=%0d word=%0d", pass, index/8, index%8);
      end
      // Changing the address must expose the entire row without another clock.
      for (address_index = 31; address_index >= 0; address_index = address_index - 1) begin
        descriptor_address = address_index[4:0];
        #1;
        if (descriptor_data_0 !== expected_memory[address_index] ||
            descriptor_data_1 !== expected_memory[address_index])
          $fatal(1, "full descriptor readback mismatch pass=%0d row=%0d", pass, address_index);
      end
    end

    $display("PASS: loader ordering, CRC, bounds, resume, and 512 word writes / 64 asynchronous row reads");
    $finish;
  end
endmodule

`default_nettype wire
