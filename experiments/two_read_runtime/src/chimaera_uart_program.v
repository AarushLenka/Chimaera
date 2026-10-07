/*
 * Phase 2 UART state descriptors.
 *
 * This module is the temporary program source for the generic reaction cell.
 * Phase 5's compiler/loader will replace this decoder with loaded descriptor
 * memory; the reaction-cell fast path does not contain UART-specific logic.
 */

`default_nettype none
`timescale 1ns / 1ps

module chimaera_uart_program #(
    parameter integer STATE_WIDTH = 4,
    parameter integer TIMER_WIDTH = 16,
    parameter integer BIT_CYCLES = 16,
    parameter integer RX_PIN = 0,
    parameter integer TX_PIN = 1
) (
    input  wire [STATE_WIDTH-1:0] state_id,
    input  wire                   tx_bit,
    output reg  [3:0]             event_kind,
    output reg  [7:0]             event_mask,
    output reg  [7:0]             event_value,
    output reg  [7:0]             level_mask,
    output reg  [7:0]             level_value,
    output reg  [TIMER_WIDTH-1:0] timeout_cycles,
    output reg  [7:0]             sample_mask,
    output reg  [7:0]             action_mask,
    output reg  [7:0]             action_value,
    output reg  [7:0]             oe_mask,
    output reg  [7:0]             oe_value
);

  localparam [3:0] EVENT_NONE  = 4'd0;
  localparam [3:0] EVENT_FALL  = 4'd2;
  localparam [3:0] EVENT_LEVEL = 4'd3;
  localparam integer HALF_BIT_CYCLES = BIT_CYCLES / 2;

  localparam [STATE_WIDTH-1:0] STATE_IDLE        = 0;
  localparam [STATE_WIDTH-1:0] STATE_RX_VALIDATE = 1;
  localparam [STATE_WIDTH-1:0] STATE_RX_DATA     = 2;
  localparam [STATE_WIDTH-1:0] STATE_RX_STOP     = 3;
  localparam [STATE_WIDTH-1:0] STATE_TX_START    = 4;
  localparam [STATE_WIDTH-1:0] STATE_TX_DATA     = 5;
  localparam [STATE_WIDTH-1:0] STATE_TX_STOP     = 6;

  always @(*) begin
    event_kind    = EVENT_NONE;
    event_mask    = 8'h00;
    event_value   = 8'h00;
    level_mask    = 8'h00;
    level_value   = 8'h00;
    timeout_cycles = {TIMER_WIDTH{1'b0}};
    sample_mask   = 8'h00;
    action_mask   = 8'h00;
    action_value  = 8'h00;
    oe_mask       = 8'h00;
    oe_value      = 8'h00;

    case (state_id)
      STATE_IDLE: begin
        event_kind = EVENT_FALL;
        event_mask = (8'h01 << RX_PIN);
      end
      STATE_RX_VALIDATE: begin
        timeout_cycles = HALF_BIT_CYCLES[TIMER_WIDTH-1:0];
        sample_mask    = (8'h01 << RX_PIN);
      end
      STATE_RX_DATA: begin
        timeout_cycles = BIT_CYCLES[TIMER_WIDTH-1:0];
        sample_mask    = (8'h01 << RX_PIN);
      end
      STATE_RX_STOP: begin
        timeout_cycles = BIT_CYCLES[TIMER_WIDTH-1:0];
        sample_mask    = (8'h01 << RX_PIN);
      end
      STATE_TX_START: begin
        // Zero-mask level matching is an unconditional one-cycle event.
        event_kind   = EVENT_LEVEL;
        action_mask  = (8'h01 << TX_PIN);
        action_value = 8'h00;
      end
      STATE_TX_DATA: begin
        timeout_cycles = BIT_CYCLES[TIMER_WIDTH-1:0];
        action_mask    = (8'h01 << TX_PIN);
        action_value   = tx_bit ? (8'h01 << TX_PIN) : 8'h00;
      end
      STATE_TX_STOP: begin
        timeout_cycles = BIT_CYCLES[TIMER_WIDTH-1:0];
        action_mask    = (8'h01 << TX_PIN);
        action_value   = (8'h01 << TX_PIN);
      end
      default: begin
        event_kind = EVENT_FALL;
        event_mask = (8'h01 << RX_PIN);
      end
    endcase
  end

endmodule

`default_nettype wire
