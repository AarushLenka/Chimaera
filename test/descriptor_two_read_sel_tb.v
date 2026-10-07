`default_nettype none
`timescale 1ns / 1ps

module descriptor_two_read_sel_tb;
  reg [19:0] candidates_0;
  reg [19:0] candidates_1;
  reg pending_0;
  reg pending_1;
  reg timeout_0;
  reg timeout_1;
  reg branch_0;
  reg branch_1;
  wire [31:0] select_row_0;
  wire [31:0] select_row_1;
  reg [255:0] words;
  wire [7:0] data_0;
  wire [7:0] data_1;

  chimaera_descriptor_read_slice #(.READ_WIDTH(8), .USE_SHARED_SELECT(1)) reader_0 (
      .candidates(40'b0), .decision(7'b0), .shared_select_row(select_row_0),
      .words(words), .data(data_0)
  );
  chimaera_descriptor_read_slice #(.READ_WIDTH(8), .USE_SHARED_SELECT(1)) reader_1 (
      .candidates(40'b0), .decision(7'b0), .shared_select_row(select_row_1),
      .words(words), .data(data_1)
  );

  chimaera_context_selector selector_0 (
      .candidates(candidates_0),
      .pending(pending_0),
      .fire_timeout(timeout_0),
      .branch_condition(branch_0),
      .select_row(select_row_0)
  );
  chimaera_context_selector selector_1 (
      .candidates(candidates_1),
      .pending(pending_1),
      .fire_timeout(timeout_1),
      .branch_condition(branch_1),
      .select_row(select_row_1)
  );

  integer address_index;
  integer choice;
  integer checks;
  reg [4:0] expected;

  function [4:0] candidate_at;
    input [19:0] candidate_bus;
    input integer index;
    begin
      candidate_at = candidate_bus[index*5 +: 5];
    end
  endfunction

  task check_context;
    input [19:0] candidate_bus;
    input pending;
    input timeout;
    input branch;
    input [31:0] selected;
    input integer context_id;
    begin
      if (pending)
        expected = candidate_at(candidate_bus, 3);
      else if (timeout)
        expected = candidate_at(candidate_bus, 2);
      else if (branch)
        expected = candidate_at(candidate_bus, 0);
      else
        expected = candidate_at(candidate_bus, 1);
      if (selected !== (32'b1 << expected)) begin
        $display("FAIL: context %0d priority mismatch pending=%b timeout=%b branch=%b expected=%0d row=%h",
                 context_id, pending, timeout, branch, expected, selected);
        $fatal(1);
      end
      checks = checks + 1;
    end
  endtask

  initial begin
    checks = 0;
    candidates_0 = {5'd31, 5'd23, 5'd15, 5'd7};
    candidates_1 = {5'd30, 5'd22, 5'd14, 5'd6};

    // Cover every address in every candidate position.  The two contexts use
    // different rows so a swapped bus or context index is caught as well.
    for (address_index = 0; address_index < 32; address_index = address_index + 1) begin
      candidates_0[4:0]   = address_index[4:0];
      candidates_0[9:5]   = (address_index + 1) & 31;
      candidates_0[14:10] = (address_index + 2) & 31;
      candidates_0[19:15] = (address_index + 3) & 31;
      candidates_1[4:0]   = (address_index + 4) & 31;
      candidates_1[9:5]   = (address_index + 5) & 31;
      candidates_1[14:10] = (address_index + 6) & 31;
      candidates_1[19:15] = (address_index + 7) & 31;
      for (choice = 0; choice < 8; choice = choice + 1) begin
        branch_0  = choice[0];
        timeout_0 = choice[1];
        pending_0 = choice[2];
        branch_1  = ~choice[0];
        timeout_1 = ~choice[1];
        pending_1 = ~choice[2];
        #1;
        check_context(candidates_0, pending_0, timeout_0, branch_0,
                      select_row_0, 0);
        check_context(candidates_1, pending_1, timeout_1, branch_1,
                      select_row_1, 1);
      end
    end

    // Aliased candidates still obey the same priority and produce exactly one
    // selected row; this catches accidental OR-based priority implementation.
    candidates_0 = {4{5'd9}};
    candidates_1 = {4{5'd18}};
    for (choice = 0; choice < 8; choice = choice + 1) begin
      branch_0 = choice[0]; timeout_0 = choice[1]; pending_0 = choice[2];
      branch_1 = choice[0]; timeout_1 = choice[1]; pending_1 = choice[2];
      #1;
      check_context(candidates_0, pending_0, timeout_0, branch_0,
                    select_row_0, 0);
      check_context(candidates_1, pending_1, timeout_1, branch_1,
                    select_row_1, 1);
    end

    // Unwritten rows must not poison either known private read. A selected
    // unknown row must propagate only to the context reading that row.
    words = {256{1'bx}};
    words[9*8 +: 8] = 8'ha5;
    words[18*8 +: 8] = 8'h5a;
    #1;
    if (data_0 !== 8'ha5 || data_1 !== 8'h5a)
      $fatal(1, "unselected unknown rows poisoned a private read");
    words[9*8 +: 8] = 8'hxx;
    #1;
    if (data_0 !== 8'hxx || data_1 !== 8'h5a)
      $fatal(1, "selected unknown row leaked between contexts");

    $display("PASS: %0d per-context selections and priority cases; selected/unselected unknown rows", checks);
    $finish;
  end
endmodule

`default_nettype wire
