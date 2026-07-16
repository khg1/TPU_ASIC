module processing_element #(
	parameter int ACT_WIDTH = 8,
	parameter int ACC_WIDTH = 32,
	parameter int WT_WIDTH = 8
)(
	input	logic					clk, resetn, en, weight_load,
	input	logic signed	[WT_WIDTH-1:0]		weight,
	input	logic signed	[ACT_WIDTH-1:0]		act_in,
	input	logic signed	[ACC_WIDTH-1:0]		acc_in,
	output	logic signed	[ACT_WIDTH-1:0]		act_out,
	output	logic signed	[ACC_WIDTH-1:0]		acc_out
);

logic signed	[WT_WIDTH-1:0]	q_weight;
logic signed	[ACT_WIDTH+WT_WIDTH-1:0]	product;
logic signed	[ACC_WIDTH-1:0] d_acc;

assign product = act_in * q_weight;
assign d_acc = ACC_WIDTH'(product) + acc_in;


always_ff @(posedge clk or negedge resetn) begin
	if(!resetn) begin
		act_out <= '0;
		acc_out <= '0;
		q_weight <= '0;
	end
	else begin
		if(weight_load)	q_weight <= weight;
		else begin
			if(en) begin
				act_out <= act_in;
				acc_out <= d_acc;
			end
			else begin
				act_out <= '0;
				acc_out <= '0;
			end
		end
	end
end

endmodule
