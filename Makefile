# VCS Makefile with struct support for FSDB waveforms and coverage
SHELL = /bin/bash

# Tool paths - UPDATE THESE FOR YOUR SYSTEM
VCS = vcs
VERDI_HOME ?= /opt/synopsys/verdi/Verdi_O-2018.09-SP2

# Enhanced VCS options for struct visibility - For Verdi 2024.09+
VCS_OPTS = -full64 -sverilog +v2k \
           -debug_acc+all+dmptf \
           +define+FSDB_DUMP \
           +structs=all \
           +memcbk \
           +vpi \
           -kdb \
           -debug_region+cell+encrypt \
           +incdir+.

# Coverage options
COVERAGE_OPTS = \
    -cm line+cond+fsm+tgl+branch+assert \
    -cm_name $(TOP)_cov \
    -cm_dir ./coverage_data \
    -cm_log ./coverage_data/cm.log
# SpyGlass paths and options
SPYGLASS = sg_shell
#SPYGLASS = spyglass #this is the gui
SPYGLASS_PROJECT = spyglass.prj
SPYGLASS_LOG = spyglass.log
SPYGLASS_WORK = spyglass_work

# SpyGlass lint goal (can be changed to power, cdc, etc.)
SPYGLASS_GOAL = lint/lint_rtl

# Test-specific coverage options (can be overridden)
CM_TESTNAME ?= test_default
CM_OPTIONS = +testname+$(CM_TESTNAME)

# Testbench parameters (override: make compile NUM_POLY=8 WAIT_MIN=0 WAIT_MAX=5 NUM_BUTFLY_PER_STAGE=4)
NUM_POLY ?= 2
WAIT_MIN ?= 0
WAIT_MAX ?= 3
NUM_BUTFLY_PER_STAGE ?= 1
TB_DEFINES = +define+NUM_POLY=$(NUM_POLY) +define+WAIT_MIN=$(WAIT_MIN) +define+WAIT_MAX=$(WAIT_MAX) \
             +define+NUM_BUTFLY_PER_STAGE=$(NUM_BUTFLY_PER_STAGE)

# RTL sources (SpyGlass lint). Packages and leaf modules first; basemul before poly_mul.
RTL_FILES = \
    ntt_pkg.sv \
    modulus_funcs.sv \
    mod_mul.sv \
    w_calc.sv \
    w_gen.sv \
    butterfly.sv \
    ntt_stage.sv \
    forward_ntt.sv \
    inverse_ntt.sv \
    basemul.sv \
    poly_mul.sv \
    phi_calc.sv \
    phi_gen.sv

# Testbenches (not linted as top-level RTL)
TB_FILES = \
    nttg_tb.sv \
    tb_poly_mul.sv \
    tb_poly_mul_rand.sv \
    tb_fwd_ntt.sv

# Simulation sources (RTL + testbenches)
FILES = $(RTL_FILES) $(TB_FILES)

TOP ?= tb_poly_mul
SPYGLASS_TOP ?= poly_mul
SIMV = simv
FSDB = waveform.fsdb
COMPILE_LOG = compile.log
SIM_LOG = simulation.log
COV_DIR = coverage_data
COV_REPORT_DIR = coverage_report

# Default: poly_mul randomized testbench with reference comparison
all: poly_mul_rand

# poly_mul workflow (stimulus-only TB, no reference check)
poly_mul: compile run
poly_mul_compile: compile
poly_mul_run: run
poly_mul_verdi: verdi
poly_mul_verdi_coverage: verdi_coverage
poly_mul_coverage_report: coverage_report
poly_mul_coverage_summary: coverage_summary
poly_mul_coverage_detail: coverage_detail
poly_mul_merge_coverage: merge_coverage
poly_mul_run_test: run_test
poly_mul_debug: debug
poly_mul_run_debug: run_debug
poly_mul_clean: clean
poly_mul_clean_coverage: clean_coverage

poly_mul_rand_clean_coverage: clean_coverage

