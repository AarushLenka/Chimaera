// Independent truth-table reference for the seven descriptor event kinds.
// All pin vectors, masks, values and all 16 kind encodings are SAT inputs.
`default_nettype none
module event_matcher_equiv (
    input wire [3:0] event_kind,
    input wire [7:0] event_mask, event_value, level_mask, level_value,
    input wire [7:0] sync_inputs, rise_edges, fall_edges,
    output wire equivalent
);
  wire actual;
  chimaera_event_matcher candidate (
      .event_kind(event_kind), .event_mask(event_mask),
      .event_value(event_value), .level_mask(level_mask),
      .level_value(level_value), .sync_inputs(sync_inputs),
      .rise_edges(rise_edges), .fall_edges(fall_edges),
      .event_match(actual)
  );
  wire rise = |(rise_edges & event_mask);
  wire fall = |(fall_edges & event_mask);
  wire pin_match = ~|((sync_inputs ^ event_value) & event_mask);
  wire level_match = ~|((sync_inputs ^ level_value) & level_mask);
  wire [7:0] truth_table = {
      fall | level_match, rise | level_match,
      fall & level_match, rise & level_match,
      pin_match, fall, rise, 1'b0
  };
  wire expected = !event_kind[3] && truth_table[event_kind[2:0]];
  assign equivalent = actual == expected;
endmodule
`default_nettype wire
