`default_nettype none
// All registered state and configuration are arbitrary. Compare the two
// precomputed branch predicates with the original sampled-byte computation.
module branch_lookahead_equiv (
    input wire [7:0] current_shift,
    input wire [7:0] sample,
    input wire [3:0] count_after,
    input wire [34:0] control,
    input wire [127:0] mutation_config,
    input wire [15:0] fault_lfsr,
    output wire equivalent
);
  wire [1:0] condition_by_sample;
  chimaera_branch_predicate predicate (
      .current_shift(current_shift), .count_after(count_after),
      .control(control), .mutation_config(mutation_config),
      .fault_lfsr(fault_lfsr), .condition_by_sample(condition_by_sample)
  );
  wire candidate_condition = (|sample) ? condition_by_sample[1] : condition_by_sample[0];

  // Original next_shift and corruption loop from 39c1395. Retain the serial
  // application of masks and the original enable predicate as the reference.
  reg [7:0] shift_after;
  reg [7:0] faulted_shift;
  integer slot;
  always @(*) begin
    shift_after = current_shift;
    if (control[31])
      shift_after = 8'h00;
    if (control[32])
      shift_after = control[28:21];
    case (control[34:33])
      2'd1: shift_after = {shift_after[6:0], |sample};
      2'd2: shift_after = {1'b0, shift_after[7:1]};
      default: shift_after = shift_after;
    endcase
    faulted_shift = shift_after;
    for (slot = 0; slot < 4; slot = slot + 1) begin
      if (mutation_config[slot*32+31] &&
          mutation_config[slot*32+24 +: 4] == 4'd1 &&
          shift_after == mutation_config[slot*32+16 +: 8] &&
          (((mutation_config[slot*32+28 +: 3] >= 3'd3) &&
            (mutation_config[slot*32+3 +: 5] == 5'd0)) ||
           ((mutation_config[slot*32+28 +: 3] < 3'd3) &&
            (fault_lfsr[7:0] ^ fault_lfsr[15:8]) <= mutation_config[slot*32 +: 8]))) begin
        if (mutation_config[slot*32+28 +: 3] == 3'd1)
          faulted_shift = faulted_shift ^ mutation_config[slot*32+8 +: 8];
      end
    end
  end
  wire reference_condition =
      (!control[15] || count_after == control[19:16]) &&
      (!control[20] || faulted_shift == control[28:21]);
  assign equivalent = candidate_condition == reference_condition;
endmodule
`default_nettype wire
