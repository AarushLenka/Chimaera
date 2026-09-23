`default_nettype none
`timescale 1ns / 1ps

module config_spi_tb;
  reg clk = 1'b0;
  reg rst_n = 1'b0;
  reg cs_n = 1'b1;
  reg sclk = 1'b0;
  reg mosi = 1'b0;
  reg [31:0] tx_data = 32'ha55a_c33c;
  wire miso;
  wire transaction_active;
  wire frame_strobe;
  wire [31:0] frame_data;
  wire framing_error;
  reg [31:0] observed_frame;
  integer observed_count = 0;
  integer bit_index;

  chimaera_config_spi dut (
      .clk(clk),
      .rst_n(rst_n),
      .async_cs_n(cs_n),
      .async_sclk(sclk),
      .async_mosi(mosi),
      .tx_data(tx_data),
      .miso(miso),
      .transaction_active(transaction_active),
      .frame_strobe(frame_strobe),
      .frame_data(frame_data),
      .framing_error(framing_error)
  );

  always #10 clk = ~clk;

  always @(posedge clk) begin
    if (frame_strobe) begin
      observed_frame <= frame_data;
      observed_count <= observed_count + 1;
    end
  end

  task automatic begin_transaction;
    begin
      cs_n = 1'b1;
      sclk = 1'b0;
      repeat (4) @(posedge clk);
      cs_n = 1'b0;
      repeat (4) @(posedge clk);
    end
  endtask

  task automatic end_transaction;
    begin
      sclk = 1'b0;
      repeat (3) @(posedge clk);
      cs_n = 1'b1;
      repeat (4) @(posedge clk);
    end
  endtask

  task automatic send_bit;
    input bit_value;
    begin
      mosi = bit_value;
      #50;
      sclk = 1'b1;
      #80;
      sclk = 1'b0;
      #50;
    end
  endtask

  task automatic send_word;
    input [31:0] value;
    begin
      for (bit_index = 31; bit_index >= 0; bit_index = bit_index - 1)
        send_bit(value[bit_index]);
    end
  endtask

  initial begin
    repeat (4) @(posedge clk);
    rst_n = 1'b1;
    repeat (4) @(posedge clk);

    begin_transaction();
    send_word(32'h1234_abcd);
    end_transaction();
    if (observed_count != 1 || observed_frame !== 32'h1234_abcd || framing_error) begin
      $display("FAIL: complete configuration frame %08h count=%0d error=%0b",
               observed_frame, observed_count, framing_error);
      $fatal(1);
    end

    begin_transaction();
    for (bit_index = 7; bit_index >= 0; bit_index = bit_index - 1)
      send_bit((8'h5a >> bit_index) & 1'b1);
    end_transaction();
    if (!framing_error || observed_count != 1) begin
      $display("FAIL: partial frame was not rejected");
      $fatal(1);
    end

    begin_transaction();
    send_word(32'h89ab_cdef);
    end_transaction();
    if (observed_count != 2 || observed_frame !== 32'h89ab_cdef || framing_error) begin
      $display("FAIL: recovery frame %08h count=%0d error=%0b",
               observed_frame, observed_count, framing_error);
      $fatal(1);
    end

    $display("PASS: synchronized config frames and partial-frame recovery");
    $finish;
  end
endmodule

`default_nettype wire
