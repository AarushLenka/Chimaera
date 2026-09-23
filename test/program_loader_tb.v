`default_nettype none
`timescale 1ns / 1ps

module program_loader_tb;
  reg clk = 1'b0;
  reg rst_n = 1'b0;
  reg frame_strobe = 1'b0;
  reg [31:0] frame_data = 32'd0;
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

  integer index;
  reg [15:0] words [0:15];

  chimaera_program_loader dut (
      .clk(clk),
      .rst_n(rst_n),
      .frame_strobe(frame_strobe),
      .frame_data(frame_data),
      .descriptor_address(descriptor_address),
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
    if (descriptor_data !== 128'h0100_0001_0810_1010_1000_0000_0000_0009) begin
      $display("FAIL: descriptor 0 readback %032h", descriptor_data);
      $fatal(1);
    end
    descriptor_address = 5'd1;
    #1;
    if (descriptor_data !== 128'h0000_0000_0010_1000_1000_0020_0000_000a) begin
      $display("FAIL: descriptor 1 readback %032h", descriptor_data);
      $fatal(1);
    end

    send_frame(make_frame(4'h3, 1'b0, 5'd0, 3'd0, 16'h0001));
    if (execution_halted) begin
      $display("FAIL: committed program did not resume");
      $fatal(1);
    end

    $display("PASS: loader ordering, CRC, bounds, readback, and resume");
    $finish;
  end
endmodule

`default_nettype wire
