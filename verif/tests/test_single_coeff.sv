// One nonzero coefficient in each input.
//   5*x^3 * 7*x^4 = 35*x^7                         no wrap
//   5*x^200 * 9*x^100 = 45*x^300 = -45*x^44        wraps through x^256 = -1
// The second pair is the one that hits the ring reduction.
// Run: make test TEST=single_coeff

task automatic run_test_single_coeff();
    polynomial_t x0, y0, x1, y1;
    x0 = fill_poly(0);
    y0 = fill_poly(0);
    x1 = fill_poly(0);
    y1 = fill_poly(0);
    x0[3]   = 5;
    y0[4]   = 7;
    x1[200] = 5;
    y1[100] = 9;
    begin_test("single_coeff");
    record_and_drive(x0, y0);
    idle_cycles(2);
    record_and_drive(x1, y1);
    finish_and_check(2);
endtask
