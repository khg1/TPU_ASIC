TB_TOP = ../uvm/ACT_UNIT/tb_top.sv
RTL_FILES = ../rtl/activation_unit.sv
IF_FILES = ../uvm/ACT_UNIT/activation_if.sv
PKG_FILES = ../uvm/ACT_UNIT/activation_tb_pkg.sv
SVA_FILES = ../sva/activation_sva.sv

TESTNAME = activation_test

VCS_CMD = vcs -sverilog -full64
UVM_FLAGS = -ntb_opts uvm-1.2
DEBUG_FLAGS = -kdb -debug_access+all
TIMESCALE = -timescale=1ns/1ps

#=========== module-level testbenches (plain SV, no UVM) ===========
SYSTOLIC_RTL = ../rtl/shift_register.sv \
               ../rtl/processing_element.sv \
               ../rtl/systolic_array.sv
VECTOR_RTL   = ../rtl/vector_unit.sv
NPU_RTL      = $(SYSTOLIC_RTL) $(VECTOR_RTL) \
               ../rtl/activation_unit.sv \
               ../rtl/npu_core.sv

.PHONY: all compile run verdi clean tb_systolic tb_vector tb_npu tb_all regress cov_report

all: compile run

tb_systolic:
	@echo "COMPILING tb_systolic"
	$(VCS_CMD) $(DEBUG_FLAGS) $(TIMESCALE) -o simv_systolic \
		$(SYSTOLIC_RTL) ../tb/tb_systolic.sv -l compile_systolic.log
	@echo "RUNNING tb_systolic"
	./simv_systolic -l sim_systolic.log

tb_vector:
	@echo "COMPILING tb_vector_unit"
	$(VCS_CMD) $(DEBUG_FLAGS) $(TIMESCALE) -o simv_vector \
		$(VECTOR_RTL) ../tb/tb_vector_unit.sv -l compile_vector.log
	@echo "RUNNING tb_vector_unit"
	./simv_vector -l sim_vector.log

tb_npu:
	@echo "COMPILING tb_npu_core"
	$(VCS_CMD) $(DEBUG_FLAGS) $(TIMESCALE) -o simv_npu \
		$(NPU_RTL) ../tb/tb_npu_core.sv -l compile_npu.log
	@echo "RUNNING tb_npu_core"
	./simv_npu -l sim_npu.log

tb_all: tb_systolic tb_vector tb_npu

compile:
	@echo "COMPILING WITH VCS"
	$(VCS_CMD) $(UVM_FLAGS) $(DEBUG_FLAGS) $(TIMESCALE) \
		$(RTL_FILES) $(IF_FILES) $(PKG_FILES) $(TB_TOP) \
		$(SVA_FILES) -l compile.log -cm line+cond+fsm+tgl+branch+assert

run:
	@echo "RUNNING SIMULATION"
	./simv +UVM_TESTNAME=$(TESTNAME) +UVM_VERBOSITY=UVM_LOW \
		-l sim.log +fsdb+autoflush -cm line+cond+fsm+tgl+branch+assert

#=========== regression: N random seeds, coverage merged into simv.vdb ===========
NUM_SEEDS ?= 10

regress: compile
	@echo "RUNNING REGRESSION: $(NUM_SEEDS) seeds"
	@for s in $$(seq 1 $(NUM_SEEDS)); do \
		echo "---- seed $$s ----"; \
		./simv +UVM_TESTNAME=$(TESTNAME) +UVM_VERBOSITY=UVM_LOW \
			+ntb_random_seed=$$s -l sim_seed$$s.log \
			-cm line+cond+fsm+tgl+branch+assert -cm_name seed$$s || exit 1; \
		if grep -Eq "UVM_ERROR *: *0" sim_seed$$s.log && grep -Eq "UVM_FATAL *: *0" sim_seed$$s.log; then \
			echo "seed $$s PASS"; \
		else \
			echo "seed $$s FAIL — see sim_seed$$s.log"; exit 1; \
		fi; \
	done
	@echo "ALL $(NUM_SEEDS) SEEDS PASSED"
	$(MAKE) cov_report

cov_report:
	@echo "GENERATING COVERAGE REPORT (urg)"
	urg -dir simv.vdb -report coverage_report -format text
	@echo "Open coverage_report/dashboard.txt for the summary"
	cat coverage_report/dashboard.txt
verdi:
	@echo "OPENING VERDI"
	verdi -dbdir simv.daidir/ -cov -covdir simv.vdb -nologo &

clean:
	rm -rf simv simv.* simv_* *.log *.daidir verdi_config_file *.key *.h csrc novas.* verdiLog vfastLog *.fsdb vdCovLog coverage_report
