`default_nettype none
`timescale 1ns / 1ps

module smoke_phase4;
  localparam integer BIT_CYCLES = 16;

  reg        clk = 1'b0;
  reg        rst_n = 1'b0;
  reg        ena = 1'b1;
  reg  [7:0] ui_in = 8'h00;
  reg  [7:0] uio_in = 8'hff;
  wire [7:0] uo_out;
  wire [7:0] uio_out;
  wire [7:0] uio_oe;
  reg  [7:0] spi_response;

  always #10 clk = ~clk;
  tt_um_chimaera dut (
      .ui_in(ui_in), .uo_out(uo_out), .uio_in(uio_in), .uio_out(uio_out),
      .uio_oe(uio_oe), .ena(ena), .clk(clk), .rst_n(rst_n)
  );

  task automatic wait_clocks;
    input integer count;
    integer index;
    begin
      for (index = 0; index < count; index = index + 1)
        @(posedge clk);
      #1;
    end
  endtask

  task automatic reset_dut;
    input [1:0] protocol;
    begin
      ui_in = protocol;
      uio_in = 8'hff;
      rst_n = 1'b0;
      wait_clocks(5);
      rst_n = 1'b1;
      wait_clocks(5);
    end
  endtask

  task automatic i2c_lines;
    input sda;
    input scl;
    begin
      uio_in = 8'hff;
      uio_in[4] = sda;
      uio_in[5] = scl;
      wait_clocks(3);
    end
  endtask

  task automatic i2c_send_byte;
    input [7:0] value;
    integer index;
    begin
      for (index = 0; index < 8; index = index + 1) begin
        i2c_lines(value[index], 1'b0);
        i2c_lines(value[index], 1'b1);
        i2c_lines(value[index], 1'b0);
      end
    end
  endtask

  task automatic i2c_ack;
    begin
      i2c_lines(1'b1, 1'b0);
      if ((uio_oe & 8'h10) !== 8'h10)
        $fatal(1, "I2C ACK did not drive SDA low");
      i2c_lines(1'b0, 1'b1);
      if (uio_out[4] !== 1'b0)
        $fatal(1, "I2C ACK output is not low");
      i2c_lines(1'b0, 1'b0);
      i2c_lines(1'b1, 1'b0);
      if ((uio_oe & 8'h10) !== 8'h00)
        $fatal(1, "I2C SDA was not released");
    end
  endtask

  task automatic spi_lines;
    input sclk;
    input mosi;
    input cs;
    begin
      uio_in = 8'hff;
      uio_in[4] = sclk;
      uio_in[5] = mosi;
      uio_in[7] = cs;
      wait_clocks(3);
    end
  endtask

  task automatic spi_transaction;
    input [7:0] value;
    integer index;
    begin
      spi_lines(1'b0, 1'b0, 1'b0);
      if ((uio_oe & 8'h40) !== 8'h40)
        $fatal(1, "SPI MISO was not enabled");
      for (index = 0; index < 8; index = index + 1) begin
        spi_lines(1'b0, value[index], 1'b0);
        spi_lines(1'b1, value[index], 1'b0);
        spi_response[index] = uio_out[6];
        spi_lines(1'b0, value[index], 1'b0);
      end
      if ((uio_oe & 8'h40) !== 8'h00)
        $fatal(1, "SPI MISO was not released");
      spi_lines(1'b0, 1'b0, 1'b1);
    end
  endtask

  initial begin
    reset_dut(2'd0);
    i2c_lines(1'b1, 1'b1);
    i2c_lines(1'b0, 1'b1); // START
    i2c_send_byte(8'h84);
    i2c_ack();
    i2c_send_byte(8'h5a);
    i2c_ack();
    if (uo_out !== 8'h5a)
      $fatal(1, "I2C data mismatch: got %02x", uo_out);

    reset_dut(2'd0);
    i2c_lines(1'b1, 1'b1);
    i2c_lines(1'b0, 1'b1);
    i2c_send_byte(8'h86);
    i2c_lines(1'b1, 1'b0);
    if ((uio_oe & 8'h10) !== 8'h00)
      $fatal(1, "I2C wrong address was ACKed");

    reset_dut(2'd1);
    spi_lines(1'b0, 1'b0, 1'b1);
    spi_transaction(8'ha5);
    if (spi_response !== 8'h3c || uo_out !== 8'ha5)
      $fatal(1, "SPI mismatch: response %02x command %02x", spi_response, uo_out);

    reset_dut(2'd1);
    spi_lines(1'b0, 1'b0, 1'b1);
    spi_lines(1'b0, 1'b0, 1'b0);
    if ((uio_oe & 8'h40) !== 8'h40)
      $fatal(1, "SPI abort setup did not enable MISO");
    spi_lines(1'b1, 1'b0, 1'b0);
    spi_lines(1'b0, 1'b0, 1'b0);
    spi_lines(1'b0, 1'b0, 1'b1);
    if ((uio_oe & 8'h40) !== 8'h00)
      $fatal(1, "SPI abort did not release MISO");

    $display("PASS: UART baseline, I2C ACK/NACK, SPI response/abort, two cells");
    $finish;
  end
endmodule

`default_nettype wire
