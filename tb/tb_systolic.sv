`timescale 1ns/1ps
//=============================================================================
// tb_systolic — self-checking testbench for systolic_array
//
// Protocol (mirrors npu_core):
//   1. Assert weights_avail, then stream one weight row per cycle on
//      weight_buffer, LAST row first (the array shifts rows downward
//      internally, so W[GRID_DIM-1] is presented first and W[0] last).
//   2. Drive act_buffer, hold en high, wait for the one-cycle done pulse.
//   3. result[c] = sum over r of act[r] * W[r][c]
//
// Every test prints the input stimulus, the expected result from an
// independent reference model, the actual DUT result, and PASS/FAIL per lane.
//=============================================================================
module tb_systolic();

	localparam int GRID_DIM		= 8;
	localparam int ACT_WIDTH	= 8;
	localparam int WT_WIDTH		= 8;
	localparam int ACC_WIDTH	= 32;
	localparam int CLK_PERIOD	= 10;
	localparam int NUM_RANDOM_TESTS	= 20;

	logic						clk, resetn, en, weights_avail;
	logic signed [GRID_DIM-1:0][WT_WIDTH-1:0]	weight_buffer;
	logic signed [GRID_DIM-1:0][ACT_WIDTH-1:0]	act_buffer;
	logic signed [GRID_DIM-1:0][ACC_WIDTH-1:0]	result;
	logic						done, ready;

	// Test stimulus / reference (plain ints so all arithmetic is signed)
	int	test_weights	[GRID_DIM][GRID_DIM];	// [row][col]
	int	test_acts	[GRID_DIM];
	int	expected	[GRID_DIM];

	int	test_count = 0;
	int	pass_count = 0;
	int	fail_count = 0;

	systolic_array #(
		.GRID_DIM(GRID_DIM),
		.ACT_WIDTH(ACT_WIDTH),
		.WT_WIDTH(WT_WIDTH),
		.ACC_WIDTH(ACC_WIDTH)
	) dut (
		.clk(clk),
		.resetn(resetn),
		.en(en),
		.weights_avail(weights_avail),
		.weight_buffer(weight_buffer),
		.act_buffer(act_buffer),
		.result(result),
		.done(done),
		.ready(ready)
	);

	initial begin
		clk = 0;
		forever #(CLK_PERIOD/2) clk = ~clk;
	end

	// Watchdog
	initial begin
		#2_000_000;
		$display("[TB] TIMEOUT — simulation hung");
		$finish;
	end

	//====================== reference model ======================
	function automatic void compute_expected();
		for (int c = 0; c < GRID_DIM; c++) begin
			expected[c] = 0;
			for (int r = 0; r < GRID_DIM; r++)
				expected[c] += test_acts[r] * test_weights[r][c];
		end
	endfunction

	//====================== protocol tasks ======================
	task automatic pulse_reset();
		resetn		= 0;
		en		= 0;
		weights_avail	= 0;
		weight_buffer	= '0;
		act_buffer	= '0;
		repeat (3) @(negedge clk);
		resetn = 1;
		@(negedge clk);
	endtask

	task automatic load_weights();
		do @(negedge clk); while (!ready);
		weights_avail = 1;
		@(negedge clk);					// array enters LOAD
		for (int r = GRID_DIM-1; r >= 0; r--) begin	// last row first
			for (int c = 0; c < GRID_DIM; c++)
				weight_buffer[c] = WT_WIDTH'(test_weights[r][c]);
			@(negedge clk);				// row sampled at next posedge
		end
		weights_avail = 0;
	endtask

	task automatic run_compute();
		for (int r = 0; r < GRID_DIM; r++)
			act_buffer[r] = ACT_WIDTH'(test_acts[r]);
		en = 1;
		wait (done === 1);
		@(negedge clk);					// result registers stable
		en = 0;
	endtask

	//====================== reporting ======================
	task automatic check_and_report(string test_name);
		string	s;
		bit	test_ok = 1;

		test_count++;
		compute_expected();

		$display("\n[TEST %0d] %s", test_count, test_name);
		$display("  weight matrix W[row][0..%0d]:", GRID_DIM-1);
		for (int r = 0; r < GRID_DIM; r++) begin
			s = $sformatf("    row %0d:", r);
			for (int c = 0; c < GRID_DIM; c++)
				s = {s, $sformatf(" %5d", test_weights[r][c])};
			$display("%s", s);
		end
		s = "  activations :";
		for (int r = 0; r < GRID_DIM; r++)
			s = {s, $sformatf(" %5d", test_acts[r])};
		$display("%s", s);

		$display("  %-5s %12s %12s   %s", "lane", "expected", "actual", "status");
		for (int c = 0; c < GRID_DIM; c++) begin
			int actual = int'(result[c]);
			if (actual === expected[c])
				$display("  %-5d %12d %12d   PASS", c, expected[c], actual);
			else begin
				$display("  %-5d %12d %12d   FAIL", c, expected[c], actual);
				test_ok = 0;
			end
		end

		if (test_ok) begin
			pass_count++;
			$display("  => TEST PASSED");
		end else begin
			fail_count++;
			$display("  => TEST FAILED");
		end
	endtask

	task automatic run_test(string test_name);
		load_weights();
		run_compute();
		check_and_report(test_name);
	endtask

	//====================== test sequence ======================
	initial begin
		$display("========================================");
		$display("  Systolic Array Testbench");
		$display("========================================");

		pulse_reset();

		// Test 1: identical rows, unit activations — result[c] = 8*(c+1)
		foreach (test_weights[r,c])	test_weights[r][c] = c + 1;
		foreach (test_acts[r])		test_acts[r] = 1;
		run_test("dot product (identical rows, unit activations)");

		// Test 2: row/column orientation — one-hot activation selects row 2,
		// distinct W[r][c] so a transposed load cannot pass
		foreach (test_weights[r,c])	test_weights[r][c] = r*GRID_DIM + c;
		foreach (test_acts[r])		test_acts[r] = (r == 2) ? 1 : 0;
		run_test("orientation check (one-hot activation, distinct weights)");

		// Test 3: signed weights and activations
		foreach (test_weights[r,c])	test_weights[r][c] = (r - 4) * (c - 3);
		foreach (test_acts[r])		test_acts[r] = (r % 2) ? -3 : 5;
		run_test("signed weights and activations");

		// Test 4: extreme values (checker pattern of +127 / -128)
		foreach (test_weights[r,c])	test_weights[r][c] = ((r + c) % 2) ? -128 : 127;
		foreach (test_acts[r])		test_acts[r] = (r % 2) ? 127 : -128;
		run_test("extreme values (+127 / -128)");

		// Test 5: all zeros
		foreach (test_weights[r,c])	test_weights[r][c] = 0;
		foreach (test_acts[r])		test_acts[r] = $urandom_range(0, 255) - 128;
		run_test("zero weights");

		// Tests 6..: random back-to-back operations
		for (int t = 0; t < NUM_RANDOM_TESTS; t++) begin
			foreach (test_weights[r,c])	test_weights[r][c] = $urandom_range(0, 255) - 128;
			foreach (test_acts[r])		test_acts[r] = $urandom_range(0, 255) - 128;
			run_test($sformatf("random stimulus %0d", t));
		end

		$display("\n========================================");
		$display("  Test Summary");
		$display("========================================");
		$display("Total Tests: %0d", test_count);
		$display("Passed:      %0d", pass_count);
		$display("Failed:      %0d", fail_count);
		if (fail_count == 0)	$display("\n*** ALL TESTS PASSED ***");
		else			$display("\n*** SOME TESTS FAILED ***");
		$display("========================================\n");
		$finish;
	end

endmodule
