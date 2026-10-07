/* Compact runtime timing-contract monitor.
 *
 * Contract records are loaded separately from reaction descriptors.  A
 * violation is observable immediately at the next clock edge, releases the
 * reaction outputs for that edge, freezes the four-entry event window, and
 * leaves the protocol engine running afterwards.
 */

`default_nettype none
`timescale 1ns / 1ps

module chimaera_contract_monitor (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        enabled,
    input  wire [127:0] contract_config_0,
    input  wire [127:0] contract_config_1,
    input  wire [7:0]  sync_inputs,
    input  wire [7:0]  rise_edges,
    input  wire [7:0]  fall_edges,
    output reg         trigger,
    output reg [7:0]   violation_count,
    output reg [3:0]   violation_id,
    output reg [31:0]  violation_timestamp,
    output reg         trace_frozen,
    output reg         release_pulse,
    output wire [31:0]  trace_latest
);

  reg [15:0] high_count [0:7];
  reg [7:0]  high_active;
  reg [15:0] event_timer [0:7];
  reg [7:0]  event_armed;
  reg [7:0]  event_reported;
  reg [7:0]  width_reported;
  reg [7:0]  negative_reported;
  reg [31:0] trace_memory [0:3];
  reg [1:0]  trace_pointer;
  integer pin_index;
  integer combinational_record_index;
  integer sequential_record_index;
  reg        violation_now;
  reg [3:0]  violation_now_id;
  reg [2:0]  violation_now_kind;
  wire [31:0] contract_records [0:7];

  genvar config_index;
  generate
    for (config_index = 0; config_index < 4; config_index = config_index + 1) begin : gen_contract_records
      assign contract_records[config_index] = contract_config_0[config_index * 32 +: 32];
      assign contract_records[config_index + 4] = contract_config_1[config_index * 32 +: 32];
    end
  endgenerate

  assign trace_latest = trace_memory[trace_pointer];

  function edge_seen;
    input [1:0] edge_code;
    input [7:0] rise;
    input [7:0] fall;
    input [2:0] pin;
    begin
      if (edge_code == 2'd1)
        edge_seen = rise[pin];
      else if (edge_code == 2'd2)
        edge_seen = fall[pin[2:0]];
      else
        edge_seen = 1'b0;
    end
  endfunction

  always @(*) begin
    violation_now = 1'b0;
    violation_now_id = 4'h0;
    violation_now_kind = 3'd0;
    for (combinational_record_index = 0; combinational_record_index < 8; combinational_record_index = combinational_record_index + 1) begin
      if (contract_records[combinational_record_index][31] === 1'b1 && !violation_now) begin
        case (contract_records[combinational_record_index][30:28])
          3'd1: begin // stable(pin_a) while pin_b == edge_a[0]
            if (!contract_records[combinational_record_index][27] && !contract_records[combinational_record_index][23] &&
                sync_inputs[contract_records[combinational_record_index][22:20]] == contract_records[combinational_record_index][18] &&
                (rise_edges[contract_records[combinational_record_index][26:24]] || fall_edges[contract_records[combinational_record_index][26:24]])) begin
              violation_now = 1'b1;
              violation_now_id = combinational_record_index[3:0];
              violation_now_kind = 3'd1;
            end
          end
          3'd2: begin // high_width(pin_a) >= duration
            if (!contract_records[combinational_record_index][27] && fall_edges[contract_records[combinational_record_index][26:24]] &&
                high_active[contract_records[combinational_record_index][26:24]] &&
                high_count[contract_records[combinational_record_index][26:24]] < contract_records[combinational_record_index][15:0]) begin
              violation_now = 1'b1;
              violation_now_id = combinational_record_index[3:0];
              violation_now_kind = 3'd2;
            end
          end
          3'd3: begin // high_width(pin_a) <= duration
            if (!contract_records[combinational_record_index][27] && high_active[contract_records[combinational_record_index][26:24]] &&
                high_count[contract_records[combinational_record_index][26:24]] >= contract_records[combinational_record_index][15:0] &&
                !width_reported[combinational_record_index]) begin
              violation_now = 1'b1;
              violation_now_id = combinational_record_index[3:0];
              violation_now_kind = 3'd3;
            end
          end
          3'd4: begin // target event within duration after source event
            if (event_armed[combinational_record_index] && event_timer[combinational_record_index] == 16'd0 &&
                !event_reported[combinational_record_index]) begin
              violation_now = 1'b1;
              violation_now_id = combinational_record_index[3:0];
              violation_now_kind = 3'd4;
            end
          end
          3'd5: begin // not(pin_a == edge_a[0])
            if (!contract_records[combinational_record_index][27] && sync_inputs[contract_records[combinational_record_index][26:24]] == contract_records[combinational_record_index][18] &&
                !negative_reported[combinational_record_index]) begin
              violation_now = 1'b1;
              violation_now_id = combinational_record_index[3:0];
              violation_now_kind = 3'd5;
            end
          end
          default: begin end
        endcase
      end
    end
  end

  always @(posedge clk) begin
    if (!rst_n) begin
      trigger <= 1'b0;
      violation_count <= 8'h00;
      violation_id <= 4'h0;
      violation_timestamp <= 32'h00000000;
      trace_frozen <= 1'b0;
      release_pulse <= 1'b0;
      high_active <= 8'h00;
      event_armed <= 8'h00;
      event_reported <= 8'h00;
      width_reported <= 8'h00;
      negative_reported <= 8'h00;
      trace_pointer <= 2'd0;
      for (pin_index = 0; pin_index < 8; pin_index = pin_index + 1)
        high_count[pin_index] <= 16'd0;
      for (sequential_record_index = 0; sequential_record_index < 8; sequential_record_index = sequential_record_index + 1)
        event_timer[sequential_record_index] <= 16'd0;
      for (sequential_record_index = 0; sequential_record_index < 4; sequential_record_index = sequential_record_index + 1)
        trace_memory[sequential_record_index] <= 32'd0;
    end else begin
      release_pulse <= 1'b0;
      if (enabled) begin
        if (!trigger)
          violation_timestamp <= violation_timestamp + 32'd1;

        if (!trace_frozen) begin
          trace_memory[trace_pointer] <= {sync_inputs, rise_edges, fall_edges, violation_timestamp[7:0]};
          trace_pointer <= trace_pointer + 2'd1;
        end

        for (pin_index = 0; pin_index < 8; pin_index = pin_index + 1) begin
          if (rise_edges[pin_index]) begin
            high_active[pin_index] <= 1'b1;
            high_count[pin_index] <= 16'd1;
          end else if (fall_edges[pin_index]) begin
            high_active[pin_index] <= 1'b0;
            high_count[pin_index] <= 16'd0;
          end else if (high_active[pin_index] && high_count[pin_index] != 16'hffff) begin
            high_count[pin_index] <= high_count[pin_index] + 16'd1;
          end
        end

        for (sequential_record_index = 0; sequential_record_index < 8; sequential_record_index = sequential_record_index + 1) begin
          if (contract_records[sequential_record_index][31] === 1'b1 && contract_records[sequential_record_index][30:28] == 3'd4) begin
            if (edge_seen(contract_records[sequential_record_index][17:16], rise_edges, fall_edges, contract_records[sequential_record_index][22:20])) begin
              event_armed[sequential_record_index] <= 1'b1;
              event_timer[sequential_record_index] <= contract_records[sequential_record_index][15:0];
              event_reported[sequential_record_index] <= 1'b0;
            end else if (event_timer[sequential_record_index] != 16'd0 &&
                         edge_seen(contract_records[sequential_record_index][19:18], rise_edges, fall_edges, contract_records[sequential_record_index][26:24])) begin
              event_armed[sequential_record_index] <= 1'b0;
              event_timer[sequential_record_index] <= 16'd0;
            end else if (event_armed[sequential_record_index] && event_timer[sequential_record_index] != 16'd0) begin
              event_timer[sequential_record_index] <= event_timer[sequential_record_index] - 16'd1;
            end
          end

          if (contract_records[sequential_record_index][31] === 1'b1 && contract_records[sequential_record_index][30:28] == 3'd3 &&
              (!high_active[contract_records[sequential_record_index][26:24]] || fall_edges[contract_records[sequential_record_index][26:24]]))
            width_reported[sequential_record_index] <= 1'b0;
          if (contract_records[sequential_record_index][31] === 1'b1 && contract_records[sequential_record_index][30:28] == 3'd5 &&
              sync_inputs[contract_records[sequential_record_index][26:24]] != contract_records[sequential_record_index][18])
            negative_reported[sequential_record_index] <= 1'b0;
        end

        if (violation_now) begin
          trigger <= 1'b1;
          trace_frozen <= 1'b1;
          release_pulse <= 1'b1;
          if (!trigger)
            violation_id <= violation_now_id;
          if (violation_count != 8'hff)
            violation_count <= violation_count + 8'd1;
          if (!trace_frozen)
            trace_memory[trace_pointer] <= {sync_inputs, rise_edges, fall_edges, violation_timestamp[7:0]};
          if (violation_now_id < 8) begin
            if (violation_now_kind == 3'd3)
              width_reported[violation_now_id[2:0]] <= 1'b1;
            if (violation_now_kind == 3'd4)
              event_reported[violation_now_id[2:0]] <= 1'b1;
            if (violation_now_kind == 3'd5)
              negative_reported[violation_now_id[2:0]] <= 1'b1;
          end
        end
      end
    end
  end

endmodule

`default_nettype wire
