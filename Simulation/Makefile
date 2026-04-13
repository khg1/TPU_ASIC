TB_TOP = ../UVM/ACT_UNIT/tb_top.sv
RTL_FILES = ../rtl/compute/activation_unit.sv
IF_FILES = ../UVM/ACT_UNIT/activation_if.sv
PKG_FILES = ../UVM/ACT_UNIT/activation_tb_pkg.sv
SVA_FILES = ../SVA/activation_sva.sv

TESTNAME = activation_test

VCS_CMD = vcs -sverilog -full64
UVM_FLAGS = -ntb_opts uvm-1.2
DEBUG_FLAGS = -kdb -debug_access+all
TIMESCALE = -timescale=1ns/1ps

.PHONY: all compile run verdi clean

all: compile run

compile:
	@echo "COMPILING WITH VCS"
	$(VCS_CMD) $(UVM_FLAGS) $(DEBUG_FLAGS) $(TIMESCALE) \
		$(RTL_FILES) $(IF_FILES) $(PKG_FILES) $(TB_TOP) \
		$(SVA_FILES) -l compile.log -cm line+cond+fsm+tgl+branch+assert

run:
	@echo "RUNNING SIMULATION"
	./simv +UVM_TESTNAME=$(TESTNAME) +UVM_VERBOSITY=UVM_LOW \
		-l sim.log +fsdb+autoflush -cm line+cond+fsm+tgl+branch+assert

verdi:
	@echo "OPENING VERDI"
	verdi -dbdir simv.daidir/ -cov -covdir simv.vdb -nologo &

clean:
	rm -rf simv simv.* *.log *.daidir verdi_config_file *.key *.h csrc novas.* verdiLog vfastLog *.fsdb vdCovLog
