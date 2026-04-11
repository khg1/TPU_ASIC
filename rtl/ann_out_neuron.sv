/*
* The primary difference between this module and ann_neuron is the length of
* the data_out. Since this is the output neuron, there is no need for
* quantizing output, to retain precision for final classification.
*/

`timescale 1ns/1ps;

module ann_out_neuron #(parameter NUM_INPUT = 10, parameter DATA_WIDTH = 8, parameter FRAC_BITS = 4)(
	input logic 			     	 clk,rst,en,			// clk: 1.25GHz, rst asynchronous, en (control signal for state transition)
        input logic  signed [DATA_WIDTH-1:0] 	 data_in [0:NUM_INPUT-1],	// Array of 4 elements each representing one of the features of IRIS dataset
        input logic  signed [DATA_WIDTH-1:0] 	 sram_port,			// weights and biases loaded from block called sram
        output logic signed [(DATA_WIDTH*2)-1:0] data_out,			// neuron output after activation function
	output logic 			     	 rdy   				// rdy is used as write_enable for the spi sram
);

//package containing enumeration for states of FSM
import fsm_pkg::*;

state_e current_state, next_state;

localparam MAC_WIDTH = 2*DATA_WIDTH;						//2*8 = 16
localparam MAX = {1'b0, {(DATA_WIDTH-1){1'b1}}};				//127
localparam MIN = {1'b1, {(DATA_WIDTH-1){1'b0}}};				//-128
  

// local signals
logic signed [MAC_WIDTH-1:0] sig_accumulator, sig_perceptron_output, sig_ext_bias;
logic [5:0] num_mac_op;

// state register
always_ff @(posedge clk or posedge rst) begin
	if(rst) current_state <= IDLE_STATE;
	else	current_state <= next_state;
end

// next state decode
always_comb begin
	case(current_state)
	IDLE_STATE: next_state = (en) ? MAC_STATE:IDLE_STATE;
	MAC_STATE: next_state = (num_mac_op == (NUM_INPUT - 1)) ? OUTPUT_STATE:MAC_STATE;
	OUTPUT_STATE: next_state = (!en) ? IDLE_STATE:OUTPUT_STATE;
	default: next_state = IDLE_STATE;
	endcase
end

// state output decode
always_ff @(posedge clk) begin
	case(current_state)
	IDLE_STATE: begin
	num_mac_op <= '0;
	sig_accumulator <= '0;
        sig_perceptron_output <= '0;
	rdy <= 0;
	end
	MAC_STATE: begin
	num_mac_op <= num_mac_op + 1;
	sig_accumulator <= sig_accumulator + signed'(MAC_WIDTH'(data_in[num_mac_op] * sram_port));
        sig_perceptron_output <= '0;
	rdy <= 0;
	end
	OUTPUT_STATE: begin
	num_mac_op <= '0;
	sig_perceptron_output <= sig_accumulator + sig_ext_bias;
	sig_accumulator <= '0;
	rdy <= 1;
	end	
	endcase
end

// assignment of local signals
assign sig_ext_bias = {{DATA_WIDTH-FRAC_BITS{sram_port[DATA_WIDTH-1]}},sram_port,{FRAC_BITS{1'b0}}};
assign data_out = sig_perceptron_output;

endmodule
