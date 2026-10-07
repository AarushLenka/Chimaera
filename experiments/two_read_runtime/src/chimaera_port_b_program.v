/*
 * Phase 4 bootstrap program selector for reaction cell 1.
 *
 * ui_in[1:0] selects the descriptor source: 0 = I2C target, 1 = SPI target,
 * and 2/3 = disabled.  This strap is intentionally temporary; Phase 5's
 * configuration loader will select compiler-emitted descriptors instead.
 */

`default_nettype none
`timescale 1ns / 1ps

module chimaera_port_b_program #(
    parameter integer STATE_WIDTH = 5,
    parameter integer TIMER_WIDTH = 16
) (
    input  wire [1:0]             protocol_select,
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

  wire [3:0] i2c_event_kind;
  wire [7:0] i2c_event_mask;
  wire [7:0] i2c_event_value;
  wire [7:0] i2c_level_mask;
  wire [7:0] i2c_level_value;
  wire [TIMER_WIDTH-1:0] i2c_timeout_cycles;
  wire [7:0] i2c_sample_mask;
  wire [7:0] i2c_action_mask;
  wire [7:0] i2c_action_value;
  wire [7:0] i2c_oe_mask;
  wire [7:0] i2c_oe_value;

  wire [3:0] spi_event_kind;
  wire [7:0] spi_event_mask;
  wire [7:0] spi_event_value;
  wire [7:0] spi_level_mask;
  wire [7:0] spi_level_value;
  wire [TIMER_WIDTH-1:0] spi_timeout_cycles;
  wire [7:0] spi_sample_mask;
  wire [7:0] spi_action_mask;
  wire [7:0] spi_action_value;
  wire [7:0] spi_oe_mask;
  wire [7:0] spi_oe_value;

  chimaera_i2c_program #(
      .STATE_WIDTH (STATE_WIDTH),
      .TIMER_WIDTH (TIMER_WIDTH)
  ) i2c_program (
      .state_id       (state_id),
      .event_kind     (i2c_event_kind),
      .event_mask     (i2c_event_mask),
      .event_value    (i2c_event_value),
      .level_mask     (i2c_level_mask),
      .level_value    (i2c_level_value),
      .timeout_cycles (i2c_timeout_cycles),
      .sample_mask    (i2c_sample_mask),
      .action_mask    (i2c_action_mask),
      .action_value   (i2c_action_value),
      .oe_mask        (i2c_oe_mask),
      .oe_value       (i2c_oe_value)
  );

  chimaera_spi_program #(
      .STATE_WIDTH (STATE_WIDTH),
      .TIMER_WIDTH (TIMER_WIDTH)
  ) spi_program (
      .state_id       (state_id),
      .tx_bit         (tx_bit),
      .event_kind     (spi_event_kind),
      .event_mask     (spi_event_mask),
      .event_value    (spi_event_value),
      .level_mask     (spi_level_mask),
      .level_value    (spi_level_value),
      .timeout_cycles (spi_timeout_cycles),
      .sample_mask    (spi_sample_mask),
      .action_mask    (spi_action_mask),
      .action_value   (spi_action_value),
      .oe_mask        (spi_oe_mask),
      .oe_value       (spi_oe_value)
  );

  always @(*) begin
    event_kind     = 4'd0;
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

    case (protocol_select)
      2'd0: begin
        event_kind     = i2c_event_kind;
        event_mask     = i2c_event_mask;
        event_value    = i2c_event_value;
        level_mask     = i2c_level_mask;
        level_value    = i2c_level_value;
        timeout_cycles = i2c_timeout_cycles;
        sample_mask    = i2c_sample_mask;
        action_mask    = i2c_action_mask;
        action_value   = i2c_action_value;
        oe_mask        = i2c_oe_mask;
        oe_value       = i2c_oe_value;
      end
      2'd1: begin
        event_kind     = spi_event_kind;
        event_mask     = spi_event_mask;
        event_value    = spi_event_value;
        level_mask     = spi_level_mask;
        level_value    = spi_level_value;
        timeout_cycles = spi_timeout_cycles;
        sample_mask    = spi_sample_mask;
        action_mask    = spi_action_mask;
        action_value   = spi_action_value;
        oe_mask        = spi_oe_mask;
        oe_value       = spi_oe_value;
      end
      default: begin
        event_kind = 4'd0;
      end
    endcase
  end

endmodule

`default_nettype wire
