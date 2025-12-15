import switch_defs::*;

module switch_4port(
	input logic clk, 
	input logic rst_n,
	port_if port0, 
	port_if port1, 
	port_if port2, 
	port_if port3
);

	localparam NUM_PORTS = `NUM_PORTS;

	packet_t [NUM_PORTS-1:0] rx_pkt_in_structs; 
	packet_t [NUM_PORTS-1:0] tx_pkt_out_structs;
	wire     [NUM_PORTS-1:0] rx_valids_in;
	wire     [NUM_PORTS-1:0] tx_valids_out;

	assign rx_pkt_in_structs[0] = {port0.source_in, port0.target_in, port0.data_in};
	assign rx_pkt_in_structs[1] = {port1.source_in, port1.target_in, port1.data_in};
	assign rx_pkt_in_structs[2] = {port2.source_in, port2.target_in, port2.data_in};
	assign rx_pkt_in_structs[3] = {port3.source_in, port3.target_in, port3.data_in};
	
	assign rx_valids_in[0] = port0.valid_in;
	assign rx_valids_in[1] = port1.valid_in;
	assign rx_valids_in[2] = port2.valid_in;
	assign rx_valids_in[3] = port3.valid_in;

	assign {port0.source_out, port0.target_out, port0.data_out} = tx_pkt_out_structs[0];
	assign {port1.source_out, port1.target_out, port1.data_out} = tx_pkt_out_structs[1];
	assign {port2.source_out, port2.target_out, port2.data_out} = tx_pkt_out_structs[2];
	assign {port3.source_out, port3.target_out, port3.data_out} = tx_pkt_out_structs[3];
	
	assign port0.valid_out = tx_valids_out[0];
	assign port1.valid_out = tx_valids_out[1];
	assign port2.valid_out = tx_valids_out[2];
	assign port3.valid_out = tx_valids_out[3];


	packet_t [NUM_PORTS-1:0] matrix_pkts;      
	wire     [NUM_PORTS-1:0] matrix_valids;    
	wire     [NUM_PORTS-1:0] matrix_grants [NUM_PORTS-1:0];

	genvar i;
	generate
		for (i = 0; i < NUM_PORTS; i++) begin : PORTS
			logic [NUM_PORTS-1:0] my_grant_vec;
			
			always_comb begin
				for (int j = 0; j < NUM_PORTS; j++) begin
					my_grant_vec[j] = matrix_grants[j][i];
				end
			end

			rx_port rx_inst (
				.clk(clk), .rst_n(rst_n),
				.valid_in(rx_valids_in[i]), 
				.pkt_in(rx_pkt_in_structs[i]),
				.pkt_out(matrix_pkts[i]), 
				.pkt_valid(matrix_valids[i]), 
				.grant_vec(my_grant_vec)
			);

			
			tx_port #(.PORT_ID(i)) tx_inst (
				.clk(clk), .rst_n(rst_n),
				.rx_pkts(matrix_pkts), 
				.rx_valids(matrix_valids),
				.grants(matrix_grants[i]), 
				.valid_out(tx_valids_out[i]), 
				.pkt_out(tx_pkt_out_structs[i])
			);

		end
	endgenerate

endmodule