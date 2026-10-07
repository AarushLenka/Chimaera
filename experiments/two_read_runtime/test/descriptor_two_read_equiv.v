`default_nettype none
`timescale 1ns / 1ps

// Compare each private context bus with the existing production selector for
// the same context. The proof leaves all candidate addresses, six local
// decisions, and 4,096 bits of descriptor storage unconstrained.
module descriptor_two_read_equiv (
    input  wire [39:0]   candidates,
    input  wire [5:0]    decision,
    input  wire [4095:0] words,
    output wire          equivalent
);
  wire [127:0] shared_data_0;
  wire [127:0] shared_data_1;
  wire [127:0] local_data_0;
  wire [127:0] local_data_1;
  wire [31:0] local_select_0;
  wire [31:0] local_select_1;

  // The production selector sees the same local decisions with its grant
  // forced to context 0 or context 1, respectively.
  chimaera_descriptor_read_slice #(
      .READ_WIDTH(128), .USE_SHARED_SELECT(0)
  ) shared_reader_0 (
      .candidates(candidates),
      .decision({1'b0, decision}),
      .shared_select_row(32'b0),
      .words(words),
      .data(shared_data_0)
  );
  chimaera_descriptor_read_slice #(
      .READ_WIDTH(128), .USE_SHARED_SELECT(0)
  ) shared_reader_1 (
      .candidates(candidates),
      .decision({1'b1, decision}),
      .shared_select_row(32'b0),
      .words(words),
      .data(shared_data_1)
  );

  chimaera_context_selector local_selector_0 (
      .candidates(candidates[19:0]),
      .pending(decision[4]),
      .fire_timeout(decision[2]),
      .branch_condition(decision[0]),
      .select_row(local_select_0)
  );
  chimaera_context_selector local_selector_1 (
      .candidates(candidates[39:20]),
      .pending(decision[5]),
      .fire_timeout(decision[3]),
      .branch_condition(decision[1]),
      .select_row(local_select_1)
  );
  chimaera_descriptor_read_slice #(
      .READ_WIDTH(128), .USE_SHARED_SELECT(1)
  ) local_reader_0 (
      .candidates(40'b0), .decision(7'b0),
      .shared_select_row(local_select_0), .words(words), .data(local_data_0)
  );
  chimaera_descriptor_read_slice #(
      .READ_WIDTH(128), .USE_SHARED_SELECT(1)
  ) local_reader_1 (
      .candidates(40'b0), .decision(7'b0),
      .shared_select_row(local_select_1), .words(words), .data(local_data_1)
  );

  assign equivalent = (shared_data_0 == local_data_0) &&
                       (shared_data_1 == local_data_1);
endmodule

`default_nettype wire
