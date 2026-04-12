module activation_unit #(
	parameter int NUM_LANES = 16,
	parameter int ACC_WIDTH = 16
)(
	input	logic	clk, resetn,
	input	logic	en,
	input	logic	[1:0]	fn_sel,
	input	logic	signed	[ACC_WIDTH-1:0]	data_in	[0:NUM_LANES-1];
	output	logic	signed	[ACC_WIDTH-1:0]	data_out	[0:NUM_LANES-1];
	output	logic	data_valid,
	output	logic	ready
);

typedef enum logic [1:0] {RELU=2'b00, GELU=2'b01, SOFTMAX=2'b10, SIGMOID=2'b11} fn_sel_t;

localparam int PIPE_STAGE = 3;
localparam int LUT_DEPTH = 256;

localparam logic signed [ACC_WIDTH-1:0]	Q_MAX = 16'h7FFF;
localparam logic signed [ACC_WIDTH-1:0]	Q_MIN = 16'h8000;

logic signed [ACC_WIDTH-1:0] lut_gelu 		[0:LUT_DEPTH-1];
logic signed [ACC_WIDTH-1:0] lut_sigmoid	[0:LUT_DEPTH-1];
logic signed [ACC_WIDTH-1:0] lut_exp		[0:LUT_DEPTH-1];

initial begin
	$readmemh("../LUT/lut/gelu_q88.hex", lut_gelu);
	$readmemh("../LUT/lut/sigmoid_q88.hex", lut_sigmoid);
	$readmemh("../LUT/lut/exp_q88.hex", lut_exp);
end

logic		signed [ACC_WIDTH-1:0]	reg_in [0:NUM_LANES-1];
fn_sel_t				reg_fn;
logic					reg_valid;

//=============stage 1===============
logic	signed [ACC_WIDTH-1:0]	s1_lut [0:NUM_LANES-1];
logic	signed [ACC_WIDTH-1:0]	s1_in  [0:NUM_LANES-1];
fn_sel_t			s1_fn;
logic				s1_valid;

//=============stage 2================
logic	signed [ACC_WIDTH-1:0]	s2_out	[0:NUM_LANES-1];
fn_sel_t			s2_fn;
logic				s2_valid;

//=============stage 3==============
logic	signed [ACC_WIDTH-1:0]	s3_out	[0:NUM_LANES-1];
logic				s3_valid;

logic	[PIPE_STAGE-1:0]	busy;

logic	signed [ACC_WIDTH-1:0]		softmax_max;
logic	signed [2*ACC_WIDTH-1:0]	softmax_exp	[0:NUM_LANES-1];
logic	signed [2*ACC_WIDTH-1:0]	softmax_sum;

logic	[7:0]	fraction;
logic	signed	[ACC_WIDTH-1:0]		lut_next;
logic	signed	[2*ACC_WIDTH-1:0]	delta;
logic	signed	[2*ACC_WIDTH-1:0]	corrected;

always_ff @(posedge clk or negedge resetn) begin
	if(!resetn)	busy <= '0;
	else		busy <= {busy[PIPE_STAGE-2:0], en};
end

assign ready = ~(|pipe_busy) & ~en;

always_ff @(posedge clk or negedge resetn) begin
	if(!resetn) begin
		reg_valid <= 0;
		reg_fn	<= fn_sel_t'('0);
		for(int i=0;i<NUM_LANE;i++) reg_in[i] <= '0;
	end
	else if(en) begin
		reg_valid <= 1;
		reg_fn	<= fn_sel;
		for(int i=0;i<NUM_LANE;i++) reg_in[i] <= data_in[i];
	end else begin
		reg_valid <= 0;
	end
end

//===============stage 1===============
always_comb begin
	softmax_max = reg_in[0];
	for(int i=0;i<NUM_LANE;i++) begin
		if(reg_in[i]>softmax_max)	softmax_max = reg_in[i];
	end
end

always_ff @(posedge clk or negedge resetn) begin
	if(!resetn) begin
		s1_valid <= 0;
		s1_fn	<= fn_sel_t'('0);
		for(int i=0;i<NUM_LANE;i++) begin
			s1_lut[i] <= '0;
			s1_in[i]  <= '0;
		end
	end
	else begin
		s1_valid <= reg_valid;
		s1_fn <= reg_fn;
		for(int i=0;i<NUM_LANES;i++) begin
			s1_in[i] <= reg_in[i];
			unique case (reg_fn)
				RELU:	s1_lut[i] <= (reg_in[i] < '0) ? '0:reg_in[i];
				GELU:	s1_lut[i] <= lut_gelu[reg_in[15:8]];
				SIGMOID: s1_lut[i] <= lut_sigmoid[reg_in[15:8]];
				SOFTMAX: s1_lut[i] <= reg_in[i] - softmax_max;
				default: s1_lut[i] <= reg_in[i];
			endcase
		end
	end
end

//============stage 2================
always_comb begin
	softmax_sum ='0;
	for (int i=0;i<NUM_LANES;i++) begin
		softmax_sum = softmax_sum + 32'(lut_exp[s1_lut[i][15:8]]);
	end
end

always_ff @(posedge clk or negedge resetn) begin
	if(!resetn) begin
		s2_valid <= 0;
		s2_fn	 <= fn_sel_t'('0);
		for(int i=0;i<NUM_LANES;i++)	s2_out[i] <= '0;
	end
	else begin
		s2_valid <= s1_valid;
		s2_fn	<= s1_fn;
		for(int i=0;i<NUM_LANES;i++) begin
			unique case (s1_fn)
				RELU: s2_out[i] <= s1_lut[i];
				GELU, SIGMOID: begin
					fraction <= s1_in[i][7:0];
					lut_next <= (s1_fn == GELU) ? lut_gelu[s1_in[i][15:8] + 1]
								: lut_sigmoid[s1_inn[i][15:8] + 1];
					delta	<= 32'(lut_next) - 32'(s1_lut[i]);
					corrected <= 32'(s1_lut[i]) + ((delta * 32'(fraction))>>>8);
					if(corrected > 32'(Q_MAX))	s2_out[i] <= Q_MAX;
					else if(corrected < 32(Q_MIN))	s2_out[i] <= Q_MIN;
					else				s2_out[i] <= 16'(corrected);
				end
				SOFTMAX: begin
					if(softmax_sum != '0)	s2_out[i] <= 16'((32'(lut_exp[s1_lut[i][15:8]]) << 8) / softmax_sum);
					else			s2_out[i] <= '0;
				end
				default: s2_out[i] <= s1_lut[i];
			endcase
		end
	end
end

assign data_valid = s2_valid;
assign data_out = s2_out;

endmodule
