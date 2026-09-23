`default_nettype none
`timescale 1ns / 1ps

module host_interface_tb;
  reg clk = 1'b0;
  reg rst_n = 1'b0;
  reg cfg_cs_n = 1'b1;
  reg cfg_sclk = 1'b0;
  reg cfg_mosi = 1'b0;
  reg [4:0] descriptor_address = 5'd0;
  wire cfg_miso;
  wire cfg_active;
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
  wire [31:0] status_word;
  reg [31:0] frames [0:20];
  integer frame_index;
  integer bit_index;

  chimaera_host_interface dut (
      .clk(clk),
      .rst_n(rst_n),
      .cfg_cs_n(cfg_cs_n),
      .cfg_sclk(cfg_sclk),
      .cfg_mosi(cfg_mosi),
      .cfg_miso(cfg_miso),
      .cfg_active(cfg_active),
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
      .computed_crc(computed_crc),
      .status_word(status_word)
  );

  always #10 clk = ~clk;

  task automatic send_frame;
    input [31:0] value;
    begin
      cfg_cs_n = 1'b1;
      cfg_sclk = 1'b0;
      repeat (4) @(posedge clk);
      cfg_cs_n = 1'b0;
      repeat (4) @(posedge clk);
      for (bit_index = 31; bit_index >= 0; bit_index = bit_index - 1) begin
        cfg_mosi = value[bit_index];
        #50;
        cfg_sclk = 1'b1;
        #80;
        cfg_sclk = 1'b0;
        #50;
      end
      repeat (3) @(posedge clk);
      cfg_cs_n = 1'b1;
      repeat (4) @(posedge clk);
    end
  endtask

  initial begin
    frames[0]  = 32'h00000000;
    frames[1]  = 32'h10000009;
    frames[2]  = 32'h10080000;
    frames[3]  = 32'h10100000;
    frames[4]  = 32'h10181000;
    frames[5]  = 32'h10201010;
    frames[6]  = 32'h10280810;
    frames[7]  = 32'h10300001;
    frames[8]  = 32'h10380100;
    frames[9]  = 32'h1040000a;
    frames[10] = 32'h10480000;
    frames[11] = 32'h10500020;
    frames[12] = 32'h10581000;
    frames[13] = 32'h10601000;
    frames[14] = 32'h10680010;
    frames[15] = 32'h10700000;
    frames[16] = 32'h10780000;
    frames[17] = 32'h20000020;
    frames[18] = 32'h40000000;
    frames[19] = 32'he040ca08;
    frames[20] = 32'h30000001;

    repeat (4) @(posedge clk);
    rst_n = 1'b1;
    repeat (4) @(posedge clk);

    for (frame_index = 0; frame_index < 21; frame_index = frame_index + 1)
      send_frame(frames[frame_index]);

    if (!program_valid || execution_halted || load_error ||
        loaded_descriptor_count != 6'd2 || computed_crc != 16'hca08 ||
        context_enable != 2'b01 || context_entry_0 != 5'd0 ||
        open_drain_mask != 8'h00) begin
      $display("FAIL: serial loader status %08h", status_word);
      $fatal(1);
    end
    descriptor_address = 5'd0;
    #1;
    if (descriptor_data !== 128'h0100_0001_0810_1010_1000_0000_0000_0009) begin
      $display("FAIL: serial descriptor readback %032h", descriptor_data);
      $fatal(1);
    end

    $display("PASS: compiler frame stream loaded through synchronized serial host interface");
    $finish;
  end
endmodule

`default_nettype wire
