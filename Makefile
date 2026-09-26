# VCS Makefile with struct support for FSDB waveforms and coverage
SHELL = /bin/bash

# Tool paths - UPDATE THESE FOR YOUR SYSTEM
VCS = vcs
VERDI_HOME ?= /opt/synopsys/verdi/Verdi_O-2018.09-SP2

# Compile options. Verdi debug and -kdb are only for waveform runs.
# -kdb starts Verdi while it builds the design database, so regression
# (FSDB_DUMP=0) leaves them off and collects coverage only.
VCS_OPTS = -full64 -sverilog +v2k \
           +incdir+rtl +incdir+testbench +incdir+verif/common +incdir+verif/tests +incdir+.

# Waveforms for a single `make test`. Regression targets turn this off.
FSDB_DUMP ?= 1
ifeq ($(FSDB_DUMP),1)
VCS_OPTS += -debug_acc+all+dmptf \
           +structs=all \
           +memcbk \
           +vpi \
           -kdb \
           -debug_region+cell+encrypt \
           +define+FSDB_DUMP
FSDB_PLUSARGS = +fsdb+autoflush +fsdb+struct=on +fsdb+mda=on
endif

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

# Coverage test name. -cm_name at compile only sets the default. VCS does
# not treat +testname+ as a coverage test, so every run must pass -cm_name.
CM_TESTNAME ?= test_default
CM_OPTIONS = -cm_name $(CM_TESTNAME) -cm_dir ./$(COV_DIR)

# Testbench parameters (override: make compile NUM_POLY=8 WAIT_MIN=0 WAIT_MAX=5 NUM_BUTFLY_PER_STAGE=4)
NUM_POLY ?= 2
WAIT_MIN ?= 0
WAIT_MAX ?= 3
NUM_BUTFLY_PER_STAGE ?= 1
SKIP_Y_FWD_NTT ?= 0
# Downstream backpressure stimulus (BP_ENABLE=1 randomly deasserts downstream_ready)
BP_ENABLE ?= 0
BP_LOW_MAX ?= 5
BP_GAP_MAX ?= 20
# verif/tests/run_test.svh. One of the names in TESTS, or any of them via `make test`.
TEST ?= random
SIM_PLUSARGS = +TEST=$(TEST)
TESTS = random long_random both_zero one_zero unit all_qm1 single_coeff repeat_pair commute \
        ready_tied bp_random stall_first stall_last stall_long gaps \
        reset_idle reset_mid reset_stall
TB_DEFINES = +define+NUM_POLY=$(NUM_POLY) +define+WAIT_MIN=$(WAIT_MIN) +define+WAIT_MAX=$(WAIT_MAX) \
             +define+NUM_BUTFLY_PER_STAGE=$(NUM_BUTFLY_PER_STAGE)

ifeq ($(SKIP_Y_FWD_NTT),1)
TB_DEFINES += +define+SKIP_Y_FWD_NTT
endif

ifeq ($(BP_ENABLE),1)
TB_DEFINES += +define+BP_ENABLE +define+BP_LOW_MAX=$(BP_LOW_MAX) +define+BP_GAP_MAX=$(BP_GAP_MAX)
endif

# Source directories
RTL_DIR = rtl
TB_DIR = testbench
PYTHON_DIR = python

# RTL sources (SpyGlass lint). Packages and leaf modules first; basemul before point_mul before poly_mul.
RTL_FILES = \
    $(RTL_DIR)/ntt_pkg.sv \
    $(RTL_DIR)/modulus_funcs.sv \
    $(RTL_DIR)/mod_mul.sv \
    $(RTL_DIR)/w_calc.sv \
    $(RTL_DIR)/w_gen.sv \
    $(RTL_DIR)/butterfly.sv \
    $(RTL_DIR)/ntt_stage.sv \
    $(RTL_DIR)/forward_ntt.sv \
    $(RTL_DIR)/inverse_ntt.sv \
    $(RTL_DIR)/basemul.sv \
    $(RTL_DIR)/point_mul.sv \
    $(RTL_DIR)/poly_mul.sv \
    $(RTL_DIR)/scaler_mod.sv

