// Stall the first output beat for a few cycles, then accept it.
// While it is stalled the beat must not change and input_ready must be low.
// Run: make test TEST=stall_first

task automatic run_test_stall_first();
    begin_test("stall_first");
    stall_mode = STALL_FIRST;
    record_and_drive(ramp_poly(3, 1), ramp_poly(5, 2));
    finish_and_check(1);
endtask
