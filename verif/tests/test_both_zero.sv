// Both inputs are the zero polynomial. The product is zero.
// Run: make test TEST=both_zero

task automatic run_test_both_zero();
    polynomial_t x;
    polynomial_t y;
    x = fill_poly(0);
    y = fill_poly(0);
    begin_test("both_zero");
    record_and_drive(x, y);
    finish_and_check(1);
endtask