# Testbenches (not linted as top-level RTL)
TB_FILES = \
    $(TB_DIR)/nttg_tb.sv \
    $(TB_DIR)/tb_poly_mul.sv \
    verif/tb/tb_poly_mul_rand.sv \
    $(TB_DIR)/tb_fwd_ntt.sv

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

# Bare `make` runs the random scenario on tb_poly_mul_rand.
.DEFAULT_GOAL := test

# Sanity: tb_poly_mul_rand + reference check across supported parallelism levels.
SANITY_NUM_POLY = 6
SANITY_WAIT_MIN = 0
SANITY_WAIT_MAX = 3
SANITY_BUTFLIES = 1 2 4 8
SANITY_BP_ENABLE ?= 0

# Same sweep as sanity but with random downstream backpressure applied.
sanity_bp: SANITY_BP_ENABLE = 1
sanity_bp: sanity

sanity:
	@echo "=========================================="
	@echo "Sanity: tb_poly_mul_rand for NUM_BUTFLY_PER_STAGE in ($(SANITY_BUTFLIES))"
	@echo "  NUM_POLY=$(SANITY_NUM_POLY) WAIT_MIN=$(SANITY_WAIT_MIN) WAIT_MAX=$(SANITY_WAIT_MAX)"
	@echo "  Includes SKIP_Y_FWD_NTT=0 (default) and SKIP_Y_FWD_NTT=1 (y bypass)"
	@echo "  BP_ENABLE=$(SANITY_BP_ENABLE) (backpressure stimulus)"
	@echo "=========================================="
	@fail=0; \
	for skip_y in 0 1; do \
	    for nbf in $(SANITY_BUTFLIES); do \
	        echo ""; \
	        echo "------------------------------------------"; \
	        echo "Sanity config: SKIP_Y_FWD_NTT=$$skip_y NUM_BUTFLY_PER_STAGE=$$nbf BP_ENABLE=$(SANITY_BP_ENABLE)"; \
	        echo "------------------------------------------"; \
	        $(MAKE) --no-print-directory clean >/dev/null; \
	        if $(MAKE) --no-print-directory compile run \
	                TOP=tb_poly_mul_rand \
	                SKIP_Y_FWD_NTT=$$skip_y \
	                NUM_BUTFLY_PER_STAGE=$$nbf \
	                NUM_POLY=$(SANITY_NUM_POLY) \
	                WAIT_MIN=$(SANITY_WAIT_MIN) \
	                WAIT_MAX=$(SANITY_WAIT_MAX) \
	                BP_ENABLE=$(SANITY_BP_ENABLE) \
	                CM_TESTNAME=sanity_skip$${skip_y}_nbf_$$nbf; then \
	            if grep -q 'TEST RESULT: PASS' $(SIM_LOG) 2>/dev/null; then \
	                echo "PASS: SKIP_Y_FWD_NTT=$$skip_y NUM_BUTFLY_PER_STAGE=$$nbf"; \
	            else \
	                echo "FAIL: SKIP_Y_FWD_NTT=$$skip_y NUM_BUTFLY_PER_STAGE=$$nbf (see $(SIM_LOG))"; \
	                fail=1; \
	            fi; \
	        else \
	            echo "FAIL: SKIP_Y_FWD_NTT=$$skip_y NUM_BUTFLY_PER_STAGE=$$nbf (compile/run error)"; \
	            fail=1; \
	        fi; \
	    done; \
	done; \
	echo ""; \
	echo "=========================================="; \
	if [ $$fail -eq 0 ]; then \
	    echo "SANITY RESULT: PASS (all SKIP_Y_FWD_NTT and NUM_BUTFLY_PER_STAGE configs)"; \
	else \
	    echo "SANITY RESULT: FAIL"; \
	    exit 1; \
	fi; \
	echo "=========================================="

