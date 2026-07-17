// Second analysis imp so this component can subscribe to BOTH the input stream
// (ap_in, via the built-in uvm_subscriber export) and the output stream (ap_out).
`uvm_analysis_imp_decl(_out)

class activation_coverage #(parameter int NUM_LANES=16, parameter int ACC_WIDTH=16) extends uvm_subscriber #(activation_seq_item#(NUM_LANES, ACC_WIDTH));
	`uvm_component_param_utils(activation_coverage#(NUM_LANES, ACC_WIDTH))

	// ap_in arrives on the built-in uvm_subscriber analysis_export -> write().
	// ap_out arrives here.
	uvm_analysis_imp_out #(activation_seq_item#(NUM_LANES, ACC_WIDTH),
	                       activation_coverage#(NUM_LANES, ACC_WIDTH)) ap_out_imp;

	activation_seq_item #(NUM_LANES, ACC_WIDTH) tr;		// input sample handle
	activation_seq_item #(NUM_LANES, ACC_WIDTH) tr_out;	// output sample handle

	//====================================================================
	// Input coverage — the stimulus that drives the DUT into its corners.
	//
	// NOTE on encodings: tr.data_in[i] is an element select of a *packed*
	// array, so it is UNSIGNED (0..65535). All value bins are therefore
	// written as unsigned two's-complement Q8.8 codes (same convention as
	// the seq_item dist constraint).
	//====================================================================
	covergroup cg_in;
		option.per_instance = 1;

		cp_fn_sel: coverpoint tr.fn_sel {
			bins relu	= {2'b00};
			bins gelu	= {2'b01};
			bins sigmoid	= {2'b10};
		}

		// Full-range partition of the input, isolating the saturation corners.
		cp_in_value: coverpoint tr.data_in[0] {
			bins q_max	= {16'h7FFF};			// +127.996  (Q_MAX)
			bins q_min	= {16'h8000};			// -128.0    (Q_MIN)
			bins zero	= {16'h0000};			//  0.0
			bins small_pos	= {[16'h0001:16'h00FF]};	//  0 <  x <  1   (pure fraction)
			bins small_neg	= {[16'hFF01:16'hFFFF]};	// -1 <  x <  0
			bins mid_pos	= {[16'h0100:16'h7FFE]};	//  1 <= x < +127.996
			bins mid_neg	= {[16'h8001:16'hFF00]};	// -128 < x <= -1
		}

		// Upper byte = integer part = LUT address. These are the interpolation
		// boundary indexes where the neighbour-fetch bug lived:
		//   0x7F (+127) : clamp — no successor entry
		//   0xFF (-1)   : 0xFF -> 0x00 wrap is the correct neighbour (x = 0)
		cp_lut_index: coverpoint tr.data_in[0][15:8] {
			bins idx_pos_max	= {8'h7F};		// clamp boundary (bug site)
			bins idx_neg_one	= {8'hFF};		// wrap boundary  (bug site)
			bins idx_zero		= {8'h00};
			bins idx_neg_max	= {8'h80};		// -128
			bins idx_other_pos	= {[8'h01:8'h7E]};
			bins idx_other_neg	= {[8'h81:8'hFE]};
		}

		// Lower byte = fractional part = interpolation weight.
		cp_frac: coverpoint tr.data_in[0][7:0] {
			bins frac_zero	= {8'h00};		// exact table entry, no interpolation
			bins frac_max	= {8'hFF};		// nearly at the next entry
			bins frac_mid	= {[8'h01:8'hFE]};
		}

		// Every function seen at every value corner (sign + saturation).
		cross_fn_value: cross cp_fn_sel, cp_in_value;

		// Interpolation boundaries only matter for the LUT-based functions;
		// exclude ReLU (which does not use the table) from these crosses.
		cross_fn_index: cross cp_fn_sel, cp_lut_index {
			ignore_bins relu_na = binsof(cp_fn_sel.relu);
		}
		cross_fn_frac: cross cp_fn_sel, cp_frac {
			ignore_bins relu_na = binsof(cp_fn_sel.relu);
		}
	endgroup

	//====================================================================
	// Output coverage — confirms the saturation corners are actually
	// PRODUCED, not just requested. (The output transaction carries no
	// fn_sel, so this cannot cross with the function; sampling output
	// coverage in the scoreboard would be the way to add that.)
	//====================================================================
	covergroup cg_out;
		option.per_instance = 1;

		cp_out_value: coverpoint tr_out.data_out[0] {
			bins q_max_out	= {16'h7FFF};	// clamped/passed high
			bins q_min_out	= {16'h8000};	// clamped low
			bins zero_out	= {16'h0000};	// ReLU of negatives, Sigmoid near 0
			bins other	= default;	// not counted toward the goal
		}
	endgroup

	function new(string name = "activation_coverage", uvm_component parent = null);
		super.new(name, parent);
		cg_in  = new();
		cg_out = new();
		ap_out_imp = new("ap_out_imp", this);
	endfunction

	// Input stream (uvm_subscriber built-in export).
	virtual function void write(activation_seq_item#(NUM_LANES, ACC_WIDTH) t);
		tr = t;
		if(tr.en)	cg_in.sample();
	endfunction

	// Output stream (ap_out).
	virtual function void write_out(activation_seq_item#(NUM_LANES, ACC_WIDTH) t);
		tr_out = t;
		if(tr_out.data_valid)	cg_out.sample();
	endfunction
endclass
