`define NUM_PORTS 4
`define DATA_WIDTH 8

package switch_defs;

	localparam PTR_W = $clog2(`NUM_PORTS);
	
	typedef struct packed {
		logic [`NUM_PORTS-1:0]  source;
		logic [`NUM_PORTS-1:0]  target;
		logic [`DATA_WIDTH-1:0] data;
	} packet_t;

endpackage