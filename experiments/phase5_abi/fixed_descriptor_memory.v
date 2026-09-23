/*
 * Phase 5 ABI sizing experiment only; this is not production loader RTL.
 *
 * A descriptor is written as eight 16-bit configuration words and read as one
 * 128-bit value.  Parameter sweeps expose the generic cell cost of preserving a
 * one-cycle descriptor read at different state counts.
 */

`default_nettype none

module chimaera_fixed_descriptor_memory #(
    parameter integer ADDRESS_WIDTH = 5,
    parameter integer DEPTH = 32
) (
    input  wire                       clk,
    input  wire                       write_enable,
    input  wire [ADDRESS_WIDTH-1:0]   write_state,
    input  wire [2:0]                 write_word,
    input  wire [15:0]                write_data,
    input  wire [ADDRESS_WIDTH-1:0]   read_state,
    output reg  [127:0]               descriptor
);

  reg [127:0] memory [0:DEPTH-1];

  always @(posedge clk) begin
    if (write_enable)
      memory[write_state][write_word * 16 +: 16] <= write_data;
    descriptor <= memory[read_state];
  end

endmodule

module abi_fixed_32 (
    input wire clk,
    input wire we,
    input wire [4:0] wa,
    input wire [2:0] ww,
    input wire [15:0] wd,
    input wire [4:0] ra,
    output wire [127:0] q
);
  chimaera_fixed_descriptor_memory #(.ADDRESS_WIDTH(5), .DEPTH(32)) memory (
      .clk(clk), .write_enable(we), .write_state(wa), .write_word(ww),
      .write_data(wd), .read_state(ra), .descriptor(q)
  );
endmodule

module abi_fixed_64 (
    input wire clk,
    input wire we,
    input wire [5:0] wa,
    input wire [2:0] ww,
    input wire [15:0] wd,
    input wire [5:0] ra,
    output wire [127:0] q
);
  chimaera_fixed_descriptor_memory #(.ADDRESS_WIDTH(6), .DEPTH(64)) memory (
      .clk(clk), .write_enable(we), .write_state(wa), .write_word(ww),
      .write_data(wd), .read_state(ra), .descriptor(q)
  );
endmodule

module abi_fixed_128 (
    input wire clk,
    input wire we,
    input wire [6:0] wa,
    input wire [2:0] ww,
    input wire [15:0] wd,
    input wire [6:0] ra,
    output wire [127:0] q
);
  chimaera_fixed_descriptor_memory #(.ADDRESS_WIDTH(7), .DEPTH(128)) memory (
      .clk(clk), .write_enable(we), .write_state(wa), .write_word(ww),
      .write_data(wd), .read_state(ra), .descriptor(q)
  );
endmodule

`default_nettype wire
