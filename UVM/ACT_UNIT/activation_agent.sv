class activation_agent #(parameter int NUM_LANES=16, parameter int ACC_WIDTH=16) extends uvm_agent;
	`uvm_component_param_utils(activation_agent#(NUM_LANES, ACC_WIDTH))

	activation_driver #(NUM_LANES, ACC_WIDTH) drv;
	activation_monitor #(NUM_LANES, ACC_WIDTH) mon;

	uvm_sequencer #(activation_seq_item#(NUM_LANES, ACC_WIDTH)) sqr;

	function new(string name = "activation_agent", uvm_component parent = null);
		super.new(name, parent);
	endfunction

	function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		mon = activation_monitor#(NUM_LANES, ACC_WIDTH)::type_id::create("mon", this);
		if(get_is_active() == UVM_ACTIVE) begin
			drv = activation_driver#(NUM_LANES, ACC_WIDTH)::type_id::create("drv", this);
			sqr = uvm_sequencer#(activation_seq_item#(NUM_LANES, ACC_WIDTH))::type_id::create("sqr", this);
		end
	endfunction

	function void connect_phase(uvm_phase phase);
		super.connect_phase(phase);
		if(get_is_active() == UVM_ACTIVE) begin
			drv.seq_item_port.connect(sqr.seq_item_export);
		end
	endfunction

endclass
