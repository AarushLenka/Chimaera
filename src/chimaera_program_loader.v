/*
 * Chimaera Phase 5 descriptor memory and frame-level program loader.
 *
 * The serial configuration front end will present complete 32-bit frames here.
 * Keeping that pin sampler separate lets this block's ordering, CRC, bounds, and
 * halt/resume behavior be verified before asynchronous serial timing is added.
 */

`default_nettype none
`timescale 1ns / 1ps

// Preserve decoder/selector boundaries, so unused descriptor bits can still be
// removed when the read data is connected to the runtime at the top level.
/* verilator lint_off DECLFILENAME */
(* keep_hierarchy = "yes" *)
module chimaera_descriptor_decoder (
    input  wire [4:0]  address,
    output wire [31:0] select_row
);
  genvar row;
  generate
    for (row = 0; row < 32; row = row + 1) begin : decode_row
      assign select_row[row] = address == row[4:0];
    end
  endgenerate
endmodule

// One context's private descriptor selection. Decodes that context's four
// registered candidate addresses (event, alternate, timeout, pending) and
// applies only that context's own late decisions, in the production successor
// priority: pending, timeout, branch, then alternate. No cross-context
// arbitration signal exists on this path.
(* keep_hierarchy = "yes" *)
module chimaera_context_selector (
    input  wire [19:0] candidates,
    input  wire        pending,
    input  wire        fire_timeout,
    input  wire        branch_condition,
    output wire [31:0] select_row
);
  wire [31:0] decoded [0:3];
  genvar candidate;
  generate
    for (candidate = 0; candidate < 4; candidate = candidate + 1) begin : decode_candidate
      (* keep = "true", keep_hierarchy = "yes" *)
      chimaera_descriptor_decoder decoder (
          .address(candidates[candidate*5 +: 5]),
          .select_row(decoded[candidate])
      );
    end
  endgenerate
  // Candidates: event/alternate/timeout/pending successors for this context.
  assign select_row = pending ? decoded[3] :
      fire_timeout ? decoded[2] : branch_condition ? decoded[0] : decoded[1];
endmodule

// Decode stable successor candidates before late event/arbitration decisions.
// Preserve both boundaries: ABC may optimize each decoder and the selector,
// but cannot turn the path back into binary muxes followed by a row decoder.
// Retained for the standalone read-slice proof benches and the production
// shared-read reference used by the equivalence miter.
(* keep_hierarchy = "yes" *)
module chimaera_descriptor_selector (
    input  wire [39:0] candidates,
    input  wire [6:0]  decision,
    output wire [31:0] select_row
);
  wire [31:0] decoded [0:7];
  genvar candidate;
  generate
    for (candidate = 0; candidate < 8; candidate = candidate + 1) begin : decode_candidate
      (* keep = "true", keep_hierarchy = "yes" *)
      chimaera_descriptor_decoder decoder (
          .address(candidates[candidate*5 +: 5]),
          .select_row(decoded[candidate])
      );
    end
  endgenerate
  // Candidates: event/alternate/timeout/pending for context 0, then context 1.
  // Decisions: condition 0/1, timeout 0/1, pending 0/1, context-1 winner.
  wire [31:0] request_0 = decision[4] ? decoded[3] :
      decision[2] ? decoded[2] : decision[0] ? decoded[0] : decoded[1];
  wire [31:0] request_1 = decision[5] ? decoded[7] :
      decision[3] ? decoded[6] : decision[1] ? decoded[4] : decoded[5];
  assign select_row = decision[6] ? request_1 : request_0;
endmodule

