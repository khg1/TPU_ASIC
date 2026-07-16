module systolic_array #(
	parameter int GRID_DIM = 8,
	parameter int ACT_WIDTH = 8,
	parameter int WT_WIDTH = 8,
	parameter int ACC_WIDTH = 32
)(
	input	logic						clk, resetn, en, weights_avail,	//en (change state to compute); capture_weight (_|-> when all weights are at correct row)
	input	logic	signed	[GRID_DIM-1:0][WT_WIDTH-1:0]	weight_buffer,				//filled by memory controller
	input	logic	signed	[GRID_DIM-1:0][ACT_WIDTH-1:0]	act_buffer,				//filled by memory controller
	output	logic	signed	[GRID_DIM-1:0][ACC_WIDTH-1:0]	result,					//filled by systolic array
	output	logic						done, ready				// done (downstream pipeline handshake) ; ready (upstream pipeline handshake)
);

typedef enum logic [1:0] {IDLE=2'b00, LOAD=2'b01, COMPUTE=2'b10} state_t;
state_t current_state, next_state;

logic	signed	[ACT_WIDTH-1:0]	act_inter	[GRID_DIM-1:0][GRID_DIM:0];		//need extra column for input from shift register.
logic	signed	[ACC_WIDTH-1:0]	acc_inter	[GRID_DIM:0][GRID_DIM-1:0];		//need extra row for input from logic 0 for accumulator for row 0.
logic	signed	[WT_WIDTH-1:0]	wt_inter	[GRID_DIM-1:0][GRID_DIM-1:0];

logic	[$clog2(GRID_DIM << 1):0]	compute_counter; // Grid is always square
logic					capture_weight;
logic	[$clog2(GRID_DIM):0]		load_row_ptr;	 // Counter for keeping track for loading weights
logic					en_flag_shift_reg;

generate
	for(genvar r = 0; r < GRID_DIM; r++) begin : gen_shift_reg
		shift_register #(
			.WIDTH(ACT_WIDTH),
			.STAGES(r)
		) inst_shift_row (
			.clk(clk),
			.resetn(resetn),
			.en(en_flag_shift_reg),
			.d_in(act_buffer[r]),		
			.d_out(act_inter[r][0])		//input to PE's in column 0
		);
	end
endgenerate

assign	ready			= (current_state == IDLE);
assign	en_flag_shift_reg	= (current_state == COMPUTE) & en;

assign capture_weight = (load_row_ptr == GRID_DIM) ? 1 : 0;

always_ff @(posedge clk or negedge resetn) begin
	if(!resetn) begin
		load_row_ptr <= '0;
	end else if(current_state == LOAD) begin
		load_row_ptr <= load_row_ptr + 1;
	end
	else	load_row_ptr <= '0;
end

generate
	for(genvar r = 0; r<GRID_DIM; r++) begin		: gen_sys_row
		for(genvar c = 0; c<GRID_DIM; c++) begin	: gen_sys_col
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
				.weight(wt_inter[r][c]),
				.weight_load(capture_weight),
				.en(en_flag_shift_reg),
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
		IDLE:		next_state = (weights_avail)	? LOAD:IDLE;
		LOAD:		next_state = (capture_weight)	? COMPUTE:LOAD;
		COMPUTE:	next_state = (done)		? IDLE:COMPUTE;
		default:	next_state = IDLE;
	endcase
end

always_ff @(posedge clk or negedge resetn) begin
	if(!resetn) begin
		compute_counter <= '0;
		done <= 0;
		result <= '{default: '0};
		wt_inter <= '{default: '0};
	end
	else begin
		unique case (current_state)
			IDLE: begin
				compute_counter <= '0;
				done <= 0;
			end
			LOAD: begin
				for(int r = 0; r<GRID_DIM; r++) begin
					for(int c = 0; c<GRID_DIM; c++) begin
						if(r == 0)	wt_inter[r][c] <= weight_buffer[c];
						else		wt_inter[r][c] <= wt_inter[r-1][c];
					end
				end
			end
			COMPUTE: begin
				if(en_flag_shift_reg)	compute_counter <= compute_counter + 1;
				if((compute_counter >= GRID_DIM) && (compute_counter < (GRID_DIM << 1))) begin
					result[compute_counter - GRID_DIM] <= acc_inter[GRID_DIM][compute_counter-GRID_DIM];
				end
				else if(compute_counter >= ((GRID_DIM<<1) - 1)) begin
					done <= 1;
					compute_counter <= '0;
				end
				// done must be a one-cycle pulse: the FSM only reaches
				// IDLE (which also clears done) one edge after done
				// rises, so without this clear done stays high for two
				// cycles and the downstream vector/activation units run
				// twice per operation.
				else	done <= 0;
			end
			default: begin
				compute_counter <= '0;
				done <= 0;
				end
			endcase
	end
end

endmodule
