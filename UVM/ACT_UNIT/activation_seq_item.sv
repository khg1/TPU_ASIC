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

// data_in[i] is an element select of a packed array, which the constraint
// solver treats as UNSIGNED (range 0..65535). Signed range bounds therefore
// never match: [-100:100] cannot produce negatives, and [16'h8001:16'h7FFE]
// is empty (32769 > 32766). All ranges below are written as unsigned
// two's-complement encodings, split around the wrap, with :/ so the wide
// ranges share their weight instead of drowning out the corner cases.
constraint c_data_in{
	foreach(data_in[i]){
		data_in[i] dist {
			16'h7FFF := 1,			// +127.996 (Q_MAX)
			16'h8000 := 1,			// -128.0   (Q_MIN)
			16'h0000 := 2,
			[16'h0001:16'h0064] :/ 5,	//   +1 .. +100  (small positive)
			[16'hFF9C:16'hFFFF] :/ 5,	// -100 ..   -1  (small negative)
			[16'h0065:16'h7FFE] :/ 10,	// +101 .. +32766
			[16'h8001:16'hFF9B] :/ 10	// -32767 .. -101
		};
	}
}

function new(string name = "activation_seq_item");
	super.new(name);
endfunction

endclass
