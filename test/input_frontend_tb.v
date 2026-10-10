`default_nettype none
`timescale 1ns / 1ps

module input_frontend_tb;

  reg clk;
  reg rst_n;
  reg [7:0] async_inputs;

  wire [7:0] legacy_sync_inputs;
  wire [7:0] legacy_rise_edges;
  wire [7:0] legacy_fall_edges;
  wire [7:0] loaded_sync_inputs;
  wire [7:0] loaded_rise_edges;
  wire [7:0] loaded_fall_edges;
  wire [7:0] loaded_cell0_sync_inputs;
  wire [7:0] loaded_cell0_rise_edges;
  wire [7:0] loaded_cell0_fall_edges;
  wire [7:0] loaded_cell1_sync_inputs;
  wire [7:0] loaded_cell1_rise_edges;
  wire [7:0] loaded_cell1_fall_edges;
  wire [7:0] execution_sync_inputs;
  wire [7:0] execution_rise_edges;
  wire [7:0] execution_fall_edges;

  chimaera_input_frontend dut (
      .clk                   (clk),
      .rst_n                 (rst_n),
      .async_inputs          (async_inputs),
      .sync_inputs           (legacy_sync_inputs),
      .rise_edges            (legacy_rise_edges),
      .fall_edges            (legacy_fall_edges),
      .loaded_sync_inputs    (loaded_sync_inputs),
      .loaded_rise_edges     (loaded_rise_edges),
      .loaded_fall_edges     (loaded_fall_edges),
      .loaded_cell0_sync_inputs(loaded_cell0_sync_inputs),
      .loaded_cell0_rise_edges (loaded_cell0_rise_edges),
      .loaded_cell0_fall_edges (loaded_cell0_fall_edges),
      .loaded_cell1_sync_inputs(loaded_cell1_sync_inputs),
      .loaded_cell1_rise_edges (loaded_cell1_rise_edges),
      .loaded_cell1_fall_edges (loaded_cell1_fall_edges),
      .execution_sync_inputs (execution_sync_inputs),
      .execution_rise_edges  (execution_rise_edges),
      .execution_fall_edges  (execution_fall_edges)
  );

  always #5 clk = ~clk;

  task check_banks;
    input [7:0] expected_sync;
    input [7:0] expected_rise;
    input [7:0] expected_fall;
    begin
      #1;
      if (legacy_sync_inputs !== expected_sync ||
          loaded_sync_inputs !== expected_sync ||
          execution_sync_inputs !== expected_sync ||
          legacy_rise_edges !== expected_rise ||
          loaded_rise_edges !== expected_rise ||
          loaded_cell0_sync_inputs !== expected_sync ||
          loaded_cell0_rise_edges !== expected_rise ||
          loaded_cell0_fall_edges !== expected_fall ||
          loaded_cell1_sync_inputs !== expected_sync ||
          loaded_cell1_rise_edges !== expected_rise ||
          loaded_cell1_fall_edges !== expected_fall ||
          execution_rise_edges !== expected_rise ||
          legacy_fall_edges !== expected_fall ||
          loaded_fall_edges !== expected_fall ||
          execution_fall_edges !== expected_fall)
        $fatal(1, "synchronizer banks are not aligned");
    end
  endtask

  initial begin
    clk = 1'b0;
    rst_n = 1'b0;
    async_inputs = 8'hff;

    @(posedge clk);
    check_banks(8'hff, 8'h00, 8'h00);
    @(posedge clk);
    check_banks(8'hff, 8'h00, 8'h00);

    rst_n = 1'b1;
    async_inputs = 8'hfe;
    @(posedge clk);
    check_banks(8'hff, 8'h00, 8'h00);
    @(posedge clk);
    check_banks(8'hfe, 8'h00, 8'h01);

    async_inputs = 8'hff;
    @(posedge clk);
    check_banks(8'hfe, 8'h00, 8'h00);
    @(posedge clk);
    check_banks(8'hff, 8'h01, 8'h00);

    $display("input_frontend_tb passed");
    $finish;
  end

endmodule

`default_nettype wire
