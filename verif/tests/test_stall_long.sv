// Hold the first output beat longer than the modular multiplier pipe
// (MUL_PIPE_DEPTH is 4; this hold is 64 cycles). The frozen pipe must
// keep that beat and every later coefficient.
// Run: make test TEST=stall_long

task automatic run_test_stall_long();
    begin_test("stall_long");
    stall_mode = STALL_LONG;
    record_and_drive(ramp_poly(3, 1), ramp_poly(5, 2));
    finish_and_check(1);
endtask
