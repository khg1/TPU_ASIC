`timescale 1ns/1ps
//=============================================================================
// tb_npu_core — self-checking end-to-end testbench for npu_core
//
// Drives the documented transaction protocol (default 8x8 / 8-bit / 32-bit):
//   beats  0..15 : weights, row-major, 4 weights per 32-bit beat
//                  (lowest byte = lowest column index)
//   beats 16..17 : activations, 4 per beat (lowest byte = lowest lane)
//   beats 18..25 : bias, one sign-extended 32-bit Q8.8 word per beat
// then waits for the one-cycle out_valid pulse and compares data_out against
// a software model of the whole pipeline:
//   mac[c]  = sum_r act[r] * W[r][c]
//   vec[c]  = ADD:   sat_q88(bias[c] + mac[c])
//             MUL:   sat_q88((bias[c] * mac[c])  >>> 8)
//             SCALE: sat_q88((bias[c] * scale)   >>> 8)
//   out[c]  = RELU / GELU / SIGMOID (LUT + linear interpolation, same hex
//             files and index scheme as the RTL)
//
// Every test prints the input stimulus, the expected output, the actual
// output, and PASS/FAIL per lane. valid-gap and back-to-back transactions
// are exercised as well.
//
// NOTE: run from the Simulation/ directory so ../LUT/lut/*.hex resolves for
// both the DUT and this testbench.
//=============================================================================
module tb_npu_core();

	localparam int DATA_WIDTH	= 32;
	localparam int GRID_DIM		= 8;
	localparam int WT_WIDTH		= 8;
	localparam int ACT_WIDTH	= 8;
	localparam int ACC_WIDTH	= 32;
	localparam int CLK_PERIOD	= 10;
	localparam int NUM_RANDOM_TESTS	= 10;

	localparam int WT_BEATS		= 16;
	localparam int ACT_BEATS	= 2;
	localparam int BIAS_BEATS	= 8;
	localparam int TOTAL_BEATS	= WT_BEATS + ACT_BEATS + BIAS_BEATS;

	localparam int Q_MAX = 32767;
	localparam int Q_MIN = -32768;

	logic						clk, resetn, valid;
	logic	signed	[DATA_WIDTH-1:0]		data_in;
	logic	[1:0]					vec_op_sel, act_fn_sel;
	logic	signed	[ACC_WIDTH-1:0]			vect_scale;
	logic	signed	[GRID_DIM-1:0][ACC_WIDTH-1:0]	data_out;
	logic						out_valid, ready;

	// Test stimulus / reference (plain ints so all arithmetic is signed)
	int	W	[GRID_DIM][GRID_DIM];	// [row][col]
	int	acts	[GRID_DIM];
	int	bias	[GRID_DIM];
	int	expected[GRID_DIM];
	int	actual	[GRID_DIM];

	// Reference copies of the activation LUTs (same files as the DUT)
	logic signed [15:0]	ref_lut_gelu	[0:255];
	logic signed [15:0]	ref_lut_sigmoid	[0:255];

	int	test_count = 0;
	int	pass_count = 0;
	int	fail_count = 0;

	npu_core #(
		.DATA_WIDTH(DATA_WIDTH),
		.GRID_DIM(GRID_DIM),
		.WT_WIDTH(WT_WIDTH),
		.ACT_WIDTH(ACT_WIDTH),
		.ACC_WIDTH(ACC_WIDTH)
	) dut (
		.clk(clk),
		.resetn(resetn),
		.data_in(data_in),
		.vec_op_sel(vec_op_sel),
		.act_fn_sel(act_fn_sel),
		.valid(valid),
		.vect_scale(vect_scale),
		.data_out(data_out),
		.out_valid(out_valid),
		.ready(ready)
	);

	initial begin
		clk = 0;
		forever #(CLK_PERIOD/2) clk = ~clk;
	end

	initial begin
		$readmemh("../LUT/lut/gelu_q88.hex", ref_lut_gelu);
		$readmemh("../LUT/lut/sigmoid_q88.hex", ref_lut_sigmoid);
	end

	// Watchdog
	initial begin
		#5_000_000;
		$display("[TB] TIMEOUT — simulation hung");
		$finish;
	end

	//====================== reference model ======================
	function automatic int sat_q88(input longint x);
		if (x > Q_MAX)		return Q_MAX;
		else if (x < Q_MIN)	return Q_MIN;
		else			return int'(x);
	endfunction

	// x is guaranteed to be within [Q_MIN, Q_MAX] (vector unit saturates)
	function automatic int ref_activation(input logic [1:0] fn, input int x);
		logic [7:0]	idx, frac, idx_next;
		int		lut_val, lut_next, corr;

		case (fn)
			2'b00: return (x < 0) ? 0 : x;			// RELU
			2'b01, 2'b10: begin				// GELU / SIGMOID
				idx	= x[15:8];
				frac	= x[7:0];
				// clamp at x = +127 (0x7F); 0xFF wraps naturally to 0x00
				idx_next = (idx == 8'h7F) ? 8'h7F : (idx + 8'd1);
				lut_val  = (fn == 2'b01) ? int'(ref_lut_gelu[idx])
				                         : int'(ref_lut_sigmoid[idx]);
				lut_next = (fn == 2'b01) ? int'(ref_lut_gelu[idx_next])
				                         : int'(ref_lut_sigmoid[idx_next]);
				corr = lut_val + (((lut_next - lut_val) * int'(frac)) >>> 8);
				return sat_q88(longint'(corr));
			end
			default: return x;				// passthrough
		endcase
	endfunction

	function automatic void compute_expected(input logic [1:0] vec_op,
	                                         input logic [1:0] act_fn,
	                                         input int scale_v);
		for (int c = 0; c < GRID_DIM; c++) begin
			longint	mac = 0;
			longint	v;
			int	vec_res;
			for (int r = 0; r < GRID_DIM; r++)
				mac += acts[r] * W[r][c];
			case (vec_op)
				2'b00:	 v = longint'(bias[c]) + mac;			// ADD
				2'b01:	 v = (longint'(bias[c]) * mac) >>> 8;		// MUL
				2'b10:	 v = (longint'(bias[c]) * scale_v) >>> 8;	// SCALE
				default: v = longint'(bias[c]);
			endcase
			vec_res = (vec_op inside {2'b00, 2'b01, 2'b10}) ? sat_q88(v) : int'(v);
			expected[c] = ref_activation(act_fn, vec_res);
		end
	endfunction

	function automatic string vec_op_name(input logic [1:0] op);
		case (op)
			2'b00:	 return "ADD";
			2'b01:	 return "MUL";
			2'b10:	 return "SCALE";
			default: return "PASSTHROUGH";
		endcase
	endfunction

	function automatic string act_fn_name(input logic [1:0] fn);
		case (fn)
			2'b00:	 return "RELU";
			2'b01:	 return "GELU";
			2'b10:	 return "SIGMOID";
			default: return "PASSTHROUGH";
		endcase
	endfunction

	//====================== transaction driver ======================
	// max_gap > 0 inserts random idle cycles (valid = 0) between beats to
	// verify that beats are qualified by valid.
	task automatic send_transaction(input logic [1:0] vec_op,
	                                input logic [1:0] act_fn,
	                                input int scale_v,
	                                input int max_gap);
		logic [DATA_WIDTH-1:0]	beats [0:TOTAL_BEATS-1];
		int			k = 0;

		// pack weights: 2 beats per row, lowest byte = lowest column
		for (int r = 0; r < GRID_DIM; r++)
			for (int half = 0; half < 2; half++) begin
				logic [DATA_WIDTH-1:0] b = '0;
				for (int j = 0; j < 4; j++)
					b[j*WT_WIDTH +: WT_WIDTH] = 8'(W[r][half*4 + j]);
				beats[k++] = b;
			end
		// pack activations: 2 beats, lowest byte = lowest lane
		for (int half = 0; half < 2; half++) begin
			logic [DATA_WIDTH-1:0] b = '0;
			for (int j = 0; j < 4; j++)
				b[j*ACT_WIDTH +: ACT_WIDTH] = 8'(acts[half*4 + j]);
			beats[k++] = b;
		end
		// pack bias: one 32-bit word per beat
		for (int i = 0; i < GRID_DIM; i++)
			beats[k++] = bias[i];

		vec_op_sel	= vec_op;
		act_fn_sel	= act_fn;
		vect_scale	= scale_v;

		do @(negedge clk); while (!ready);
		for (int b = 0; b < TOTAL_BEATS; b++) begin
			valid	= 1;
			data_in	= beats[b];
			@(negedge clk);
			if ((max_gap > 0) && (b < TOTAL_BEATS-1)) begin
				int gap = $urandom_range(0, max_gap);
				if (gap > 0) begin
					valid = 0;
					repeat (gap) @(negedge clk);
				end
			end
		end
		valid = 0;

		wait (out_valid === 1);
		for (int c = 0; c < GRID_DIM; c++)
			actual[c] = int'(data_out[c]);
	endtask

	//====================== reporting ======================
	task automatic check_and_report(string test_name,
	                                input logic [1:0] vec_op,
	                                input logic [1:0] act_fn,
	                                input int scale_v);
		string	s;
		bit	test_ok = 1;

		test_count++;
		compute_expected(vec_op, act_fn, scale_v);

		$display("\n[TEST %0d] %s  (vec_op=%s, act_fn=%s%s)",
			test_count, test_name, vec_op_name(vec_op), act_fn_name(act_fn),
			(vec_op == 2'b10) ? $sformatf(", scale=%0d", scale_v) : "");
		$display("  weight matrix W[row][0..%0d]:", GRID_DIM-1);
		for (int r = 0; r < GRID_DIM; r++) begin
			s = $sformatf("    row %0d:", r);
			for (int c = 0; c < GRID_DIM; c++)
				s = {s, $sformatf(" %5d", W[r][c])};
			$display("%s", s);
		end
		s = "  activations :";
		for (int r = 0; r < GRID_DIM; r++)	s = {s, $sformatf(" %6d", acts[r])};
		$display("%s", s);
		s = "  bias        :";
		for (int c = 0; c < GRID_DIM; c++)	s = {s, $sformatf(" %6d", bias[c])};
		$display("%s", s);

		$display("  %-5s %12s %12s   %s", "lane", "expected", "actual", "status");
		for (int c = 0; c < GRID_DIM; c++) begin
			if (actual[c] === expected[c])
				$display("  %-5d %12d %12d   PASS", c, expected[c], actual[c]);
			else begin
				$display("  %-5d %12d %12d   FAIL", c, expected[c], actual[c]);
				test_ok = 0;
			end
		end

		// out_valid must be a single-cycle pulse (first negedge after the
		// wait() is still inside the pulse, so check one full cycle later)
		@(negedge clk);
		@(negedge clk);
		if (out_valid !== 0) begin
			$display("  out_valid longer than one cycle => FAIL");
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

	task automatic run_test(string test_name,
	                        input logic [1:0] vec_op,
	                        input logic [1:0] act_fn,
	                        input int scale_v,
	                        input int max_gap);
		send_transaction(vec_op, act_fn, scale_v, max_gap);
		check_and_report(test_name, vec_op, act_fn, scale_v);
	endtask

	//====================== test sequence ======================
	initial begin
		$display("========================================");
		$display("  NPU Core Testbench");
		$display("========================================");

		resetn = 0; valid = 0; data_in = '0;
		vec_op_sel = '0; act_fn_sel = '0; vect_scale = '0;
		repeat (4) @(negedge clk);
		resetn = 1;

		// Test 1: RELU + bias ADD, small mixed-sign values.
		// Some lanes go negative before RELU and must clamp to 0.
		foreach (W[r,c])	W[r][c] = ((r + c) % 7) - 3;
		foreach (acts[r])	acts[r] = (r % 3) - 1;
		foreach (bias[c])	bias[c] = (c - 4) * 512;
		run_test("RELU + bias ADD (mixed signs)", 2'b00, 2'b00, 0, 0);

		// Test 2: GELU + bias ADD, results spread across the Q8.8 range
		foreach (W[r,c])	W[r][c] = (c - 3) * 2;
		foreach (acts[r])	acts[r] = r + 1;
		foreach (bias[c])	bias[c] = (c - 4) * 300;
		run_test("GELU + bias ADD", 2'b00, 2'b01, 0, 0);

		// Test 3: SIGMOID + bias ADD
		foreach (W[r,c])	W[r][c] = ((r * c) % 5) - 2;
		foreach (acts[r])	acts[r] = 2 - r;
		foreach (bias[c])	bias[c] = (c - 4) * 700;
		run_test("SIGMOID + bias ADD", 2'b00, 2'b10, 0, 0);

		// Test 4: positive saturation — mac >> Q_MAX, RELU passes Q_MAX
		foreach (W[r,c])	W[r][c] = 127;
		foreach (acts[r])	acts[r] = 127;
		foreach (bias[c])	bias[c] = 0;
		run_test("positive saturation (mac = 129032 -> 32767)", 2'b00, 2'b00, 0, 0);

		// Test 5: negative saturation — mac << Q_MIN, RELU clamps to 0
		foreach (W[r,c])	W[r][c] = 127;
		foreach (acts[r])	acts[r] = -128;
		foreach (bias[c])	bias[c] = 0;
		run_test("negative saturation (mac = -130048 -> -32768 -> RELU 0)", 2'b00, 2'b00, 0, 0);

		// Test 6: vector MUL (bias as Q8.8 gain on the accumulator)
		foreach (W[r,c])	W[r][c] = c - 3;
		foreach (acts[r])	acts[r] = 3;
		foreach (bias[c])	bias[c] = 128;		// 0.5 in Q8.8
		run_test("vector MUL (gain 0.5) + RELU", 2'b01, 2'b00, 0, 0);

		// Test 7: back-to-back transactions (reuses Test 1 stimulus shape)
		foreach (W[r,c])	W[r][c] = ((r * 2 + c) % 9) - 4;
		foreach (acts[r])	acts[r] = (r % 4) - 2;
		foreach (bias[c])	bias[c] = c * 200 - 800;
		run_test("back-to-back txn 1/2", 2'b00, 2'b00, 0, 0);
		foreach (W[r,c])	W[r][c] = ((r + 3*c) % 11) - 5;
		foreach (acts[r])	acts[r] = 3 - (r % 5);
		foreach (bias[c])	bias[c] = 600 - c * 150;
		run_test("back-to-back txn 2/2", 2'b00, 2'b10, 0, 0);

		// Test 8: valid gaps — random idle cycles between beats
		foreach (W[r,c])	W[r][c] = ((r + c) % 7) - 3;
		foreach (acts[r])	acts[r] = (r % 3) - 1;
		foreach (bias[c])	bias[c] = (c - 4) * 512;
		run_test("valid-gap stress (same stimulus as test 1)", 2'b00, 2'b00, 0, 3);

		// Tests 9..: random regression over all activation functions
		for (int t = 0; t < NUM_RANDOM_TESTS; t++) begin
			logic [1:0] fn = 2'($urandom_range(0, 2));
			foreach (W[r,c])	W[r][c] = $urandom_range(0, 255) - 128;
			foreach (acts[r])	acts[r] = $urandom_range(0, 255) - 128;
			foreach (bias[c])	bias[c] = $urandom_range(0, 4096) - 2048;
			run_test($sformatf("random stimulus %0d", t), 2'b00, fn,
			         0, $urandom_range(0, 2));
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