// One combinational read slice. Each local select drives only READ_WIDTH bits.
/* verilator lint_off WIDTHTRUNC */
/* verilator lint_off UNUSEDSIGNAL */
module chimaera_descriptor_read_slice #(
    parameter integer READ_WIDTH = 32,
    parameter bit USE_SHARED_SELECT = 1'b0
) (
    input  wire [39:0]                  candidates,
    input  wire [6:0]                   decision,
    input  wire [31:0]                  shared_select_row,
    input  wire [32*READ_WIDTH-1:0]     words,
    output wire [READ_WIDTH-1:0]        data
);
  wire [31:0] select_row;
  wire [READ_WIDTH-1:0] selected [0:31];
  wire [READ_WIDTH-1:0] pairs [0:15];
  wire [READ_WIDTH-1:0] quads [0:7];
  wire [READ_WIDTH-1:0] octets [0:3];
  wire [READ_WIDTH-1:0] halves [0:1];

  generate
    if (USE_SHARED_SELECT) begin : external_selector
      assign select_row = shared_select_row;
    end else begin : local_selector
      // Standalone proof and simulation use the original self-contained form.
      // Production slices share selectors in pairs to reduce replicated logic.
      (* keep = "true", keep_hierarchy = "yes" *)
      chimaera_descriptor_selector selector (
          .candidates(candidates),
          .decision(decision),
          .select_row(select_row)
      );
    end
  endgenerate

  genvar row;
  generate
    for (row = 0; row < 32; row = row + 1) begin : decode_row
      assign selected[row] = words[row*READ_WIDTH +: READ_WIDTH] &
                             {READ_WIDTH{select_row[row]}};
    end
    for (row = 0; row < 16; row = row + 1) begin : reduce_pairs
      assign pairs[row] = selected[2*row] | selected[2*row+1];
    end
    for (row = 0; row < 8; row = row + 1) begin : reduce_quads
      assign quads[row] = pairs[2*row] | pairs[2*row+1];
    end
    for (row = 0; row < 4; row = row + 1) begin : reduce_octets
      assign octets[row] = quads[2*row] | quads[2*row+1];
    end
    for (row = 0; row < 2; row = row + 1) begin : reduce_halves
      assign halves[row] = octets[2*row] | octets[2*row+1];
    end
  endgenerate
  assign data = halves[0] | halves[1];
endmodule
/* verilator lint_on UNUSEDSIGNAL */
/* verilator lint_on WIDTHTRUNC */
/* verilator lint_on DECLFILENAME */

