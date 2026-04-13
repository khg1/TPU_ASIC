class activation_env #(parameter int NUM_LANES=16, parameter int ACC_WIDTH=16) extends uvm_env;
	`uvm_component_param_utils(activation_env#(NUM_LANES, ACC_WIDTH))

	activation_agent	#(NUM_LANES, ACC_WIDTH) agt;
	activation_scoreboard	#(NUM_LANES, ACC_WIDTH) scb;
	activation_subscriber	#(NUM_LANES, ACC_WIDTH)	cov;

	function new (string name = "activation_env", uvm_component parent = null);
		super.new(name, parent);
	endfunction

	function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		agt = activation_agent#(NUM_LANES, ACC_WIDTH)::type_id::create("agt", this);
		scb = activation_scoreboard#(NUM_LANES, ACC_WIDTH)::type_id::create("scb", this);
		cov = activation_subscriber#(NUM_LANES, ACC_WIDTH)::type_id::create("cov", this);
	endfunction

	function void connect_phase(uvm_phase phase);
		super.connect_phase(phase);
		agt.mon.ap_in.connect(scb.exp_fifo.analysis_export);
		agt.mon.ap_in.connect(cov.analysis_export);
		agt.mon.ap_out.connect(scb.act_fifo.analysis_export);
	endfunction
endclass
