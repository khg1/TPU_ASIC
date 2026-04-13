interface activation_if #(
	parameter int NUM_LANES = 16,
	parameter int ACC_WIDTH = 16
)(
	input	logic	clk,
	input	logic	resetn
);

logic	en;
logic	[1:0]	fn_sel;
logic	signed	[NUM_LANES-1:0][ACC_WIDTH-1:0]	data_in;
logic	signed	[NUM_LANES-1:0][ACC_WIDTH-1:0]	data_out;
logic	data_valid;
logic	ready;

clocking cb_driver @(posedge clk);
	default input #1step output #1ns;
	output	en;
	output	fn_sel;
	output	data_in;
	input	ready;
endclocking

clocking cb_monitor @(posedge clk);
	default input #1step output #1ns;
	input	en;
	input	fn_sel;
	input	data_in;
	input	data_out;
	input	data_valid;
	input	ready;
endclocking

endinterface
