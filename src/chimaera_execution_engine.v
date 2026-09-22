/*
 * Shared Phase 4 execution engine.
 *
 * The two reaction cells have independent descriptor/state IDs but their
 * bookkeeping is handled in this one engine: the UART context occupies cell 0
 * and the selectable I2C/SPI context occupies cell 1.  The datapath is still
 * deliberately small (two shift registers and counters) so the synthesis
 * checkpoint can show the cost of adding a context without introducing a CPU.
 */

`default_nettype none
`timescale 1ns / 1ps

module chimaera_execution_engine #(
    parameter integer STATE_WIDTH = 5,
    parameter integer RX_PIN = 0,
    parameter integer I2C_SDA_PIN = 4,
    parameter integer SPI_MOSI_PIN = 5,
    parameter integer SPI_CS_PIN = 7
) (
    input  wire                   clk,
    input  wire                   rst_n,
    input  wire                   fire_0,
    input  wire [STATE_WIDTH-1:0] current_state_0,
    input  wire [7:0]             fire_sample_0,
    input  wire                   fire_1,
    input  wire [STATE_WIDTH-1:0] current_state_1,
    input  wire [7:0]             fire_sample_1,
    input  wire [7:0]             sync_inputs,
    input  wire [1:0]             protocol_select,
    output reg  [STATE_WIDTH-1:0] next_state_0,
    output reg                    next_tx_bit_0,
    output reg  [STATE_WIDTH-1:0] next_state_1,
    output reg                    next_tx_bit_1,
    output reg  [7:0]             received_byte,
    output reg                    received_strobe
);

  localparam [STATE_WIDTH-1:0] STATE_UART_IDLE        = 5'd0;
  localparam [STATE_WIDTH-1:0] STATE_UART_RX_VALIDATE = 5'd1;
  localparam [STATE_WIDTH-1:0] STATE_UART_RX_DATA     = 5'd2;
  localparam [STATE_WIDTH-1:0] STATE_UART_RX_STOP     = 5'd3;
  localparam [STATE_WIDTH-1:0] STATE_UART_TX_START    = 5'd4;
  localparam [STATE_WIDTH-1:0] STATE_UART_TX_DATA     = 5'd5;
  localparam [STATE_WIDTH-1:0] STATE_UART_TX_STOP     = 5'd6;

  localparam [STATE_WIDTH-1:0] STATE_I2C_WAIT_START       = 5'd8;
  localparam [STATE_WIDTH-1:0] STATE_I2C_ADDRESS          = 5'd9;
  localparam [STATE_WIDTH-1:0] STATE_I2C_ACK_PREP         = 5'd10;
  localparam [STATE_WIDTH-1:0] STATE_I2C_ACK_HOLD         = 5'd11;
  localparam [STATE_WIDTH-1:0] STATE_I2C_ACK_RELEASE      = 5'd12;
  localparam [STATE_WIDTH-1:0] STATE_I2C_NACK_PREP        = 5'd13;
  localparam [STATE_WIDTH-1:0] STATE_I2C_NACK_HOLD        = 5'd14;
  localparam [STATE_WIDTH-1:0] STATE_I2C_NACK_RELEASE     = 5'd15;
  localparam [STATE_WIDTH-1:0] STATE_I2C_DATA             = 5'd16;
  localparam [STATE_WIDTH-1:0] STATE_I2C_DATA_ACK_PREP    = 5'd17;
  localparam [STATE_WIDTH-1:0] STATE_I2C_DATA_ACK_HOLD    = 5'd18;
  localparam [STATE_WIDTH-1:0] STATE_I2C_DATA_ACK_RELEASE = 5'd19;

  localparam [STATE_WIDTH-1:0] STATE_SPI_WAIT_CS      = 5'd20;
  localparam [STATE_WIDTH-1:0] STATE_SPI_SHIFT        = 5'd21;
  localparam [STATE_WIDTH-1:0] STATE_SPI_CHANGE       = 5'd22;
  localparam [STATE_WIDTH-1:0] STATE_SPI_END          = 5'd23;
  localparam [STATE_WIDTH-1:0] STATE_SPI_WAIT_CS_HIGH = 5'd24;
  localparam [STATE_WIDTH-1:0] STATE_DISABLED          = 5'd31;

  localparam [1:0] PROTOCOL_I2C = 2'd0;
  localparam [1:0] PROTOCOL_SPI = 2'd1;

  reg [7:0] rx_shift_0;
  reg [7:0] tx_shift_0;
  reg [2:0] bit_index_0;
  reg [7:0] rx_shift_1;
  reg [7:0] tx_shift_1;
  reg [2:0] bit_index_1;

  wire [7:0] shifted_rx_0 = {fire_sample_0[RX_PIN], rx_shift_0[7:1]};
  wire [7:0] shifted_rx_1 = {fire_sample_1[I2C_SDA_PIN], rx_shift_1[7:1]};
  wire [7:0] shifted_spi_rx = {fire_sample_1[SPI_MOSI_PIN], rx_shift_1[7:1]};

  always @(*) begin
    next_state_0 = STATE_UART_IDLE;
    next_tx_bit_0 = tx_shift_0[0];

    case (current_state_0)
      STATE_UART_IDLE: begin
        next_state_0 = STATE_UART_RX_VALIDATE;
      end
      STATE_UART_RX_VALIDATE: begin
        next_state_0 = fire_sample_0[RX_PIN] ?
            STATE_UART_IDLE : STATE_UART_RX_DATA;
      end
      STATE_UART_RX_DATA: begin
        next_state_0 = (bit_index_0 == 3'd7) ?
            STATE_UART_RX_STOP : STATE_UART_RX_DATA;
      end
      STATE_UART_RX_STOP: begin
        next_state_0 = fire_sample_0[RX_PIN] ?
            STATE_UART_TX_START : STATE_UART_IDLE;
      end
      STATE_UART_TX_START: begin
        next_state_0 = STATE_UART_TX_DATA;
        next_tx_bit_0 = tx_shift_0[0];
      end
      STATE_UART_TX_DATA: begin
        next_state_0 = (bit_index_0 == 3'd7) ?
            STATE_UART_TX_STOP : STATE_UART_TX_DATA;
        if (bit_index_0 != 3'd7)
          next_tx_bit_0 = tx_shift_0[1];
      end
      STATE_UART_TX_STOP: begin
        next_state_0 = STATE_UART_IDLE;
      end
      default: begin
        next_state_0 = STATE_UART_IDLE;
      end
    endcase
  end

  always @(*) begin
    next_state_1 = STATE_DISABLED;
    next_tx_bit_1 = tx_shift_1[0];

    case (protocol_select)
      PROTOCOL_I2C: begin
        case (current_state_1)
          STATE_I2C_WAIT_START: begin
            next_state_1 = STATE_I2C_ADDRESS;
          end
          STATE_I2C_ADDRESS: begin
            if (bit_index_1 == 3'd7) begin
              // 0x42 write address, transmitted LSB first, is 0x84.
              next_state_1 = (shifted_rx_1 == 8'h84) ?
                  STATE_I2C_ACK_PREP : STATE_I2C_NACK_PREP;
            end else begin
              next_state_1 = STATE_I2C_ADDRESS;
            end
          end
          STATE_I2C_ACK_PREP: begin
            next_state_1 = STATE_I2C_ACK_HOLD;
          end
          STATE_I2C_ACK_HOLD: begin
            next_state_1 = STATE_I2C_ACK_RELEASE;
          end
          STATE_I2C_ACK_RELEASE: begin
            next_state_1 = STATE_I2C_DATA;
          end
          STATE_I2C_NACK_PREP: begin
            next_state_1 = STATE_I2C_NACK_HOLD;
          end
          STATE_I2C_NACK_HOLD: begin
            next_state_1 = STATE_I2C_NACK_RELEASE;
          end
          STATE_I2C_NACK_RELEASE: begin
            next_state_1 = STATE_I2C_WAIT_START;
          end
          STATE_I2C_DATA: begin
            next_state_1 = (bit_index_1 == 3'd7) ?
                STATE_I2C_DATA_ACK_PREP : STATE_I2C_DATA;
          end
          STATE_I2C_DATA_ACK_PREP: begin
            next_state_1 = STATE_I2C_DATA_ACK_HOLD;
          end
          STATE_I2C_DATA_ACK_HOLD: begin
            next_state_1 = STATE_I2C_DATA_ACK_RELEASE;
          end
          STATE_I2C_DATA_ACK_RELEASE: begin
            next_state_1 = STATE_I2C_WAIT_START;
          end
          default: begin
            next_state_1 = STATE_I2C_WAIT_START;
          end
        endcase
      end
      PROTOCOL_SPI: begin
        case (current_state_1)
          STATE_SPI_WAIT_CS: begin
            next_state_1 = STATE_SPI_SHIFT;
            // The temporary SPI response is 0x3c, whose first LSB is zero.
            next_tx_bit_1 = 1'b0;
          end
          STATE_SPI_SHIFT: begin
            if (sync_inputs[SPI_CS_PIN])
              next_state_1 = STATE_SPI_WAIT_CS_HIGH;
            else if (bit_index_1 == 3'd7)
              next_state_1 = STATE_SPI_END;
            else
              next_state_1 = STATE_SPI_CHANGE;
            if (bit_index_1 != 3'd7)
              // tx_shift_1 is shifted at the sampling edge, so its old bit 1
              // is the value that must be driven after this edge.
              next_tx_bit_1 = tx_shift_1[1];
          end
          STATE_SPI_CHANGE: begin
            next_state_1 = sync_inputs[SPI_CS_PIN] ?
                STATE_SPI_WAIT_CS_HIGH : STATE_SPI_SHIFT;
          end
          STATE_SPI_END: begin
            next_state_1 = STATE_SPI_WAIT_CS_HIGH;
          end
          STATE_SPI_WAIT_CS_HIGH: begin
            next_state_1 = STATE_SPI_WAIT_CS;
          end
          default: begin
            next_state_1 = STATE_SPI_WAIT_CS;
          end
        endcase
      end
      default: begin
        next_state_1 = STATE_DISABLED;
      end
    endcase
  end

  always @(posedge clk) begin
    if (!rst_n) begin
      rx_shift_0       <= 8'h00;
      tx_shift_0       <= 8'h00;
      bit_index_0      <= 3'd0;
      rx_shift_1       <= 8'h00;
      tx_shift_1       <= 8'h00;
      bit_index_1      <= 3'd0;
      received_byte    <= 8'h00;
      received_strobe <= 1'b0;
    end else begin
      received_strobe <= 1'b0;

      if (fire_0) begin
        case (current_state_0)
          STATE_UART_RX_VALIDATE: begin
            if (!fire_sample_0[RX_PIN]) begin
              rx_shift_0  <= 8'h00;
              bit_index_0 <= 3'd0;
            end
          end
          STATE_UART_RX_DATA: begin
            rx_shift_0 <= shifted_rx_0;
            if (bit_index_0 != 3'd7)
              bit_index_0 <= bit_index_0 + 3'd1;
          end
          STATE_UART_RX_STOP: begin
            if (fire_sample_0[RX_PIN]) begin
              received_byte   <= rx_shift_0;
              received_strobe <= 1'b1;
              tx_shift_0      <= rx_shift_0;
              bit_index_0     <= 3'd0;
            end
          end
          STATE_UART_TX_START: begin
            bit_index_0 <= 3'd0;
          end
          STATE_UART_TX_DATA: begin
            tx_shift_0 <= {1'b0, tx_shift_0[7:1]};
            if (bit_index_0 != 3'd7)
              bit_index_0 <= bit_index_0 + 3'd1;
          end
          default: begin
            bit_index_0 <= bit_index_0;
          end
        endcase
      end

      if (fire_1) begin
        case (protocol_select)
          PROTOCOL_I2C: begin
            case (current_state_1)
              STATE_I2C_WAIT_START: begin
                rx_shift_1  <= 8'h00;
                bit_index_1 <= 3'd0;
              end
              STATE_I2C_ADDRESS: begin
                rx_shift_1 <= shifted_rx_1;
                if (bit_index_1 != 3'd7)
                  bit_index_1 <= bit_index_1 + 3'd1;
              end
              STATE_I2C_ACK_RELEASE,
              STATE_I2C_NACK_RELEASE: begin
                bit_index_1 <= 3'd0;
              end
              STATE_I2C_DATA: begin
                rx_shift_1 <= shifted_rx_1;
                if (bit_index_1 == 3'd7) begin
                  received_byte   <= shifted_rx_1;
                  received_strobe <= 1'b1;
                end else begin
                  bit_index_1 <= bit_index_1 + 3'd1;
                end
              end
              default: begin
                bit_index_1 <= bit_index_1;
              end
            endcase
          end
          PROTOCOL_SPI: begin
            case (current_state_1)
              STATE_SPI_WAIT_CS: begin
                rx_shift_1  <= 8'h00;
                tx_shift_1  <= 8'h3c;
                bit_index_1 <= 3'd0;
              end
              STATE_SPI_SHIFT: begin
                if (sync_inputs[SPI_CS_PIN]) begin
                  bit_index_1 <= 3'd0;
                end else begin
                  rx_shift_1 <= shifted_spi_rx;
                  if (bit_index_1 == 3'd7) begin
                    received_byte   <= shifted_spi_rx;
                    received_strobe <= 1'b1;
                  end else begin
                    tx_shift_1  <= {1'b0, tx_shift_1[7:1]};
                    bit_index_1 <= bit_index_1 + 3'd1;
                  end
                end
              end
              STATE_SPI_CHANGE: begin
                if (sync_inputs[SPI_CS_PIN])
                  bit_index_1 <= 3'd0;
              end
              STATE_SPI_WAIT_CS_HIGH: begin
                bit_index_1 <= 3'd0;
              end
              default: begin
                bit_index_1 <= bit_index_1;
              end
            endcase
          end
          default: begin
            bit_index_1 <= 3'd0;
          end
        endcase
      end
    end
  end

endmodule

`default_nettype wire
