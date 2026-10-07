/*
 * Phase 4 SPI mode-0 target descriptor source.
 *
 * The temporary program accepts one 8-bit transaction while CS is low,
 * samples MOSI on rising SCLK edges, and returns the fixed response 0x3c on
 * MISO.  The response is intentionally fixed until the compiler/loader phase;
 * the generic reaction cell still owns all edge timing and pin actions.
 */

`default_nettype none
`timescale 1ns / 1ps

module chimaera_spi_program #(
    parameter integer STATE_WIDTH = 5,
    parameter integer TIMER_WIDTH = 16,
    parameter integer SCLK_PIN = 4,
    parameter integer MOSI_PIN = 5,
    parameter integer MISO_PIN = 6,
    parameter integer CS_PIN = 7
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

  localparam [3:0] EVENT_NONE          = 4'd0;
  localparam [3:0] EVENT_FALL          = 4'd2;
  localparam [3:0] EVENT_LEVEL         = 4'd3;
  localparam [3:0] EVENT_RISE_OR_LEVEL = 4'd6;
  localparam [3:0] EVENT_FALL_OR_LEVEL = 4'd7;

  localparam [STATE_WIDTH-1:0] STATE_WAIT_CS      = 5'd20;
  localparam [STATE_WIDTH-1:0] STATE_SHIFT        = 5'd21;
  localparam [STATE_WIDTH-1:0] STATE_CHANGE       = 5'd22;
  localparam [STATE_WIDTH-1:0] STATE_END          = 5'd23;
  localparam [STATE_WIDTH-1:0] STATE_WAIT_CS_HIGH = 5'd24;

  localparam [7:0] SCLK_MASK = (8'h01 << SCLK_PIN);
  localparam [7:0] MOSI_MASK = (8'h01 << MOSI_PIN);
  localparam [7:0] MISO_MASK = (8'h01 << MISO_PIN);
  localparam [7:0] CS_MASK   = (8'h01 << CS_PIN);

  always @(*) begin
    event_kind     = EVENT_NONE;
    event_mask     = 8'h00;
    event_value    = 8'h00;
    level_mask     = 8'h00;
    level_value    = 8'h00;
    timeout_cycles = {TIMER_WIDTH{1'b0}};
    sample_mask    = 8'h00;
    action_mask    = 8'h00;
    action_value   = 8'h00;
    oe_mask        = 8'h00;
    oe_value       = 8'h00;

    case (state_id)
      STATE_WAIT_CS: begin
        event_kind   = EVENT_FALL;
        event_mask   = CS_MASK;
        action_mask  = MISO_MASK;
        action_value = tx_bit ? MISO_MASK : 8'h00;
        oe_mask      = MISO_MASK;
        oe_value     = MISO_MASK;
      end
      STATE_SHIFT: begin
        // A CS rise aborts an incomplete transaction and is handled by the
        // shared engine; otherwise this is the normal rising-clock event.
        event_kind   = EVENT_RISE_OR_LEVEL;
        event_mask   = SCLK_MASK;
        level_mask   = CS_MASK;
        level_value  = CS_MASK;
        sample_mask  = MOSI_MASK;
      end
      STATE_CHANGE: begin
        // MISO changes on the falling edge in SPI mode 0.  CS high also
        // releases an aborted transaction through the top-level safety gate.
        event_kind   = EVENT_FALL_OR_LEVEL;
        event_mask   = SCLK_MASK;
        level_mask   = CS_MASK;
        level_value  = CS_MASK;
        action_mask  = MISO_MASK;
        action_value = tx_bit ? MISO_MASK : 8'h00;
        oe_mask      = MISO_MASK;
        oe_value     = MISO_MASK;
      end
      STATE_END: begin
        event_kind   = EVENT_FALL_OR_LEVEL;
        event_mask   = SCLK_MASK;
        level_mask   = CS_MASK;
        level_value  = CS_MASK;
        action_mask  = MISO_MASK;
        action_value = 8'h00;
        oe_mask      = MISO_MASK;
        oe_value     = 8'h00;
      end
      STATE_WAIT_CS_HIGH: begin
        event_kind  = EVENT_LEVEL;
        event_mask  = CS_MASK;
        event_value = CS_MASK;
      end
      default: begin
        event_kind = EVENT_NONE;
      end
    endcase
  end

endmodule

`default_nettype wire
