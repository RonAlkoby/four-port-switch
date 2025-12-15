import switch_defs::*;

// =============================================================================
// Module description
// =============================================================================
// This module implements a Synchronous FIFO (First-In, First-Out) buffer.
// It uses a ring buffer architecture with separate read and write pointers.
// The module manages 'full' and 'empty' flags to provide flow control
// back to the producer and consumer. A 'count' register tracks the number
// of elements currently in the FIFO.

// =============================================================================
// Module declaration
// =============================================================================
module sync_fifo (
	clk,
	rst_n,
	push,
	pop,
	data_in,
	data_out,
	full,
	empty
);

	// =========================================================================
	// Port declarations
	// =========================================================================
	input  wire          clk;
	input  wire          rst_n;
	input  wire          push;
	input  wire          pop;
	input  wire packet_t data_in;

	output wire packet_t data_out;
	output wire          full;
	output wire          empty;
	
	// =========================================================================
	// Parameters
	// =========================================================================
	parameter DEPTH = 16;
	localparam ADDR_W = $clog2(DEPTH);

	// =========================================================================
	// Declaration of wires, regs and variables
	// =========================================================================
	
	// Memory array (Regs)
	packet_t             mem [0:DEPTH-1];
	
	// Pointers and Counters (Regs)
	reg [ADDR_W-1:0]     wr_ptr;
	reg [ADDR_W-1:0]     rd_ptr;
	reg [ADDR_W:0]       count; // Width is ADDR_W + 1 to hold value 'DEPTH'

	// =========================================================================
	// Continuous assignments
	// =========================================================================
	
	// Status flags based on item count
	assign full  = (count == DEPTH);
	assign empty = (count == 0);
	
	// Data output (Asynchronous read logic)
	assign data_out = mem[rd_ptr];

	// =========================================================================
	// Procedural blocks
	// =========================================================================

	// Sequential Logic: Pointers, Memory Write, and Count Update
	always_ff @(posedge clk or negedge rst_n) begin
		if (!rst_n) begin
			wr_ptr <= 0;
			rd_ptr <= 0;
			count  <= 0;
			// Note: 'mem' is not reset to save logic, invalid data should ignored via 'empty'
		end else begin
			// Write operation
			if (push && !full) begin
				mem[wr_ptr] <= data_in;
				wr_ptr      <= wr_ptr + 1'b1;
			end

			// Read operation (Pointer update only)
			if (pop && !empty) begin
				rd_ptr <= rd_ptr + 1'b1;
			end

			// Count update logic
			// Increment if pushing but not popping
			if (push && !full && !(pop && !empty)) begin
				count <= count + 1;
			end
			// Decrement if popping but not pushing
			else if (pop && !empty && !(push && !full)) begin
				count <= count - 1;
			end
			// If simultaneous push and pop, count remains unchanged
		end
	end

endmodule