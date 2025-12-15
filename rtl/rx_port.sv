import switch_defs::*;

// =============================================================================
// Module description
// =============================================================================
// This module implements the Receive Port with FSM. It manages the input FIFO and
// handles packet processing. It supports Multicast (sending to multiple ports)
// by holding the packet in the FIFO until all target ports have granted access.
// It uses a registered "pop" signal to acknowledge the FIFO only when transmission
// to all targets is complete.

// =============================================================================
// Module declaration
// =============================================================================

module rx_port (
	clk,
	rst_n,
	valid_in,
	pkt_in,
	grant_vec,
	pkt_out,
	pkt_valid
	);

	// =========================================================================
	// Port declarations
	// =========================================================================
	input  wire                     clk;
	input  wire                     rst_n;
	input  wire                     valid_in;  // Data valid from outside
	input  wire packet_t            pkt_in;    // Data payload from outside
	input  wire [`NUM_PORTS-1:0]    grant_vec; // Grant vector from TX arbiters
	output wire packet_t            pkt_out;   // Packet output (from FIFO)
	output reg                      pkt_valid; // Valid signal to Crossbar
	
	// =========================================================================
	// Parameters
	// =========================================================================
	// FSM State Encoding
	localparam [0:0] ST_FRESH   = 1'b0;
	localparam [0:0] ST_PARTIAL = 1'b1;
	
	// =========================================================================
	// Declaration of wires, regs and variables
	// =========================================================================
	// Wires
	wire                  push;
	wire                  full;
	wire                  empty;
	logic		   	      pop;
	
	// Regs
	reg                   current_state;
	reg                   next_state;
	reg [`NUM_PORTS-1:0]  pending_mask;  // Tracks which ports still need to grant

	reg [`NUM_PORTS-1:0]  targets_to_check;
	reg [`NUM_PORTS-1:0]  remaining_needs;
	reg                   all_serviced;


	// =========================================================================
	// Other modules and lower level instantiations
	// =========================================================================
	// Input FIFO instantiation
	// Buffers incoming packets and provides flow control (full/empty)
	sync_fifo #(.DEPTH(`NUM_PORTS*4)) rx_fifo (
		.clk      (clk),
		.rst_n    (rst_n),
		.push     (push),
		.pop      (pop),
		.data_in  (pkt_in),
		.data_out (pkt_out),
		.full     (full),
		.empty    (empty)
	);
	
	// =========================================================================
	// Continuous assignments
	// =========================================================================
	// Push to FIFO if input is valid and FIFO is not full
	assign push = valid_in && !full;


	// =========================================================================
	// Procedural blocks
	// =========================================================================

	// 1. Helper Logic (Combinatorial)
	always_comb begin
		if (current_state == ST_PARTIAL) begin
			targets_to_check = pending_mask;
		end else begin
			// In FRESH state, check head of FIFO
			targets_to_check = empty ? {`NUM_PORTS{1'b0}} : pkt_out.target; 
		end

		remaining_needs = targets_to_check & ~grant_vec;
		
		// Done if no needs remain AND we actually had a target to check
		all_serviced    = (remaining_needs == {`NUM_PORTS{1'b0}}) && (targets_to_check != {`NUM_PORTS{1'b0}});
	end

	// 2. FSM State Register (Sequential)
	always_ff @(posedge clk or negedge rst_n) begin
		if (!rst_n) 
			current_state <= ST_FRESH;
		else 
			current_state <= next_state;
	end

	// 3. Next State Logic (Combinatorial)
	always_comb begin
		next_state = current_state; 

		case (current_state)
			ST_FRESH: begin
				if (!empty && !all_serviced) begin
					next_state = ST_PARTIAL;
				end
			end

			ST_PARTIAL: begin
				if (all_serviced) begin
					next_state = ST_FRESH;
				end
			end
		endcase
	end

	// 4. Output Logic (Combinatorial)
	always_comb begin
		// Defaults
		pop       = 1'b0;
		pkt_valid = 1'b0;

		case (current_state)
			ST_FRESH: begin
				if (!empty) begin
					pkt_valid = 1'b1;
					
					if (all_serviced) begin
						pop = 1'b1;
					end
				end
			end

			ST_PARTIAL: begin
				pkt_valid = 1'b1;
				
				if (all_serviced) begin
					pop = 1'b1;
				end
			end
		endcase
	end

	// 5. Pending Mask Update (Sequential)
	always_ff @(posedge clk or negedge rst_n) begin
		if (!rst_n) begin
			pending_mask <= {`NUM_PORTS{1'b0}};
		end else begin
			if (current_state == ST_FRESH && !empty && !all_serviced) begin
				pending_mask <= remaining_needs;
			end 
			else if (current_state == ST_PARTIAL && !all_serviced) begin
				pending_mask <= remaining_needs;
			end 
			else if (all_serviced) begin
				pending_mask <= {`NUM_PORTS{1'b0}};
			end
		end
	end

endmodule