// +TEST=<name> runs one task. The default is random.
// Keep the names in sync with TESTS in the Makefile.

task automatic run_selected_test(input string name);
    case (name)
        "random":       run_test_random();
        "long_random":  run_test_long_random();
        "both_zero":    run_test_both_zero();
        "one_zero":     run_test_one_zero();
        "unit":         run_test_unit();
        "all_qm1":      run_test_all_qm1();
        "single_coeff": run_test_single_coeff();
        "repeat_pair":  run_test_repeat_pair();
        "commute":      run_test_commute();
        "ready_tied":   run_test_ready_tied();
        "bp_random":    run_test_bp_random();
        "stall_first":  run_test_stall_first();
        "stall_last":   run_test_stall_last();
        "stall_long":   run_test_stall_long();
        "gaps":         run_test_gaps();
        "reset_idle":   run_test_reset_idle();
        "reset_mid":    run_test_reset_mid();
        "reset_stall":  run_test_reset_stall();
        default:        abort_check($sformatf("unknown TEST=%s", name));
    endcase
endtask

initial begin
    string name;
    reset_n            = 1'b0;
    x_in               = '0;
    y_in               = '0;
    downstream_ready   = 1'b1;
    stall_mode         = STALL_OFF;
    total_fails        = 0;
    total_phases       = 0;
    test_aborted       = 1'b0;
    if (!$value$plusargs("TEST=%s", name))
        name = "random";
    $display("[TB] TEST=%s  NUM_BUTFLY_PER_STAGE=%0d", name, NUM_BUTFLY_PER_STAGE);
`ifdef SKIP_Y_FWD_NTT
    $display("[TB] SKIP_Y_FWD_NTT: y is already in the NTT domain");
`else
    $display("[TB] y is transformed by the DUT forward NTT");
`endif
    test_name = name;
    run_selected_test(name);
    report_test_result();
    if (total_fails != 0 || total_phases == 0)
        $fatal(1, "[TB] %s failed", name);
    $finish;
end
