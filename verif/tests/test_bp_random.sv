// downstream_ready falls and rises at random, including across valid
// output beats. A stalled beat must be held, and the product must still
// match once the beats are accepted.
// Run: make test TEST=bp_random

task automatic run_test_bp_random();
    polynomial_t x;
    polynomial_t y;
    void'($urandom(32'h0BA0));
    x = random_poly();
    y = random_poly();
    begin_test("bp_random");
    stall_mode = STALL_RANDOM;
    $display("[TB] random ready, low <= %0d cycles, gap <= %0d cycles",
             BP_LOW_MAX_C, BP_GAP_MAX_C);
    record_and_drive(x, y);
    idle_cycles(2);
    x = random_poly();
    y = random_poly();
    record_and_drive(x, y);
    finish_and_check(2);
endtask
