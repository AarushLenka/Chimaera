/* Frame sampler plus checksum-validating descriptor loader. */

`default_nettype none
`timescale 1ns / 1ps

module chimaera_host_interface (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         cfg_cs_n,
    input  wire         cfg_sclk,
    input  wire         cfg_mosi,
    output wire         cfg_miso,
    output wire         cfg_active,

    input  wire [4:0]   descriptor_address,
    output wire [127:0] descriptor_data,
    output wire [4:0]   context_entry_0,
    output wire [4:0]   context_entry_1,
    output wire [1:0]   context_enable,
    output wire [7:0]   open_drain_mask,
    output wire         program_valid,
    output wire         execution_halted,
    output wire         load_error,
    output wire         load_in_progress,
    output wire [5:0]   loaded_descriptor_count,
    output wire [15:0]  computed_crc,
    output wire [31:0]  status_word
);

  wire frame_strobe;
  wire [31:0] frame_data;
  wire framing_error;

  assign status_word = {
      program_valid,
      execution_halted,
      load_error,
      framing_error,
      loaded_descriptor_count,
      computed_crc,
      context_enable,
      4'b0000
  };

  chimaera_config_spi config_spi (
      .clk               (clk),
      .rst_n             (rst_n),
      .async_cs_n        (cfg_cs_n),
      .async_sclk        (cfg_sclk),
      .async_mosi        (cfg_mosi),
      .tx_data           (status_word),
      .miso              (cfg_miso),
      .transaction_active(cfg_active),
      .frame_strobe      (frame_strobe),
      .frame_data        (frame_data),
      .framing_error     (framing_error)
  );

  chimaera_program_loader program_loader (
      .clk                    (clk),
      .rst_n                  (rst_n),
      .frame_strobe           (frame_strobe),
      .frame_data             (frame_data),
      .descriptor_address     (descriptor_address),
      .descriptor_data        (descriptor_data),
      .context_entry_0        (context_entry_0),
      .context_entry_1        (context_entry_1),
      .context_enable         (context_enable),
      .open_drain_mask        (open_drain_mask),
      .program_valid          (program_valid),
      .execution_halted       (execution_halted),
      .load_error             (load_error),
      .load_in_progress       (load_in_progress),
      .loaded_descriptor_count(loaded_descriptor_count),
      .computed_crc           (computed_crc)
  );

endmodule

`default_nettype wire
