// downstream_ready stays high for the whole run.
// NTT_ready must stay high as well: with nothing stalling the output,
// the pipe must keep accepting inputs.
// Run: make test TEST=ready_tied

task automatic run_test_ready_tied();
    polynomial_t x;
    polynomial_t y;
    void'($urandom(32'h0EADE));
    x = random_poly();
    y = random_poly();
    begin_test("ready_tied");
    stall_mode        = STALL_OFF;
    check_ready_tied  = 1'b1;
    record_and_drive(x, y);
    finish_and_check(1);
endtask