# One scenario from verif/tests. Compiles tb_poly_mul_rand, then runs +TEST=$(TEST).
test:
	$(MAKE) compile TOP=tb_poly_mul_rand CM_TESTNAME=$(TEST) NUM_POLY=$(NUM_POLY)
	$(MAKE) run TOP=tb_poly_mul_rand TEST=$(TEST) CM_TESTNAME=$(TEST)

# Every scenario, one elaboration (butterfly width 1, y in coefficient domain).
# This is the regression to run. Coverage from these runs shares one design.
# Drop any earlier database first. A vdb from another butterfly width, y path,
# or -debug_acc build has a different toggle shape, and urg then warns
# UCAPI-INSTANCEMISMATCH and drops that instance.
regression:
	@echo "=========================================="
	@echo "Regression: all tests, NUM_BUTFLY_PER_STAGE=$(NUM_BUTFLY_PER_STAGE), SKIP_Y_FWD_NTT=$(SKIP_Y_FWD_NTT)"
	@echo "=========================================="
	rm -rf $(COV_DIR) $(COV_DIR).vdb $(COV_REPORT_DIR)
	$(MAKE) compile TOP=tb_poly_mul_rand CM_TESTNAME=regression \
	    NUM_BUTFLY_PER_STAGE=$(NUM_BUTFLY_PER_STAGE) SKIP_Y_FWD_NTT=$(SKIP_Y_FWD_NTT) \
	    BP_ENABLE=0 NUM_POLY=4 FSDB_DUMP=0
	@fail=0; \
	for t in $(TESTS); do \
	    echo ""; \
	    echo "------------------------------------------"; \
	    echo "TEST $$t"; \
	    echo "------------------------------------------"; \
	    if ./$(SIMV) \
	            -cm line+cond+fsm+tgl+branch+assert \
	            -cm_dir ./$(COV_DIR) \
	            -cm_name $$t \
	            +TEST=$$t \
	            -l sim_$$t.log \
	        && grep -q "TEST RESULT: PASS" sim_$$t.log; then \
	        echo "PASS $$t"; \
	    else \
	        echo "FAIL $$t (see sim_$$t.log)"; \
	        fail=1; \
	    fi; \
	done; \
	echo ""; \
	if [ $$fail -ne 0 ]; then \
	    echo "REGRESSION RESULT: FAIL"; \
	    exit 1; \
	fi; \
	echo "REGRESSION RESULT: PASS"

# Same scenarios as regression, then the HTML report from coverage_report.
# Do not merge this database with a different butterfly width or SKIP_Y_FWD_NTT.
# FSDB_DUMP=0 on regression keeps -kdb off, so this does not open Verdi.
regression_cov: regression
	$(MAKE) coverage_report

# Random and random-backpressure across every legal width and both y paths.
regression_configs:
	@echo "=========================================="
	@echo "Config regression: random and bp_random"
	@echo "  NUM_BUTFLY_PER_STAGE in (1 2 4 8), SKIP_Y_FWD_NTT in (0 1)"
	@echo "=========================================="
	@fail=0; \
	for skip_y in 0 1; do \
	    for nbf in 1 2 4 8; do \
	        for t in random bp_random; do \
	            echo ""; \
	            echo "------------------------------------------"; \
	            echo "TEST $$t  SKIP_Y_FWD_NTT=$$skip_y  NUM_BUTFLY_PER_STAGE=$$nbf"; \
	            echo "------------------------------------------"; \
	            if $(MAKE) test TEST=$$t \
	                    SKIP_Y_FWD_NTT=$$skip_y \
	                    NUM_BUTFLY_PER_STAGE=$$nbf \
	                    NUM_POLY=4 BP_ENABLE=0 FSDB_DUMP=0 \
	                    CM_TESTNAME=$${t}_skip$${skip_y}_nbf_$$nbf; then \
	                echo "PASS $$t skip=$$skip_y nbf=$$nbf"; \
	            else \
	                echo "FAIL $$t skip=$$skip_y nbf=$$nbf"; \
	                fail=1; \
	            fi; \
	        done; \
	    done; \
	done; \
	echo ""; \
	if [ $$fail -ne 0 ]; then \
	    echo "CONFIG REGRESSION RESULT: FAIL"; \
	    exit 1; \
	fi; \
	echo "CONFIG REGRESSION RESULT: PASS"

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

