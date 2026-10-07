/*
 * Chimaera asynchronous-input front end.
 *
 * External pins pass through two flip-flops before edge detection.  Reaction
 * latency is therefore specified from sync_inputs/rise_edges/fall_edges, not
 * directly from the asynchronous package pins.
 */

`default_nettype none
`timescale 1ns / 1ps

// Each consumer bank is a complete two-flop synchronizer plus its previous
// synchronized sample.  The hierarchy boundary and keep attributes stop
// synthesis from folding the physically separate banks back together.
/* verilator lint_off DECLFILENAME */
(* keep_hierarchy = "yes" *)
module chimaera_input_bank (
    input  wire       clk,
    input  wire       rst_n,
    input  wire [7:0] async_inputs,
    output wire [7:0] sync_inputs,
    output wire [7:0] rise_edges,
    output wire [7:0] fall_edges
);

  (* keep = "true", dont_touch = "true" *) reg [7:0] sync_meta;
  (* keep = "true", dont_touch = "true" *) reg [7:0] sync_value;
  (* keep = "true", dont_touch = "true" *) reg [7:0] sync_previous;

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
  assign rise_edges  = sync_value & ~sync_previous;
  assign fall_edges  = ~sync_value & sync_previous;

endmodule
/* verilator lint_on DECLFILENAME */

module chimaera_input_frontend (
    input  wire       clk,
    input  wire       rst_n,
    input  wire [7:0] async_inputs,

    // The original ports remain the legacy reaction-path interface.  Each
    // additional bank has its own synchronizer and edge history so no
    // second-stage bit is broadcast to all consumers.
    output wire [7:0] sync_inputs,
    output wire [7:0] rise_edges,
    output wire [7:0] fall_edges,
    output wire [7:0] loaded_sync_inputs,
    output wire [7:0] loaded_rise_edges,
    output wire [7:0] loaded_fall_edges,
    output wire [7:0] execution_sync_inputs,
    output wire [7:0] execution_rise_edges,
    output wire [7:0] execution_fall_edges
);

  // Keep each consumer bank as a separate hierarchy boundary so all three
  // banks remain physically distinct while their logical signals stay aligned.
  (* keep_hierarchy = "yes", dont_touch = "true" *)
  chimaera_input_bank legacy_bank (
      .clk          (clk),
      .rst_n        (rst_n),
      .async_inputs (async_inputs),
      .sync_inputs  (sync_inputs),
      .rise_edges   (rise_edges),
      .fall_edges   (fall_edges)
  );

  (* keep_hierarchy = "yes", dont_touch = "true" *)
  chimaera_input_bank loaded_bank (
      .clk          (clk),
      .rst_n        (rst_n),
      .async_inputs (async_inputs),
      .sync_inputs  (loaded_sync_inputs),
      .rise_edges   (loaded_rise_edges),
      .fall_edges   (loaded_fall_edges)
  );

  (* keep_hierarchy = "yes", dont_touch = "true" *)
  chimaera_input_bank execution_bank (
      .clk          (clk),
      .rst_n        (rst_n),
      .async_inputs (async_inputs),
      .sync_inputs  (execution_sync_inputs),
      .rise_edges   (execution_rise_edges),
      .fall_edges   (execution_fall_edges)
  );

endmodule

`default_nettype wire
