module processing_element #(
	parameter int ACT_WIDTH = 8,
	parameter int ACC_WIDTH = 32,
	parameter int WT_WDITH = 8
)(
	input	logic					clk, resetn,
	input	logic signed	[WT_WIDTH-1:0]		weight,
	input	logic					weight_load,
	input	logic					en,
	input	logic signed	[ACT_WIDTH-1:0]		act_in,
	input	logic signed	[ACC_WIDTH-1:0]		acc_in,
	output	logic signed	[ACT_WIDTH-1:0]		act_out,
	output	logic signed	[ACC_WIDTH-1:0]		acc_out
);

logic signed	[ACT_WIDTH-1:0]	weight_reg;

always_ff @(posedge clk or negedge resetn) begin
	if(!resetn) begin
		act_out <= '0;
		acc_out <= '0;
		weight_reg <= '0;
	end
	else begin
		if(weight_load)	weight_reg <= weight;
		else begin
			if(en) begin
				act_out <= act_in;
				acc_out <= ACC_WIDTH'(act_in * weight_reg) + acc_in;
			end
			else begin
				act_out <= '0;
				acc_out <= '0;
			end
		end
	end
end

endmodule