# make compile run DEBUG_PROBE=1 NUM_POLY=1 writes ntt_debug_trace.txt.
# check_stages compares that trace to the software model. Off by default.
DEBUG_PROBE ?= 0
PYTHON ?= python3

ifeq ($(DEBUG_PROBE),1)
TB_FILES   += $(TB_DIR)/ntt_debug_probe.sv
TB_DEFINES += +define+NTT_DEBUG_PROBE
endif

CHECK_STAGES = $(PYTHON_DIR)/check_ntt_stages.py

check_stages:
	$(PYTHON) $(CHECK_STAGES) -t ntt_debug_trace.txt

# Compilation target with coverage
compile: $(FILELIST)
	@echo "=========================================="
	@echo "Compiling with enhanced struct support..."
	@echo "=========================================="
	@echo "FSDB/Verdi debug: $(FSDB_DUMP)"
	@echo "Top module: $(TOP)"
	@echo "File list:  $(FILELIST) (includes basemul.sv)"
	@echo "TB params: NUM_POLY=$(NUM_POLY) WAIT_MIN=$(WAIT_MIN) WAIT_MAX=$(WAIT_MAX) NUM_BUTFLY_PER_STAGE=$(NUM_BUTFLY_PER_STAGE)"
	@echo "Backpressure: BP_ENABLE=$(BP_ENABLE) BP_LOW_MAX=$(BP_LOW_MAX) BP_GAP_MAX=$(BP_GAP_MAX)"
	@grep -q '^$(RTL_DIR)/basemul\.sv$$' $(FILELIST) || { echo "ERROR: $(RTL_DIR)/basemul.sv missing from $(FILELIST)"; exit 1; }
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
	@echo "Running simulation with coverage..."
	@echo "=========================================="
	@echo "Top module: $(TOP)"
	@echo "Test name: $(CM_TESTNAME)"
	@echo "Plusargs: $(SIM_PLUSARGS)"
	@echo "FSDB dump: $(FSDB_DUMP)"
	./$(SIMV) $(FSDB_PLUSARGS) \
	    -cm line+cond+fsm+tgl+branch+assert \
	    $(CM_OPTIONS) \
	    $(SIM_PLUSARGS) \
	    -l $(SIM_LOG)
	@echo ""
	@echo "Simulation complete."
	@echo "Log file: $(SIM_LOG)"
	@echo "Coverage data: $(COV_DIR)"
	@if [ "$(FSDB_DUMP)" = "1" ]; then \
	    echo "FSDB file: $(FSDB)"; \
	    if [ -f "$(FSDB)" ]; then \
	        echo "FSDB file size:" $$(du -h "$(FSDB)" | cut -f1); \
	    else \
	        echo "Warning: FSDB file not created!"; \
	    fi; \
	fi

# HTML and text coverage report. Batch urg only; this does not open Verdi.
# -cm_dir coverage_data is stored as coverage_data.vdb on current VCS.
coverage_report:
	@echo "=========================================="
	@echo "Generating HTML coverage report..."
	@echo "=========================================="
	@if [ -d "$(COV_DIR).vdb" ]; then \
	    covdb="$(COV_DIR).vdb"; \
	elif [ -d "$(COV_DIR)" ]; then \
	    covdb="$(COV_DIR)"; \
	else \
	    echo "Error: no coverage database. Run 'make regression' or 'make run' first."; \
	    exit 1; \
	fi; \
	echo "Using coverage data from: $$covdb"; \
	urg -dir "$$covdb" \
	    -format both \
	    -report $(COV_REPORT_DIR); \
	test -f $(COV_REPORT_DIR)/hierarchy.html; \
	echo ""; \
	echo "Coverage report generated:"; \
	echo "  HTML: $(COV_REPORT_DIR)/hierarchy.html"; \
	echo "  Text: $(COV_REPORT_DIR)/report.txt"

