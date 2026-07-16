module vector_unit #(
	parameter int NUM_LANES = 16,
	parameter int ACC_WIDTH = 16
)(
	input	logic	clk, resetn,
	input	logic	en,
	input	logic	[1:0] op_sel,
	input	logic	signed	[NUM_LANES-1:0][ACC_WIDTH-1:0]	vector_a,
	input	logic	signed	[NUM_LANES-1:0][ACC_WIDTH-1:0]	vector_b,
	input	logic	signed	[ACC_WIDTH-1:0]			scale,
	output	logic	signed	[NUM_LANES-1:0][ACC_WIDTH-1:0]	result,
	output	logic						result_valid,
	output	logic						ready
);

typedef	enum	logic	[1:0] {ADD=2'b00, MUL=2'b01, SCALE=2'b10} op_sel_t;
// Q8.8 saturation bounds; sign-extended so they stay correct when ACC_WIDTH > 16
localparam	logic	signed	[ACC_WIDTH-1:0]	Q_MAX	= ACC_WIDTH'(16'sh7FFF);
localparam	logic	signed	[ACC_WIDTH-1:0] Q_MIN	= ACC_WIDTH'(16'sh8000);

logic	signed	[NUM_LANES-1:0][ACC_WIDTH-1:0]	reg_a;
logic	signed	[NUM_LANES-1:0][ACC_WIDTH-1:0]	reg_b;
logic	signed	[ACC_WIDTH-1:0]			reg_scale;
op_sel_t					reg_op;
logic						reg_valid;

logic	signed	[NUM_LANES-1:0][ACC_WIDTH-1:0]	reg_result;
logic						reg_result_valid;

function automatic logic signed [ACC_WIDTH-1:0]	saturation(input logic signed [2*ACC_WIDTH-1:0] x);
	logic	signed [ACC_WIDTH-1:0] sat_res;
	if(x > Q_MAX)		sat_res = Q_MAX;
	else if(x<Q_MIN)	sat_res = Q_MIN;
	else			sat_res = ACC_WIDTH'(x);
	return	sat_res;
endfunction

assign	ready = 1;
assign	result = reg_result;
assign	result_valid = reg_result_valid;

always_ff @(posedge clk or negedge resetn) begin
	if(!resetn) begin
		reg_a <= '0;
		reg_b <= '0;
		reg_scale <= '0;
		reg_op <= op_sel_t'('0);
		reg_valid <= 0;
	end
	else  begin
		reg_valid <= en;
		if(en) begin
			for(int i=0; i<NUM_LANES;i++) begin
				reg_a[i] <= vector_a[i];
				reg_b[i] <= vector_b[i];
			end
			reg_scale <= scale;
			reg_op <= op_sel_t'(op_sel);
		end
	end
end

always_ff @(posedge clk or negedge resetn) begin
	if(!resetn) begin
		for(int i=0; i<NUM_LANES; i++) begin
			reg_result[i] <= '0;
		end
		reg_result_valid <= 0;
	end
	else begin
		reg_result_valid <= reg_valid;
		for(int i = 0; i<NUM_LANES; i++) begin
			unique case (reg_op)
				// signed'() before widening: packed-array element selects are
				// unsigned, so a bare width cast would zero-extend negatives
				ADD:	reg_result[i] <= saturation((2*ACC_WIDTH)'(signed'(reg_a[i])) + (2*ACC_WIDTH)'(signed'(reg_b[i])));
				MUL:	reg_result[i] <= saturation(((2*ACC_WIDTH)'(signed'(reg_a[i])) * (2*ACC_WIDTH)'(signed'(reg_b[i]))) >>> 8);
				SCALE:	reg_result[i] <= saturation(((2*ACC_WIDTH)'(signed'(reg_a[i])) * (2*ACC_WIDTH)'(reg_scale)) >>> 8);
				default: reg_result[i] <= reg_a[i];
			endcase
		end
	end
end

endmodule
