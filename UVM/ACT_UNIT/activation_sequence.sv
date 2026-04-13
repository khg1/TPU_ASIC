class activation_sequence #(parameter int NUM_LANES=16, parameter int ACC_WIDTH=16) extends uvm_sequence #(activation_seq_item#(NUM_LANES, ACC_WIDTH));
	`uvm_object_param_utils(activation_sequence#(NUM_LANES, ACC_WIDTH))

	rand int num_transactions;

	constraint c_num {
		num_transactions inside {[50:150]};
	}

	function new(string name = "activation_sequence");
		super.new(name);
	endfunction

	virtual task body();
		activation_seq_item #(NUM_LANES, ACC_WIDTH) req;
		`uvm_info("SEQ_START", $sformatf("Starting sequence with %0d transactions", num_transactions), UVM_LOW)

		for(int i=0; i<num_transactions;i++) begin
			req = activation_seq_item#(NUM_LANES, ACC_WIDTH)::type_id::create("req", this);
			
			start_item(req);
			if(!req.randomize() with {en == 1}) begin
				`uvm_error("SEQ_ERR", "Randomization failed!")
			end
			finish_item(req);
		end
		`uvm_info("SEQ_DONE", "Finished sending all transactions", UVM_LOW)
	endtask
endclass