# Open Verdi to view waveforms
verdi:
	@echo "Opening Verdi with waveform..."
	@if [ -f "$(FSDB)" ]; then \
	    verdi -ssf $(FSDB) & \
	else \
	    echo "Error: $(FSDB) not found. Run 'make run' first."; \
	    exit 1; \
	fi

spyglass_prj:
	@echo "Creating SpyGlass project file (RTL only, top=$(SPYGLASS_TOP))..."
	@echo "set_option top $(SPYGLASS_TOP)" > $(SPYGLASS_PROJECT)
	@echo "set_option language_mode sverilog" >> $(SPYGLASS_PROJECT)
	@echo "set_option enableSV yes" >> $(SPYGLASS_PROJECT)
	@echo "set_option enableSV09 yes" >> $(SPYGLASS_PROJECT)
	@echo "set_option incdir $(RTL_DIR)" >> $(SPYGLASS_PROJECT)
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






# Clean up generated files
clean:
	@echo "Cleaning generated files..."
	rm -rf \
	    $(SIMV) \
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
	    $(COV_DIR) $(COV_DIR).vdb \
	    $(COV_REPORT_DIR) \
	    merged_coverage \
	    ntt_debug_trace.txt \
	    $(SPYGLASS_WORK) $(SPYGLASS_PROJECT) $(SPYGLASS_LOG)
	@echo "Clean complete."

