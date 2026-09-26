// Reset in the middle of a polynomial. That partial result must not
// come out. After release, a new pair must match the reference.
// Run: make test TEST=reset_mid

task automatic run_test_reset_mid();
    polynomial_t x_drop, y_drop, x, y;
    bit done;
    test_name  = "reset_mid";
    stall_mode = STALL_OFF;
    clear_counts();
    release_reset();

    x_drop = ramp_poly(1, 1);
    y_drop = ramp_poly(2, 2);

    fork : reset_mid_drive
        begin
            drive_polynomial(x_drop, y_drop, done);
        end
        begin
            wait (input_beats_accepted >= 4);
            @(ev_ready_settled);
            check_that(num_collected == 0,
                       "reset_mid: a full polynomial came out before reset");
            reset_n = 1'b0;
        end
    join_any
    disable reset_mid_drive;

    hold_reset(4);
    check_that(c_out.valid === 1'b0, "reset_mid: output valid while reset is held");
    report_phase("reset mid-polynomial");

    clear_counts();
    check_early_valid = 1'b1;
    reset_n = 1'b1;
    @(ev_ready_settled);

    void'($urandom(32'h31D0));
    x = random_poly();
    y = random_poly();
    record_and_drive(x, y);
    finish_and_check(1);
endtask
