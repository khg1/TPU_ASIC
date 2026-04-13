module tb_top;

	import uvm_pkg::*;
	import activation_tb_pkg::*;

	localparam int NUM_LANES = 16;
	localparam int ACC_WIDTH = 16;

	logic	clk;
	logic	resetn;

	initial begin
		clk = 0;
		forever #5 clk = ~clk;
	end

	initial begin
		resetn = 0;
		#20 resetn = 1;
	end

	activation_if #(NUM_LANES, ACC_WIDTH) vif(clk, resetn);

	activation_unit #(.NUM_LANES(NUM_LANES), .ACC_WIDTH(ACC_WIDTH)) dut(
		.clk(clk),
		.resetn(resetn),
		.en(vif.en),
		.fn_sel(vif.fn_sel),
		.data_in(vif.data_in),
		.data_out(vif.data_out),
		.data_valid(vif.data_valid),
		.ready(vif.ready)
	);

	bind activation_unit activation_sva #(NUM_LANES, ACC_WIDTH) sva_inst (
		.clk(clk),
		.resetn(resetn),
		.en(en),
		.fn_sel(fn_sel),
		.data_valid(data_valid),
		.ready(ready)
	);

	initial begin
		uvm_config_db#(virtual activation_if#(NUM_LANES, ACC_WIDTH))::set(null, "*", "vif", vif);
		run_test("activation_test");
	end

	initial begin
		$dumpfile("dump.fsdb");
		$dumpvars(0, tb_top);
	end

endmodule
