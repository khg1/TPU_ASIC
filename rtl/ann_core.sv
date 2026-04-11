/*
* This module provides cross domain crossing syncronization with SPI domain
* using 2-stage flip flops
*/

`timescale 1ns/1ps;

module ann_core #(parameter INPUT_WIDTH = 32) (
	input  logic 				 clk_1_25G, rst, spi_valid_flag,
	input  logic unsigned [INPUT_WIDTH-1:0]  spi_data_out,
	output logic 	      [INPUT_WIDTH-1:0]  ann_inference_out,
	output logic  				 spi_ready_flag
);

logic reg_flag_q1, reg_flag_q2;    //signals for 2 stage syncronizer
logic reg_flag_q3;		   //for detecting edge
logic detection;
logic [31:0] reg_data;
logic [1:0] sig_ann_out;

assign ann_inference_out = {30'b0, sig_ann_out};
assign detection = !reg_flag_q3 && reg_flag_q2;

// 2-stage flip-flop syncronizer
always_ff @(posedge clk_1_25G or posedge rst) begin
	if(rst) begin
		reg_flag_q1 <= 0;
		reg_flag_q2 <= 0;
		reg_flag_q3 <= 0;
	end
	else begin
		reg_flag_q1 <= spi_valid_flag;
		reg_flag_q2 <= reg_flag_q1;
		reg_flag_q3 <= reg_flag_q2;
	end
end


always_ff @(posedge clk_1_25G or posedge rst) begin
	if(rst) 		reg_data <= 0;
	//else if(detection)	reg_data <= spi_data_out;
	else 			reg_data <= spi_data_out;
end

top_ann TOP_ANN_INST (
	.clk(clk_1_25G), 
	.rst(rst), 
	.data_avail_flag(reg_flag_q2), 
	.data_in('{reg_data[31:24], reg_data[23:16], reg_data[15:8], reg_data[7:0]}), 
	.inference_result(sig_ann_out), .spi_ready_flag(spi_ready_flag)
);

endmodule
