// Fifty random pairs. Between polynomials the inputs sit idle for a random
// number of clocks, from 0 (back-to-back) up to 3 * POLYNOMIAL_LENGTH.
// Every product must match the schoolbook reference in order.
// Run: make test TEST=long_random

task automatic run_test_long_random();
    int n;
    int gap;
    int wait_max;
    polynomial_t x;
    polynomial_t y;

    n        = 50;
    wait_max = 3 * POLYNOMIAL_LENGTH;
    if (n > MAX_PAIRS) begin
        abort_check($sformatf("long_random: %0d pairs exceeds MAX_PAIRS %0d", n, MAX_PAIRS));
        finish_and_check(0);
        return;
    end

    void'($urandom(32'h1057));
    begin_test("long_random");
    $display("[TB] %0d random pairs, idle clocks in [0, %0d]", n, wait_max);

    for (int i = 0; i < n; i++) begin
        x = random_poly();
        y = random_poly();
        if (i > 0) begin
            gap = $urandom_range(wait_max, 0);
            $display("[TB] idle %0d clocks before pair %0d", gap, i);
            idle_clocks(gap);
        end
        record_and_drive(x, y);
    end

    finish_and_check(n);
endtask
