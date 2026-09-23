/*
 * SPI-like host frame sampler.
 *
 * External configuration pins are synchronized into the Chimaera clock domain.
 * MOSI is captured MSB-first on synchronized SCLK rising edges; MISO advances on
 * falling edges.  Configuration SCLK must therefore remain below one quarter of
 * the 50 MHz system clock so both synchronized edge types are observable.
 */

`default_nettype none
`timescale 1ns / 1ps

module chimaera_config_spi (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        async_cs_n,
    input  wire        async_sclk,
    input  wire        async_mosi,
    input  wire [31:0] tx_data,
    output wire        miso,
    output reg         transaction_active,
    output reg         frame_strobe,
    output reg [31:0]  frame_data,
    output reg         framing_error
);

  reg [1:0] cs_sync;
  reg [1:0] sclk_sync;
  reg [1:0] mosi_sync;
  reg previous_cs_n;
  reg previous_sclk;
  reg [5:0] bit_count;
  reg [30:0] rx_shift;
  reg [31:0] tx_shift;

  wire cs_n = cs_sync[1];
  wire sclk = sclk_sync[1];
  wire mosi = mosi_sync[1];
  wire cs_fall = previous_cs_n && !cs_n;
  wire cs_rise = !previous_cs_n && cs_n;
  wire sclk_rise = !previous_sclk && sclk;
  wire sclk_fall = previous_sclk && !sclk;

  assign miso = transaction_active ? tx_shift[31] : 1'b0;

  always @(posedge clk) begin
    if (!rst_n) begin
      cs_sync           <= 2'b00;
      sclk_sync         <= 2'b00;
      mosi_sync         <= 2'b00;
      previous_cs_n     <= 1'b0;
      previous_sclk     <= 1'b0;
      bit_count         <= 6'd0;
      rx_shift          <= 31'd0;
      tx_shift          <= 32'd0;
      transaction_active<= 1'b0;
      frame_strobe      <= 1'b0;
      frame_data        <= 32'd0;
      framing_error     <= 1'b0;
    end else begin
      cs_sync <= {cs_sync[0], async_cs_n};
      sclk_sync <= {sclk_sync[0], async_sclk};
      mosi_sync <= {mosi_sync[0], async_mosi};
      previous_cs_n <= cs_n;
      previous_sclk <= sclk;
      frame_strobe <= 1'b0;

      if (cs_fall) begin
        transaction_active <= 1'b1;
        bit_count <= 6'd0;
        rx_shift <= 31'd0;
        tx_shift <= tx_data;
        framing_error <= 1'b0;
      end else if (cs_rise) begin
        transaction_active <= 1'b0;
        if (bit_count != 6'd0)
          framing_error <= 1'b1;
        bit_count <= 6'd0;
      end else if (transaction_active) begin
        if (sclk_rise) begin
          rx_shift <= {rx_shift[29:0], mosi};
          if (bit_count == 6'd31) begin
            frame_data <= {rx_shift, mosi};
            frame_strobe <= 1'b1;
            bit_count <= 6'd0;
          end else begin
            bit_count <= bit_count + 6'd1;
          end
        end
        if (sclk_fall)
          tx_shift <= {tx_shift[30:0], 1'b0};
      end
    end
  end

endmodule

`default_nettype wire
