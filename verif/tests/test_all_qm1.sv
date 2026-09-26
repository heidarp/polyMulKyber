// Every coefficient is q-1, which is -1 mod q.
// The product has to follow x^256 = -1, not a plain integer multiply.
// Run: make test TEST=all_qm1

task automatic run_test_all_qm1();
    polynomial_t x;
    polynomial_t y;
    x = fill_poly(MODULUS - 1);
    y = fill_poly(MODULUS - 1);
    begin_test("all_qm1");
    record_and_drive(x, y);
    finish_and_check(1);
endtask
