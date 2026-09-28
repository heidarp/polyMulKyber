// Stall the first output beat, then assert reset while that beat is held.
// Nothing from the stalled polynomial may be committed. After release,
// with ready tied high, a new pair must match the reference.
// Run: make test TEST=reset_stall

task automatic run_test_reset_stall();
    polynomial_t x_drop, y_drop, x, y;
    bit done;
    test_name  = "reset_stall";
    stall_mode = STALL_FIRST;
    clear_counts();
    release_reset();

    x_drop = ramp_poly(3, 1);
    y_drop = ramp_poly(5, 2);

    fork : reset_stall_drive
        begin
            drive_polynomial(x_drop, y_drop, done);
        end
        begin
            wait (directed_stall_seen == 1'b1);
            repeat (3) @(ev_ready_settled);
            check_that(output_ready === 1'b0 && c_out.valid === 1'b1,
                       "reset_stall: reset did not land during a held beat");
            check_that(num_collected == 0,
                       "reset_stall: a full polynomial came out before reset");
            check_that(hold_violations == 0,
                       "reset_stall: held beat changed before reset");
            reset_n = 1'b0;
        end
    join_any
    disable reset_stall_drive;

    hold_reset(4);
    check_that(c_out.valid === 1'b0, "reset_stall: output valid while reset is held");
    report_phase("reset during a held output beat");

    clear_counts();
    stall_mode        = STALL_OFF;
    check_early_valid = 1'b1;
    reset_n           = 1'b1;
    @(ev_ready_settled);

    void'($urandom(32'h57A11));
    x = random_poly();
    y = random_poly();
    record_and_drive(x, y);
    finish_and_check(1);
endtask
