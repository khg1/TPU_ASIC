`timescale 1ns/1ps;

//package containing enumeration for states of FSM
package fsm_sram;
	typedef enum logic [2:0] {L1_LOAD=3'b000, L1_ACTIVE=3'b001, L2_LOAD=3'b010, L2_ACTIVE=3'b011, IDLE=3'b100} state_e;
endpackage

//block named sram which is intended to be used as read only memory for
//storing weights and biases. It also generates control signals for
//data path pipelining.
module sram #(parameter DATA_WIDTH = 8, parameter NUM_INPUT = 4, parameter NUM_HIDDEN = 10, parameter NUM_OUT = 3)(
	input  logic 				clk, rst, data_avail_flag,	// data_avail_flag indicates when the input data is available from SPI SUB
	output logic 				en,				// control signal for neurons FSM state transition
	output logic signed  [DATA_WIDTH-1:0] hidden_port [0:NUM_HIDDEN-1],	// output array connected to hidden layer's neurons
	output logic signed  [DATA_WIDTH-1:0] out_port 	  [0:NUM_OUT-1]		// output array connected to output layer's neurons
);

import fsm_sram::*;

state_e current_state, next_state;

// hidden layer weights are quantized to Q8.4
localparam logic signed [DATA_WIDTH-1:0] weights_hidden [0:NUM_INPUT-1][0:NUM_HIDDEN-1] = '{
	'{8'hff, 8'h06, 8'h01, 8'h00, 8'h04, 8'h04, 8'h03, 8'h00, 8'hfd, 8'h00},
	'{8'h00, 8'h01, 8'h03, 8'h03, 8'h03, 8'hfe, 8'h00, 8'hf9, 8'h02, 8'h04},
	'{8'hf9, 8'h07, 8'hf8, 8'h06, 8'h06, 8'hfc, 8'h05, 8'hfa, 8'hfb, 8'hfc},
	'{8'hfc, 8'hfd, 8'hfa, 8'h02, 8'hfc, 8'hfa, 8'hfe, 8'hfb, 8'h05, 8'h07}
};

// hidden layer biases are quantized to Q8.4
localparam logic signed [DATA_WIDTH-1:0] biases_hidden  [0:NUM_HIDDEN-1] = '{
	8'h02, 8'h02, 8'hfd, 8'hf8, 8'hf9, 8'hfd, 8'h06, 8'h06, 8'h08, 8'hf9
};

// output layer weights are quantized to Q8.4
localparam logic signed [DATA_WIDTH-1:0] weights_out    [0:NUM_HIDDEN-1][0:NUM_OUT-1] = '{
	'{8'hfc, 8'h01, 8'hfd},
	'{8'hfd, 8'h05, 8'hff},
	'{8'hfe, 8'hef, 8'he1},
	'{8'hfe, 8'he8, 8'h5a},
	'{8'h02, 8'h09, 8'hff},
	'{8'h01, 8'h80, 8'hd8},
	'{8'h01, 8'h11, 8'hf8},
	'{8'h04, 8'h02, 8'h03},
	'{8'h02, 8'hfe, 8'hfc},
	'{8'hff, 8'h80, 8'h60}
};

// output layer biases are quantized to Q8.4
localparam logic signed [DATA_WIDTH-1:0] biases_out     [0:NUM_OUT-1] = '{
	8'hfd, 8'h15, 8'h99
};

logic signed [DATA_WIDTH-1:0] num_clk_edges;

//main sequential block containing state register for finite state machine
//used for correctly loading weights and biases depending on the current stage
//of pipeline
always_ff @(posedge clk or posedge rst) begin
	if(rst)	begin
		current_state <= L1_LOAD;
		num_clk_edges <= 0;
	end
	else	begin
		current_state <= next_state;
		if(current_state == L1_LOAD)		num_clk_edges <= 0;
		else					num_clk_edges <= num_clk_edges + 1;
	end
end

//next state logic
always_comb begin
	case(current_state)
	L1_LOAD:   next_state = (data_avail_flag)     ? 	L1_ACTIVE : L1_LOAD;
	L1_ACTIVE: next_state = (num_clk_edges == 4)  ? 	L2_LOAD   : L1_ACTIVE;
	L2_LOAD:   next_state = (num_clk_edges == 7)  ? 	L2_ACTIVE : L2_LOAD;
	L2_ACTIVE: next_state = (num_clk_edges == 16) ? 	IDLE      : L2_ACTIVE;
	IDLE: 	   next_state = (num_clk_edges == 18) ? 	L1_LOAD   : IDLE;
	default:   next_state = L1_LOAD;
	endcase
end

//output logic
always_ff @(posedge clk) begin
	case(current_state)
		L1_LOAD: begin
			hidden_port <= weights_hidden[0];
			if(next_state == L1_ACTIVE)     en <= 1;
			else				en <= 0;
		end
		L1_ACTIVE: begin
			if(num_clk_edges <= 3)		hidden_port <= weights_hidden[num_clk_edges];
			else if(num_clk_edges == 4)     hidden_port <= biases_hidden;
			en <= 0;
		end
		L2_LOAD: begin
			en <= 0;
			if(num_clk_edges >= 6 && num_clk_edges <= 7)		out_port <= weights_out[num_clk_edges - 6];
		end
		L2_ACTIVE: begin
			if(num_clk_edges >= 8 && num_clk_edges <= 15)		out_port <= weights_out[num_clk_edges - 6];
			if(num_clk_edges == 16)					out_port <= biases_out;
		end
		IDLE: begin
			if(num_clk_edges == 17)					hidden_port <= weights_hidden[0];
		end
	endcase
end


endmodule

