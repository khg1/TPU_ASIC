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
localparam	logic	signed	[ACC_WIDTH-1:0]	Q_MAX	= 16'h7FFF;
localparam	logic	signed	[ACC_WIDTH-1:0] Q_MIN	= 16'h8000;

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
		for(int i=0;i<NUM_LANES;i++) begin
			reg_a <= '0;
			reg_b <= '0;
		end
		reg_scale <= '0;
		reg_op <= '0;
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
				ADD:	reg_result[i] <= saturation(32'(reg_a[i]) + 32'(reg_b[i]));
				MUL:	reg_result[i] <= saturation((32'(reg_a[i]) * 32'(reg_b[i])) >>> 8);
				SCALE:	reg_result[i] <= saturation((32'(reg_a[i]) * 32'(reg_scale)) >>> 8);
				default: reg_result[i] <= reg_a[i];
			endcase
		end
	end
end

endmodule
