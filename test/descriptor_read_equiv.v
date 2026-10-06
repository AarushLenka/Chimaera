// Decode-before-selection equals selection-before-decode, for arbitrary
// candidate addresses, branch/arbitration decisions and memory contents.
module descriptor_read_equiv (
    input  wire [39:0]  candidates,
    input  wire [6:0]   decision,
    input  wire [1023:0] words,
    output wire        equivalent
);
  wire [31:0] data;
  chimaera_descriptor_read_slice #(.READ_WIDTH(32)) dut (
      .candidates(candidates),
      .decision(decision),
      .words(words),
      .data(data)
  );
  wire [4:0] request_0 = decision[4] ? candidates[19:15] :
      decision[2] ? candidates[14:10] :
      decision[0] ? candidates[4:0] : candidates[9:5];
  wire [4:0] request_1 = decision[5] ? candidates[39:35] :
      decision[3] ? candidates[34:30] :
      decision[1] ? candidates[24:20] : candidates[29:25];
  wire [4:0] address = decision[6] ? request_1 : request_0;
  assign equivalent = data == words[address*32 +: 32];
endmodule
