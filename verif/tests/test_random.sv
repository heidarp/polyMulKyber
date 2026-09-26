// Random polynomials, back-to-back and with idle gaps between them.
// Every coefficient must match the schoolbook product in order.
// Run: make test TEST=random

task automatic run_test_random();
    int n;
    int gap;
    int wait_min;
    int wait_max;
    polynomial_t x;
    polynomial_t y;

`ifdef NUM_POLY
    n = `NUM_POLY;
`else
    n = 4;
`endif
    // One back-to-back pair and one gap need at least three polynomials.
    if (n < 3)
        n = 3;
    if (n > MAX_PAIRS) begin
        abort_check($sformatf("random: NUM_POLY %0d exceeds MAX_PAIRS %0d", n, MAX_PAIRS));
        finish_and_check(0);
        return;
    end

`ifdef WAIT_MIN
    wait_min = `WAIT_MIN;
`else
    wait_min = 0;
`endif
`ifdef WAIT_MAX
    wait_max = `WAIT_MAX;
`else
    wait_max = 3;
`endif
    if (wait_max < wait_min) begin
        abort_check("random: WAIT_MAX < WAIT_MIN");
        finish_and_check(0);
        return;
    end

    void'($urandom(32'hA11CE));
    begin_test("random");
    $display("[TB] %0d random pairs, idle range [%0d, %0d]", n, wait_min, wait_max);

    for (int i = 0; i < n; i++) begin
        x = random_poly();
        y = random_poly();
        // Pair 1 follows pair 0 on the next cycle. Later pairs insert a gap.
        if (i == 0 || i == 1)
            gap = 0;
        else
            gap = $urandom_range(wait_max, wait_min);
        if (gap > 0) begin
            $display("[TB] idle %0d cycles before pair %0d", gap, i);
            idle_cycles(gap);
        end
        record_and_drive(x, y);
    end

    finish_and_check(n);
endtask
