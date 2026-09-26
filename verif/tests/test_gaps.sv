// Idle cycles are inserted only between polynomials.
// The driver never drops valid in the middle of a polynomial; the
// harness counts that if it happens, and this test fails on it.
// A bubble inside a polynomial is not part of the streaming contract.
// Run: make test TEST=gaps

task automatic run_test_gaps();
    polynomial_t x;
    polynomial_t y;
    void'($urandom(32'h6A95));
    begin_test("gaps");
    for (int i = 0; i < 3; i++) begin
        x = random_poly();
        y = random_poly();
        if (i > 0) begin
            $display("[TB] idle 5 cycles between pair %0d and %0d", i - 1, i);
            idle_cycles(5);
        end
        record_and_drive(x, y);
    end
    finish_and_check(3);
endtask
