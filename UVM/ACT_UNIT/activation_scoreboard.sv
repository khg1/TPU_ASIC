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
					// signed'(): element select of a packed array is unsigned,
					// so the bare compare against 0 would never be true
					expected_out[i] = (signed'(exp_tr.data_in[i]) < 0) ? 0 : exp_tr.data_in[i];
				end
				else begin
					logic	[(ACC_WIDTH/2)-1:0]		index = exp_tr.data_in[i][15:8];
					logic	[(ACC_WIDTH/2)-1:0]		frac  = exp_tr.data_in[i][7:0];
					logic	[(ACC_WIDTH/2)-1:0]		index_next;
					logic	signed	[ACC_WIDTH-1:0]		lut_val, lut_next;
					logic	signed	[(2*ACC_WIDTH)-1:0]	delta, corrected;

					// Matches the RTL: clamp at x = +127 (0x7F); the 8-bit wrap
					// 0xFF -> 0x00 is the correct neighbour (x = -1 -> x = 0).
					index_next = (index == 8'h7F) ? 8'h7F : (index + 8'd1);

					if(exp_tr.fn_sel == 2'b01) begin
						lut_val = ref_lut_gelu[index];
						lut_next = ref_lut_gelu[index_next];
					end
					else begin
						lut_val = ref_lut_sigmoid[index];
						lut_next = ref_lut_sigmoid[index_next];
					end

					delta = (2*ACC_WIDTH)'(lut_next) - (2*ACC_WIDTH)'(lut_val);
					corrected = (2*ACC_WIDTH)'(lut_val) + ((delta * (2*ACC_WIDTH)'(signed'({1'b0, frac}))) >>> 8);

					if(corrected > 32'sh00007FFF) expected_out[i] = 16'h7FFF;
					else if(corrected < 32'shFFFF8000) expected_out[i] = 16'h8000;
					else				expected_out[i] = 16'(corrected);
				end
				if(expected_out[i] !== act_tr.data_out[i]) begin
					`uvm_error("SCB_FAIL", $sformatf("Mismatch Lane %0d: Expected=%0h, Actual=%0h", i, expected_out[i], act_tr.data_out[i]))
				end
			end
		end
	endtask
endclass
