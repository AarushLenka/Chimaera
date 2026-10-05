// Combinational proof against the original indexed read for every address and
// arbitrary descriptor contents. Simulation separately covers unknown words.
module descriptor_read_equiv (
    input  wire [4:0]   address,
    input  wire [1023:0] words,
    output wire        equivalent
);
  wire [31:0] data;
  chimaera_descriptor_read_slice #(.READ_WIDTH(32)) dut (
      .address(address),
      .words(words),
      .data(data)
  );
  assign equivalent = data == words[address*32 +: 32];
endmodule
