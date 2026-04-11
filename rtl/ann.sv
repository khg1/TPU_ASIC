/*
* This is the top level module for the ANN accelerator, it creates the neural
* topology comprising of three layers, layer 1 input, layer 2 hidden, and
* layer 3 output
*/
`timescale 1ns / 1ps;

module ann #(parameter DATA_WIDTH = 8, parameter NUM_INPUT = 4, parameter NUM_HIDDEN = 10, parameter NUM_OUT = 3) (
	input logic 				 clk, rst, en,					// en is input from the read_only memory block
	input logic signed [DATA_WIDTH-1:0]	 data_in 		[0:NUM_INPUT-1],
	input logic signed [DATA_WIDTH-1:0] 	 hidden_parameters 	[0:NUM_HIDDEN-1],
	input logic signed [DATA_WIDTH-1:0] 	 out_parameters 	[0:NUM_OUT-1],
	output logic [1:0]			 classification,				// holds the classification result
	output logic 				 spi_ready_flag					// write_enable for the SPI sram
);

logic	     [DATA_WIDTH-1:0]	  num_clk_t;
logic 				  sig_hidden_rdy_flag [0:NUM_HIDDEN-1];
logic 				  sig_out_rdy_flag    [0:NUM_OUT-1];
logic signed [DATA_WIDTH-1:0] 	  sig_hidden_out      [0:NUM_HIDDEN-1];
logic signed [(DATA_WIDTH*2)-1:0] sig_out_out         [0:NUM_OUT-1];
logic signed [DATA_WIDTH-1:0]     reg_pipeline        [0:NUM_HIDDEN-1];

//generate block for creating instances of hidden and output layer neuron.
//No. of hidden neuron -> 10
//No. of output neuron -> 3
genvar i,j;
generate
	for(i=0;i<NUM_HIDDEN;i++) begin
		ann_neuron #(.NUM_INPUT(NUM_INPUT))  hidden_layer(
			.clk(clk),
			.rst(rst),
			.en(en),
			.data_in(data_in),
			.sram_port(hidden_parameters[i]),
			.data_out(sig_hidden_out[i]),
			.rdy(sig_hidden_rdy_flag[i])
		);
	end
endgenerate

generate
	for(j=0;j<NUM_OUT;j++) begin
		ann_out_neuron #(.NUM_INPUT(NUM_HIDDEN)) out_layer(
			.clk(clk),
			.rst(rst),
			.en(sig_hidden_rdy_flag[j]),
			.data_in(reg_pipeline),
			.sram_port(out_parameters[j]),
			.data_out(sig_out_out[j]),
			.rdy(sig_out_rdy_flag[j])
		);
	end
endgenerate

// sequential block for comparing the outputs from the neuron, and predicting
// classification based on the greater number amongst the three 
always_ff @(posedge clk) begin
	if(sig_out_rdy_flag[0] && sig_out_rdy_flag[1] && sig_out_rdy_flag[2])	begin
		if((sig_out_out[0] > sig_out_out[1]) && (sig_out_out[0]>sig_out_out[2])) 	classification <= 1;
		else if((sig_out_out[1] > sig_out_out[0]) && (sig_out_out[1]>sig_out_out[2])) 	classification <= 2;
		else if((sig_out_out[2] > sig_out_out[0]) && (sig_out_out[2]>sig_out_out[1])) 	classification <= 3;
		else									      	classification <= 0;
		spi_ready_flag <= 1;
	end
	else	begin
		classification <= 0;
		spi_ready_flag <= 0;
	end
end

// sequential block for counting the number of positive edges
always_ff @(posedge clk) begin
	if(en)	num_clk_t <= 0;
	else begin
		if(num_clk_t >= 16) num_clk_t <= 0;
		else		    num_clk_t <= num_clk_t + 1;
	end
end

// pipeline register for holding results from hidden layer to be transferred
// to output layer neuron
always_ff @(posedge clk) begin
	for(int i=0; i<NUM_HIDDEN; i++) begin
		if(rst || sig_out_rdy_flag[0])		    	reg_pipeline[i] <= 0;
		else if(num_clk_t == 5) 			reg_pipeline[i] <= sig_hidden_out[i]; 
	end
end

endmodule
