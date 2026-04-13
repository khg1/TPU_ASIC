class activation_test #(parameter int NUM_LANES=16, parameter int ACC_WIDTH=16) extends uvm_test;
	`uvm_component_param_utils(activation_test#(NUM_LANES, ACC_WIDTH))

	activation_env #(NUM_LANES, ACC_WIDTH) env;

	function new(string name = "activation_test", uvm_component parent = null);
		super.new(name, parent);
	endfunction

	function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		env = activation_env#(NUM_LANES, ACC_WIDTH)::type_id::create("env", this);
	endfunction

	function void end_of_elaboration_phase(uvm_phase phase);
		super.end_of_elaboration_phase(phase);
		uvm_top.print_topology();
	endfunction

	task run_phase(uvm_phase phase);
		activation_sequence #(NUM_LANES, ACC_WIDTH) seq;
		seq = activation_sequence#(NUM_LANES, ACC_WIDTH)::type_id::create("seq");
		if(!seq.randomize()) begin
			`uvm_fatal("TEST_ERR", "Failed to randomize sequence")
		end
		phase.raise_objection(this, "Starting Main Sequence");
		#100ns;
		seq.start(env.agt.sqr);
		#200ns;
		phase.drop_objection(this, "Main Sequence Complete");
	endtask

endclass
