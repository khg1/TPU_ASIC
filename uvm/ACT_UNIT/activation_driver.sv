class activation_driver #(parameter int NUM_LANES=16, parameter int ACC_WIDTH=16) extends uvm_driver #(activation_seq_item#(NUM_LANES,ACC_WIDTH));
	`uvm_component_param_utils(activation_driver#(NUM_LANES, ACC_WIDTH))

	virtual activation_if #(NUM_LANES, ACC_WIDTH) vif;

	function new(string name = "activation_driver", uvm_component parent);
		super.new(name, parent);
	endfunction

	function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		if(!uvm_config_db#(virtual activation_if#(NUM_LANES,ACC_WIDTH))::get(this, "", "vif", vif)) begin
			`uvm_fatal("NO_VIF", {"virtual interface must be set for: ", get_full_name(), ".vif"});
		end
	endfunction

	task run_phase(uvm_phase phase);
		vif.cb_driver.en	<= 0;
		vif.cb_driver.fn_sel	<= '0;
		for(int i=0; i<NUM_LANES; i++) begin
			vif.cb_driver.data_in[i] <= '0;
		end

		wait(vif.resetn == 1);
		
		forever begin
			seq_item_port.get_next_item(req);
			@(vif.cb_driver);
			vif.cb_driver.en	<= req.en;
			vif.cb_driver.fn_sel	<= req.fn_sel;
			vif.cb_driver.data_in	<= req.data_in;

			seq_item_port.item_done();

			if (seq_item_port.has_do_available() == 0) begin
				@(vif.cb_driver);
				vif.cb_driver.en <= 0;
			end
		end
	endtask
endclass
