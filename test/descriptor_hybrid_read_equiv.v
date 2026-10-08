`default_nettype none
`timescale 1ns / 1ps

// Prove the hybrid read topology against the original eight-candidate
// selector. The shared final bus may choose either context, but only after
// each context has decoded its own four registered candidates. The proof is
// for one 32-bit slice; the production generate repeats the same slice wiring
// across all four descriptor words.
module descriptor_hybrid_read_equiv (
    input  wire [39:0]   candidates,
    input  wire [5:0]    decision,
    input  wire          select_request_1,
    input  wire [1023:0] words,
    output wire          equivalent
);
  wire [31:0] context_row_0;
  wire [31:0] context_row_1;
  wire [31:0] selected_row;
  wire [31:0] hybrid_data;
  wire [31:0] reference_data_0;
  wire [31:0] reference_data_1;
  wire [31:0] reference_data;

  chimaera_context_selector context_selector_0 (
      .candidates(candidates[19:0]),
      .pending(decision[4]),
      .fire_timeout(decision[2]),
      .branch_condition(decision[0]),
      .select_row(context_row_0)
  );
  chimaera_context_selector context_selector_1 (
      .candidates(candidates[39:20]),
      .pending(decision[5]),
      .fire_timeout(decision[3]),
      .branch_condition(decision[1]),
      .select_row(context_row_1)
  );

  assign selected_row = select_request_1 ? context_row_1 : context_row_0;

  chimaera_descriptor_read_slice #(
      .READ_WIDTH(32),
      .USE_SHARED_SELECT(1)
  ) hybrid_reader (
      .candidates(40'b0),
      .decision(7'b0),
      .shared_select_row(selected_row),
      .words(words),
      .data(hybrid_data)
  );

  // The original production selector is used as the reference for each
  // context and each slice. Its context winner bit is forced independently.
  chimaera_descriptor_read_slice #(
      .READ_WIDTH(32),
      .USE_SHARED_SELECT(0)
  ) reference_reader_0 (
      .candidates(candidates),
      .decision({1'b0, decision}),
      .shared_select_row(32'b0),
      .words(words),
      .data(reference_data_0)
  );
  chimaera_descriptor_read_slice #(
      .READ_WIDTH(32),
      .USE_SHARED_SELECT(0)
  ) reference_reader_1 (
      .candidates(candidates),
      .decision({1'b1, decision}),
      .shared_select_row(32'b0),
      .words(words),
      .data(reference_data_1)
  );

  assign reference_data = select_request_1 ? reference_data_1 : reference_data_0;
  assign equivalent = hybrid_data == reference_data;
endmodule

`default_nettype wire
