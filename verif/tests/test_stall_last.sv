// Stall the output beat that finishes a polynomial, then accept it.
// The rest of the product still has to match in order.
// Run: make test TEST=stall_last

task automatic run_test_stall_last();
    begin_test("stall_last");
    stall_mode = STALL_LAST;
    record_and_drive(ramp_poly(3, 1), ramp_poly(5, 2));
    finish_and_check(1);
endtask
