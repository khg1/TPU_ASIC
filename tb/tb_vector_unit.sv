`timescale 1ns/1ps
//=============================================================================
// tb_vector_unit — self-checking testbench for vector_unit
//
// Tested at NUM_LANES=8 / ACC_WIDTH=32, the configuration npu_core uses
// (32-bit accumulator lanes saturated into the Q8.8 range [-32768, 32767]).
//
// Timing: en is pulsed for one cycle; result_valid pulses one cycle exactly
// two clocks later.
//
// Ops: ADD   = sat(a + b)
//      MUL   = sat((a * b) >>> 8)     (Q8.8 product)
//      SCALE = sat((a * scale) >>> 8)
//      other = a (raw passthrough, no saturation)
//
// Every test prints the input stimulus, the expected result from an
// independent reference model, the actual DUT result, and PASS/FAIL per lane.
//=============================================================================
module tb_vector_unit();

	localparam int NUM_LANES	= 8;
	localparam int ACC_WIDTH	= 32;
	localparam int CLK_PERIOD	= 10;
	localparam int NUM_RANDOM_TESTS	= 30;

	localparam int Q_MAX = 32767;
	localparam int Q_MIN = -32768;

	logic						clk, resetn, en;
	logic	[1:0]					op_sel;
	logic signed [NUM_LANES-1:0][ACC_WIDTH-1:0]	vector_a, vector_b, result;
	logic signed [ACC_WIDTH-1:0]			scale;
	logic						result_valid, ready;

	int	a_in		[NUM_LANES];
	int	b_in		[NUM_LANES];
	int	scale_in;
	int	expected	[NUM_LANES];

	int	test_count = 0;
	int	pass_count = 0;
	int	fail_count = 0;

	vector_unit #(
		.NUM_LANES(NUM_LANES),
		.ACC_WIDTH(ACC_WIDTH)
	) dut (
		.clk(clk),
		.resetn(resetn),
		.en(en),
		.op_sel(op_sel),
		.vector_a(vector_a),
		.vector_b(vector_b),
		.scale(scale),
		.result(result),
		.result_valid(result_valid),
		.ready(ready)
	);

	initial begin
		clk = 0;
		forever #(CLK_PERIOD/2) clk = ~clk;
	end

	// Watchdog
	initial begin
		#1_000_000;
		$display("[TB] TIMEOUT — simulation hung");
		$finish;
	end

	//====================== reference model ======================
	function automatic int ref_op(input int a, input int b, input int s,
	                              input logic [1:0] op);
		longint full;
		case (op)
			2'b00:	 full = longint'(a) + longint'(b);		// ADD
			2'b01:	 full = (longint'(a) * longint'(b)) >>> 8;	// MUL
			2'b10:	 full = (longint'(a) * longint'(s)) >>> 8;	// SCALE
			default: return a;					// raw passthrough
		endcase
		if (full > Q_MAX)	return Q_MAX;
		else if (full < Q_MIN)	return Q_MIN;
		else			return int'(full);
	endfunction

	function automatic string op_name(input logic [1:0] op);
		case (op)
			2'b00:	 return "ADD";
			2'b01:	 return "MUL";
			2'b10:	 return "SCALE";
			default: return "PASSTHROUGH";
		endcase
	endfunction

	//====================== drive + check ======================
	task automatic run_test(string test_name, logic [1:0] op);
		bit test_ok = 1;

		test_count++;

		@(negedge clk);
		for (int i = 0; i < NUM_LANES; i++) begin
			vector_a[i] = a_in[i];
			vector_b[i] = b_in[i];
		end
		scale	= scale_in;
		op_sel	= op;
		en	= 1;
		@(negedge clk);
		en	= 0;
		@(negedge clk);			// result_valid must be high now

		$display("\n[TEST %0d] %s  (op=%s%s)", test_count, test_name, op_name(op),
			(op == 2'b10) ? $sformatf(", scale=%0d", scale_in) : "");

		if (result_valid !== 1) begin
			$display("  => TEST FAILED: result_valid not asserted 2 cycles after en");
			fail_count++;
			return;
		end

		$display("  %-5s %12s %12s %12s %12s   %s",
			"lane", "a", "b", "expected", "actual", "status");
		for (int i = 0; i < NUM_LANES; i++) begin
			int actual = int'(result[i]);
			expected[i] = ref_op(a_in[i], b_in[i], scale_in, op);
			if (actual === expected[i])
				$display("  %-5d %12d %12d %12d %12d   PASS",
					i, a_in[i], b_in[i], expected[i], actual);
			else begin
				$display("  %-5d %12d %12d %12d %12d   FAIL",
					i, a_in[i], b_in[i], expected[i], actual);
				test_ok = 0;
			end
		end

		// result_valid must be a single-cycle pulse
		@(negedge clk);
		if (result_valid !== 0) begin
			$display("  result_valid longer than one cycle => FAIL");
			test_ok = 0;
		end

		if (test_ok) begin
			pass_count++;
			$display("  => TEST PASSED");
		end else begin
			fail_count++;
			$display("  => TEST FAILED");
		end
	endtask

	//====================== test sequence ======================
	initial begin
		$display("========================================");
		$display("  Vector Unit Testbench");
		$display("========================================");

		resetn = 0; en = 0; op_sel = '0;
		vector_a = '0; vector_b = '0; scale = '0;
		scale_in = 0;
		repeat (3) @(negedge clk);
		resetn = 1;

		// Test 1: ADD, in-range bias add (typical npu_core use)
		foreach (a_in[i]) a_in[i] = (i - 4) * 256;		// bias: -4.0 .. +3.0 in Q8.8
		foreach (b_in[i]) b_in[i] = i * 1000 - 3500;		// accumulator-like values
		run_test("ADD in-range", 2'b00);

		// Test 2: ADD positive saturation
		foreach (a_in[i]) a_in[i] = 30000;
		foreach (b_in[i]) b_in[i] = 30000 + i;
		run_test("ADD positive saturation", 2'b00);

		// Test 3: ADD negative saturation
		foreach (a_in[i]) a_in[i] = -30000;
		foreach (b_in[i]) b_in[i] = -(30000 + i);
		run_test("ADD negative saturation", 2'b00);

		// Test 4: ADD with large raw accumulator inputs (beyond Q8.8)
		foreach (a_in[i]) a_in[i] = 0;
		foreach (b_in[i]) b_in[i] = (i % 2) ? 130000 : -130000;
		run_test("ADD raw 32-bit accumulator saturation", 2'b00);

		// Test 5: MUL, Q8.8 products (e.g. 2.0 * 1.5 = 3.0)
		foreach (a_in[i]) a_in[i] = (i + 1) * 256;		// 1.0 .. 8.0
		foreach (b_in[i]) b_in[i] = (i % 2) ? 384 : -384;	// +/-1.5
		run_test("MUL Q8.8 products", 2'b01);

		// Test 6: MUL saturation
		foreach (a_in[i]) a_in[i] = 32767;
		foreach (b_in[i]) b_in[i] = (i % 2) ? 32767 : -32768;
		run_test("MUL saturation", 2'b01);

		// Test 7: SCALE by 0.5 (128 in Q8.8)
		scale_in = 128;
		foreach (a_in[i]) a_in[i] = (i - 4) * 1000;
		foreach (b_in[i]) b_in[i] = 0;
		run_test("SCALE by 0.5", 2'b10);

		// Test 8: SCALE by -2.0 with saturation
		scale_in = -512;
		foreach (a_in[i]) a_in[i] = (i + 1) * 5000;
		foreach (b_in[i]) b_in[i] = 0;
		run_test("SCALE by -2.0 with saturation", 2'b10);

		// Test 9: undefined op = raw passthrough of vector_a
		foreach (a_in[i]) a_in[i] = i * 100000 - 400000;
		foreach (b_in[i]) b_in[i] = 12345;
		run_test("undefined op passthrough", 2'b11);

		// Tests 10..: random stimulus over all ops
		for (int t = 0; t < NUM_RANDOM_TESTS; t++) begin
			logic [1:0] op = 2'($urandom_range(0, 2));
			scale_in = $urandom_range(0, 131072) - 65536;
			foreach (a_in[i]) a_in[i] = $urandom_range(0, 400000) - 200000;
			foreach (b_in[i]) b_in[i] = $urandom_range(0, 400000) - 200000;
			run_test($sformatf("random stimulus %0d", t), op);
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
