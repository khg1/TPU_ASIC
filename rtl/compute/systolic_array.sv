module systolic_array #(
	parameter int GRID_DIM = 8,
	parameter int ACT_WIDTH = 8,
	parameter int WT_WIDTH = 8,
	parameter int ACC_WIDTH = 32
)(
	input	logic	clk, resetn,
	input	logic	en,
	input	logic	capture_weight,
	input	logic	signed	[GRID_DIM-1:0][WT_WIDTH-1:0]	weight_data,
	input	logic	signed	[GRID_DIM-1:0][ACT_WIDTH-1:0]	act_in,

	output	logic	signed	[GRID_DIM-1:0][ACC_WIDTH-1:0]	result,
	output	logic						done,
	output	logic						ready	
);

typedef enum logic [1:0] {IDLE=2'b00, LOAD=2'b01, COMPUTE=2'b10} state_t;

logic	signed	[ACT_WIDTH-1:0]	act_inter	[GRID_DIM-1:0][GRID_DIM:0];
logic	signed	[ACC_WIDTH-1:0]	acc_inter	[GRID_DIM:0][GRID_DIM-1:0];

state_t current_state, next_state;

logic	[4:0]			compute_counter;
logic	[$clog2(GRID_DIM)-1:0]	load_row_ptr;
logic	[GRID_DIM-1:0]		load_en_onehot;
logic				computing_flag;

generate
	for(genvar r = 0; r < GRID_DIM; r++) begin
		shift_register #(
			.WIDTH(ACT_WIDTH),
			.STAGES(r)
		) inst_shift_row (
			.clk(clk),
			.resetn(resetn),
			.clear('0),
			.shift_en(computing_flag),
			.data_in(act_in[r]),
			.data_out(act_inter[r][0])
		);
	end
endgenerate

assign ready = (current_state == IDLE);
assign computing_flag = (current_state == COMPUTE);

always_ff @(posedge clk or negedge resetn) begin
	if(!resetn) begin
		load_row_ptr <= '0;
	end else if(current_state == LOAD) begin
		load_row_ptr <= load_row_ptr + 1;
	end
	else	load_row_ptr <= '0;
end

assign load_en_onehot = (current_state == LOAD) ? (1'b1 << load_row_ptr) : '0;

generate
	for(genvar r = 0; r<GRID_DIM; r++) begin
		for(genvar c = 0; c<GRID_DIM; c++) begin
			if(r == 0) begin
				assign acc_inter[0][c] = '0;
			end

			processing_element #(
				.ACT_WIDTH(ACT_WIDTH),
				.ACC_WIDTH(ACC_WIDTH),
				.WT_WIDTH(WT_WIDTH)
			) pe_inst (
				.clk(clk),
				.resetn(resetn),
				.weight(weight_data[c]),
				.weight_load(load_en_onehot[r]),
				.en(computing_flag),
				.act_in(act_inter[r][c]),
				.acc_in(acc_inter[r][c]),
				.act_out(act_inter[r][c+1]),
				.acc_out(acc_inter[r+1][c])
			);
		end
	end
endgenerate


always_ff @(posedge clk or negedge resetn) begin
	if(!resetn)	current_state <= IDLE;	
	else		current_state <= next_state;
end

always_comb begin
	unique case (current_state)
		IDLE: begin
			if(capture_weight)	next_state = LOAD;
			else if(en)		next_state = COMPUTE;
			else			next_state = IDLE;
		end
		LOAD:	next_state = (load_row_ptr == (GRID_DIM-1)) ? IDLE:LOAD;
		COMPUTE: next_state = (done) ? IDLE:COMPUTE;
		default: next_state = IDLE;
	endcase
end

always_ff @(posedge clk or negedge resetn) begin
	if(!resetn) begin
		compute_counter <= '0;
		done <= 0;
		result <= '{default: '0};
	end
	else begin
		unique case (current_state)
			IDLE: begin
				compute_counter <= '0;
				done <= 0;
			end
			COMPUTE: begin
				compute_counter <= compute_counter + 1;
				if(compute_counter >= GRID_DIM && compute_counter < 2*GRID_DIM) begin
					result[compute_counter - GRID_DIM] <= acc_inter[GRID_DIM][compute_counter-GRID_DIM];
				end
				else if(compute_counter >= 2*GRID_DIM - 1) begin
					done <= 1;
				end
			end
			default: begin
				compute_counter <= '0;
				done <= 0;
			end
		endcase
	end
end

endmodule
