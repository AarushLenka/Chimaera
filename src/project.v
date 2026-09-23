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

  localparam integer STATE_WIDTH = 5;
  localparam integer TIMER_WIDTH = 16;
  localparam integer UART_BIT_CYCLES = 16;
  localparam [1:0] PROTOCOL_I2C = 2'd0;
  localparam [1:0] PROTOCOL_SPI = 2'd1;

  // Phase 4 bootstrap selection remains as a regression-safe power-on fallback.
  // A BEGIN frame switches pin ownership to the Phase 5 loaded-program path.
  wire [1:0] protocol_select = ui_in[1:0];

  wire [7:0] synchronized_inputs;
  wire [7:0] rising_edges;
  wire [7:0] falling_edges;

  wire                   cell_fire_0;
  wire                   cell_fire_from_timeout_0;
  wire [7:0]             cell_fire_sample_0;
  wire [STATE_WIDTH-1:0] cell_state_0;
  wire [7:0]             cell_drive_value_0;
  wire [7:0]             cell_drive_enable_0;

  wire                   cell_fire_1;
  wire                   cell_fire_from_timeout_1;
  wire [7:0]             cell_fire_sample_1;
  wire [STATE_WIDTH-1:0] cell_state_1;
  wire [7:0]             cell_drive_value_1;
  wire [7:0]             cell_drive_enable_1;

  wire [STATE_WIDTH-1:0] next_state_0;
  wire                   next_tx_bit_0;
  wire [STATE_WIDTH-1:0] next_state_1;
  wire                   next_tx_bit_1;
  wire [7:0]             received_byte;
  wire                   received_strobe;

  wire                   cfg_miso;
  wire                   cfg_active;
  wire [4:0]             loaded_descriptor_address;
  wire [127:0]           loaded_descriptor_data;
  wire [4:0]             loaded_context_entry_0;
  wire [4:0]             loaded_context_entry_1;
  wire [1:0]             loaded_context_enable;
  wire [7:0]             loaded_open_drain_mask;
  wire                   loaded_program_valid;
  wire                   loaded_execution_halted;
  wire                   loaded_load_error;
  wire                   loaded_load_in_progress;
  wire [5:0]             loaded_descriptor_count;
  wire [15:0]            loaded_crc;
  wire [31:0]            cfg_status_word;
  wire [7:0]             loaded_drive_value_0;
  wire [7:0]             loaded_drive_enable_0;
  wire [7:0]             loaded_drive_value_1;
  wire [7:0]             loaded_drive_enable_1;
  wire                   loaded_fire_0;
  wire                   loaded_fire_1;

  reg boot_pending;

  wire [3:0]             program_event_kind_0;
  wire [7:0]             program_event_mask_0;
  wire [7:0]             program_event_value_0;
  wire [7:0]             program_level_mask_0;
  wire [7:0]             program_level_value_0;
  wire [TIMER_WIDTH-1:0] program_timeout_0;
  wire [7:0]             program_sample_mask_0;
  wire [7:0]             program_action_mask_0;
  wire [7:0]             program_action_value_0;
  wire [7:0]             program_oe_mask_0;
  wire [7:0]             program_oe_value_0;

  wire [3:0]             program_event_kind_1;
  wire [7:0]             program_event_mask_1;
  wire [7:0]             program_event_value_1;
  wire [7:0]             program_level_mask_1;
  wire [7:0]             program_level_value_1;
  wire [TIMER_WIDTH-1:0] program_timeout_1;
  wire [7:0]             program_sample_mask_1;
  wire [7:0]             program_action_mask_1;
  wire [7:0]             program_action_value_1;
  wire [7:0]             program_oe_mask_1;
  wire [7:0]             program_oe_value_1;

  wire load_cell_0 = boot_pending | cell_fire_0;
  wire load_cell_1 = boot_pending | cell_fire_1;
  wire [STATE_WIDTH-1:0] descriptor_state_0 = boot_pending ?
      {STATE_WIDTH{1'b0}} : next_state_0;
  wire [STATE_WIDTH-1:0] descriptor_state_1 = boot_pending ?
      ((protocol_select == PROTOCOL_SPI) ? 5'd20 :
       (protocol_select == PROTOCOL_I2C) ? 5'd8 : 5'd31) : next_state_1;

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

  chimaera_host_interface host_interface (
      .clk                    (clk),
      .rst_n                  (rst_n),
      .cfg_cs_n               (ui_in[2]),
      .cfg_sclk               (ui_in[3]),
      .cfg_mosi               (ui_in[4]),
      .cfg_miso               (cfg_miso),
      .cfg_active             (cfg_active),
      .descriptor_address     (loaded_descriptor_address),
      .descriptor_data        (loaded_descriptor_data),
      .context_entry_0        (loaded_context_entry_0),
      .context_entry_1        (loaded_context_entry_1),
      .context_enable         (loaded_context_enable),
      .open_drain_mask        (loaded_open_drain_mask),
      .program_valid          (loaded_program_valid),
      .execution_halted       (loaded_execution_halted),
      .load_error             (loaded_load_error),
      .load_in_progress       (loaded_load_in_progress),
      .loaded_descriptor_count(loaded_descriptor_count),
      .computed_crc           (loaded_crc),
      .status_word            (cfg_status_word)
  );

  chimaera_program_runtime loaded_runtime (
      .clk                 (clk),
      .rst_n               (rst_n),
      .execution_halted    (loaded_execution_halted),
      .context_enable      (loaded_context_enable),
      .context_entry_0     (loaded_context_entry_0),
      .context_entry_1     (loaded_context_entry_1),
      .descriptor_address  (loaded_descriptor_address),
      .descriptor_data     (loaded_descriptor_data),
      .sync_inputs         (synchronized_inputs),
      .rise_edges          (rising_edges),
      .fall_edges          (falling_edges),
      .drive_value_0       (loaded_drive_value_0),
      .drive_enable_0      (loaded_drive_enable_0),
      .drive_value_1       (loaded_drive_value_1),
      .drive_enable_1      (loaded_drive_enable_1),
      .fire_0              (loaded_fire_0),
      .fire_1              (loaded_fire_1)
  );

  chimaera_uart_program #(
      .STATE_WIDTH (STATE_WIDTH),
      .TIMER_WIDTH (TIMER_WIDTH),
      .BIT_CYCLES  (UART_BIT_CYCLES),
      .RX_PIN      (0),
      .TX_PIN      (1)
  ) uart_program (
      .state_id       (descriptor_state_0),
      .tx_bit         (next_tx_bit_0),
      .event_kind     (program_event_kind_0),
      .event_mask     (program_event_mask_0),
      .event_value    (program_event_value_0),
      .level_mask     (program_level_mask_0),
      .level_value    (program_level_value_0),
      .timeout_cycles (program_timeout_0),
      .sample_mask    (program_sample_mask_0),
      .action_mask    (program_action_mask_0),
      .action_value   (program_action_value_0),
      .oe_mask        (program_oe_mask_0),
      .oe_value       (program_oe_value_0)
  );

  chimaera_port_b_program #(
      .STATE_WIDTH (STATE_WIDTH),
      .TIMER_WIDTH (TIMER_WIDTH)
  ) port_b_program (
      .protocol_select(protocol_select),
      .state_id       (descriptor_state_1),
      .tx_bit         (next_tx_bit_1),
      .event_kind     (program_event_kind_1),
      .event_mask     (program_event_mask_1),
      .event_value    (program_event_value_1),
      .level_mask     (program_level_mask_1),
      .level_value    (program_level_value_1),
      .timeout_cycles (program_timeout_1),
      .sample_mask    (program_sample_mask_1),
      .action_mask    (program_action_mask_1),
      .action_value   (program_action_value_1),
      .oe_mask        (program_oe_mask_1),
      .oe_value       (program_oe_value_1)
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
      .load              (load_cell_0),
      .load_state        (descriptor_state_0),
      .load_event_kind   (program_event_kind_0),
      .load_event_mask   (program_event_mask_0),
      .load_event_value  (program_event_value_0),
      .load_level_mask   (program_level_mask_0),
      .load_level_value  (program_level_value_0),
      .load_timeout      (program_timeout_0),
      .load_sample_mask  (program_sample_mask_0),
      .load_action_mask  (program_action_mask_0),
      .load_action_value (program_action_value_0),
      .load_oe_mask      (program_oe_mask_0),
      .load_oe_value     (program_oe_value_0),
      .fire              (cell_fire_0),
      .fire_from_timeout (cell_fire_from_timeout_0),
      .fire_sample       (cell_fire_sample_0),
      .current_state     (cell_state_0),
      .drive_value       (cell_drive_value_0),
      .drive_enable      (cell_drive_enable_0)
  );

  chimaera_reaction_cell #(
      .STATE_WIDTH       (STATE_WIDTH),
      .TIMER_WIDTH       (TIMER_WIDTH),
      .RESET_DRIVE_VALUE (8'h00),
      .RESET_DRIVE_ENABLE(8'h00)
  ) reaction_cell_1 (
      .clk               (clk),
      .rst_n             (rst_n),
      .sync_inputs       (synchronized_inputs),
      .rise_edges        (rising_edges),
      .fall_edges        (falling_edges),
      .load              (load_cell_1),
      .load_state        (descriptor_state_1),
      .load_event_kind   (program_event_kind_1),
      .load_event_mask   (program_event_mask_1),
      .load_event_value  (program_event_value_1),
      .load_level_mask   (program_level_mask_1),
      .load_level_value  (program_level_value_1),
      .load_timeout      (program_timeout_1),
      .load_sample_mask  (program_sample_mask_1),
      .load_action_mask  (program_action_mask_1),
      .load_action_value (program_action_value_1),
      .load_oe_mask      (program_oe_mask_1),
      .load_oe_value     (program_oe_value_1),
      .fire              (cell_fire_1),
      .fire_from_timeout (cell_fire_from_timeout_1),
      .fire_sample       (cell_fire_sample_1),
      .current_state     (cell_state_1),
      .drive_value       (cell_drive_value_1),
      .drive_enable      (cell_drive_enable_1)
  );

  chimaera_execution_engine #(
      .STATE_WIDTH   (STATE_WIDTH),
      .RX_PIN        (0),
      .I2C_SDA_PIN   (4),
      .SPI_MOSI_PIN  (5),
      .SPI_CS_PIN    (7)
  ) execution_engine (
      .clk             (clk),
      .rst_n           (rst_n),
      .fire_0          (cell_fire_0),
      .current_state_0 (cell_state_0),
      .fire_sample_0   (cell_fire_sample_0),
      .fire_1          (cell_fire_1),
      .current_state_1 (cell_state_1),
      .fire_sample_1   (cell_fire_sample_1),
      .sync_inputs     (synchronized_inputs),
      .protocol_select (protocol_select),
      .next_state_0    (next_state_0),
      .next_tx_bit_0   (next_tx_bit_0),
      .next_state_1    (next_state_1),
      .next_tx_bit_1   (next_tx_bit_1),
      .received_byte   (received_byte),
      .received_strobe (received_strobe)
  );

  // Cell 0 owns UART pins [1:0].  Cell 1 owns Port B [7:4].  The I2C branch
  // intentionally masks all driven values to zero and clamps OE to low-only,
  // making an active-high open-drain drive impossible in this output stage.
  wire [7:0] cell1_pin_value = (protocol_select == PROTOCOL_I2C) ?
      8'h00 : cell_drive_value_1;
  wire [7:0] cell1_oe_low_only =
      (protocol_select == PROTOCOL_I2C) ?
      (cell_drive_enable_1 & ~cell1_pin_value) : cell_drive_enable_1;
  wire [7:0] spi_abort_release =
      (protocol_select == PROTOCOL_SPI && synchronized_inputs[7]) ? 8'h40 : 8'h00;

  wire [7:0] legacy_uio_out = cell_drive_value_0 | cell1_pin_value;
  wire [7:0] legacy_uio_oe =
      cell_drive_enable_0 | (cell1_oe_low_only & ~spi_abort_release);
  wire use_loaded_path = loaded_program_valid || loaded_load_in_progress;
  wire [7:0] loaded_value = loaded_drive_value_0 | loaded_drive_value_1;
  wire [7:0] loaded_enable = loaded_drive_enable_0 | loaded_drive_enable_1;
  // The loaded pin-mode mask makes active-high open-drain drive structurally
  // impossible even if a malformed descriptor bypasses compiler checks.
  wire [7:0] loaded_value_low_only = loaded_value & ~loaded_open_drain_mask;

  assign uo_out[0] = cfg_active ? cfg_miso : received_byte[0];
  assign uo_out[7:1] = received_byte[7:1];
  assign uio_out = use_loaded_path ? loaded_value_low_only : legacy_uio_out;
  assign uio_oe = use_loaded_path ? loaded_enable : legacy_uio_oe;

  wire _unused = &{ena, ui_in[7:5], cell_fire_from_timeout_0,
                   cell_fire_from_timeout_1, received_strobe,
                   loaded_load_error, loaded_descriptor_count, loaded_crc,
                   cfg_status_word, loaded_fire_0, loaded_fire_1, 1'b0};

endmodule
/* verilator lint_on DECLFILENAME */

`default_nettype wire
