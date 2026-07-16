module activation_sva #(
	parameter int NUM_LANES = 16,
	parameter int ACC_WIDTH = 16
)(
	input	logic		clk, resetn,
	input	logic		en,
	input	logic	[1:0]	fn_sel,
	input	logic		data_valid,
	input	logic		ready
);

localparam int PIPE_STAGE = 3;

property p_valid_latency;
	@(posedge clk)	disable iff (!resetn)
	en |-> ##PIPE_STAGE data_valid;
endproperty

property p_ready_deassert;
	@(posedge clk)	disable iff (!resetn)
	en |-> ~ready;
endproperty

assert property(p_valid_latency) else	$error("Latency mismatch");
assert property(p_ready_deassert) else	$error("Ready failed to deassert");

endmodule