help:
	@echo "polyMulKyber    (bare make runs: make test)"
	@echo ""
	@echo "Targets"
	@echo "  make test                One scenario on tb_poly_mul_rand, then the sim."
	@echo "  make regression          Every scenario, one compile. Waveforms off."
	@echo "  make regression_cov      Every scenario, then $(COV_REPORT_DIR)/hierarchy.html. No Verdi."
	@echo "  make regression_configs  random and bp_random at widths 1, 2, 4, 8 and both y paths."
	@echo "  make sanity              TEST at widths 1, 2, 4, 8, with and without the y bypass."
	@echo "  make sanity_bp           Same sweep with random downstream_ready."
	@echo "  make compile             Elaborate TOP (default tb_poly_mul) with coverage."
	@echo "  make run                 Run ./simv. Build options are already fixed by compile."
	@echo "  make verdi               Open waveform.fsdb. Needs a run with FSDB_DUMP=1."
	@echo "  make coverage_report     Write coverage_report/hierarchy.html from the last runs."
	@echo "  make check_stages        Compare ntt_debug_trace.txt to the software model."
	@echo "  make lint                SpyGlass lint/lint_rtl."
	@echo "  make spyglass_prj        Write the SpyGlass project lint uses."
	@echo "  make filelist            Regenerate filelist.f and rtl.f."
	@echo "  make clean               Remove sim, waves, coverage, and SpyGlass output."
	@echo "  make help                This list."
	@echo ""
	@echo "Scenarios (make test TEST=<name>)"
	@echo "  random         Several random pairs. One back-to-back, then idle gaps."
	@echo "  long_random    50 random pairs. Idle 0 to 3*256 clocks between them."
	@echo "  both_zero      Zero times zero."
	@echo "  one_zero       A zero operand on either side."
	@echo "  unit           Multiply by the polynomial 1."
	@echo "  all_qm1        Every coefficient is q-1."
	@echo "  single_coeff   One hot coefficient, including a wrap through x^256 = -1."
	@echo "  repeat_pair    The same pair twice."
	@echo "  commute        x*y and then y*x."
	@echo "  ready_tied     downstream_ready held high. NTT_ready must stay high."
	@echo "  bp_random      downstream_ready falls and rises at random."
	@echo "  stall_first    Stall the first output beat."
	@echo "  stall_last     Stall the beat that finishes a polynomial."
	@echo "  stall_long     Hold a beat for 64 cycles."
	@echo "  gaps           Idle cycles only between polynomials."
	@echo "  reset_idle     Check a polynomial, reset while idle, check the next one."
	@echo "  reset_mid      Reset mid-polynomial, then a fresh pair."
	@echo "  reset_stall    Reset while an output beat is held."
	@echo ""
	@echo "Build options (read at compile time; recompile to change them)"
	@echo "  NUM_POLY=2"
	@echo "      Pairs in the random scenario. Raised to 3 if smaller, rejected above 64."
	@echo "      Other scenarios ignore it. regression and regression_configs force 4."
	@echo "      sanity and sanity_bp force 6."
	@echo "  WAIT_MIN=0  WAIT_MAX=3"
	@echo "      Idle clocks between polynomials in random. WAIT_MAX must be >= WAIT_MIN."
	@echo "      Other scenarios ignore them. sanity and sanity_bp force 0 and 3."
	@echo "  NUM_BUTFLY_PER_STAGE=1"
	@echo "      Butterflies per NTT stage. Legal values: 1, 2, 4, 8."
	@echo "      regression and regression_cov use the value you pass."
	@echo "      regression_configs, sanity, and sanity_bp sweep 1, 2, 4, and 8."
	@echo "  SKIP_Y_FWD_NTT=0"
	@echo "      1: y is already in the NTT domain. The testbench aligns it."
	@echo "      regression and regression_cov use the value you pass."
	@echo "      regression_configs, sanity, and sanity_bp sweep 0 and 1."
	@echo "  BP_ENABLE=0"
	@echo "      1: random downstream_ready, unless the scenario sets its own stall"
	@echo "      (stall_*, ready_tied, reset_*, bp_random)."
	@echo "      regression, regression_cov, and regression_configs force 0."
	@echo "      sanity forces 0. sanity_bp forces 1."
	@echo "  BP_LOW_MAX=5  BP_GAP_MAX=20"
	@echo "      Longest ready-low stretch and longest ready-high gap, in cycles."
	@echo "      Compiled in only when BP_ENABLE=1. bp_random always stalls at"
	@echo "      random, and uses 5 and 20 unless BP_ENABLE=1 is set too."
	@echo "  FSDB_DUMP=1"
	@echo "      1 writes waveform.fsdb. 0 skips it."
	@echo "      regression, regression_cov, and regression_configs force 0."
	@echo "  DEBUG_PROBE=0"
	@echo "      1 on compile dumps ntt_debug_trace.txt. Then: make check_stages."
	@echo "      Use NUM_POLY=1. Example: make compile run DEBUG_PROBE=1 NUM_POLY=1"
	@echo "  TOP=tb_poly_mul"
	@echo "      compile and run only. test and the regressions force tb_poly_mul_rand."
	@echo "  CM_TESTNAME=test_default"
	@echo "      Coverage test name (-cm_name at run). test sets it to TEST."
	@echo "      regression names each scenario this way, so the report lists all of them."
	@echo "  SPYGLASS_GOAL=lint/lint_rtl   SPYGLASS_TOP=poly_mul"
	@echo "      lint only. spyglass_prj uses SPYGLASS_TOP."
	@echo ""
	@echo "Run option"
	@echo "  TEST=random"
	@echo "      Scenario for make test and make run. Ignored by regression."
	@echo "      sanity and sanity_bp run this scenario at every config (default random)."
	@echo "      regression_configs runs only random and bp_random."
	@echo ""
	@echo "Examples"
	@echo "  make test TEST=unit"
	@echo "  make test TEST=random NUM_POLY=8 WAIT_MAX=5 NUM_BUTFLY_PER_STAGE=4"
	@echo "  make test TEST=bp_random BP_ENABLE=1 BP_LOW_MAX=8 BP_GAP_MAX=12"
	@echo "  make regression NUM_BUTFLY_PER_STAGE=4 SKIP_Y_FWD_NTT=1"
	@echo "  make compile run && make verdi && make coverage_report"

.PHONY: sanity sanity_bp \
        test regression regression_cov regression_configs \
        compile run coverage_report verdi clean \
        filelist $(FILELIST) $(RTL_FILELIST) \
        check_stages \
        spyglass_prj lint help
