`default_nettype none
`timescale 1ns / 1ps

module phase5_loader_top_tb;
  reg [7:0] ui_in = 8'h04; // Configuration CS idle high.
  wire [7:0] uo_out;
  reg [7:0] uio_in = 8'h00;
  wire [7:0] uio_out;
  wire [7:0] uio_oe;
  reg ena = 1'b1;
  reg clk = 1'b0;
  reg rst_n = 1'b0;
  reg [31:0] frames [0:20];
  integer frame_index;
  integer bit_index;
  integer timeout;

  tt_um_chimaera dut (
      .ui_in(ui_in),
      .uo_out(uo_out),
      .uio_in(uio_in),
      .uio_out(uio_out),
      .uio_oe(uio_oe),
      .ena(ena),
      .clk(clk),
      .rst_n(rst_n)
  );

  always #10 clk = ~clk;

  task automatic send_frame;
    input [31:0] value;
    begin
      ui_in[2] = 1'b1;
      ui_in[3] = 1'b0;
      repeat (4) @(posedge clk);
      ui_in[2] = 1'b0;
      repeat (4) @(posedge clk);
      for (bit_index = 31; bit_index >= 0; bit_index = bit_index - 1) begin
        ui_in[4] = value[bit_index];
        #50;
        ui_in[3] = 1'b1;
        #80;
        ui_in[3] = 1'b0;
        #50;
      end
      repeat (3) @(posedge clk);
      ui_in[2] = 1'b1;
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

    repeat (5) @(posedge clk);
    rst_n = 1'b1;
    repeat (5) @(posedge clk);

    for (frame_index = 0; frame_index < 21; frame_index = frame_index + 1)
      send_frame(frames[frame_index]);
    ui_in[4:2] = 3'b001; // CS high, clock/data low.
    repeat (8) @(posedge clk);

    uio_in[0] = 1'b1;
    timeout = 0;
    while (!(uio_oe[1] && uio_out[1]) && timeout < 16) begin
      @(posedge clk);
      timeout = timeout + 1;
    end
    if (!(uio_oe[1] && uio_out[1])) begin
      $display("FAIL: serially loaded program did not assert response");
      $fatal(1);
    end

    timeout = 0;
    while (uio_out[1] && timeout < 12) begin
      @(posedge clk);
      timeout = timeout + 1;
    end
    if (!uio_oe[1] || uio_out[1]) begin
      $display("FAIL: loaded program timeout did not drive response low");
      $fatal(1);
    end

    $display("PASS: top-level serial load, commit, resume, event action, and timeout");
    $finish;
  end
endmodule

`default_nettype wire
