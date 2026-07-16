//=============================================================================
// npu_core
//
// One inference transaction:
//   1. Host waits for ready, then streams TOTAL_BEATS beats on data_in, one
//      beat per cycle in which valid is high (e.g. RVALID && RREADY). The
//      first beat may arrive in the same cycle that starts the transaction.
//        beats 0  .. 15 : weights, row-major. Each beat carries
//                         WTS_PER_BEAT (= DATA_WIDTH/WT_WIDTH) weights,
//                         lowest byte = lowest column index.
//                         weight_matrix[r][c] ends up in PE row r, column c,
//                         so the array computes result[c] = sum_r act[r]*w[r][c].
//        beats 16 .. 17 : activations, ACTS_PER_BEAT per beat, lowest byte
//                         = lowest lane index.
//        beats 18 .. 25 : bias, one sign-extended ACC_WIDTH word per beat
//                         (Q8.8), lane 0 first.
//      (Beat counts shown for the default 8x8 / 8-bit / 32-bit parameters.)
//   2. LOADW streams the captured weight rows into the systolic array
//      (bottom row first, matching the array's internal top-down shift).
//   3. MAC / VECTOR / ACTIVATION run the pipeline; data_out is qualified by
//      a one-cycle out_valid pulse and holds until the next transaction.
//
// vec_op_sel, act_fn_sel and vect_scale must be held stable for the whole
// transaction.
//=============================================================================
module npu_core #(
	parameter int DATA_WIDTH = 32,
	parameter int GRID_DIM = 8,
	parameter int WT_WIDTH = 8,
	parameter int ACT_WIDTH = 8,
	parameter int ACC_WIDTH = 32
)(
	input	logic						clk, resetn,
	input	logic	signed	[DATA_WIDTH-1:0]		data_in,
	input	logic	[1:0]					vec_op_sel, act_fn_sel,
	input	logic						valid,				// qualifies each data_in beat
	input	logic	signed	[ACC_WIDTH-1:0]			vect_scale,
	output	logic	signed	[GRID_DIM-1:0][ACC_WIDTH-1:0]	data_out,
	output	logic						out_valid,
	output	logic						ready
);

typedef	enum	logic [2:0]	{IDLE = 3'h0, CAPTURE = 3'h1, LOADW = 3'h2, MAC = 3'h3, VECTOR = 3'h4, ACTIVATION = 3'h5} state_t;

state_t current_state, next_state;

localparam int WTS_PER_BEAT		= DATA_WIDTH / WT_WIDTH;	//4
localparam int WT_BEATS_PER_ROW		= GRID_DIM / WTS_PER_BEAT;	//2
localparam int WT_BEATS			= GRID_DIM * WT_BEATS_PER_ROW;	//16
localparam int ACTS_PER_BEAT		= DATA_WIDTH / ACT_WIDTH;	//4
localparam int ACT_BEATS		= GRID_DIM / ACTS_PER_BEAT;	//2
localparam int BIAS_BEATS		= GRID_DIM;			//8
localparam int TOTAL_BEATS		= WT_BEATS + ACT_BEATS + BIAS_BEATS;	//26

initial begin
	if((GRID_DIM % WTS_PER_BEAT != 0) || (GRID_DIM % ACTS_PER_BEAT != 0))
		$fatal(1, "npu_core: GRID_DIM must be a multiple of the per-beat weight/activation counts");
end

logic	signed	[GRID_DIM-1:0][WT_WIDTH-1:0]	weight_buff;
logic	signed	[GRID_DIM-1:0][ACT_WIDTH-1:0]	input_buff;
logic	signed	[GRID_DIM-1:0][ACC_WIDTH-1:0]	bias_buff;
logic	signed	[GRID_DIM-1:0][ACC_WIDTH-1:0]	result_buff_syst, result_buff_vect;

logic	signed	[GRID_DIM-1:0][WT_WIDTH-1:0]	weight_matrix	[0:GRID_DIM-1];

logic	[$clog2(TOTAL_BEATS):0]	beat_cnt;
logic	[$clog2(GRID_DIM):0]	load_cnt;
logic				capture_beat;
logic				sig_wt_avail, sig_syst_en, sig_vec_en, sig_act_en, sig_act_valid;
logic				ready_syst, ready_vec, ready_act;

assign ready		= (current_state == IDLE) && ready_syst && ready_vec && ready_act;
assign capture_beat	= valid && (((current_state == IDLE) && ready) || (current_state == CAPTURE));
assign sig_wt_avail	= (current_state == LOADW);
assign sig_syst_en	= (current_state == MAC);
assign out_valid	= sig_act_valid;

