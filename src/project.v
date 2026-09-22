/*
 * Copyright (c) 2024 Your Name
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none
`timescale 1ns / 1ps

/* verilator lint_off DECLFILENAME */
module tt_um_chimaera (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered, so you can ignore it
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);

  localparam integer STATE_WIDTH = 4;
  localparam integer TIMER_WIDTH = 16;
  localparam integer UART_BIT_CYCLES = 16;

  wire [7:0] synchronized_inputs;
  wire [7:0] rising_edges;
  wire [7:0] falling_edges;

  wire                   cell_fire;
  wire                   cell_fire_from_timeout;
  wire [7:0]             cell_fire_sample;
  wire [STATE_WIDTH-1:0] cell_state;
  wire [7:0]             cell_drive_value;
  wire [7:0]             cell_drive_enable;

  wire [STATE_WIDTH-1:0] next_state;
  wire                   next_tx_bit;
  wire [7:0]             received_byte;
  wire                   received_strobe;

  reg boot_pending;

  wire [1:0]             program_event_kind;
  wire [7:0]             program_event_mask;
  wire [7:0]             program_event_value;
  wire [TIMER_WIDTH-1:0] program_timeout;
  wire [7:0]             program_sample_mask;
  wire [7:0]             program_action_mask;
  wire [7:0]             program_action_value;
  wire [7:0]             program_oe_mask;
  wire [7:0]             program_oe_value;

  // A fired cell immediately receives its next predecoded descriptor.  With a
  // single Phase 2 cell there is no scheduler contention; Phase 4 will arbitrate
  // this load path when the second cell is added.
  wire load_cell = boot_pending | cell_fire;
  wire [STATE_WIDTH-1:0] descriptor_state = boot_pending ?
      {STATE_WIDTH{1'b0}} : next_state;

  always @(posedge clk) begin
    if (!rst_n)
      boot_pending <= 1'b1;
    else if (boot_pending)
      boot_pending <= 1'b0;
  end

  chimaera_input_frontend input_frontend (
      .clk          (clk),
      .rst_n        (rst_n),
      .async_inputs (uio_in),
      .sync_inputs  (synchronized_inputs),
      .rise_edges   (rising_edges),
      .fall_edges   (falling_edges)
  );

  chimaera_uart_program #(
      .STATE_WIDTH (STATE_WIDTH),
      .TIMER_WIDTH (TIMER_WIDTH),
      .BIT_CYCLES  (UART_BIT_CYCLES),
      .RX_PIN      (0),
      .TX_PIN      (1)
  ) uart_program (
      .state_id       (descriptor_state),
      .tx_bit         (next_tx_bit),
      .event_kind     (program_event_kind),
      .event_mask     (program_event_mask),
      .event_value    (program_event_value),
      .timeout_cycles (program_timeout),
      .sample_mask    (program_sample_mask),
      .action_mask    (program_action_mask),
      .action_value   (program_action_value),
      .oe_mask        (program_oe_mask),
      .oe_value       (program_oe_value)
  );

  chimaera_reaction_cell #(
      .STATE_WIDTH       (STATE_WIDTH),
      .TIMER_WIDTH       (TIMER_WIDTH),
      .RESET_DRIVE_VALUE (8'h02),
      .RESET_DRIVE_ENABLE(8'h02)
  ) reaction_cell_0 (
      .clk               (clk),
      .rst_n             (rst_n),
      .sync_inputs       (synchronized_inputs),
      .rise_edges        (rising_edges),
      .fall_edges        (falling_edges),
      .load              (load_cell),
      .load_state        (descriptor_state),
      .load_event_kind   (program_event_kind),
      .load_event_mask   (program_event_mask),
      .load_event_value  (program_event_value),
      .load_timeout      (program_timeout),
      .load_sample_mask  (program_sample_mask),
      .load_action_mask  (program_action_mask),
      .load_action_value (program_action_value),
      .load_oe_mask      (program_oe_mask),
      .load_oe_value     (program_oe_value),
      .fire              (cell_fire),
      .fire_from_timeout (cell_fire_from_timeout),
      .fire_sample       (cell_fire_sample),
      .current_state     (cell_state),
      .drive_value       (cell_drive_value),
      .drive_enable      (cell_drive_enable)
  );

  chimaera_execution_engine #(
      .STATE_WIDTH(STATE_WIDTH),
      .RX_PIN     (0)
  ) execution_engine (
      .clk             (clk),
      .rst_n           (rst_n),
      .fire            (cell_fire),
      .current_state   (cell_state),
      .fire_sample     (cell_fire_sample),
      .next_state      (next_state),
      .next_tx_bit     (next_tx_bit),
      .received_byte   (received_byte),
      .received_strobe (received_strobe)
  );

  assign uo_out  = received_byte;
  assign uio_out = cell_drive_value;
  assign uio_oe  = cell_drive_enable;

  // Reserved for the Phase 4 host configuration interface.
  wire _unused = &{ena, ui_in, cell_fire_from_timeout, received_strobe, 1'b0};

endmodule
/* verilator lint_on DECLFILENAME */
