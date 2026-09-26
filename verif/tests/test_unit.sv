// Multiply by the polynomial 1 (coefficient 0 is 1, the rest are 0).
// The product must be the other polynomial, unchanged.
// Run: make test TEST=unit

task automatic run_test_unit();
    polynomial_t x;
    polynomial_t one;
    one = fill_poly(0);
    one[0] = 1;
    // Distinct coefficients so a swapped or rotated result cannot pass.
    for (int i = 0; i < POLYNOMIAL_LENGTH; i++)
        x[i] = (i * 17 + 3) % MODULUS;
    begin_test("unit");
    record_and_drive(x, one);
    finish_and_check(1);
endtask
