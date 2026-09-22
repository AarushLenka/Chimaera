/*
 * Chimaera asynchronous-input front end.
 *
 * External pins pass through two flip-flops before edge detection.  Reaction
 * latency is therefore specified from sync_inputs/rise_edges/fall_edges, not
 * directly from the asynchronous package pins.
 */

`default_nettype none
`timescale 1ns / 1ps

module chimaera_input_frontend (
    input  wire       clk,
    input  wire       rst_n,
    input  wire [7:0] async_inputs,
    output wire [7:0] sync_inputs,
    output wire [7:0] rise_edges,
    output wire [7:0] fall_edges
);

  reg [7:0] sync_meta;
  reg [7:0] sync_value;
  reg [7:0] sync_previous;

  always @(posedge clk) begin
    if (!rst_n) begin
      // UART and the other initial serial protocols are idle high.
      sync_meta     <= 8'hff;
      sync_value    <= 8'hff;
      sync_previous <= 8'hff;
    end else begin
      sync_meta     <= async_inputs;
      sync_value    <= sync_meta;
      sync_previous <= sync_value;
    end
  end

  assign sync_inputs = sync_value;
  assign rise_edges  =  sync_value & ~sync_previous;
  assign fall_edges  = ~sync_value &  sync_previous;

endmodule

`default_nettype wire
