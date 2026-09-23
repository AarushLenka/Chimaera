/* Shared counter/shift bookkeeping for compiler-loaded descriptors. */

`default_nettype none
`timescale 1ns / 1ps

module chimaera_generic_execution_engine (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        fire_0,
    input  wire        fire_timeout_0,
    input  wire [7:0]  fire_sample_0,
    input  wire [34:0] control_0,
    output wire [4:0]  next_state_0,
    output wire [7:0]  current_shift_0,
    output wire [7:0]  post_shift_0,

    input  wire        fire_1,
    input  wire        fire_timeout_1,
    input  wire [7:0]  fire_sample_1,
    input  wire [34:0] control_1,
    output wire [4:0]  next_state_1,
    output wire [7:0]  current_shift_1,
    output wire [7:0]  post_shift_1
);

  reg [7:0] shift_0;
  reg [7:0] shift_1;
  reg [3:0] count_0;
  reg [3:0] count_1;

  wire [7:0] shift_after_0;
  wire [7:0] shift_after_1;
  wire [3:0] count_after_0;
  wire [3:0] count_after_1;
  wire condition_0;
  wire condition_1;

  function [7:0] next_shift;
    input [7:0] current;
    input [7:0] sample;
    input shift_reset;
    input shift_load;
    input [7:0] shift_literal;
    input [1:0] serial_mode;
    reg [7:0] work;
    begin
      work = current;
      if (shift_reset)
        work = 8'h00;
      if (shift_load)
        work = shift_literal;
      case (serial_mode)
        2'd1: work = {work[6:0], |sample};
        2'd2: work = {1'b0, work[7:1]};
        default: work = work;
      endcase
      next_shift = work;
    end
  endfunction

  function [3:0] next_count;
    input [3:0] current;
    input count_reset;
    input count_increment;
    reg [3:0] work;
    begin
      work = count_reset ? 4'd0 : current;
      if (count_increment)
        work = work + 4'd1;
      next_count = work;
    end
  endfunction

  assign shift_after_0 = next_shift(
      shift_0, fire_sample_0, control_0[31], control_0[32],
      control_0[28:21], control_0[34:33]);
  assign shift_after_1 = next_shift(
      shift_1, fire_sample_1, control_1[31], control_1[32],
      control_1[28:21], control_1[34:33]);
  assign count_after_0 = next_count(count_0, control_0[30], control_0[29]);
  assign count_after_1 = next_count(count_1, control_1[30], control_1[29]);

  assign condition_0 = (!control_0[15] || count_after_0 == control_0[19:16]) &&
                       (!control_0[20] || shift_after_0 == control_0[28:21]);
  assign condition_1 = (!control_1[15] || count_after_1 == control_1[19:16]) &&
                       (!control_1[20] || shift_after_1 == control_1[28:21]);

  assign next_state_0 = fire_timeout_0 ? control_0[14:10] :
                        condition_0 ? control_0[4:0] : control_0[9:5];
  assign next_state_1 = fire_timeout_1 ? control_1[14:10] :
                        condition_1 ? control_1[4:0] : control_1[9:5];
  assign current_shift_0 = shift_0;
  assign current_shift_1 = shift_1;
  assign post_shift_0 = shift_after_0;
  assign post_shift_1 = shift_after_1;

  always @(posedge clk) begin
    if (!rst_n) begin
      shift_0 <= 8'h00;
      shift_1 <= 8'h00;
      count_0 <= 4'd0;
      count_1 <= 4'd0;
    end else begin
      if (fire_0) begin
        shift_0 <= shift_after_0;
        count_0 <= count_after_0;
      end
      if (fire_1) begin
        shift_1 <= shift_after_1;
        count_1 <= count_after_1;
      end
    end
  end

endmodule

`default_nettype wire
