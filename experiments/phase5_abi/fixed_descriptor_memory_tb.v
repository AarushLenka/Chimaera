`default_nettype none

module fixed_descriptor_memory_tb;
  reg clk = 1'b0;
  reg we = 1'b0;
  reg [4:0] wa = 5'd0;
  reg [2:0] ww = 3'd0;
  reg [15:0] wd = 16'd0;
  reg [4:0] ra = 5'd0;
  wire [127:0] q;
  integer index;

  abi_fixed_32 dut (
      .clk(clk), .we(we), .wa(wa), .ww(ww), .wd(wd), .ra(ra), .q(q)
  );

  always #5 clk = ~clk;

  initial begin
    for (index = 0; index < 8; index = index + 1) begin
      @(negedge clk);
      we = 1'b1;
      ww = index[2:0];
      wd = 16'h1000 + index;
    end
    @(negedge clk);
    we = 1'b0;
    repeat (2) @(posedge clk);
    #1;
    if (q !== 128'h1007_1006_1005_1004_1003_1002_1001_1000) begin
      $display("FAIL: descriptor readback %032h", q);
      $fatal(1);
    end
    $display("PASS: 128-bit descriptor write/read");
    $finish;
  end
endmodule

`default_nettype wire
