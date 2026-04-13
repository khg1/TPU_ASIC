class acitvation_monitor #(parameter int NUM_LANES=16, parameter int ACC_WIDTH=16) extends uvm_monitor;
	`uvm_component_param_utils(activation_monitor#(NUM_LANES, ACC_WIDTH))

	virtual activation_if #(NUM_LANES, ACC_WIDTH) vif;

	uvm_analysis_port #(activation_seq_item#(NUM_LANES, ACC_WIDTH)) ap_in;
	uvm_analysis_port #(activation_seq_item#(NUM_LANES, ACC_WIDTH)) ap_out;

	function new(string name = "activation_monitor", uvm_component parent = null);
		super.new(name, parent);
		ap_in = new("ap_in", this);
		ap_out = new("ap_out", this);
	endfunction

	function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		if(!uvm_config_db#(virtual activation_if#(NUM_LANES, ACC_WIDTH))::get(this, "", "vif", vif)) begin
			`uvm_fatal("NO_VIF", {"virtual interface must be set for: ",  get_full_name(), ".vif"});
		end
	endfunction

	task run_phase(uvm_phase phase);
		wait(vif.resetn == 1);
		fork
			monitor_inputs();
			monitor_outputs();
		join_none
	endtask

	virtual task monitor_inputs();
		activation_seq_item #(NUM_LANES, ACC_WIDTH) tr_in;
		forever begin
			@(vif.cb_monitor);
			if(vif.cb_monitor.en) begin
				tr_in = activation_seq_item#(NUM_LANES, ACC_WIDTH)::type_id::create("tr_in");
				tr_in.en	=	vif.cb_monitor.en;
				tr_in.fn_sel	=	vif.cb_monitor.fn_sel;
				tr_in.data_in	=	vif.cb_monitor.data_in;

				ap_in.write(tr_in);
			end
		end	
	endtask

	virtual task monitor_outputs();
		activation_seq_item #(NUM_LANES, ACC_WIDTH) tr_out;
		forever begin
			@(vif.cb_monitor);
			if(vif.cb_monitor.data_valid) begin
				tr_out = activation_seq_item#(NUM_LANES, ACC_WIDTH)::type_id::create("tr_out");
				tr_out.data_valid = vif.cb_monitor.data_valid;
				tr_out.data_out	= vif.cb_monitor.data_out;
				ap_out.write(tr_out);
			end
		end
	endtask

endclass
