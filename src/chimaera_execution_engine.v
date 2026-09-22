/*
 * Minimum shared execution-engine slice for Phase 2.
 *
 * Shifting, bit counting and conditional state selection live here rather than
 * in the reaction cell.  The interface is intentionally state-descriptor based
 * so another reaction cell can share this datapath in Phase 4.
 */

`default_nettype none
`timescale 1ns / 1ps

module chimaera_execution_engine #(
    parameter integer STATE_WIDTH = 4,
    parameter integer RX_PIN = 0
) (
    input  wire                   clk,
    input  wire                   rst_n,
    input  wire                   fire,
    input  wire [STATE_WIDTH-1:0] current_state,
    input  wire [7:0]             fire_sample,
    output reg  [STATE_WIDTH-1:0] next_state,
    output reg                    next_tx_bit,
    output reg  [7:0]             received_byte,
    output reg                    received_strobe
);

  localparam [STATE_WIDTH-1:0] STATE_IDLE        = 0;
  localparam [STATE_WIDTH-1:0] STATE_RX_VALIDATE = 1;
  localparam [STATE_WIDTH-1:0] STATE_RX_DATA     = 2;
  localparam [STATE_WIDTH-1:0] STATE_RX_STOP     = 3;
  localparam [STATE_WIDTH-1:0] STATE_TX_START    = 4;
  localparam [STATE_WIDTH-1:0] STATE_TX_DATA     = 5;
  localparam [STATE_WIDTH-1:0] STATE_TX_STOP     = 6;

  reg [7:0] rx_shift;
  reg [7:0] tx_shift;
  reg [2:0] bit_index;

  always @(*) begin
    next_state  = STATE_IDLE;
    next_tx_bit = tx_shift[0];

    case (current_state)
      STATE_IDLE: begin
        next_state = STATE_RX_VALIDATE;
      end
      STATE_RX_VALIDATE: begin
        next_state = fire_sample[RX_PIN] ? STATE_IDLE : STATE_RX_DATA;
      end
      STATE_RX_DATA: begin
        next_state = (bit_index == 3'd7) ? STATE_RX_STOP : STATE_RX_DATA;
      end
      STATE_RX_STOP: begin
        next_state = fire_sample[RX_PIN] ? STATE_TX_START : STATE_IDLE;
      end
      STATE_TX_START: begin
        next_state  = STATE_TX_DATA;
        next_tx_bit = tx_shift[0];
      end
      STATE_TX_DATA: begin
        next_state = (bit_index == 3'd7) ? STATE_TX_STOP : STATE_TX_DATA;
        // The next descriptor is predecoded on this cycle, before the shift
        // register updates at the edge.
        next_tx_bit = tx_shift[1];
      end
      STATE_TX_STOP: begin
        next_state = STATE_IDLE;
      end
      default: begin
        next_state = STATE_IDLE;
      end
    endcase
  end

  always @(posedge clk) begin
    if (!rst_n) begin
      rx_shift       <= 8'h00;
      tx_shift       <= 8'h00;
      bit_index      <= 3'd0;
      received_byte  <= 8'h00;
      received_strobe <= 1'b0;
    end else begin
      received_strobe <= 1'b0;

      if (fire) begin
        case (current_state)
          STATE_RX_VALIDATE: begin
            if (!fire_sample[RX_PIN]) begin
              rx_shift  <= 8'h00;
              bit_index <= 3'd0;
            end
          end
          STATE_RX_DATA: begin
            rx_shift <= {fire_sample[RX_PIN], rx_shift[7:1]};
            if (bit_index != 3'd7)
              bit_index <= bit_index + 3'd1;
          end
          STATE_RX_STOP: begin
            if (fire_sample[RX_PIN]) begin
              received_byte   <= rx_shift;
              received_strobe <= 1'b1;
              tx_shift        <= rx_shift;
              bit_index       <= 3'd0;
            end
          end
          STATE_TX_START: begin
            bit_index <= 3'd0;
          end
          STATE_TX_DATA: begin
            tx_shift <= {1'b0, tx_shift[7:1]};
            if (bit_index != 3'd7)
              bit_index <= bit_index + 3'd1;
          end
          default: begin
            bit_index <= bit_index;
          end
        endcase
      end
    end
  end

endmodule

`default_nettype wire
