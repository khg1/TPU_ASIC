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
	input	logic						valid,
	input	logic	signed	[ACC_WIDTH-1:0]			vect_scale,
	output	logic	signed	[GRID_DIM-1:0][ACC_WIDTH-1:0]	data_out,
	output	logic						ready
);

typedef	enum	logic [2:0]	{IDLE = 3'h0, CAPTURE = 3'h1, MAC = 3'h2, VECTOR = 3'h3, ACTIVATION = 3'h4} state_t;

state_t current_state, next_state;

logic	signed	[GRID_DIM-1:0][WT_WIDTH-1:0]	weight_buff;
logic	signed	[GRID_DIM-1:0][ACT_WIDTH-1:0]	input_buff;
logic	signed	[GRID_DIM-1:0][ACC_WIDTH-1:0]	bias_buff;
logic	signed	[GRID_DIM-1:0][ACC_WIDTH-1:0]	result_buff_syst, result_buff_vect;

logic		[7:0]	num_edge;
logic			sig_act_valid;
logic			sig_syst_en, sig_vec_en, sig_act_en;
logic			ctrl_weight_load;

logic		ready_syst, ready_vec, ready_act;

assign ready = (current_state == IDLE) && ready_syst && ready_vec && ready_act;

always_ff @(posedge clk or negedge resetn) begin
	if(!resetn)	num_edge <= '0;
	else begin
		if(current_state == CAPTURE)	num_edge <= num_edge + 1;
		else				num_edge <= '0;
	end
end

systolic_array #(
	.GRID_DIM(GRID_DIM),
	.ACT_WIDTH(ACT_WIDTH),
	.WT_WIDTH(WT_WIDTH),
	.ACC_WIDTH(ACC_WIDTH)
) sys_array_inst(
	.clk(clk),
	.resetn(resetn),
	.en(sig_syst_en),
	.weight_load(ctrl_weight_load),
	.weight_data(weight_buff),
	.act_in(input_buff),
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
)act_unit_inst(
	.clk(clk),
	.resetn(resetn),
	.en(sig_act_en),
	.fn_sel(act_fn_sel),
	.data_in(result_buff_vect),
	.data_out(data_out),
	.data_valid(sig_act_valid),
	.ready(ready_act)
);

always_ff @(posedge clk or negedge resetn) begin
	if(!resetn)	current_state	<= IDLE;
	else		current_state	<= next_state;
end

always_comb begin
	unique case (current_state)
		IDLE:		next_state = (valid)		? CAPTURE	: IDLE;
		CAPTURE:	next_state = (num_edge == 11)	? MAC		: CAPTURE;
		MAC:		next_state = (sig_vec_en)	? VECTOR	: MAC;
		VECTOR:		next_state = (sig_act_en)	? ACTIVATION	: VECTOR;
		ACTIVATION:	next_state = (sig_act_valid)	? IDLE		: ACTIVATION;
		default:	next_state = IDLE;	
	endcase
end

always_ff @(posedge clk or negedge resetn) begin
	if(!resetn) begin
		sig_syst_en		<= 0;
		ctrl_weight_load	<= 0;
		weight_buff		<= '{default '0};
		input_buff		<= '{default '0};
		bias_buff		<= '{default '0};
	end
	else begin
		unique case (current_state)
			IDLE:	ctrl_weight_load <= 0;
			CAPTURE: begin
				if(num_edge < 2) begin
					for(int i=0; i< (GRID_DIM >> 1); i++) begin
						weight_buff[i + 4*num_edge] <= data_in[i*WT_WIDTH +: WT_WIDTH];
					end
				end
				else if(num_edge >= 2 && num_edge <4) begin
					ctrl_weight_load <= 1;
					for(int i=0; i< (GRID_DIM >> 1); i++) begin
						input_buff[i + 4*(num_edge-2)] <= data_in[i*ACT_WIDTH +: ACT_WIDTH];
					end
				end
				else if(num_edge >=4 && num_edge <12) begin
					if(num_edge == 4)	sig_syst_en <= 1;
					else			sig_syst_en <= 0;
					bias_buff[num_edge - 4] <= data_in;
				end
			end
			MAC:	ctrl_weight_load <= 0;
			VECTOR: ctrl_weight_load <= 0;
			ACTIVATION: ctrl_weight_load <= 0;
			default: begin
                		weight_buff             <= '{default '0};
                		input_buff              <= '{default '0};
                		bias_buff               <= '{default '0};
			end
		endcase
	end
end

endmodule
