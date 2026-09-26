// One operand is zero and the other is random. The product is zero
// either way around: (0, y) then (x, 0).
// Run: make test TEST=one_zero

task automatic run_test_one_zero();
    polynomial_t zero;
    polynomial_t x;
    polynomial_t y;
    zero = fill_poly(0);
    void'($urandom(32'h0E20));
    x = random_poly();
    y = random_poly();
    begin_test("one_zero");
    record_and_drive(zero, y);
    idle_cycles(2);
    record_and_drive(x, zero);
    finish_and_check(2);
endtask
