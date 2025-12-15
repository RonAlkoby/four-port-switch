import switch_defs::*;

// =============================================================================
// Module description
// =============================================================================
// This module implements a transmit port with arbiter using a Round Robin algorithm.
// It receives packet requests from multiple input ports, selects one based on
// the current priority pointer to ensure fair access (preventing starvation),
// and forwards the selected packet to the output while asserting the
// corresponding grant signal.

// =============================================================================
// Module declaration
// =============================================================================
module tx_port (
	clk,
	rst_n,
	rx_pkts,
	rx_valids,
	grants,
	valid_out,
	pkt_out
);

	// =========================================================================
	// Port declarations
	// =========================================================================
	input  wire                     	 clk;
	input  wire                     	 rst_n;
	input  packet_t [`NUM_PORTS-1:0] 	 rx_pkts;    // Incoming packets from all ports
	input  wire     [`NUM_PORTS-1:0]     rx_valids;  // Incoming valid signals

	output reg      [`NUM_PORTS-1:0]     grants;     // Grants to requesting ports
	output reg                      	 valid_out;  // Valid signal for output packet
	output packet_t                  	 pkt_out;    // Selected packet for transmission

	// =========================================================================
	// Parameters
	// =========================================================================
	parameter PORT_ID = 0;

	// =========================================================================
	// Declaration of wires, regs and variables
	// =========================================================================
	// Wires
	wire [`NUM_PORTS-1:0] requests;      // Vector of request signals targeted at this port

	// Regs
	reg [PTR_W-1:0]       rr_ptr;        // Round Robin pointer state
	reg [PTR_W-1:0]       winner_idx;    // Index of the selected winner
	reg                   winner_found;  // Flag: logic high if a winner exists

	// Variables
	genvar i;                           // Variable for generate loop
	
	// =========================================================================
	// Procedural blocks
	// =========================================================================

	// 1. Combinatorial Logic: Arbitration
	// Determines the next winner based on requests and current pointer
	always_comb begin
		winner_found = |requests; 
		
		if (winner_found) begin
			winner_idx = find_next_grant(requests, rr_ptr);
		end else begin
			winner_idx = '0;
		end
	end
	
	// 2. Combinatorial Logic: Grants
	// Drives the grant signals based on the calculated winner
	always_comb begin
		grants = '0;
		if (winner_found) begin
			grants[winner_idx] = 1'b1;
		end
	end

	// 3. Sequential Logic: Output & State Update
	// Updates the Round Robin pointer and drives the output registers
	always_ff @(posedge clk or negedge rst_n) begin
		if (!rst_n) begin
			valid_out <= 1'b0;
			pkt_out   <= '0;
			rr_ptr    <= '0;
		end else begin
			valid_out <= 1'b0;
			
			if (winner_found) begin
				if (winner_idx == PORT_ID[PTR_W-1:0]) begin
					valid_out <= 1'b0; // Drop packet
				end else begin
					valid_out <= 1'b1; // Forward packet
				end
				pkt_out   <= rx_pkts[winner_idx];
				// Rotate pointer to the next index
				rr_ptr    <= (winner_idx + 1'b1) % `NUM_PORTS;
			end
		end
	end

	// =========================================================================
	// Generate blocks
	// =========================================================================
	
	// Generate the request vector based on validity and target ID
	generate
		for (i = 0; i < `NUM_PORTS; i++) begin : GEN_REQS
			assign requests[i] = rx_valids[i] && rx_pkts[i].target[PORT_ID];
		end
	endgenerate

	// =========================================================================
	// Tasks and functions
	// =========================================================================

	// Function: Find Next Grant
	// Scans for the next active request starting from the current pointer
	function automatic reg [PTR_W-1:0] find_next_grant(
		input reg [`NUM_PORTS-1:0] reqs,
		input reg [PTR_W-1:0]     ptr
	);
		reg [PTR_W-1:0] idx;
		integer j;
		
		for (j = 0; j < `NUM_PORTS; j++) begin
			idx = (ptr + j[PTR_W-1:0]) % `NUM_PORTS;
			
			if (reqs[idx]) begin
				return idx;
			end
		end
		
		return ptr;
	endfunction

endmodule
