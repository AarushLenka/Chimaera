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
    output wire [7:0] fall_edges,
    // The loaded runtime gets two physical second-stage views.  They capture
    // the same shared first-stage sample, so they stay cycle-aligned while
    // keeping each reaction cone's synchronized bus local after the flop.
    output wire [7:0] sync_inputs_view_1,
    output wire [7:0] rise_edges_view_1,
    output wire [7:0] fall_edges_view_1,
    output wire [7:0] sync_inputs_view_2,
    output wire [7:0] rise_edges_view_2,
    output wire [7:0] fall_edges_view_2
);

  (* keep = "true", dont_touch = "true" *) reg [7:0] sync_meta;
  (* keep = "true", dont_touch = "true" *) reg [7:0] sync_value;
  (* keep = "true", dont_touch = "true" *) reg [7:0] sync_previous;
  (* keep = "true", dont_touch = "true" *) reg [7:0] sync_value_view_1;
  (* keep = "true", dont_touch = "true" *) reg [7:0] sync_previous_view_1;
  (* keep = "true", dont_touch = "true" *) reg [7:0] sync_value_view_2;
  (* keep = "true", dont_touch = "true" *) reg [7:0] sync_previous_view_2;

  always @(posedge clk) begin
    if (!rst_n) begin
      // UART and the other initial serial protocols are idle high.
      sync_meta     <= 8'hff;
      sync_value    <= 8'hff;
      sync_previous <= 8'hff;
      sync_value_view_1    <= 8'hff;
      sync_previous_view_1 <= 8'hff;
      sync_value_view_2    <= 8'hff;
      sync_previous_view_2 <= 8'hff;
    end else begin
      sync_meta     <= async_inputs;
      sync_value    <= sync_meta;
      sync_previous <= sync_value;
      // These are parallel second-stage synchronizer views, not pipeline
      // stages: each captures the same sync_meta value as sync_value does.
      sync_value_view_1    <= sync_meta;
      sync_previous_view_1 <= sync_value_view_1;
      sync_value_view_2    <= sync_meta;
      sync_previous_view_2 <= sync_value_view_2;
    end
  end

  assign sync_inputs = sync_value;
  assign rise_edges  = sync_value & ~sync_previous;
  assign fall_edges  = ~sync_value & sync_previous;
  assign sync_inputs_view_1 = sync_value_view_1;
  assign rise_edges_view_1  = sync_value_view_1 & ~sync_previous_view_1;
  assign fall_edges_view_1  = ~sync_value_view_1 & sync_previous_view_1;
  assign sync_inputs_view_2 = sync_value_view_2;
  assign rise_edges_view_2  = sync_value_view_2 & ~sync_previous_view_2;
  assign fall_edges_view_2  = ~sync_value_view_2 & sync_previous_view_2;

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
    output wire [7:0] loaded_cell0_sync_inputs,
    output wire [7:0] loaded_cell0_rise_edges,
    output wire [7:0] loaded_cell0_fall_edges,
    output wire [7:0] loaded_cell1_sync_inputs,
    output wire [7:0] loaded_cell1_rise_edges,
    output wire [7:0] loaded_cell1_fall_edges,
    output wire [7:0] execution_sync_inputs,
    output wire [7:0] execution_rise_edges,
    output wire [7:0] execution_fall_edges
);

  // Only the loaded bank uses the extra views. Keep explicit sinks on the
  // other banks so lint sees every expanded bank port as intentionally wired.
  wire [7:0] legacy_sync_inputs_view_1_unused;
  wire [7:0] legacy_rise_edges_view_1_unused;
  wire [7:0] legacy_fall_edges_view_1_unused;
  wire [7:0] legacy_sync_inputs_view_2_unused;
  wire [7:0] legacy_rise_edges_view_2_unused;
  wire [7:0] legacy_fall_edges_view_2_unused;
  wire [7:0] execution_sync_inputs_view_1_unused;
  wire [7:0] execution_rise_edges_view_1_unused;
  wire [7:0] execution_fall_edges_view_1_unused;
  wire [7:0] execution_sync_inputs_view_2_unused;
  wire [7:0] execution_rise_edges_view_2_unused;
  wire [7:0] execution_fall_edges_view_2_unused;

  // Keep each consumer bank as a separate hierarchy boundary so all three
  // banks remain physically distinct while their logical signals stay aligned.
  (* keep_hierarchy = "yes", dont_touch = "true" *)
  chimaera_input_bank legacy_bank (
      .clk          (clk),
      .rst_n        (rst_n),
      .async_inputs (async_inputs),
      .sync_inputs  (sync_inputs),
      .rise_edges   (rise_edges),
      .fall_edges   (fall_edges),
      .sync_inputs_view_1 (legacy_sync_inputs_view_1_unused),
      .rise_edges_view_1  (legacy_rise_edges_view_1_unused),
      .fall_edges_view_1  (legacy_fall_edges_view_1_unused),
      .sync_inputs_view_2 (legacy_sync_inputs_view_2_unused),
      .rise_edges_view_2  (legacy_rise_edges_view_2_unused),
      .fall_edges_view_2  (legacy_fall_edges_view_2_unused)
  );

  (* keep_hierarchy = "yes", dont_touch = "true" *)
  chimaera_input_bank loaded_bank (
      .clk          (clk),
      .rst_n        (rst_n),
      .async_inputs (async_inputs),
      .sync_inputs  (loaded_sync_inputs),
      .rise_edges   (loaded_rise_edges),
      .fall_edges   (loaded_fall_edges),
      .sync_inputs_view_1 (loaded_cell0_sync_inputs),
      .rise_edges_view_1  (loaded_cell0_rise_edges),
      .fall_edges_view_1  (loaded_cell0_fall_edges),
      .sync_inputs_view_2 (loaded_cell1_sync_inputs),
      .rise_edges_view_2  (loaded_cell1_rise_edges),
      .fall_edges_view_2  (loaded_cell1_fall_edges)
  );

  (* keep_hierarchy = "yes", dont_touch = "true" *)
  chimaera_input_bank execution_bank (
      .clk          (clk),
      .rst_n        (rst_n),
      .async_inputs (async_inputs),
      .sync_inputs  (execution_sync_inputs),
      .rise_edges   (execution_rise_edges),
      .fall_edges   (execution_fall_edges),
      .sync_inputs_view_1 (execution_sync_inputs_view_1_unused),
      .rise_edges_view_1  (execution_rise_edges_view_1_unused),
      .fall_edges_view_1  (execution_fall_edges_view_1_unused),
      .sync_inputs_view_2 (execution_sync_inputs_view_2_unused),
      .rise_edges_view_2  (execution_rise_edges_view_2_unused),
      .fall_edges_view_2  (execution_fall_edges_view_2_unused)
  );

endmodule

`default_nettype wire
