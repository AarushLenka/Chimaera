/*
 * Phase 4 I2C target descriptor source.
 *
 * This is deliberately a small, fixed demonstration program until the Phase 5
 * loader can replace it with compiler-emitted descriptors.  It accepts one
 * write transaction for 7-bit address 0x42, ACKs the address and one data byte,
 * then returns to the START detector.  SDA is always released or driven low;
 * the top-level output stage enforces the same open-drain rule structurally.
 */

`default_nettype none
`timescale 1ns / 1ps

module chimaera_i2c_program #(
    parameter integer STATE_WIDTH = 5,
    parameter integer TIMER_WIDTH = 16,
    parameter integer SDA_PIN = 4,
    parameter integer SCL_PIN = 5
) (
    input  wire [STATE_WIDTH-1:0] state_id,
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

  localparam [3:0] EVENT_NONE             = 4'd0;
  localparam [3:0] EVENT_RISE             = 4'd1;
  localparam [3:0] EVENT_FALL             = 4'd2;
  localparam [3:0] EVENT_FALL_WHILE_LEVEL = 4'd5;

  localparam [STATE_WIDTH-1:0] STATE_WAIT_START      = 5'd8;
  localparam [STATE_WIDTH-1:0] STATE_ADDRESS         = 5'd9;
  localparam [STATE_WIDTH-1:0] STATE_ACK_PREP        = 5'd10;
  localparam [STATE_WIDTH-1:0] STATE_ACK_HOLD        = 5'd11;
  localparam [STATE_WIDTH-1:0] STATE_ACK_RELEASE     = 5'd12;
  localparam [STATE_WIDTH-1:0] STATE_NACK_PREP       = 5'd13;
  localparam [STATE_WIDTH-1:0] STATE_NACK_HOLD       = 5'd14;
  localparam [STATE_WIDTH-1:0] STATE_NACK_RELEASE    = 5'd15;
  localparam [STATE_WIDTH-1:0] STATE_DATA             = 5'd16;
  localparam [STATE_WIDTH-1:0] STATE_DATA_ACK_PREP   = 5'd17;
  localparam [STATE_WIDTH-1:0] STATE_DATA_ACK_HOLD   = 5'd18;
  localparam [STATE_WIDTH-1:0] STATE_DATA_ACK_RELEASE= 5'd19;

  localparam [7:0] SDA_MASK = (8'h01 << SDA_PIN);
  localparam [7:0] SCL_MASK = (8'h01 << SCL_PIN);

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
      STATE_WAIT_START: begin
        // START is SDA falling while SCL is high.
        event_kind  = EVENT_FALL_WHILE_LEVEL;
        event_mask  = SDA_MASK;
        level_mask  = SCL_MASK;
        level_value = SCL_MASK;
      end
      STATE_ADDRESS: begin
        event_kind  = EVENT_RISE;
        event_mask  = SCL_MASK;
        sample_mask = SDA_MASK;
      end
      STATE_ACK_PREP: begin
        event_kind   = EVENT_FALL;
        event_mask   = SCL_MASK;
        action_mask  = SDA_MASK;
        action_value = 8'h00;
        oe_mask      = SDA_MASK;
        oe_value     = SDA_MASK;
      end
      STATE_ACK_HOLD: begin
        event_kind = EVENT_RISE;
        event_mask = SCL_MASK;
      end
      STATE_ACK_RELEASE: begin
        event_kind   = EVENT_FALL;
        event_mask   = SCL_MASK;
        action_mask  = SDA_MASK;
        action_value = 8'h00;
        oe_mask      = SDA_MASK;
        oe_value     = 8'h00;
      end
      STATE_NACK_PREP: begin
        event_kind   = EVENT_FALL;
        event_mask   = SCL_MASK;
        action_mask  = SDA_MASK;
        action_value = 8'h00;
        oe_mask      = SDA_MASK;
        oe_value     = 8'h00;
      end
      STATE_NACK_HOLD: begin
        event_kind = EVENT_RISE;
        event_mask = SCL_MASK;
      end
      STATE_NACK_RELEASE: begin
        event_kind   = EVENT_FALL;
        event_mask   = SCL_MASK;
        action_mask  = SDA_MASK;
        action_value = 8'h00;
        oe_mask      = SDA_MASK;
        oe_value     = 8'h00;
      end
      STATE_DATA: begin
        event_kind  = EVENT_RISE;
        event_mask  = SCL_MASK;
        sample_mask = SDA_MASK;
      end
      STATE_DATA_ACK_PREP: begin
        event_kind   = EVENT_FALL;
        event_mask   = SCL_MASK;
        action_mask  = SDA_MASK;
        action_value = 8'h00;
        oe_mask      = SDA_MASK;
        oe_value     = SDA_MASK;
      end
      STATE_DATA_ACK_HOLD: begin
        event_kind = EVENT_RISE;
        event_mask = SCL_MASK;
      end
      STATE_DATA_ACK_RELEASE: begin
        event_kind   = EVENT_FALL;
        event_mask   = SCL_MASK;
        action_mask  = SDA_MASK;
        action_value = 8'h00;
        oe_mask      = SDA_MASK;
        oe_value     = 8'h00;
      end
      default: begin
        event_kind = EVENT_NONE;
      end
    endcase
  end

endmodule

`default_nettype wire
