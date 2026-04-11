/*
* This module is for the hidden layer neuron.
*/

`timescale 1ns/1ps;

//package containing enumeration for states of FSM
package fsm_pkg;
	typedef enum logic [1:0] {IDLE_STATE=2'b00,MAC_STATE=2'b01,OUTPUT_STATE=2'b10}state_e;
endpackage

//parameterized neuron with number of input, width of data and number of fractions bits (Q8.4)
module ann_neuron #(parameter NUM_INPUT = 4, parameter DATA_WIDTH = 8, parameter FRAC_BITS = 4)(
	input  logic 			      clk,rst,en,		// clk: 1.25GHz, rst asynchronous, en (control signal for state transition)
        input  logic signed [DATA_WIDTH-1:0]  data_in [0:NUM_INPUT-1],	// Array of 4 elements each representing one of the features of IRIS dataset	
        input  logic signed [DATA_WIDTH-1:0]  sram_port,		// weights and biases loaded from block called sram
        output logic signed [DATA_WIDTH-1:0]  data_out,			// neuron output after activation function
	output logic 			      rdy   			// rdy is next layer's en input signal
);

import fsm_pkg::*;

state_e current_state, next_state;

// local parameters
localparam MAC_WIDTH = 2*DATA_WIDTH;			//2*8 = 16
localparam MAX 	     = {1'b0, {(DATA_WIDTH-1){1'b1}}};	//127
localparam MIN 	     = {1'b1, {(DATA_WIDTH-1){1'b0}}};	//-128
  

// local signals
logic signed [MAC_WIDTH-1:0]  sig_accumulator, sig_perceptron_output, sig_activation_output, sig_ext_bias;
logic signed [DATA_WIDTH-1:0] sig_quant_out;
logic expected_sign_bit, actual_sign_bit, overflow, underflow;
logic [5:0] num_mac_op;

// state_register
always_ff @(posedge clk or posedge rst) begin
	if(rst) current_state <= IDLE_STATE;
	else	current_state <= next_state;
end

// next_state_decode
always_comb begin
	case(current_state)
	IDLE_STATE: 	next_state = (en) ? MAC_STATE:IDLE_STATE;
	MAC_STATE: 	next_state = (num_mac_op == (NUM_INPUT - 1)) ? OUTPUT_STATE:MAC_STATE;
	OUTPUT_STATE: 	next_state = (!en) ? IDLE_STATE:OUTPUT_STATE;
	default:      	next_state = IDLE_STATE;
	endcase
end

// state_output_decode
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
assign expected_sign_bit = sig_perceptron_output[MAC_WIDTH-1-FRAC_BITS];
assign actual_sign_bit 	 = sig_perceptron_output[MAC_WIDTH-1];
assign overflow 	 = ~actual_sign_bit & expected_sign_bit;
assign underflow 	 = actual_sign_bit & ~expected_sign_bit;
assign sig_ext_bias = {{DATA_WIDTH-FRAC_BITS{sram_port[DATA_WIDTH-1]}},sram_port,{FRAC_BITS{1'b0}}};

/* combinational block for detecting overflow and also implements activation
   function */
always_comb begin
  sig_quant_out = sig_perceptron_output[MAC_WIDTH-1-FRAC_BITS:FRAC_BITS];

  if(overflow)		sig_quant_out = MAX;
  else if(underflow)	sig_quant_out = MIN;
 
  sig_activation_output = (sig_quant_out<0) ? 0:sig_quant_out;
end

assign data_out = sig_activation_output;

endmodule
