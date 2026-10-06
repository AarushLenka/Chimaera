`default_nettype none
`timescale 1ns / 1ps

module descriptor_selection_tb;
  reg [39:0] candidates;
  reg [6:0] decision;
  reg [31:0] memory [0:31];
  wire [1023:0] words;
  wire [31:0] data;
  wire [4:0] request_0 = decision[4] ? candidates[19:15] :
      decision[2] ? candidates[14:10] :
      decision[0] ? candidates[4:0] : candidates[9:5];
  wire [4:0] request_1 = decision[5] ? candidates[39:35] :
      decision[3] ? candidates[34:30] :
      decision[1] ? candidates[24:20] : candidates[29:25];
  wire [4:0] address = decision[6] ? request_1 : request_0;
  genvar row;
  generate
    for (row = 0; row < 32; row = row + 1) begin : pack_words
      assign words[row*32 +: 32] = memory[row];
    end
  endgenerate
  chimaera_descriptor_read_slice reader (
      .candidates(candidates), .decision(decision), .words(words), .data(data)
  );

  integer address_index;
  integer choice;
  integer candidate_index;
  integer checks = 0;
  initial begin
    // A known selected word must survive unknown unselected memory rows.
    memory[17] = 32'hcafef00d;
    candidates = {5'd31, 5'd30, 5'd29, 5'd28, 5'd17, 5'd2, 5'd1, 5'd0};
    decision = 7'b0010000;
    #1;
    if (data !== 32'hcafef00d)
      $fatal(1, "unknown unselected words contaminated the pending descriptor");
    decision = 7'd0;
    #1;
    if (data !== 32'hxxxxxxxx)
      $fatal(1, "an uninitialized selected descriptor lost its unknown value");

    for (address_index = 0; address_index < 32; address_index = address_index + 1)
      memory[address_index] = 32'h12345678 ^ (32'h01020408 * address_index);
    // Cover every decision combination, distinct and aliased candidates, and
    // every row in each candidate position. No random-seed dependence.
    for (address_index = 0; address_index < 32; address_index = address_index + 1) begin
      for (candidate_index = 0; candidate_index < 8; candidate_index = candidate_index + 1)
        candidates[candidate_index*5 +: 5] = 5'(address_index + candidate_index*3);
      for (choice = 0; choice < 128; choice = choice + 1) begin
        decision = choice[6:0];
        #1;
        if (data !== memory[address])
          $fatal(1, "candidate selection mismatch: candidates=%h decision=%b address=%d", candidates, decision, address);
        checks = checks + 1;
      end
      candidates = {8{address_index[4:0]}};
      for (choice = 0; choice < 128; choice = choice + 1) begin
        decision = choice[6:0];
        #1;
        if (data !== memory[address])
          $fatal(1, "aliased candidate selection mismatch");
        checks = checks + 1;
      end
    end
    $display("PASS: %0d candidate/decision reads and selected/unselected unknown-memory cases", checks);
    $finish;
  end
endmodule

`default_nettype wire
