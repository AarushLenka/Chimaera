`default_nettype none
`timescale 1ns / 1ps

module smoke_uart;
  localparam integer BIT_CYCLES = 16;

  reg        clk = 1'b0;
  reg        rst_n = 1'b0;
  reg        ena = 1'b1;
  reg  [7:0] ui_in = 8'h00;
  reg  [7:0] uio_in = 8'hff;
  wire [7:0] uo_out;
  wire [7:0] uio_out;
  wire [7:0] uio_oe;

  reg [7:0] decoded_tx;

  always #10 clk = ~clk;

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

  task automatic wait_clocks;
    input integer count;
    integer index;
    begin
      for (index = 0; index < count; index = index + 1)
        @(posedge clk);
    end
  endtask

  task automatic send_uart_byte;
    input [7:0] value;
    integer index;
    begin
      uio_in[0] = 1'b0;
      wait_clocks(BIT_CYCLES);
      for (index = 0; index < 8; index = index + 1) begin
        uio_in[0] = value[index];
        wait_clocks(BIT_CYCLES);
      end
      uio_in[0] = 1'b1;
      wait_clocks(BIT_CYCLES);
    end
  endtask

  task automatic receive_uart_byte;
    integer index;
    begin
      @(negedge uio_out[1]);
      wait_clocks(BIT_CYCLES / 2);
      #1;
      if (uio_out[1] !== 1'b0)
        $fatal(1, "TX start bit ended early");
      for (index = 0; index < 8; index = index + 1) begin
        wait_clocks(BIT_CYCLES);
        #1;
        decoded_tx[index] = uio_out[1];
      end
      wait_clocks(BIT_CYCLES);
      #1;
      if (uio_out[1] !== 1'b1)
        $fatal(1, "TX stop bit was not high");
    end
  endtask

  initial begin
    wait_clocks(5);
    rst_n = 1'b1;
    wait_clocks(5);

    if (uio_oe !== 8'h02 || uio_out[1] !== 1'b1)
      $fatal(1, "UART TX ownership/idle level is wrong");

    fork
      send_uart_byte(8'ha5);
      receive_uart_byte();
    join

    if (uo_out !== 8'ha5)
      $fatal(1, "RX byte mismatch: got %02x", uo_out);
    if (decoded_tx !== 8'ha5)
      $fatal(1, "TX byte mismatch: got %02x", decoded_tx);

    // Reset and prove that a quarter-bit low pulse is rejected.
    rst_n = 1'b0;
    wait_clocks(3);
    rst_n = 1'b1;
    wait_clocks(5);
    uio_in[0] = 1'b0;
    wait_clocks(BIT_CYCLES / 4);
    uio_in[0] = 1'b1;
    wait_clocks(BIT_CYCLES * 3);

    if (uo_out !== 8'h00 || uio_out[1] !== 1'b1)
      $fatal(1, "False UART start was accepted");

    $display("PASS: RX=0xA5, TX=0xA5, 16 clocks/bit, false start rejected");
    $finish;
  end

endmodule

`default_nettype wire
