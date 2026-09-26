// The same pair is driven twice, with a gap so the pipe has to drain
// and then accept a new polynomial. Both products match the reference
// and match each other.
// Run: make test TEST=repeat_pair

task automatic run_test_repeat_pair();
    polynomial_t x;
    polynomial_t y;
    void'($urandom(32'h0E9EA7));
    x = random_poly();
    y = random_poly();
    begin_test("repeat_pair");
    record_and_drive(x, y);
    idle_cycles(5);
    record_and_drive(x, y);
    finish_and_check(2);
    if (num_collected == 2)
        check_that(out_bank[0] === out_bank[1],
                   "repeat_pair: the two products differ");
endtask
