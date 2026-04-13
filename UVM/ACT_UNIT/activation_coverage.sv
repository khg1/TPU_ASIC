class activation_coverage #(parameter int NUM_LANES=16, parameter int ACC_WIDTH=16) extends uvm_subscriber #(activation_seq_item#(NUM_LANES, ACC_WIDTH));
	`uvm_component_param_utils(activation_coverage#(NUM_LANES, ACC_WIDTH))
	
	activation_seq_item #(NUM_LANES, ACC_WIDTH) tr;

	covergroup cg_activation;
		option.per_instance = 1;

		cp_fn_sel: coverpoint tr.fn_sel {
			bins	relu	=	{2'b00};
			bins	gelu	=	{2'b01};
			bins	sigmoid =	{2'b10};
		}
		cp_data_sign: coverpoint tr.data_in[0] {
			bins	positive	=	{[16'h0001:16'h7FFF]};
			bins	zero		=	{0};
			bins	negative	=	{[16'h8000:16'hFFFF]};
		}
		cross_fn_data: cross	cp_fn_sel, cp_data_sign;
	endgroup

	function new(string name = "activation_coverage", uvm_component parent = null);
		super.new(name, parent);
		cg_activation = new();
	endfunction

	virtual function void write(activation_seq_item#(NUM_LANES, ACC_WIDTH) t);
		tr = t;
		if(tr.en)	cg_activation.sample();	
	endfunction
endclass