module chimaera_program_loader (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         frame_strobe,
    input  wire [31:0]  frame_data,

    input  wire [39:0]  descriptor_candidates,
    input  wire [5:0]   descriptor_decision,
    output wire [255:0] descriptor_data,

    output reg  [4:0]   context_entry_0,
    output reg  [4:0]   context_entry_1,
    output reg  [1:0]   context_enable,
    output reg  [7:0]   open_drain_mask,
    output reg          program_valid,
    output reg          execution_halted,
    output reg          load_error,
    output wire         load_in_progress,
    output reg  [5:0]   loaded_descriptor_count,
    output reg  [15:0]  computed_crc,
    output reg  [15:0]  fault_seed,
    output wire [127:0] mutation_config_0,
    output wire [127:0] mutation_config_1,
    output wire [127:0] contract_config_0,
    output wire [127:0] contract_config_1
);

  localparam [3:0] OP_BEGIN            = 4'h0;
  localparam [3:0] OP_WRITE_DESCRIPTOR = 4'h1;
  localparam [3:0] OP_SET_CONTEXT      = 4'h2;
  localparam [3:0] OP_CONTROL          = 4'h3;
  localparam [3:0] OP_SET_PIN_MODES    = 4'h4;
  localparam [3:0] OP_SET_FAULT_SEED   = 4'h5;
  localparam [3:0] OP_WRITE_MUTATION   = 4'h6;
  localparam [3:0] OP_WRITE_CONTRACT   = 4'h7;
  localparam [3:0] OP_COMMIT           = 4'he;
  localparam integer DESCRIPTOR_READ_WIDTH = 32;

  reg [127:0] descriptor_memory [0:31];
  reg         load_active;
  reg [4:0]   expected_state;
  reg [2:0]   expected_word;
  reg [4:0]   highest_target;
  reg [31:0]  mutation_memory_0 [0:3];
  reg [31:0]  mutation_memory_1 [0:3];
  reg [31:0]  contract_memory_0 [0:3];
  reg [31:0]  contract_memory_1 [0:3];
  integer mutation_index;

  wire [3:0]  frame_opcode = frame_data[31:28];
  wire        frame_context = frame_data[27];
  wire [4:0]  frame_address = frame_data[26:22];
  wire [2:0]  frame_word = frame_data[21:19];
  wire [15:0] frame_payload = frame_data[15:0];
  wire [5:0]  commit_count = {1'b0, frame_address} + 6'd1;

  // Two independent per-context read buses share the 32 x 128-bit storage
  // and its single write port. Each context owns
  // two 32-bit-row selector banks (four early decoders each); every bank feeds
  // two adjacent 32-bit slices of that context's bus, keeping row-select
  // fanout bounded. The pending-first grants (load_0/load_1) live in the
  // runtime and never select descriptor data.
  genvar context_index;
  genvar bank;
  genvar slice;
  genvar descriptor;
  wire [31:0] context_select_row [0:3];
  generate
    for (context_index = 0; context_index < 2; context_index = context_index + 1) begin : context_read
      for (bank = 0; bank < 2; bank = bank + 1) begin : selector_bank
        (* keep = "true", keep_hierarchy = "yes" *)
        chimaera_context_selector selector (
            .candidates(descriptor_candidates[context_index*20 +: 20]),
            .pending(descriptor_decision[context_index+4]),
            .fire_timeout(descriptor_decision[context_index+2]),
            .branch_condition(descriptor_decision[context_index]),
            .select_row(context_select_row[context_index*2+bank])
        );
      end
      for (slice = 0; slice < 128/DESCRIPTOR_READ_WIDTH; slice = slice + 1) begin : read_slice
        wire [32*DESCRIPTOR_READ_WIDTH-1:0] slice_words;
        for (descriptor = 0; descriptor < 32; descriptor = descriptor + 1) begin : pack_words
          assign slice_words[descriptor*DESCRIPTOR_READ_WIDTH +: DESCRIPTOR_READ_WIDTH] =
              descriptor_memory[descriptor][slice*DESCRIPTOR_READ_WIDTH +: DESCRIPTOR_READ_WIDTH];
        end
        chimaera_descriptor_read_slice #(
            .READ_WIDTH(DESCRIPTOR_READ_WIDTH),
            .USE_SHARED_SELECT(1)
        ) reader (
            .candidates(40'b0),
            .decision(7'b0),
            .shared_select_row(context_select_row[context_index*2+slice/2]),
            .words(slice_words),
            .data(descriptor_data[context_index*128 + slice*DESCRIPTOR_READ_WIDTH +: DESCRIPTOR_READ_WIDTH])
        );
      end
    end
  endgenerate
  assign load_in_progress = load_active;
  assign mutation_config_0 = {
      mutation_memory_0[3], mutation_memory_0[2],
      mutation_memory_0[1], mutation_memory_0[0]
  };
  assign mutation_config_1 = {
      mutation_memory_1[3], mutation_memory_1[2],
      mutation_memory_1[1], mutation_memory_1[0]
  };
  assign contract_config_0 = {
      contract_memory_0[3], contract_memory_0[2],
      contract_memory_0[1], contract_memory_0[0]
  };
  assign contract_config_1 = {
      contract_memory_1[3], contract_memory_1[2],
      contract_memory_1[1], contract_memory_1[0]
  };

  function [15:0] crc16_byte;
    input [15:0] crc_in;
    input [7:0] data_in;
    integer bit_index;
    reg [15:0] crc_work;
    begin
      crc_work = crc_in ^ {data_in, 8'h00};
      for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
        if (crc_work[15])
          crc_work = {crc_work[14:0], 1'b0} ^ 16'h1021;
        else
          crc_work = {crc_work[14:0], 1'b0};
      end
      crc16_byte = crc_work;
    end
  endfunction

  function [15:0] crc16_word;
    input [15:0] crc_in;
    input [15:0] data_in;
    begin
      crc16_word = crc16_byte(crc16_byte(crc_in, data_in[15:8]), data_in[7:0]);
    end
  endfunction

  always @(posedge clk) begin
    if (!rst_n) begin
      context_entry_0        <= 5'd0;
      context_entry_1        <= 5'd0;
      context_enable         <= 2'b00;
      open_drain_mask        <= 8'h00;
      program_valid          <= 1'b0;
      execution_halted       <= 1'b1;
      load_error             <= 1'b0;
      loaded_descriptor_count<= 6'd0;
      computed_crc           <= 16'hffff;
      load_active            <= 1'b0;
      expected_state         <= 5'd0;
      expected_word          <= 3'd0;
      highest_target         <= 5'd0;
      fault_seed             <= 16'h0001;
      for (mutation_index = 0; mutation_index < 4; mutation_index = mutation_index + 1) begin
        mutation_memory_0[mutation_index] <= 32'h00000000;
        mutation_memory_1[mutation_index] <= 32'h00000000;
        contract_memory_0[mutation_index] <= 32'h00000000;
        contract_memory_1[mutation_index] <= 32'h00000000;
      end
    end else if (frame_strobe) begin
      if (frame_data[18:16] != 3'b000) begin
        load_error <= 1'b1;
      end else case (frame_opcode)
        OP_BEGIN: begin
          context_entry_0         <= 5'd0;
          context_entry_1         <= 5'd0;
          context_enable          <= 2'b00;
          open_drain_mask         <= 8'h00;
          program_valid           <= 1'b0;
          execution_halted        <= 1'b1;
          load_error              <= 1'b0;
          loaded_descriptor_count <= 6'd0;
          computed_crc            <= 16'hffff;
          load_active             <= 1'b1;
          expected_state          <= 5'd0;
          expected_word           <= 3'd0;
          highest_target          <= 5'd0;
          fault_seed              <= 16'h0001;
          for (mutation_index = 0; mutation_index < 4; mutation_index = mutation_index + 1) begin
            mutation_memory_0[mutation_index] <= 32'h00000000;
            mutation_memory_1[mutation_index] <= 32'h00000000;
            contract_memory_0[mutation_index] <= 32'h00000000;
            contract_memory_1[mutation_index] <= 32'h00000000;
          end
        end

        OP_WRITE_DESCRIPTOR: begin
          if (!load_active || load_error ||
              frame_address != expected_state || frame_word != expected_word) begin
            load_error <= 1'b1;
          end else begin
            descriptor_memory[frame_address][frame_word * 16 +: 16] <= frame_payload;
            computed_crc <= crc16_word(computed_crc, frame_payload);
            // Targets straddle descriptor words 5 and 6. Retaining only the
            // largest target permits a constant-cost structural check at
            // COMMIT without a second memory read port or a scan state.
            if (expected_word == 3'd5 && frame_payload[15:11] > highest_target)
              highest_target <= frame_payload[15:11];
            if (expected_word == 3'd6) begin
              if (frame_payload[4:0] > highest_target &&
                  frame_payload[4:0] >= frame_payload[9:5])
                highest_target <= frame_payload[4:0];
              else if (frame_payload[9:5] > highest_target)
                highest_target <= frame_payload[9:5];
            end
            if (expected_word == 3'd7) begin
              expected_word <= 3'd0;
              expected_state <= expected_state + 5'd1;
              loaded_descriptor_count <= loaded_descriptor_count + 6'd1;
            end else begin
              expected_word <= expected_word + 3'd1;
            end
          end
        end

        OP_SET_CONTEXT: begin
          if (!load_active || load_error || frame_payload[15:6] != 10'd0) begin
            load_error <= 1'b1;
          end else if (!frame_context) begin
            context_entry_0 <= frame_payload[4:0];
            context_enable[0] <= frame_payload[5];
          end else begin
            context_entry_1 <= frame_payload[4:0];
            context_enable[1] <= frame_payload[5];
          end
        end

        OP_COMMIT: begin
          if (!load_active || load_error || !context_enable[0] ||
              loaded_descriptor_count != commit_count ||
              expected_word != 3'd0 ||
              computed_crc != frame_payload ||
              {1'b0, highest_target} >= commit_count ||
              (context_enable[0] && {1'b0, context_entry_0} >= commit_count) ||
              (context_enable[1] && {1'b0, context_entry_1} >= commit_count)) begin
            load_error <= 1'b1;
            program_valid <= 1'b0;
          end else begin
            load_active <= 1'b0;
            load_error <= 1'b0;
            program_valid <= 1'b1;
            execution_halted <= 1'b1;
          end
        end

        OP_CONTROL: begin
          if (frame_payload[15:1] != 15'd0 || (frame_payload[0] && !program_valid)) begin
            load_error <= 1'b1;
          end else begin
            execution_halted <= ~frame_payload[0];
          end
        end

        OP_SET_PIN_MODES: begin
          if (!load_active || load_error || frame_payload[15:8] != 8'h00) begin
            load_error <= 1'b1;
          end else begin
            open_drain_mask <= frame_payload[7:0];
          end
        end

        OP_SET_FAULT_SEED: begin
          if (!load_active || load_error || frame_context ||
              frame_address != 5'd0 || frame_word != 3'd0 ||
              frame_payload == 16'h0000) begin
            load_error <= 1'b1;
          end else begin
            fault_seed <= frame_payload;
          end
        end

        OP_WRITE_MUTATION: begin
          if (!load_active || load_error || frame_address >= 5'd4 ||
              frame_word >= 3'd2) begin
            load_error <= 1'b1;
          end else if (!frame_context) begin
            if (frame_word == 3'd0)
              mutation_memory_0[frame_address[1:0]][31:16] <= frame_payload;
            else
              mutation_memory_0[frame_address[1:0]][15:0] <= frame_payload;
          end else begin
            if (frame_word == 3'd0)
              mutation_memory_1[frame_address[1:0]][31:16] <= frame_payload;
            else
              mutation_memory_1[frame_address[1:0]][15:0] <= frame_payload;
          end
        end

        OP_WRITE_CONTRACT: begin
          if (!load_active || load_error || frame_address >= 5'd4 ||
              frame_word >= 3'd2) begin
            load_error <= 1'b1;
          end else if (!frame_context) begin
            if (frame_word == 3'd0)
              contract_memory_0[frame_address[1:0]][31:16] <= frame_payload;
            else
              contract_memory_0[frame_address[1:0]][15:0] <= frame_payload;
          end else begin
            if (frame_word == 3'd0)
              contract_memory_1[frame_address[1:0]][31:16] <= frame_payload;
            else
              contract_memory_1[frame_address[1:0]][15:0] <= frame_payload;
          end
        end

        default: begin
          load_error <= 1'b1;
        end
      endcase
    end
  end

endmodule

`default_nettype wire