# poly_mul randomized testbench with reference comparison
poly_mul_rand: TOP = tb_poly_mul_rand
poly_mul_rand: compile run
poly_mul_rand_compile: TOP = tb_poly_mul_rand
poly_mul_rand_compile: compile
poly_mul_rand_run: TOP = tb_poly_mul_rand
poly_mul_rand_run: run
poly_mul_rand_verdi: TOP = tb_poly_mul_rand
poly_mul_rand_verdi: verdi
poly_mul_rand_verdi_rc: TOP = tb_poly_mul_rand
poly_mul_rand_verdi_rc:
	@echo "Opening Verdi with poly_mul_rand wave session..."
	@if [ -f "$(FSDB)" ]; then \
	    verdi -ssf $(FSDB) -nrc signal_poly_mul_rand.rc & \
	else \
	    echo "Error: $(FSDB) not found. Run 'make poly_mul_rand_run' first."; \
	    exit 1; \
	fi

# Sanity: basemul pairs coefficients across beats (NUM_BUTFLY_PER_STAGE == 1 only).
SANITY_NUM_POLY = 6
SANITY_WAIT_MIN = 0
SANITY_WAIT_MAX = 3
SANITY_BUTFLIES = 1

sanity:
	@echo "=========================================="
	@echo "Sanity: poly_mul_rand (NUM_BUTFLY_PER_STAGE=$(SANITY_BUTFLIES) only; basemul is serial)"
	@echo "  NUM_POLY=$(SANITY_NUM_POLY) WAIT_MIN=$(SANITY_WAIT_MIN) WAIT_MAX=$(SANITY_WAIT_MAX)"
	@echo "=========================================="
	@fail=0; \
	for nbf in $(SANITY_BUTFLIES); do \
	    echo ""; \
	    echo "------------------------------------------"; \
	    echo "Sanity config: NUM_BUTFLY_PER_STAGE=$$nbf"; \
	    echo "------------------------------------------"; \
	    $(MAKE) --no-print-directory clean >/dev/null; \
	    if $(MAKE) --no-print-directory poly_mul_rand \
	            TOP=tb_poly_mul_rand \
	            NUM_BUTFLY_PER_STAGE=$$nbf \
	            NUM_POLY=$(SANITY_NUM_POLY) \
	            WAIT_MIN=$(SANITY_WAIT_MIN) \
	            WAIT_MAX=$(SANITY_WAIT_MAX) \
	            CM_TESTNAME=sanity_nbf_$$nbf; then \
	        if grep -qE 'Summary: [0-9]+ passed, 0 failed' $(SIM_LOG) 2>/dev/null \
	           && grep -q 'polynomial multiply results match reference' $(SIM_LOG) 2>/dev/null; then \
	            echo "PASS: NUM_BUTFLY_PER_STAGE=$$nbf"; \
	        else \
	            echo "FAIL: NUM_BUTFLY_PER_STAGE=$$nbf (see $(SIM_LOG))"; \
	            fail=1; \
	        fi; \
	    else \
	        echo "FAIL: NUM_BUTFLY_PER_STAGE=$$nbf (compile/run error)"; \
	        fail=1; \
	    fi; \
	done; \
	echo ""; \
	echo "=========================================="; \
	if [ $$fail -eq 0 ]; then \
	    echo "SANITY RESULT: PASS (all NUM_BUTFLY_PER_STAGE configs)"; \
	else \
	    echo "SANITY RESULT: FAIL"; \
	    exit 1; \
	fi; \
	echo "=========================================="

# forward_ntt testbench (legacy)
fwd_ntt: TOP = tb_fwd_ntt
fwd_ntt: compile run
fwd_ntt_compile: TOP = tb_fwd_ntt
fwd_ntt_compile: compile
fwd_ntt_run: TOP = tb_fwd_ntt
fwd_ntt_run: run
fwd_ntt_verdi: TOP = tb_fwd_ntt
fwd_ntt_verdi: verdi
fwd_ntt_verdi_coverage: TOP = tb_fwd_ntt
fwd_ntt_verdi_coverage: verdi_coverage
fwd_ntt_coverage_report: TOP = tb_fwd_ntt
fwd_ntt_coverage_report: coverage_report
fwd_ntt_debug: TOP = tb_fwd_ntt
fwd_ntt_debug: debug
fwd_ntt_run_debug: TOP = tb_fwd_ntt
fwd_ntt_run_debug: run_debug

FILELIST = filelist.f
RTL_FILELIST = rtl.f

# Regenerate file lists from Makefile variables (keeps -f lists in sync).
$(FILELIST): Makefile
	@echo "// Auto-generated — do not edit; run 'make filelist'" > $(FILELIST)
	@for f in $(RTL_FILES) $(TB_FILES); do \
	    test -f "$$f" || { echo "ERROR: missing source $$f" >&2; exit 1; }; \
	    echo "$$f" >> $(FILELIST); \
	done

