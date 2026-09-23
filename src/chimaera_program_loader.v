/*
 * Chimaera Phase 5 descriptor memory and frame-level program loader.
 *
 * The serial configuration front end will present complete 32-bit frames here.
 * Keeping that pin sampler separate lets this block's ordering, CRC, bounds, and
 * halt/resume behavior be verified before asynchronous serial timing is added.
 */

`default_nettype none
`timescale 1ns / 1ps

module chimaera_program_loader (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         frame_strobe,
    input  wire [31:0]  frame_data,

    input  wire [4:0]   descriptor_address,
    output wire [127:0] descriptor_data,

    output reg  [4:0]   context_entry_0,
    output reg  [4:0]   context_entry_1,
    output reg  [1:0]   context_enable,
    output reg  [7:0]   open_drain_mask,
    output reg          program_valid,
    output reg          execution_halted,
    output reg          load_error,
    output wire         load_in_progress,
    output reg  [5:0]   loaded_descriptor_count,
    output reg  [15:0]  computed_crc
);

  localparam [3:0] OP_BEGIN            = 4'h0;
  localparam [3:0] OP_WRITE_DESCRIPTOR = 4'h1;
  localparam [3:0] OP_SET_CONTEXT      = 4'h2;
  localparam [3:0] OP_CONTROL          = 4'h3;
  localparam [3:0] OP_SET_PIN_MODES    = 4'h4;
  localparam [3:0] OP_COMMIT           = 4'he;

  reg [127:0] descriptor_memory [0:31];
  reg         load_active;
  reg [4:0]   expected_state;
  reg [2:0]   expected_word;
  reg [4:0]   highest_target;

  wire [3:0]  frame_opcode = frame_data[31:28];
  wire        frame_context = frame_data[27];
  wire [4:0]  frame_address = frame_data[26:22];
  wire [2:0]  frame_word = frame_data[21:19];
  wire [15:0] frame_payload = frame_data[15:0];
  wire [5:0]  commit_count = {1'b0, frame_address} + 6'd1;

  assign descriptor_data = descriptor_memory[descriptor_address];
  assign load_in_progress = load_active;

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

        default: begin
          load_error <= 1'b1;
        end
      endcase
    end
  end

endmodule

`default_nettype wire
