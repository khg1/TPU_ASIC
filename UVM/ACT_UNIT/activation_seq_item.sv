class activation_seq_item #(parameter NUM_LANES=16, ACC_WIDTH=16)
	extends uvm_sequence_item;
rand	logic	en;
rand	logic	[1:0]	fn_sel;
rand	logic	signed	[NUM_LANES-1:0][ACC_WIDTH-1:0]	data_in;

logic	signed	[NUM_LANES-1:0][ACC_WIDTH-1:0]	data_out;
logic						data_valid;

`uvm_object_param_utils(activation_seq_item#(NUM_LANES, ACC_WIDTH))

constraint c_fn_sel {
	fn_sel	inside {2'b00, 2'b01, 2'b10};
}

constraint c_data_in{
	foreach(data_in[i]){
		data_in[i] dist {
			16'h7FFF := 1,
			16'h8000 := 1,
			16'h0000 := 2,
			[-100:100] := 5,
			[16'h8001:16'h7FFE] := 10
		};
	}
}

function new(string name = "activation_seq_item");
	super.new(name);
endfunction

endclass