$(RTL_FILELIST): Makefile
	@echo "// Auto-generated RTL list — do not edit; run 'make filelist'" > $(RTL_FILELIST)
	@for f in $(RTL_FILES); do \
	    test -f "$$f" || { echo "ERROR: missing source $$f" >&2; exit 1; }; \
	    echo "$$f" >> $(RTL_FILELIST); \
	done

filelist: $(FILELIST) $(RTL_FILELIST)
	@echo "Wrote $(FILELIST) and $(RTL_FILELIST)"

# >>>>>>>>>>>>>>>>>>>>>>> DEBUG PROBE - delete this block >>>>>>>>>>>>>>>>>>>>>>>
# make poly_mul DEBUG_PROBE=1  -> compiles ntt_debug_probe.sv and writes
# ntt_debug_trace.txt, which check_ntt_stages.py reads. Off by default.
DEBUG_PROBE ?= 0

ifeq ($(DEBUG_PROBE),1)
TB_FILES   += ntt_debug_probe.sv
TB_DEFINES += +define+NTT_DEBUG_PROBE
endif

check_stages:
	python3 check_ntt_stages.py -t ntt_debug_trace.txt

debug_probe: clean
	$(MAKE) --no-print-directory poly_mul DEBUG_PROBE=1
	python3 check_ntt_stages.py -t ntt_debug_trace.txt
# <<<<<<<<<<<<<<<<<<<<<<< DEBUG PROBE - delete this block <<<<<<<<<<<<<<<<<<<<<<<

# Compilation target with coverage
compile: $(FILELIST)
	@echo "=========================================="
	@echo "Compiling with enhanced struct support..."
	@echo "=========================================="
	@echo "Using -debug_acc method for Verdi 2024.09+ compatibility"
	@echo "Top module: $(TOP)"
	@echo "File list:  $(FILELIST) (includes basemul.sv)"
	@echo "TB params: NUM_POLY=$(NUM_POLY) WAIT_MIN=$(WAIT_MIN) WAIT_MAX=$(WAIT_MAX) NUM_BUTFLY_PER_STAGE=$(NUM_BUTFLY_PER_STAGE)"
	@grep -q '^basemul\.sv$$' $(FILELIST) || { echo "ERROR: basemul.sv missing from $(FILELIST)"; exit 1; }
	mkdir -p $(COV_DIR)
	$(VCS) $(VCS_OPTS) $(TB_DEFINES) $(COVERAGE_OPTS) \
	    -f $(FILELIST) \
	    -top $(TOP) \
	    -l $(COMPILE_LOG) \
	    -o $(SIMV)
	@echo ""
	@echo "Compilation complete. Check $(COMPILE_LOG) for details."
	@echo "Binary created: $(SIMV)"
	@echo "Coverage directory: $(COV_DIR)"

# Simulation target with coverage
run:
	@echo "=========================================="
	@echo "Running simulation with FSDB dumping and coverage..."
	@echo "=========================================="
	@echo "Top module: $(TOP)"
	@echo "Test name: $(CM_TESTNAME)"
	./$(SIMV) +fsdb+autoflush +fsdb+struct=on +fsdb+mda=on \
	    -cm line+cond+fsm+tgl+branch+assert \
	    $(CM_OPTIONS) \
	    -l $(SIM_LOG)
	@echo ""
	@echo "Simulation complete."
	@echo "FSDB file: $(FSDB)"
	@echo "Log file: $(SIM_LOG)"
	@echo "Coverage data: $(COV_DIR)"
	@if [ -f "$(FSDB)" ]; then \
	    echo "FSDB file size:" $$(du -h "$(FSDB)" | cut -f1); \
	else \
	    echo "Warning: FSDB file not created!"; \
	fi

# Run specific test with coverage
run_test:
	@echo "=========================================="
	@echo "Running test: $(CM_TESTNAME) with coverage..."
	@echo "=========================================="
	@if [ -f "$(SIMV)" ]; then \
	    ./$(SIMV) +fsdb+autoflush +fsdb+struct=on +fsdb+mda=on \
	        -cm line+cond+fsm+tgl+branch+assert \
	        +testname+$(CM_TESTNAME) \
	        -l sim_$(CM_TESTNAME).log; \
	    echo "Test $(CM_TESTNAME) completed."; \
	    echo "Coverage data saved in $(COV_DIR)"; \
	else \
	    echo "Error: $(SIMV) not found. Run 'make compile' first."; \
	fi

