/*
 * Chimaera asynchronous-input front end.
 *
 * External pins pass through two flip-flops before edge detection.  Reaction
 * latency is therefore specified from sync_inputs/rise_edges/fall_edges, not
 * directly from the asynchronous package pins.
 */

`default_nettype none
`timescale 1ns / 1ps

// The synchronizer is split into a first-stage sampler and a consumer bank.
// The loaded runtime can therefore share one metastability-catching sample
// while keeping its second-stage launch points physically separate.
/* verilator lint_off DECLFILENAME */
(* keep_hierarchy = "yes" *)
module chimaera_input_sync_stage (
    input  wire       clk,
    input  wire       rst_n,
    input  wire [7:0] async_inputs,
    output wire [7:0] sync_meta
);

  (* keep = "true", dont_touch = "true" *) reg [7:0] sync_meta_reg;

  always @(posedge clk) begin
    if (!rst_n)
      sync_meta_reg <= 8'hff;
    else
      sync_meta_reg <= async_inputs;
  end

  assign sync_meta = sync_meta_reg;

endmodule

(* keep_hierarchy = "yes" *)
module chimaera_input_consumer_bank (
    input  wire       clk,
    input  wire       rst_n,
    input  wire [7:0] sync_meta,
    output wire [7:0] sync_inputs,
    output wire [7:0] rise_edges,
    output wire [7:0] fall_edges
);

  (* keep = "true", dont_touch = "true" *) reg [7:0] sync_value;
  (* keep = "true", dont_touch = "true" *) reg [7:0] sync_previous;

  always @(posedge clk) begin
    if (!rst_n) begin
      sync_value    <= 8'hff;
      sync_previous <= 8'hff;
    end else begin
      sync_value    <= sync_meta;
      sync_previous <= sync_value;
    end
  end

  assign sync_inputs = sync_value;
  assign rise_edges  = sync_value & ~sync_previous;
  assign fall_edges  = ~sync_value & sync_previous;

endmodule

(* keep_hierarchy = "yes" *)
module chimaera_input_bank (
    input  wire       clk,
    input  wire       rst_n,
    input  wire [7:0] async_inputs,
    output wire [7:0] sync_inputs,
    output wire [7:0] rise_edges,
    output wire [7:0] fall_edges
);

  wire [7:0] sync_meta;

  // Preserve the bank boundary, but leave its mapped cells/net loading
  // available to physical timing and electrical repair.
  (* keep_hierarchy = "yes" *)
  chimaera_input_sync_stage stage1 (
      .clk          (clk),
      .rst_n        (rst_n),
      .async_inputs (async_inputs),
      .sync_meta    (sync_meta)
  );

  (* keep_hierarchy = "yes" *)
  chimaera_input_consumer_bank consumer (
      .clk          (clk),
      .rst_n        (rst_n),
      .sync_meta    (sync_meta),
      .sync_inputs  (sync_inputs),
      .rise_edges   (rise_edges),
      .fall_edges   (fall_edges)
  );

endmodule
/* verilator lint_on DECLFILENAME */

module chimaera_input_frontend (
    input  wire       clk,
    input  wire       rst_n,
    input  wire [7:0] async_inputs,

    // The original ports remain the legacy reaction-path interface.  The
    // loaded runtime shares one first-stage sample, then uses three preserved
    // consumer banks so no second-stage bus is broadcast across its cones.
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

  wire [7:0] loaded_sync_meta;

  // Keep each consumer bank as a separate hierarchy boundary. The loaded
  // first-stage output is shared, so all loaded views remain cycle-aligned.
  (* keep_hierarchy = "yes" *)
  chimaera_input_bank legacy_bank (
      .clk          (clk),
      .rst_n        (rst_n),
      .async_inputs (async_inputs),
      .sync_inputs  (sync_inputs),
      .rise_edges   (rise_edges),
      .fall_edges   (fall_edges)
  );

  (* keep_hierarchy = "yes" *)
  chimaera_input_sync_stage loaded_stage1 (
      .clk          (clk),
      .rst_n        (rst_n),
      .async_inputs (async_inputs),
      .sync_meta    (loaded_sync_meta)
  );

  (* keep_hierarchy = "yes" *)
  chimaera_input_consumer_bank loaded_bank (
      .clk          (clk),
      .rst_n        (rst_n),
      .sync_meta    (loaded_sync_meta),
      .sync_inputs  (loaded_sync_inputs),
      .rise_edges   (loaded_rise_edges),
      .fall_edges   (loaded_fall_edges)
  );

  (* keep_hierarchy = "yes" *)
  chimaera_input_consumer_bank loaded_cell0_bank (
      .clk          (clk),
      .rst_n        (rst_n),
      .sync_meta    (loaded_sync_meta),
      .sync_inputs  (loaded_cell0_sync_inputs),
      .rise_edges   (loaded_cell0_rise_edges),
      .fall_edges   (loaded_cell0_fall_edges)
  );

  (* keep_hierarchy = "yes" *)
  chimaera_input_consumer_bank loaded_cell1_bank (
      .clk          (clk),
      .rst_n        (rst_n),
      .sync_meta    (loaded_sync_meta),
      .sync_inputs  (loaded_cell1_sync_inputs),
      .rise_edges   (loaded_cell1_rise_edges),
      .fall_edges   (loaded_cell1_fall_edges)
  );

  (* keep_hierarchy = "yes" *)
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
