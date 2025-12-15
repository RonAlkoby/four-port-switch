import switch_defs::*;

module switch_test;

  localparam NUM_PORTS = `NUM_PORTS;

  // Clock and reset
  bit clk = 0;
  always #5 clk = ~clk;
  bit rst_n;

  // Interfaces and DUT
  port_if port0(clk, rst_n);
  port_if port1(clk, rst_n);
  port_if port2(clk, rst_n);
  port_if port3(clk, rst_n);

  switch_4port dut (
	.clk  (clk),
	.rst_n(rst_n),
	.port0(port0),
	.port1(port1),
	.port2(port2),
	.port3(port3)
  );

  // Standalone rx_port instance for FIFO stress test
  logic                 rxov_valid_in;
  packet_t              rxov_pkt_in;
  logic [NUM_PORTS-1:0] rxov_grant_vec;
  packet_t              rxov_pkt_out;
  logic                 rxov_pkt_valid;

  rx_port rx_overflow (
	.clk      (clk),
	.rst_n    (rst_n),
	.valid_in (rxov_valid_in),
	.pkt_in   (rxov_pkt_in),
	.grant_vec(rxov_grant_vec),
	.pkt_out  (rxov_pkt_out),
	.pkt_valid(rxov_pkt_valid)
  );

  // Simple PASS/FAIL printer
  function void report_status(string msg, bit pass);
	if (pass)
	  $display("\033[1;32m[PASS] %s\033[0m", msg);
	else
	  $display("\033[1;31m[FAIL] %s\033[0m", msg);
  endfunction

  // Reset task
  task automatic do_reset();
	$display("\n=== RESET ===");
	rst_n = 0;
	repeat (10) @(posedge clk);
	rst_n = 1;
	repeat (5) @(posedge clk);
  endtask

  // ------------------------------------------------------------
  // Test 1:
  // Checks multicast behavior from Port 0 to Ports 2 and 3.
  // Verifies that only P2 and P3 receive the packet, and P0/P1 do not.
  // ------------------------------------------------------------
  task automatic test_multicast();
	packet_t s;
	packet_t rx0, rx1, rx2, rx3;
	bit got0, got1, got2, got3;

	$display("\n--- TEST 1: Multicast P0 -> P2,P3 ---");

	got0 = 0; got1 = 0; got2 = 0; got3 = 0;

	s.source = 4'b0001;  // Port 0
	s.target = 4'b1100;  // Ports 2 & 3
	s.data   = 8'h22;

	$display("  TX: Port 0 | src=%b tgt=%b data=0x%h", s.source, s.target, s.data);

	fork
	  port0.drive_packet(s);

	  // Expected: P2 + P3
	  begin
		fork
		  begin port2.collect_packet(rx2); got2 = 1; end
		  begin port3.collect_packet(rx3); got3 = 1; end
		join
	  end

	  // Unexpected: P0
	  begin : mon0
		packet_t tmp;
		fork
		  begin port0.collect_packet(tmp); rx0 = tmp; got0 = 1; end
		  begin repeat (100) @(posedge clk); end
		join_any
		disable fork;
	  end

	  // Unexpected: P1
	  begin : mon1
		packet_t tmp;
		fork
		  begin port1.collect_packet(tmp); rx1 = tmp; got1 = 1; end
		  begin repeat (100) @(posedge clk); end
		join_any
		disable fork;
	  end
	join

	$display("  RX Port 0: EXPECT no packet | got=%0b%s",
			 got0, got0 ? $sformatf(" (src=%b tgt=%b data=0x%h)", rx0.source, rx0.target, rx0.data) : "");
	$display("  RX Port 1: EXPECT no packet | got=%0b%s",
			 got1, got1 ? $sformatf(" (src=%b tgt=%b data=0x%h)", rx1.source, rx1.target, rx1.data) : "");
	$display("  RX Port 2: EXPECT packet    | got=%0b%s",
			 got2, got2 ? $sformatf(" (src=%b tgt=%b data=0x%h)", rx2.source, rx2.target, rx2.data) : "");
	$display("  RX Port 3: EXPECT packet    | got=%0b%s",
			 got3, got3 ? $sformatf(" (src=%b tgt=%b data=0x%h)", rx3.source, rx3.target, rx3.data) : "");

	report_status("Multicast P2 got correct data", got2 && (rx2.data == s.data));
	report_status("Multicast P3 got correct data", got3 && (rx3.data == s.data));
	report_status("No other ports received multicast", !got0 && !got1);
  endtask

  // ------------------------------------------------------------
  // Test 2:
  // Checks broadcast behavior from Port 0 to all ports, while ensuring
  // no self-loopback occurs (P0 should NOT receive its own broadcast).
  // ------------------------------------------------------------
  task automatic test_broadcast_no_self();
	packet_t s;
	packet_t rx0, rx1, rx2, rx3;
	bit got0, got1, got2, got3;

	$display("\n--- TEST 2: Broadcast P0 -> ALL (no loopback to P0) ---");

	got0 = 0; got1 = 0; got2 = 0; got3 = 0;

	s.source = 4'b0001;   // Port 0
	s.target = 4'b1111;   // All ports (self masked inside rx_port)
	s.data   = 8'hBC;

	$display("  TX: Port 0 | src=%b tgt=%b data=0x%h", s.source, s.target, s.data);

	fork
	  port0.drive_packet(s);

	  // Expected: P1,P2,P3
	  begin
		fork
		  begin port1.collect_packet(rx1); got1 = 1; end
		  begin port2.collect_packet(rx2); got2 = 1; end
		  begin port3.collect_packet(rx3); got3 = 1; end
		join
	  end

	  // Unexpected: P0 (no self-loop)
	  begin : mon0
		packet_t tmp;
		fork
		  begin port0.collect_packet(tmp); rx0 = tmp; got0 = 1; end
		  begin repeat (100) @(posedge clk); end
		join_any
		disable fork;
	  end
	join

	$display("  RX Port 0: EXPECT no packet | got=%0b%s",
			 got0, got0 ? $sformatf(" (src=%b tgt=%b data=0x%h)", rx0.source, rx0.target, rx0.data) : "");
	$display("  RX Port 1: EXPECT packet    | got=%0b%s",
			 got1, got1 ? $sformatf(" (src=%b tgt=%b data=0x%h)", rx1.source, rx1.target, rx1.data) : "");
	$display("  RX Port 2: EXPECT packet    | got=%0b%s",
			 got2, got2 ? $sformatf(" (src=%b tgt=%b data=0x%h)", rx2.source, rx2.target, rx2.data) : "");
	$display("  RX Port 3: EXPECT packet    | got=%0b%s",
			 got3, got3 ? $sformatf(" (src=%b tgt=%b data=0x%h)", rx3.source, rx3.target, rx3.data) : "");

	report_status("Broadcast P1 ok", got1 && (rx1.data == s.data));
	report_status("Broadcast P2 ok", got2 && (rx2.data == s.data));
	report_status("Broadcast P3 ok", got3 && (rx3.data == s.data));
	report_status("No loopback to P0", !got0);
  endtask

  // ------------------------------------------------------------
  // Test 3:
  // Checks arbitration when two different inputs send to the same output.
  // Here P0 and P2 both target P1, and P1 must receive both packets (order doesn't matter).
  // ------------------------------------------------------------
  task automatic test_arbitration_two_to_one();
	packet_t s0, s2;
	packet_t rx0, rx1, rx2, rx3;
	packet_t first, second;
	bit got0, got1, got2, got3;
	bit ok;

	$display("\n--- TEST 3: Contention P0->P1 and P2->P1 ---");

	got0 = 0; got1 = 0; got2 = 0; got3 = 0;

	s0.source = 4'b0001; s0.target = 4'b0010; s0.data = 8'hAA; // P0->P1
	s2.source = 4'b0100; s2.target = 4'b0010; s2.data = 8'hBB; // P2->P1

	$display("  TX: Port 0 | src=%b tgt=%b data=0x%h", s0.source, s0.target, s0.data);
	$display("  TX: Port 2 | src=%b tgt=%b data=0x%h", s2.source, s2.target, s2.data);

	fork
	  port0.drive_packet(s0);
	  port2.drive_packet(s2);

	  // Expected: two packets on P1
	  begin
		port1.collect_packet(first);
		port1.collect_packet(second);
		got1 = 1;
	  end

	  // Unexpected: P0
	  begin : mon0
		packet_t tmp;
		fork
		  begin port0.collect_packet(tmp); rx0 = tmp; got0 = 1; end
		  begin repeat (100) @(posedge clk); end
		join_any
		disable fork;
	  end

	  // Unexpected: P2
	  begin : mon2
		packet_t tmp;
		fork
		  begin port2.collect_packet(tmp); rx2 = tmp; got2 = 1; end
		  begin repeat (100) @(posedge clk); end
		join_any
		disable fork;
	  end

	  // Unexpected: P3
	  begin : mon3
		packet_t tmp;
		fork
		  begin port3.collect_packet(tmp); rx3 = tmp; got3 = 1; end
		  begin repeat (100) @(posedge clk); end
		join_any
		disable fork;
	  end
	join

	$display("  RX Port 1 first : src=%b tgt=%b data=0x%h", first.source,  first.target,  first.data);
	$display("  RX Port 1 second: src=%b tgt=%b data=0x%h", second.source, second.target, second.data);

	$display("  RX Port 0: EXPECT no packet | got=%0b%s",
			 got0, got0 ? $sformatf(" (src=%b tgt=%b data=0x%h)", rx0.source, rx0.target, rx0.data) : "");
	$display("  RX Port 1: EXPECT 2 packets | got=%0b", got1);
	$display("  RX Port 2: EXPECT no packet | got=%0b%s",
			 got2, got2 ? $sformatf(" (src=%b tgt=%b data=0x%h)", rx2.source, rx2.target, rx2.data) : "");
	$display("  RX Port 3: EXPECT no packet | got=%0b%s",
			 got3, got3 ? $sformatf(" (src=%b tgt=%b data=0x%h)", rx3.source, rx3.target, rx3.data) : "");

	ok = (((first.data  == s0.data) && (second.data == s2.data)) ||
		  ((first.data  == s2.data) && (second.data == s0.data)));

	report_status("Arbitration: both packets reached P1 (order don't care)", ok);
	report_status("No extra packets on other ports", !got0 && !got2 && !got3);
  endtask

  // ------------------------------------------------------------
  // Test 4:
  // Checks arbitration under heavy contention with three inputs targeting the same output.
  // Here P0, P1, and P3 all target P2; P2 must receive all three packets (order doesn't matter).
  // ------------------------------------------------------------
  task automatic test_heavy_contention_all_to_p2();
	packet_t s0, s1, s3;
	packet_t rx0, rx1, rx2, rx3;
	packet_t r_a, r_b, r_c;
	bit got0, got1, got2, got3;
	bit seen_a, seen_b, seen_c;
	bit ok;

	$display("\n--- TEST 4: Heavy contention P0,P1,P3 -> P2 ---");

	got0 = 0; got1 = 0; got2 = 0; got3 = 0;
	seen_a = 0; seen_b = 0; seen_c = 0;
	ok = 0;

	// All send to P2
	s0.source = 4'b0001; s0.target = 4'b0100; s0.data = 8'hA0; // P0->P2
	s1.source = 4'b0010; s1.target = 4'b0100; s1.data = 8'hB1; // P1->P2
	s3.source = 4'b1000; s3.target = 4'b0100; s3.data = 8'hC3; // P3->P2

	$display("  TX: Port 0 | src=%b tgt=%b data=0x%h", s0.source, s0.target, s0.data);
	$display("  TX: Port 1 | src=%b tgt=%b data=0x%h", s1.source, s1.target, s1.data);
	$display("  TX: Port 3 | src=%b tgt=%b data=0x%h", s3.source, s3.target, s3.data);

	fork
	  port0.drive_packet(s0);
	  port1.drive_packet(s1);
	  port3.drive_packet(s3);

	  // Expect three packets on P2 (order don't care)
	  begin
		port2.collect_packet(r_a);
		port2.collect_packet(r_b);
		port2.collect_packet(r_c);
		got2 = 1;
	  end

	  // Unexpected on P0
	  begin : mon0
		packet_t tmp;
		fork
		  begin port0.collect_packet(tmp); rx0 = tmp; got0 = 1; end
		  begin repeat (200) @(posedge clk); end
		join_any
		disable fork;
	  end

	  // Unexpected on P1
	  begin : mon1
		packet_t tmp;
		fork
		  begin port1.collect_packet(tmp); rx1 = tmp; got1 = 1; end
		  begin repeat (200) @(posedge clk); end
		join_any
		disable fork;
	  end

	  // Unexpected on P3
	  begin : mon3
		packet_t tmp;
		fork
		  begin port3.collect_packet(tmp); rx3 = tmp; got3 = 1; end
		  begin repeat (200) @(posedge clk); end
		join_any
		disable fork;
	  end
	join

	$display("  RX Port 2 packet 1: src=%b tgt=%b data=0x%h", r_a.source, r_a.target, r_a.data);
	$display("  RX Port 2 packet 2: src=%b tgt=%b data=0x%h", r_b.source, r_b.target, r_b.data);
	$display("  RX Port 2 packet 3: src=%b tgt=%b data=0x%h", r_c.source, r_c.target, r_c.data);

	// Check that all three data values appeared (order-free)
	seen_a = (r_a.data == s0.data) || (r_b.data == s0.data) || (r_c.data == s0.data);
	seen_b = (r_a.data == s1.data) || (r_b.data == s1.data) || (r_c.data == s1.data);
	seen_c = (r_a.data == s3.data) || (r_b.data == s3.data) || (r_c.data == s3.data);
	ok     = seen_a && seen_b && seen_c;

	$display("  RX Port 0: EXPECT no packet | got=%0b%s",
			 got0, got0 ? $sformatf(" (src=%b tgt=%b data=0x%h)", rx0.source, rx0.target, rx0.data) : "");
	$display("  RX Port 1: EXPECT no packet | got=%0b%s",
			 got1, got1 ? $sformatf(" (src=%b tgt=%b data=0x%h)", rx1.source, rx1.target, rx1.data) : "");
	$display("  RX Port 2: EXPECT 3 packets | got=%0b", got2);
	$display("  RX Port 3: EXPECT no packet | got=%0b%s",
			 got3, got3 ? $sformatf(" (src=%b tgt=%b data=0x%h)", rx3.source, rx3.target, rx3.data) : "");

	report_status("All three packets reached P2 (order don't care)", ok);
	report_status("No extra packets on P0/P1/P3", !got0 && !got1 && !got3);
  endtask

  // ------------------------------------------------------------
  // Test 5:
  // Sends two consecutive packets from P0 to P1 without idle cycles in between.
  // Verifies that P1 receives both packets in order and no other port receives packets.
  // ------------------------------------------------------------
  task automatic test_back_to_back_p0_to_p1();
	packet_t s0, s1;
	packet_t r0, r1;
	packet_t rx0, rx2, rx3;
	bit got0, got1, got2, got3;

	$display("\n--- TEST 5: Back-to-back two packets P0 -> P1 ---");

	got0 = 0; got1 = 0; got2 = 0; got3 = 0;

	s0.source = 4'b0001; s0.target = 4'b0010; s0.data = 8'h55;
	s1.source = 4'b0001; s1.target = 4'b0010; s1.data = 8'h66;

	$display("  TX: Port 0 pkt0 | src=%b tgt=%b data=0x%h", s0.source, s0.target, s0.data);
	$display("  TX: Port 0 pkt1 | src=%b tgt=%b data=0x%h", s1.source, s1.target, s1.data);

	fork
	  // Two back-to-back sends
	  begin
		port0.drive_packet(s0);
		port0.drive_packet(s1);
	  end

	  // Expect two packets on P1
	  begin
		port1.collect_packet(r0);
		port1.collect_packet(r1);
		got1 = 1;
	  end

	  // Unexpected on P0
	  begin : mon0
		packet_t tmp;
		fork
		  begin port0.collect_packet(tmp); rx0 = tmp; got0 = 1; end
		  begin repeat (200) @(posedge clk); end
		join_any
		disable fork;
	  end

	  // Unexpected on P2
	  begin : mon2
		packet_t tmp;
		fork
		  begin port2.collect_packet(tmp); rx2 = tmp; got2 = 1; end
		  begin repeat (200) @(posedge clk); end
		join_any
		disable fork;
	  end

	  // Unexpected on P3
	  begin : mon3
		packet_t tmp;
		fork
		  begin port3.collect_packet(tmp); rx3 = tmp; got3 = 1; end
		  begin repeat (200) @(posedge clk); end
		join_any
		disable fork;
	  end
	join

	$display("  RX P1 pkt0: src=%b tgt=%b data=0x%h", r0.source, r0.target, r0.data);
	$display("  RX P1 pkt1: src=%b tgt=%b data=0x%h", r1.source, r1.target, r1.data);

	$display("  RX Port 0: EXPECT no packet | got=%0b", got0);
	$display("  RX Port 1: EXPECT 2 packets | got=%0b", got1);
	$display("  RX Port 2: EXPECT no packet | got=%0b", got2);
	$display("  RX Port 3: EXPECT no packet | got=%0b", got3);

	report_status("Back-to-back P0->P1: first packet correct",
				  (r0.data == s0.data));
	report_status("Back-to-back P0->P1: second packet correct",
				  (r1.data == s1.data));
	report_status("No extra packets on other ports",
				  !got0 && !got2 && !got3);
  endtask

  // ------------------------------------------------------------
  // Test 6:
  // Sends multicast from P0 to P1+P2 and simultaneously sends unicast from P3 to P2.
  // Verifies P1 receives the multicast packet, and P2 receives both packets (order doesn't matter).
  // ------------------------------------------------------------
  task automatic test_mixed_multicast_unicast_to_p2();
	packet_t s0, s3;
	packet_t r1, r2a, r2b;
	packet_t rx0, rx3;
	bit got0, got1, got2, got3;
	bit seen_mult, seen_uni;
	bit ok;

	$display("\n--- TEST 6: Mixed multicast/unicast to P2 ---");

	got0 = 0; got1 = 0; got2 = 0; got3 = 0;
	seen_mult = 0; seen_uni = 0;
	ok = 0;

	// P0 -> P1,P2 (multicast)
	s0.source = 4'b0001; s0.target = 4'b0110; s0.data = 8'hD0;
	// P3 -> P2 (unicast)
	s3.source = 4'b1000; s3.target = 4'b0100; s3.data = 8'hE3;

	$display("  TX: Port 0 (multicast) | src=%b tgt=%b data=0x%h", s0.source, s0.target, s0.data);
	$display("  TX: Port 3 (unicast)   | src=%b tgt=%b data=0x%h", s3.source, s3.target, s3.data);

	fork
	  port0.drive_packet(s0);
	  port3.drive_packet(s3);

	  // Expect one packet on P1 (only multicast)
	  begin
		port1.collect_packet(r1);
		got1 = 1;
	  end

	  // Expect two packets on P2: one from P0, one from P3
	  begin
		port2.collect_packet(r2a);
		port2.collect_packet(r2b);
		got2 = 1;
	  end

	  // Unexpected on P0
	  begin : mon0
		packet_t tmp;
		fork
		  begin port0.collect_packet(tmp); rx0 = tmp; got0 = 1; end
		  begin repeat (200) @(posedge clk); end
		join_any
		disable fork;
	  end

	  // Unexpected on P3
	  begin : mon3
		packet_t tmp;
		fork
		  begin port3.collect_packet(tmp); rx3 = tmp; got3 = 1; end
		  begin repeat (200) @(posedge clk); end
		join_any
		disable fork;
	  end
	join

	$display("  RX P1:  src=%b tgt=%b data=0x%h", r1.source,  r1.target,  r1.data);
	$display("  RX P2a: src=%b tgt=%b data=0x%h", r2a.source, r2a.target, r2a.data);
	$display("  RX P2b: src=%b tgt=%b data=0x%h", r2b.source, r2b.target, r2b.data);

	seen_mult = (r2a.data == s0.data) || (r2b.data == s0.data);
	seen_uni  = (r2a.data == s3.data) || (r2b.data == s3.data);
	ok        = seen_mult && seen_uni;

	$display("  RX Port 0: EXPECT no packet | got=%0b", got0);
	$display("  RX Port 1: EXPECT 1 packet  | got=%0b", got1);
	$display("  RX Port 2: EXPECT 2 packets | got=%0b", got2);
	$display("  RX Port 3: EXPECT no packet | got=%0b", got3);

	report_status("P1 got only multicast data", got1 && (r1.data == s0.data));
	report_status("P2 got both multicast and unicast (order don't care)", ok);
	report_status("No extra packets on P0/P3", !got0 && !got3);
  endtask

  // ------------------------------------------------------------
  // Test 7:
  // Stresses the standalone rx_port FIFO by pushing more packets than its depth while grants are disabled.
  // After enabling grant, verifies that only the first DEPTH packets are observed and overflow packets are dropped.
  // ------------------------------------------------------------
  task automatic test_rx_fifo_overflow_drop();
	localparam int EXTRA_PKTS = 4;
	localparam int DEPTH      = NUM_PORTS*4;
	localparam int TOTAL_PKTS = DEPTH + EXTRA_PKTS;

	bit [TOTAL_PKTS-1:0] seen;
	int i;
	int idx;
	bit all_first_seen;
	bit any_extra_seen;

	$display("\n--- TEST 7: rx_port FIFO overflow (packets beyond depth dropped) ---");

	rxov_valid_in  = 1'b0;
	rxov_grant_vec = '0;
	rxov_pkt_in    = '0;
	seen           = '0;

	// Phase 1: push TOTAL_PKTS packets with grant_vec=0 (no pops)
	for (i = 0; i < TOTAL_PKTS; i++) begin
	  @(posedge clk);
	  rxov_valid_in      = 1'b1;
	  rxov_pkt_in.source = 4'b0001;
	  rxov_pkt_in.target = 4'b0010;
	  rxov_pkt_in.data   = byte'(i);  // unique data == index
	  $display("  TX to rx_port: idx=%0d src=%b tgt=%b data=0x%0h",
			   i, rxov_pkt_in.source, rxov_pkt_in.target, rxov_pkt_in.data);
	end

	// Stop driving valid
	@(posedge clk);
	rxov_valid_in  = 1'b0;

	// Phase 2: enable grants so rx_port starts popping FIFO
	rxov_grant_vec = 4'b0010;

	// Observe outputs long enough to flush all stored entries
	for (i = 0; i < TOTAL_PKTS + 10; i++) begin
	  @(posedge clk);
	  if (rxov_pkt_valid) begin
		idx = rxov_pkt_out.data;
		if (idx >= 0 && idx < TOTAL_PKTS)
		  seen[idx] = 1'b1;
	  end
	end

	// Analyze which indices were seen
	all_first_seen = 1'b1;
	any_extra_seen = 1'b0;

	for (i = 0; i < DEPTH; i++) begin
	  if (!seen[i]) all_first_seen = 1'b0;
	end
	for (i = DEPTH; i < TOTAL_PKTS; i++) begin
	  if (seen[i]) any_extra_seen = 1'b1;
	end

	$display("  Expected stored packet indices : 0..%0d", DEPTH-1);
	$display("  Expected dropped packet indices: %0d..%0d", DEPTH, TOTAL_PKTS-1);

	for (i = 0; i < TOTAL_PKTS; i++) begin
	  $display("    data_index=%0d | expected_stored=%0b | seen=%0b",
			   i, (i < DEPTH), seen[i]);
	end

	report_status("FIFO overflow: all packets 0..DEPTH-1 were seen", all_first_seen);
	report_status("FIFO overflow: no packets beyond DEPTH were seen", !any_extra_seen);
  endtask

  // Main sequence
  initial begin
	$display("\n=== STARTING EXTENDED SWITCH TESTS ===\n");

	do_reset(); test_multicast();
	do_reset(); test_broadcast_no_self();
	do_reset(); test_arbitration_two_to_one();
	do_reset(); test_heavy_contention_all_to_p2();
	do_reset(); test_back_to_back_p0_to_p1();
	do_reset(); test_mixed_multicast_unicast_to_p2();
	do_reset(); test_rx_fifo_overflow_drop();

	$display("\n=== ALL TESTS FINISHED ===");
	#100 $finish;
  end

endmodule
