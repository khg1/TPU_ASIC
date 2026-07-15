module shift_register #(
	parameter int WIDTH = 8,
	parameter int STAGES = 1
)(
	input	logic			clk, resetn, en,
	input	logic	[WIDTH-1:0]	d_in,
	output	logic	[WIDTH-1:0]	d_out
);

generate
	if(STAGES == 0) begin
		assign d_out = d_in;
	end
	else begin
		logic	[WIDTH-1:0] shift_pipe [0:STAGES-1];
		always_ff @(posedge clk or negedge resetn) begin
			if(!resetn) begin
				for(int i = 0; i<STAGES; i++) begin
					shift_pipe[i] <= '0;
				end
			end
			else if(en) begin
				shift_pipe[0]	<= d_in;
				for(int i = 1; i<STAGES; i++) begin
					shift_pipe[i] <= shift_pipe[i-1];
				end
			end
		end
		assign d_out = shift_pipe[STAGES-1];
	end
endgenerate

endmodule