//===================== beat capture =====================
always_ff @(posedge clk or negedge resetn) begin
	if(!resetn)	beat_cnt <= '0;
	else begin
		if(capture_beat)						beat_cnt <= beat_cnt + 1;
		else if(!(current_state inside {IDLE, CAPTURE}))		beat_cnt <= '0;
	end
end

// Datapath buffers carry no reset: every entry is written during CAPTURE
// before anything downstream samples it.
always_ff @(posedge clk) begin
	if(capture_beat) begin
		if(beat_cnt < WT_BEATS) begin
			for(int j = 0; j < WTS_PER_BEAT; j++)
				weight_matrix[beat_cnt / WT_BEATS_PER_ROW][((beat_cnt % WT_BEATS_PER_ROW) * WTS_PER_BEAT) + j] <= data_in[j*WT_WIDTH +: WT_WIDTH];
		end
		else if(beat_cnt < WT_BEATS + ACT_BEATS) begin
			for(int j = 0; j < ACTS_PER_BEAT; j++)
				input_buff[((beat_cnt - WT_BEATS) * ACTS_PER_BEAT) + j] <= data_in[j*ACT_WIDTH +: ACT_WIDTH];
		end
		else begin
			bias_buff[beat_cnt - WT_BEATS - ACT_BEATS] <= ACC_WIDTH'(data_in);
		end
	end
end

//===================== weight streaming into systolic array =====================
// The array shifts weight_buff downward internally, so rows are presented in
// reverse: weight_matrix[GRID_DIM-1] first, weight_matrix[0] last.
always_ff @(posedge clk or negedge resetn) begin
	if(!resetn) begin
		load_cnt	<= '0;
		weight_buff	<= '0;
	end
	else if(current_state == LOADW) begin
		if(load_cnt < GRID_DIM) begin
			weight_buff	<= weight_matrix[GRID_DIM - 1 - load_cnt];
			load_cnt	<= load_cnt + 1;
		end
	end
	else	load_cnt <= '0;
end

//===================== compute pipeline =====================
systolic_array #(
	.GRID_DIM(GRID_DIM),
	.ACT_WIDTH(ACT_WIDTH),
	.WT_WIDTH(WT_WIDTH),
	.ACC_WIDTH(ACC_WIDTH)
) sys_array_inst(
	.clk(clk),
	.resetn(resetn),
	.en(sig_syst_en),
	.weights_avail(sig_wt_avail),
	.weight_buffer(weight_buff),
	.act_buffer(input_buff),
	.result(result_buff_syst),
	.done(sig_vec_en),
	.ready(ready_syst)
);

vector_unit #(
	.NUM_LANES(GRID_DIM),
	.ACC_WIDTH(ACC_WIDTH)
) vect_unit_inst(
	.clk(clk),
	.resetn(resetn),
	.en(sig_vec_en),
	.op_sel(vec_op_sel),
	.vector_a(bias_buff),
	.vector_b(result_buff_syst),
	.scale(vect_scale),
	.result(result_buff_vect),
	.result_valid(sig_act_en),
	.ready(ready_vec)
);

activation_unit #(
	.NUM_LANES(GRID_DIM),
	.ACC_WIDTH(ACC_WIDTH)
) act_unit_inst(
	.clk(clk),
	.resetn(resetn),
	.en(sig_act_en),
	.fn_sel(act_fn_sel),
	.data_in(result_buff_vect),
	.data_out(data_out),
	.data_valid(sig_act_valid),
	.ready(ready_act)
);

//===================== FSM =====================
always_ff @(posedge clk or negedge resetn) begin
	if(!resetn)	current_state	<= IDLE;
	else		current_state	<= next_state;
end

always_comb begin
	unique case (current_state)
		IDLE:		next_state = (valid && ready)			? CAPTURE	: IDLE;
		CAPTURE:	next_state = (capture_beat && (beat_cnt == TOTAL_BEATS - 1))	? LOADW	: CAPTURE;
		LOADW:		next_state = (load_cnt == GRID_DIM)		? MAC		: LOADW;
		MAC:		next_state = (sig_vec_en)			? VECTOR	: MAC;
		VECTOR:		next_state = (sig_act_en)			? ACTIVATION	: VECTOR;
		ACTIVATION:	next_state = (sig_act_valid)			? IDLE		: ACTIVATION;
		default:	next_state = IDLE;
	endcase
end

endmodule
