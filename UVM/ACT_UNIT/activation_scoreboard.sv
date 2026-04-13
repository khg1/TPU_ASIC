class activation_scoreboard #(parameter int NUM_LANES=16, parameter int ACC_WIDTH=16) extends uvm_scoreboard;
	`uvm_component_param_utils(activation_scoreboard#(NUM_LANES, ACC_WIDTH))

	uvm_tlm_analysis_fifo #(activation_seq_item#(NUM_LANES, ACC_WIDTH)) exp_fifo;
	uvm_tlm_analysis_fifo #(activation_seq_item#(NUM_LANES, ACC_WIDTH)) act_fifo;

	logic	signed	[ACC_WIDTH-1:0]	ref_lut_gelu	[0:255];
	logic	signed	[ACC_WIDTH-1:0]	ref_lut_sigmoid	[0:255];

	function new(string name = "activation_scoreboard", uvm_component parent = null);
		super.new(name, parent);
		exp_fifo = new("exp_fifo", this);
		act_fifo = new("act_fifo", this);
	endfunction

	function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		$readmemh("../LUT/lut/gelu_q88.hex", ref_lut_gelu);
		$readmemh("../LUT/lut/sigmoid_q88.hex", ref_lut_sigmoid);
	endfunction

	task run_phase(uvm_phase phase);
		activation_seq_item#(NUM_LANES, ACC_WIDTH)	exp_tr, act_tr;
		logic	signed	[NUM_LANES-1:0][ACC_WIDTH-1:0]	expected_out;

		forever begin
			exp_fifo.get(exp_tr);
			act_fifo.get(act_tr);

			foreach(expected_out[i]) begin
				if(exp_tr.fn_sel == 2'b00) begin
					expected_out[i] = (exp_tr.data_in[i] < 0) ? 0 : exp_tr.data_in[i];
				end
				else begin
					logic	[(ACC_WIDTH/2)-1:0]		index = exp_tr.data_in[i][15:8];
					logic	[(ACC_WIDTH/2)-1:0]		frac  = exp_tr.data_in[i][7:0];
					logic	signed	[ACC_WIDTH-1:0]		lut_val, lut_next;
					logic	signed	[(2*ACC_WIDTH)-1:0]	delta, corrected;

					if(exp_tr.fn_sel == 2'b01) begin
						lut_val = ref_lut_gelu[index];
						lut_next = (index == 8'hFF) ? ref_lut_gelu[255] : ref_lut_gelu[index+1];
					end
					else begin
						lut_val = ref_lut_sigmoid[index];
						lut_next = (index == 8'hFF) ? ref_lut_sigmoid[255] : ref_lut_sigmoid[index+1];
					end
					
					delta = 32'(lut_next) - 32'(lut_val);
					corrected = 32'(lut_val) + ((delta * 32'(frac)) >>> 8);

					if(corrected > 32'h7FFF) expected_out[i] = 16'h7FFF;
					else if(corrected < 32'hFFFF8000) expected_out[i] = 16'h8000;
					else				expected_out[i] = 16'(corrected);
				end
				if(expected_out[i] !== act_tr.data_out[i]) begin
					`uvm_error("SCB_FAIL", $sformatf("Mismatch Lane %0d: Expected=%0h, Actual=%0h", i, expected_out[i], act_tr.data_out[i]))
				end
			end
		end
	endtask
endclass
