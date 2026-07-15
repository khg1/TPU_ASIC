TB_DIR	?= ../tb
TB_FILE ?= tb_systolic.sv
TOP_MODULE ?= tb_systolic

XRUN_FLAGS = -64 -sv -f run.f $(TB_DIR)/$(TB_FILE) -top $(TOP_MODULE) \
	     -access +rwc -timescale 1ns/1ps -gui

run:
	@echo "Running Target: $(TOP_MODULE)"
	xrun -clean $(XRUN_FLAGS)

tb_systolic:
	$(MAKE) run

clean:
	rm -rf *.d *.history *.log *.key *.shm
