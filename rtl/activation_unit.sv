module activation_unit #(
	parameter int NUM_LANES = 16,
	parameter int ACC_WIDTH = 16
)(
	input	logic	clk, resetn,
	input	logic	en,
	input	logic	[1:0]	fn_sel,
	input	logic	signed	[NUM_LANES-1:0][ACC_WIDTH-1:0]	data_in,
	output	logic	signed	[NUM_LANES-1:0][ACC_WIDTH-1:0]	data_out,
	output	logic	data_valid,
	output	logic	ready
);

//typedef enum logic [1:0] {RELU=2'b00, GELU=2'b01, SOFTMAX=2'b10, SIGMOID=2'b11} fn_sel_t;
typedef enum logic [1:0] {RELU=2'b00, GELU=2'b01, SIGMOID=2'b10} fn_sel_t;
localparam int PIPE_STAGE = 3;
localparam int LUT_DEPTH = 256;
localparam int LUT_WIDTH = 16;	// LUT entries are Q8.8 regardless of ACC_WIDTH

// Q8.8 saturation bounds; sign-extended so they stay correct when ACC_WIDTH > 16.
// Contract: data_in is Q8.8, i.e. already saturated to [Q_MIN, Q_MAX] by the caller.
localparam logic signed [ACC_WIDTH-1:0]	Q_MAX = ACC_WIDTH'(16'sh7FFF);
localparam logic signed [ACC_WIDTH-1:0]	Q_MIN = ACC_WIDTH'(16'sh8000);

logic signed [LUT_WIDTH-1:0] lut_gelu 		[0:LUT_DEPTH-1];
logic signed [LUT_WIDTH-1:0] lut_sigmoid	[0:LUT_DEPTH-1];
//logic signed [LUT_WIDTH-1:0] lut_exp		[0:LUT_DEPTH-1];

initial begin
	$readmemh("../LUT/lut/gelu_q88.hex", lut_gelu);
	$readmemh("../LUT/lut/sigmoid_q88.hex", lut_sigmoid);
//	$readmemh("../LUT/lut/exp_q88.hex", lut_exp);
end

logic		signed [NUM_LANES-1:0][ACC_WIDTH-1:0]	reg_in;
fn_sel_t				reg_fn;
logic					reg_valid;

//=============stage 1===============
logic	signed [NUM_LANES-1:0][ACC_WIDTH-1:0]	s1_lut;
logic	signed [NUM_LANES-1:0][ACC_WIDTH-1:0]	s1_in;
fn_sel_t			s1_fn;
logic				s1_valid;

//=============stage 2================
logic	signed [NUM_LANES-1:0][ACC_WIDTH-1:0]	s2_out;
fn_sel_t			s2_fn;
logic				s2_valid;

logic	[PIPE_STAGE-1:0]	busy;

//logic	signed [ACC_WIDTH-1:0]		softmax_max;
//logic	signed [2*ACC_WIDTH-1:0]	softmax_sum;

// Per-lane temporaries are unpacked arrays: an element select of a *packed*
// array is always unsigned in SystemVerilog, which silently breaks the signed
// interpolation/clamp arithmetic. Unpacked element selects keep their sign.
logic		[7:0]			fraction	[NUM_LANES];
logic		[7:0]			idx_next	[NUM_LANES];
logic	signed	[ACC_WIDTH-1:0]		lut_next	[NUM_LANES];
logic	signed	[2*ACC_WIDTH-1:0]	delta		[NUM_LANES];	
logic	signed	[2*ACC_WIDTH-1:0]	corrected	[NUM_LANES];

always_ff @(posedge clk or negedge resetn) begin
	if(!resetn)	busy <= '0;
	else		busy <= {busy[PIPE_STAGE-2:0], en};
end

assign ready = ~(|busy) & ~en;

always_ff @(posedge clk or negedge resetn) begin
	if(!resetn) begin
		reg_valid <= 0;
		reg_fn	<= fn_sel_t'('0);
		for(int i=0;i<NUM_LANES;i++) reg_in[i] <= '0;
	end
	else if(en) begin
		reg_valid <= 1;
		reg_fn	<= fn_sel_t'(fn_sel);
		for(int i=0;i<NUM_LANES;i++) reg_in[i] <= data_in[i];
	end else begin
		reg_valid <= 0;
	end
end

//===============stage 1===============
//always_comb begin
//	softmax_max = reg_in[0];
//	for(int i=0;i<NUM_LANES;i++) begin
//		if(reg_in[i]>softmax_max)	softmax_max = reg_in[i];
//	end
//end

always_ff @(posedge clk or negedge resetn) begin
	if(!resetn) begin
		s1_valid <= 0;
		s1_fn	<= fn_sel_t'('0);
		for(int i=0;i<NUM_LANES;i++) begin
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
				RELU:	s1_lut[i] <= (signed'(reg_in[i]) < 0) ? '0:reg_in[i];
				GELU:	s1_lut[i] <= lut_gelu[reg_in[i][15:8]];
			        SIGMOID: s1_lut[i] <= lut_sigmoid[reg_in[i][15:8]];
				//SOFTMAX: s1_lut[i] <= reg_in[i] - softmax_max;
				default: s1_lut[i] <= reg_in[i];
			endcase
		end
	end
end

//============stage 2================
always_comb begin
	//softmax_sum ='0;
	//for (int i=0;i<NUM_LANES;i++) begin
	//	softmax_sum = softmax_sum + 32'(lut_exp[s1_lut[i][15:8]]);
	//end
	for (int i=0;i<NUM_LANES;i++) begin
		fraction[i]  = s1_in[i][7:0];
		// LUT addresses are the raw two's-complement upper byte (x = -128..-1 at 0x80..0xFF,
		// x = 0..127 at 0x00..0x7F). The 8-bit wrap 0xFF -> 0x00 is the correct neighbour
		// (x = -1 -> x = 0); the only edge to clamp is x = +127 (0x7F), whose successor
		// would otherwise be x = -128 (0x80).
		idx_next[i]  = (s1_in[i][15:8] == 8'h7F) ? 8'h7F : (s1_in[i][15:8] + 8'd1);
		lut_next[i]  = (s1_fn == GELU) ? lut_gelu[idx_next[i]] : lut_sigmoid[idx_next[i]];
		delta[i]     = (2*ACC_WIDTH)'(lut_next[i]) - (2*ACC_WIDTH)'(signed'(s1_lut[i]));
		corrected[i] = (2*ACC_WIDTH)'(signed'(s1_lut[i])) + ((delta[i] * (2*ACC_WIDTH)'(signed'({1'b0, fraction[i]})))>>>8);
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
					if(corrected[i] > (2*ACC_WIDTH)'(Q_MAX))	s2_out[i] <= Q_MAX;
					else if(corrected[i] < (2*ACC_WIDTH)'(Q_MIN))	s2_out[i] <= Q_MIN;
					else						s2_out[i] <= ACC_WIDTH'(corrected[i]);
				end
				//SOFTMAX: begin
				//	if(softmax_sum != '0)	s2_out[i] <= 16'((32'(lut_exp[s1_lut[i][15:8]]) << 8) / softmax_sum);
				//	else			s2_out[i] <= '0;
				//end
				default: s2_out[i] <= s1_lut[i];
			endcase
		end
	end
end

assign data_valid = s2_valid;
assign data_out = s2_out;

endmodule
