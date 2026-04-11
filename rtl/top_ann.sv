/*
* This module connects the ANN accelerator with the module named sram which
* contains the weights and biases stored and also controller for managing data
* data flow
*/

`timescale 1ns/1ps;

module top_ann #(parameter DATA_WIDTH = 8, parameter NUM_INPUT = 4, parameter NUM_HIDDEN = 10, parameter NUM_OUT = 3) (
	input logic 			    	clk, rst, data_avail_flag,
	input logic signed [DATA_WIDTH-1:0] 	data_in [0:NUM_INPUT-1],
	output logic 	   [1:0]		inference_result,
	output logic	   			spi_ready_flag
);

logic sig_en;
logic signed [DATA_WIDTH-1:0] sig_hidden_parameters [0:NUM_HIDDEN-1];
logic signed [DATA_WIDTH-1:0] sig_out_parameters    [0:NUM_OUT-1];

ann #(.DATA_WIDTH(DATA_WIDTH),.NUM_INPUT(NUM_INPUT),.NUM_HIDDEN(NUM_HIDDEN),.NUM_OUT(NUM_OUT)) ANN_INST (
		.clk(clk), .rst(rst), .en(sig_en), .data_in(data_in), .hidden_parameters(sig_hidden_parameters), .out_parameters(sig_out_parameters), .classification(inference_result), .spi_ready_flag(spi_ready_flag));

sram #(.DATA_WIDTH(DATA_WIDTH),.NUM_INPUT(NUM_INPUT),.NUM_HIDDEN(NUM_HIDDEN),.NUM_OUT(NUM_OUT)) SRAM_INST (
	.clk(clk), .rst(rst), .data_avail_flag(data_avail_flag), .en(sig_en), .hidden_port(sig_hidden_parameters), .out_port(sig_out_parameters));

endmodule