# Generate HTML coverage report
coverage_report:
	@echo "=========================================="
	@echo "Generating HTML coverage report..."
	@echo "=========================================="
	@if [ -d "$(COV_DIR)" ]; then \
	    echo "Using coverage data from: $(COV_DIR)"; \
	    urg -dir $(COV_DIR) \
	        -format both \
	        -report $(COV_REPORT_DIR); \
	    echo ""; \
	    echo "Coverage report generated:"; \
	    echo "  HTML: $(COV_REPORT_DIR)/hierarchy.html"; \
	    echo "  Text: $(COV_REPORT_DIR)/report.txt"; \
	    echo ""; \
	    echo "To view HTML report:"; \
	    echo "  firefox $(COV_REPORT_DIR)/hierarchy.html &"; \
	    echo "  or"; \
	    echo "  google-chrome $(COV_REPORT_DIR)/hierarchy.html &"; \
	else \
	    echo "Error: $(COV_DIR) not found. Run 'make run' first."; \
	fi

# Quick coverage summary
coverage_summary:
	@echo "=========================================="
	@echo "Coverage Summary"
	@echo "=========================================="
	@if [ -d "$(COV_DIR)" ]; then \
	    urg -dir $(COV_DIR) -format text; \
	else \
	    echo "No coverage data found. Run 'make run' first."; \
	fi

# Generate detailed coverage metrics
coverage_detail:
	@echo "=========================================="
	@echo "Detailed Coverage Metrics"
	@echo "=========================================="
	@if [ -d "$(COV_DIR)" ]; then \
	    urg -dir $(COV_DIR) \
	        -format text \
	        -metric line+cond+fsm+tgl+branch+assert; \
	else \
	    echo "No coverage data found. Run 'make run' first."; \
	fi

