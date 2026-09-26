// One polynomial is checked, then reset is asserted with the inputs idle.
// Output valid must stay low while reset is held and while the inputs stay
// idle after release. The polynomial driven after that release must also
// match the reference.
// Run: make test TEST=reset_idle

task automatic run_test_reset_idle();
    polynomial_t x;
    polynomial_t y;
    test_name  = "reset_idle";
    stall_mode = STALL_OFF;
    clear_counts();
    check_early_valid = 1'b1;
    release_reset();

    void'($urandom(32'h1D1E));
    x = random_poly();
    y = random_poly();
    record_and_drive(x, y);
    finish_and_check(1);

    clear_counts();
    x_in = '0;
    y_in = '0;
    @(ev_ready_settled);
    check_that(c_out.valid === 1'b0, "reset_idle: output still valid before reset");

    reset_n = 1'b0;
    repeat (5) begin
        @(ev_ready_settled);
        check_that(c_out.valid === 1'b0,
                   "reset_idle: output valid while reset is held");
    end

    check_early_valid = 1'b1;
    reset_n = 1'b1;
    repeat (8) begin
        @(ev_ready_settled);
        check_that(c_out.valid === 1'b0,
                   "reset_idle: output valid while the inputs are idle");
    end
    check_that(early_valid_count == 0,
               "reset_idle: output valid before the next polynomial was accepted");
    report_phase("reset while idle");

    clear_counts();
    check_early_valid = 1'b1;
    x = random_poly();
    y = random_poly();
    record_and_drive(x, y);
    finish_and_check(1);
endtask
