// Drive (x, y) and then (y, x). The ring product is commutative, and
// each result has to match the reference in order.
// Run: make test TEST=commute

task automatic run_test_commute();
    polynomial_t x;
    polynomial_t y;
    void'($urandom(32'hC0FFEE));
    x = random_poly();
    y = random_poly();
    begin_test("commute");
    record_and_drive(x, y);
    idle_cycles(3);
    record_and_drive(y, x);
    finish_and_check(2);
    if (num_collected == 2)
        check_that(out_bank[0] === out_bank[1], "commute: x*y and y*x differ");
endtask