# Merge multiple test coverage runs
merge_coverage:
	@echo "=========================================="
	@echo "Merging coverage from multiple tests..."
	@echo "=========================================="
	@if [ -d "$(COV_DIR)" ]; then \
	    urg -dir $(COV_DIR)/*.vdb \
	        -format both \
	        -report $(COV_REPORT_DIR)/merged \
	        -log $(COV_DIR)/urg_merge.log; \
	    echo "Coverage merge complete."; \
	    echo "Reports in: $(COV_REPORT_DIR)/merged"; \
	else \
	    echo "Error: $(COV_DIR) not found. Run some tests first."; \
	fi

# Open Verdi to view waveforms
verdi:
	@echo "Opening Verdi with waveform..."
	@if [ -f "$(FSDB)" ]; then \
	    verdi -ssf $(FSDB) & \
	else \
	    echo "Error: $(FSDB) not found. Run 'make run' first."; \
	    exit 1; \
	fi

# Open Verdi with coverage
verdi_coverage:
	@echo "Opening Verdi with coverage data..."
	@if [ -d "$(COV_DIR)" ]; then \
	    verdi -cov -covdir $(COV_DIR) & \
	else \
	    echo "Error: $(COV_DIR) not found. Run 'make run' first."; \
	    exit 1; \
	fi
spyglass_prj:
	@echo "Creating SpyGlass project file (RTL only, top=$(SPYGLASS_TOP))..."
	@echo "set_option top $(SPYGLASS_TOP)" > $(SPYGLASS_PROJECT)
	@echo "set_option language_mode sverilog" >> $(SPYGLASS_PROJECT)
	@echo "set_option enableSV yes" >> $(SPYGLASS_PROJECT)
	@echo "set_option enableSV09 yes" >> $(SPYGLASS_PROJECT)
	@echo "set_option incdir rtl" >> $(SPYGLASS_PROJECT)
	@echo "set_option work_dir $(SPYGLASS_WORK)" >> $(SPYGLASS_PROJECT)

	@for f in $(RTL_FILES); do \
	    echo "read_file -type verilog $$f" >> $(SPYGLASS_PROJECT); \
	done




lint: spyglass_prj
	@echo "=========================================="
	@echo "Running SpyGlass goal: $(SPYGLASS_GOAL) (report-only)..."
	@echo "=========================================="
	SPYGLASS_GOAL=$(SPYGLASS_GOAL) sg_shell -tcl run_lint.tcl
	@echo ""
	@echo "SpyGlass lint completed."






# Debug compile with maximum options and coverage
debug: clean $(FILELIST)
	@echo "=========================================="
	@echo "Compiling with MAXIMUM debug options and coverage..."
	@echo "=========================================="
	mkdir -p $(COV_DIR)
	$(VCS) $(VCS_OPTS) $(TB_DEFINES) $(COVERAGE_OPTS) \
	    +vcs+flush+all \
	    +vcs+flush+log \
	    +define+DEBUG_ENABLED \
	    -f $(FILELIST) \
	    -top $(TOP) \
	    -l compile_debug.log \
	    -o simv_debug
	@echo "Debug compilation complete."

# Run debug simulation with coverage
run_debug:
	@if [ -f "simv_debug" ]; then \
	    echo "Running debug simulation with coverage..."; \
	    ./simv_debug +fsdb+autoflush +fsdb+struct=on +fsdb+mda=on \
	        -cm line+cond+fsm+tgl+branch+assert \
	        -l sim_debug.log; \
	    echo "Coverage data saved in $(COV_DIR)"; \
	else \
	    echo "Error: simv_debug not found. Run 'make debug' first."; \
	fi

# Clean up generated files
clean:
	@echo "Cleaning generated files..."
	rm -rf \
	    $(SIMV) simv_debug \
	    simv.daidir \
	    csrc \
	    *.log \
	    *.fsdb \
	    *.vpd \
	    ucli.key \
	    DVEfiles \
	    novas.* \
	    verdiLog \
	    .__* \
	    __.* \
	    *.key \
	    *~ \
	    core.* \
	    $(COV_DIR) \
	    $(COV_REPORT_DIR) \
	    merged_coverage \
	    ntt_debug_trace.txt \
	    $(SPYGLASS_WORK) $(SPYGLASS_PROJECT) $(SPYGLASS_LOG)
	@echo "Clean complete."

# Clean only coverage data
clean_coverage:
	@echo "Cleaning coverage data..."
	rm -rf $(COV_DIR) $(COV_REPORT_DIR) merged_coverage
	@echo "Coverage clean complete."

# Test coverage example
test_coverage_example:
	@echo "=========================================="
	@echo "Running coverage example sequence..."
	@echo "=========================================="
	@echo "1. Clean previous runs..."
	@$(MAKE) clean_coverage > /dev/null 2>&1
	@echo "2. Compile with coverage..."
	@$(MAKE) compile > /dev/null 2>&1
	@echo "3. Run test1..."
	@CM_TESTNAME=test1 $(MAKE) run_test > /dev/null 2>&1
	@echo "4. Run test2..."
	@CM_TESTNAME=test2 $(MAKE) run_test > /dev/null 2>&1
	@echo "5. Generate coverage report..."
	@$(MAKE) coverage_report
	@echo "6. Show coverage summary..."
	@echo ""
	@$(MAKE) coverage_summary
	@echo ""
	@echo "Example complete! Open $(COV_REPORT_DIR)/hierarchy.html in browser."

# List all source files
list:
	@echo "Source files to be compiled:"
	@for file in $(FILES); do \
	    if [ -f "$$file" ]; then \
	        echo "  ✓ $$file"; \
	    else \
	        echo "  ✗ $$file (MISSING)"; \
	    fi; \
	done

# Check environment
env:
	@echo "Environment check:"
	@echo "  VCS path: $$(which vcs)"
	@echo "  VERDI_HOME: $$VERDI_HOME"
	@if [ -d "$$VERDI_HOME" ]; then \
	    echo "  VERDI_HOME directory: ✓ exists"; \
	else \
	    echo "  VERDI_HOME directory: ✗ NOT FOUND"; \
	fi
	@echo "  Coverage tool (urg) path: $$(which urg 2>/dev/null || echo 'Not found')"
	@echo "  Current directory: $$(pwd)"

# Check URG version
urg_version:
	@echo "Checking URG version and options..."
	@urg -help | head -20

# Help message
help:
	@echo "=========================================="
	@echo "VCS Simulation Makefile with Coverage Help"
	@echo "=========================================="
	@echo ""
	@echo "Coverage Types Enabled:"
	@echo "  -cm line        : Line coverage"
	@echo "  -cm cond        : Condition coverage"
	@echo "  -cm fsm         : FSM coverage"
	@echo "  -cm tgl         : Toggle coverage"
	@echo "  -cm branch      : Branch coverage"
	@echo "  -cm assert      : Assertion coverage"
	@echo ""
	@echo "Available targets (default: make poly_mul_rand):"
	@echo "  make all                   : Same as poly_mul_rand (compile + reference check)"
	@echo "  make poly_mul              : tb_poly_mul stimulus only"
	@echo "  make compile               : Compile with coverage"
	@echo "  make run                   : Run simulation with coverage"
	@echo "  make verdi                 : Open Verdi to view waveforms"
	@echo "  make verdi_coverage        : Open Verdi with coverage data"
	@echo "  make coverage_report       : Generate HTML coverage report"
	@echo "  make coverage_summary      : Show coverage summary in terminal"
	@echo "  make coverage_detail       : Show detailed coverage metrics"
	@echo "  make merge_coverage        : Merge coverage from multiple tests"
	@echo "  make run_test              : Run specific test (set CM_TESTNAME)"
	@echo "  make debug                 : Compile with maximum debug options"
	@echo "  make run_debug             : Run debug binary"
	@echo "  make clean                 : Clean all generated files"
	@echo "  make clean_coverage        : Clean only coverage data"
	@echo ""
	@echo "poly_mul aliases (same as default):"
	@echo "  make poly_mul              : compile + run"
	@echo "  make poly_mul_compile      : compile only"
	@echo "  make poly_mul_run          : run only"
	@echo "  make poly_mul_verdi        : open Verdi waveforms"
	@echo "  make poly_mul_coverage_report"
	@echo "  make poly_mul_debug"
	@echo ""
	@echo "poly_mul_rand (random stimulus + reference check):"
	@echo "  make poly_mul_rand         : compile + run tb_poly_mul_rand"
	@echo "  make poly_mul_rand_compile : compile only"
	@echo "  make poly_mul_rand_run     : run only"
	@echo "  make poly_mul_rand NUM_POLY=8 WAIT_MAX=5"
	@echo "  make poly_mul_rand_verdi_rc  : open Verdi with debug wave groups"
	@echo ""
	@echo "sanity (poly_mul_rand + reference check, NUM_BUTFLY_PER_STAGE=1):"
	@echo "  make sanity                : NUM_POLY=6; WAIT_MIN=0; WAIT_MAX=3"
	@echo ""
	@echo "forward_ntt testbench (legacy):"
	@echo "  make fwd_ntt               : compile + run tb_fwd_ntt"
	@echo "  make fwd_ntt_compile       : compile tb_fwd_ntt"
	@echo "  make fwd_ntt_run           : run tb_fwd_ntt sim"
	@echo "  make fwd_ntt_verdi         : open Verdi"
	@echo "Usage examples:"
	@echo "  make compile && make run && make verdi"
	@echo "  make poly_mul NUM_POLY=8 WAIT_MAX=5"
	@echo "  make fwd_ntt_compile && make fwd_ntt_run"
	@echo "  make test_coverage_example : Run coverage example"
	@echo "  make list                  : List source files"
	@echo "  make env                   : Check environment setup"
	@echo ""
	@echo "Coverage files location: $(COV_DIR)"
	@echo "HTML reports: $(COV_REPORT_DIR)/"

.PHONY: all poly_mul poly_mul_compile poly_mul_run poly_mul_verdi poly_mul_verdi_coverage \
        poly_mul_coverage_report poly_mul_coverage_summary poly_mul_coverage_detail \
        poly_mul_merge_coverage poly_mul_run_test poly_mul_debug poly_mul_run_debug \
        poly_mul_clean poly_mul_clean_coverage \
        poly_mul_rand poly_mul_rand_compile poly_mul_rand_run poly_mul_rand_verdi poly_mul_rand_verdi_rc \
        sanity \
        fwd_ntt fwd_ntt_compile fwd_ntt_run fwd_ntt_verdi fwd_ntt_verdi_coverage \
        fwd_ntt_coverage_report fwd_ntt_debug fwd_ntt_run_debug \
        compile run run_test coverage_report coverage_summary coverage_detail \
        merge_coverage verdi verdi_coverage debug run_debug clean clean_coverage \
        filelist $(FILELIST) $(RTL_FILELIST) \
        check_stages debug_probe \
        spyglass_prj lint \
        test_coverage_example list env urg_version help
