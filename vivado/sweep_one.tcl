# One out-of-context synth + implementation of poly_mul.
# Invoked by run_sweep.sh. Reads configuration from the environment.
#
#   BF        butterfly count: 1, 2, 4, or 8  (NUM_BUTFLY_PER_STAGE)
#   SKIP_Y    0 or 1                          (1 defines SKIP_Y_FWD_NTT)
#   RUN_DIR   directory for this run's reports
#   RTL_DIR   directory containing the RTL sources
#   XDC       clock constraint file
#   PART      FPGA part
#   THREADS   general.maxThreads

set bf        $::env(BF)
set skip_y    $::env(SKIP_Y)
set run_dir   $::env(RUN_DIR)
set rtl_dir   $::env(RTL_DIR)
set xdc       $::env(XDC)
set part      $::env(PART)
set threads   $::env(THREADS)

set rtl_files [list \
    $rtl_dir/ntt_pkg.sv \
    $rtl_dir/modulus_funcs.sv \
    $rtl_dir/mod_mul.sv \
    $rtl_dir/w_calc.sv \
    $rtl_dir/w_gen.sv \
    $rtl_dir/butterfly.sv \
    $rtl_dir/ntt_stage.sv \
    $rtl_dir/forward_ntt.sv \
    $rtl_dir/inverse_ntt.sv \
    $rtl_dir/basemul.sv \
    $rtl_dir/point_mul.sv \
    $rtl_dir/poly_mul.sv \
    $rtl_dir/scaler_mod.sv \
]

proc write_text {path text} {
    set fh [open $path w]
    puts $fh $text
    close $fh
}

proc util_used {rpt label} {
    # Spaces in the site-type name are flexible in the report table.
    set escaped [regsub -all { } $label {\s+}]
    set re "^\\|\\s*${escaped}\\s*\\|\\s*(\[0-9,]+)"
    if {[regexp -line $re $rpt -> used]} {
        return [string map {, ""} $used]
    }
    return "NA"
}

proc run_one {} {
    global bf skip_y run_dir rtl_files xdc part threads

    file mkdir $run_dir
    set_param general.maxThreads $threads
    set_param general.usePosixSpawnForFork 1

    create_project -in_memory -part $part
    set_property default_lib xil_defaultlib [current_project]
    set_property target_language Verilog [current_project]

    # SKIP_Y_FWD_NTT is an ifdef. Defining it (any value) removes the y forward NTT.
    set defines [list NUM_BUTFLY_PER_STAGE=$bf]
    if {$skip_y} {
        lappend defines SKIP_Y_FWD_NTT
    }
    set_property verilog_define $defines [current_fileset]
    puts "INFO: verilog_define = [get_property verilog_define [current_fileset]]"

    read_verilog -library xil_defaultlib -sv $rtl_files
    read_xdc $xdc

    set info "bf=$bf\nskip_y=$skip_y\npart=$part\ndefines=$defines\nxdc=$xdc\n"
    write_text $run_dir/run_info.txt $info

    synth_design -top poly_mul -part $part -mode out_of_context
    report_utilization -file $run_dir/utilization_synth.rpt

    set y_cells [get_cells -quiet -hierarchical -filter {NAME =~ *u_fwd_ntt_y*}]
    set has_y [llength $y_cells]
    puts "INFO: u_fwd_ntt_y cell count = $has_y"
    if {$skip_y && $has_y != 0} {
        error "SKIP_Y_FWD_NTT=1 but u_fwd_ntt_y is still in the netlist"
    }
    if {!$skip_y && $has_y == 0} {
        error "skip_y=0 but u_fwd_ntt_y was optimized away or not elaborated"
    }

    opt_design
    place_design
    phys_opt_design
    route_design

    set util_rpt [report_utilization -return_string]
    write_text $run_dir/utilization_impl.rpt $util_rpt
    report_timing_summary -delay_type min_max -max_paths 10 \
        -report_unconstrained -file $run_dir/timing_summary.rpt

    set paths [get_timing_paths -delay_type max -max_paths 1 -nworst 1]
    if {[llength $paths] == 0} {
        error "no setup timing path reported"
    }
    set wns    [get_property SLACK $paths]
    set period [get_property PERIOD [get_clocks clk]]
    set whs_paths [get_timing_paths -delay_type min -max_paths 1 -nworst 1]
    if {[llength $whs_paths] == 0} {
        set whs "NA"
    } else {
        set whs [get_property SLACK $whs_paths]
    }

    set fmax [expr {1000.0 / ($period - $wns)}]

    set lut       [util_used $util_rpt "Slice LUTs"]
    set lut_logic [util_used $util_rpt "LUT as Logic"]
    set lut_mem   [util_used $util_rpt "LUT as Memory"]
    set ff        [util_used $util_rpt "Slice Registers"]
    set bram      [util_used $util_rpt "Block RAM Tile"]
    set dsp       [util_used $util_rpt "DSPs"]
    if {$lut eq "NA" || $ff eq "NA" || $dsp eq "NA" || $bram eq "NA"} {
        error "failed to parse utilization report in $run_dir/utilization_impl.rpt"
    }

    set metrics [format \
        "bf=%s\nskip_y=%s\npart=%s\nperiod_ns=%.3f\nwns_ns=%.3f\nwhs_ns=%s\nfmax_mhz=%.3f\nlut=%s\nlut_logic=%s\nlut_mem=%s\nff=%s\nbram=%s\ndsp=%s\nstatus=PASS\n" \
        $bf $skip_y $part $period $wns $whs $fmax \
        $lut $lut_logic $lut_mem $ff $bram $dsp]
    write_text $run_dir/metrics.txt $metrics
    write_text $run_dir/status.txt "PASS"
    puts "INFO: Fmax = [format %.3f $fmax] MHz  (1000 / ($period - $wns))"
    puts "INFO: LUT=$lut FF=$ff BRAM=$bram DSP=$dsp"

    close_project
}

set rc [catch {run_one} err]
if {$rc} {
    puts "ERROR: $err"
    write_text $run_dir/status.txt "FAIL"
    write_text $run_dir/error.txt $err
    catch {close_project}
    exit 1
}
exit 0
