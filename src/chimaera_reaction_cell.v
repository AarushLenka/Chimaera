/*
 * One Chimaera reaction cell.
 *
 * The active descriptor is stored locally, including its already-decoded pin
 * action.  Consequently a matched synchronized event commits its output action
 * on the observing clock edge without waiting for the shared execution engine.
 */

`default_nettype none
`timescale 1ns / 1ps

module chimaera_reaction_cell #(
    parameter integer STATE_WIDTH = 4,
    parameter integer TIMER_WIDTH = 16,
    parameter [7:0] RESET_DRIVE_VALUE = 8'h02,
    parameter [7:0] RESET_DRIVE_ENABLE = 8'h02
) (
    input  wire                   clk,
    input  wire                   rst_n,
    input  wire [7:0]             sync_inputs,
    input  wire [7:0]             rise_edges,
    input  wire [7:0]             fall_edges,

    input  wire                   load,
    input  wire [STATE_WIDTH-1:0] load_state,
    input  wire [3:0]             load_event_kind,
    input  wire [7:0]             load_event_mask,
    input  wire [7:0]             load_event_value,
    input  wire [7:0]             load_level_mask,
    input  wire [7:0]             load_level_value,
    input  wire [TIMER_WIDTH-1:0] load_timeout,
    input  wire [7:0]             load_sample_mask,
    input  wire [7:0]             load_action_mask,
    input  wire [7:0]             load_action_value,
    input  wire [7:0]             load_oe_mask,
    input  wire [7:0]             load_oe_value,

    output wire                   fire,
    output wire                   fire_from_timeout,
    output wire [7:0]             fire_sample,
    output wire [STATE_WIDTH-1:0] current_state,
    output reg  [7:0]             drive_value,
    output reg  [7:0]             drive_enable
);

  localparam [3:0] EVENT_NONE             = 4'd0;
  localparam [3:0] EVENT_RISE             = 4'd1;
  localparam [3:0] EVENT_FALL             = 4'd2;
  localparam [3:0] EVENT_LEVEL            = 4'd3;
  localparam [3:0] EVENT_RISE_WHILE_LEVEL = 4'd4;
  localparam [3:0] EVENT_FALL_WHILE_LEVEL = 4'd5;
  localparam [3:0] EVENT_RISE_OR_LEVEL    = 4'd6;
  localparam [3:0] EVENT_FALL_OR_LEVEL    = 4'd7;

  reg                         active;
  reg [STATE_WIDTH-1:0]       state_id;
  reg [3:0]                   event_kind;
  reg [7:0]                   event_mask;
  reg [7:0]                   event_value;
  reg [7:0]                   level_mask;
  reg [7:0]                   level_value;
  reg [TIMER_WIDTH-1:0]       timer;
  reg [7:0]                   sample_mask;
  reg [7:0]                   action_mask;
  reg [7:0]                   action_value;
  reg [7:0]                   oe_mask;
  reg [7:0]                   oe_value;

  reg event_match;

  always @(*) begin
    case (event_kind)
      EVENT_RISE: event_match = |(rise_edges & event_mask);
      EVENT_FALL: event_match = |(fall_edges & event_mask);
      EVENT_LEVEL: event_match =
          ((sync_inputs & event_mask) == (event_value & event_mask));
      EVENT_RISE_WHILE_LEVEL: event_match =
          (|(rise_edges & event_mask)) &&
          ((sync_inputs & level_mask) == (level_value & level_mask));
      EVENT_FALL_WHILE_LEVEL: event_match =
          (|(fall_edges & event_mask)) &&
          ((sync_inputs & level_mask) == (level_value & level_mask));
      EVENT_RISE_OR_LEVEL: event_match =
          (|(rise_edges & event_mask)) ||
          ((sync_inputs & level_mask) == (level_value & level_mask));
      EVENT_FALL_OR_LEVEL: event_match =
          (|(fall_edges & event_mask)) ||
          ((sync_inputs & level_mask) == (level_value & level_mask));
      default:     event_match = 1'b0;
    endcase
  end

  assign fire_from_timeout = active && !event_match && (timer == {{(TIMER_WIDTH-1){1'b0}}, 1'b1});
  assign fire              = active && (event_match || fire_from_timeout);
  assign fire_sample       = sync_inputs & sample_mask;
  assign current_state     = state_id;

  always @(posedge clk) begin
    if (!rst_n) begin
      active       <= 1'b0;
      state_id     <= {STATE_WIDTH{1'b0}};
      event_kind   <= EVENT_NONE;
      event_mask   <= 8'h00;
      event_value  <= 8'h00;
      level_mask   <= 8'h00;
      level_value  <= 8'h00;
      timer        <= {TIMER_WIDTH{1'b0}};
      sample_mask  <= 8'h00;
      action_mask  <= 8'h00;
      action_value <= 8'h00;
      oe_mask      <= 8'h00;
      oe_value     <= 8'h00;
      drive_value  <= RESET_DRIVE_VALUE;
      drive_enable <= RESET_DRIVE_ENABLE;
    end else begin
      if (fire) begin
        // This is the fixed-latency fast path.  No result from shared
        // bookkeeping participates in the action being committed here.
        drive_value  <= (drive_value  & ~action_mask) |
                        (action_value &  action_mask);
        drive_enable <= (drive_enable & ~oe_mask) |
                        (oe_value     &  oe_mask);
      end

      if (load) begin
        active       <= 1'b1;
        state_id     <= load_state;
        event_kind   <= load_event_kind;
        event_mask   <= load_event_mask;
        event_value  <= load_event_value;
        level_mask   <= load_level_mask;
        level_value  <= load_level_value;
        timer        <= load_timeout;
        sample_mask  <= load_sample_mask;
        action_mask  <= load_action_mask;
        action_value <= load_action_value;
        oe_mask      <= load_oe_mask;
        oe_value     <= load_oe_value;
      end else if (fire) begin
        active <= 1'b0;
      end else if (active && (timer != {TIMER_WIDTH{1'b0}})) begin
        timer <= timer - {{(TIMER_WIDTH-1){1'b0}}, 1'b1};
      end
    end
  end

endmodule

`default_nettype wire
