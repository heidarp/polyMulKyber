// Shared driver, backpressure, collector, and scoreboard.
// Included inside tb_poly_mul_rand, after polynomial_t is declared.
//
// Tests call:
//   begin_test(name)              release reset, clear scoreboard
//   record_and_drive(x, y)        remember the pair and stream it
//   idle_cycles(n)                gaps between polynomials only
//   drive_polynomial(x, y, done)  stream without recording (reset tests)
//   finish_and_check(n)           wait for n products and compare in order
//
// Output beats use the same lane map as the input driver:
//   coefs[2*i]     = coefficient in the low half
//   coefs[2*i + 1] = coefficient in the high half
// The scoreboard rebuilds natural order with that map and compares
// coefficient k to the schoolbook reference. Order is part of the check.

localparam int MAX_PAIRS          = 64;
localparam int CYCLE_TIMEOUT      = 300_000;
localparam int STALL_SHORT_CYCLES = 4;
localparam int STALL_LONG_CYCLES  = 64;

`ifndef BP_LOW_MAX
localparam int BP_LOW_MAX_C = 5;
`else
localparam int BP_LOW_MAX_C = `BP_LOW_MAX;
`endif
`ifndef BP_GAP_MAX
localparam int BP_GAP_MAX_C = 20;
`else
localparam int BP_GAP_MAX_C = `BP_GAP_MAX;
`endif

typedef enum int {
    STALL_OFF,
    STALL_RANDOM,
    STALL_FIRST,
    STALL_LAST,
    STALL_LONG
} stall_mode_e;

stall_mode_e stall_mode;

event ev_ready_settled;

polynomial_t x_bank   [0:MAX_PAIRS-1];
polynomial_t y_bank   [0:MAX_PAIRS-1];
polynomial_t out_bank [0:MAX_PAIRS-1];
polynomial_t poly_asm;

int num_expected;
int num_collected;
int out_a;
int out_b;
int input_beats_accepted;
int hold_violations;
int early_valid_count;
int ready_tied_violations;
int input_ready_stall_violations;
int mid_poly_gap_count;
int fail_count;

// fail_count is per phase. These accumulate over the whole test so the
// verdict at the end of the run covers every phase and every check.
int total_fails;
int total_phases;
// Set when a check cannot continue (timeout, stimulus aborted). Driving
// tasks return early so the run still reaches the verdict.
bit test_aborted;

bit check_early_valid;
bit check_ready_tied;
bit first_input_done;
bit poly_active;
bit directed_stall_done;
bit directed_stall_seen;

int  stall_cnt;
bit  bp_low;
int  bp_cnt;
bit  hold_expected;
poly_type c_out_prev;

string test_name;

function automatic int stall_hold_cycles();
    if (stall_mode == STALL_LONG)
        return STALL_LONG_CYCLES;
    return STALL_SHORT_CYCLES;
endfunction

function automatic bit beat_completes_poly();
    return (out_a + (NUM_COEFS_PER_STAGE / 2) >= (POLYNOMIAL_LENGTH / 2));
endfunction

function automatic bit want_directed_stall();
    if (directed_stall_done)
        return 0;
    if (stall_mode == STALL_FIRST || stall_mode == STALL_LONG)
        return 1;
    if (stall_mode == STALL_LAST)
        return beat_completes_poly();
    return 0;
endfunction

// One accepted output beat. Lanes match the driver (low half, high half).
function automatic void collect_beat();
    int step;
    if (num_collected >= MAX_PAIRS)
        return;
    step = NUM_COEFS_PER_STAGE / 2;
    for (int i = 0; i < step; i++) begin
        poly_asm[out_a + i] = c_out.coefs[2 * i];
        poly_asm[out_b + i] = c_out.coefs[2 * i + 1];
    end
    out_a += step;
    out_b += step;
    if (out_a >= POLYNOMIAL_LENGTH / 2) begin
        out_bank[num_collected] = poly_asm;
        $display("[TB] Captured output %0d at %0t ns", num_collected, $time);
        num_collected++;
        out_a    = 0;
        out_b    = POLYNOMIAL_LENGTH / 2;
        poly_asm = '0;
    end
endfunction

// output_ready changes on negedge so it is stable at the next posedge,
// which is when poly_mul samples it. A beat is scored only when the next
// posedge will accept it (valid and ready, and we are not choosing to stall).
always @(negedge clk) begin
    if (reset_n == 1'b0) begin
        output_ready   = 1'b1;
        stall_cnt          = 0;
        out_a              = 0;
        out_b              = POLYNOMIAL_LENGTH / 2;
        poly_asm           = '0;
        poly_active        = 1'b0;
        -> ev_ready_settled;
    end else begin
        if (check_early_valid && c_out.valid && !first_input_done)
            early_valid_count++;
        if (poly_active && input_ready && !x_in.valid)
            mid_poly_gap_count++;

        if (stall_cnt > 0) begin
            stall_cnt--;
            if (stall_cnt == 0) begin
                output_ready = 1'b1;
                if (c_out.valid)
                    collect_beat();
            end else begin
                output_ready = 1'b0;
            end
        end else if (c_out.valid && output_ready && want_directed_stall()) begin
            output_ready    = 1'b0;
            stall_cnt           = stall_hold_cycles();
            directed_stall_done = 1'b1;
            directed_stall_seen = 1'b1;
            $display("[TB] stalling output beat for %0d cycles at %0t ns (mode %s)",
                     stall_hold_cycles(), $time, stall_mode.name());
        end else if (stall_mode == STALL_RANDOM && bp_low) begin
            output_ready = 1'b0;
        end else if (c_out.valid && !output_ready) begin
            output_ready = 1'b1;
            collect_beat();
        end else if (c_out.valid && output_ready) begin
            collect_beat();
        end else begin
            output_ready = 1'b1;
        end

        -> ev_ready_settled;
    end
end

// Random ready runs on posedge so a low period cannot cancel a beat that
// the negedge has already decided to accept. bp_low is only consumed by
// the negedge block above.
always @(posedge clk) begin
    if (reset_n == 1'b0) begin
        hold_expected <= 1'b0;
        c_out_prev    <= '0;
        bp_low        <= 1'b0;
        bp_cnt        <= BP_GAP_MAX_C;
    end else begin
        if (hold_expected && c_out !== c_out_prev)
            hold_violations++;
        if (check_ready_tied && !input_ready)
            ready_tied_violations++;
        if (c_out.valid && !output_ready && input_ready)
            input_ready_stall_violations++;
        hold_expected <= c_out.valid && !output_ready;
        c_out_prev    <= c_out;

        if (stall_mode == STALL_RANDOM) begin
            if (bp_cnt > 1) begin
                bp_cnt <= bp_cnt - 1;
            end else begin
                bp_low <= ~bp_low;
                // bp_low still holds the period that just ended, so the
                // next stretch is a gap after a low, and a low after a gap.
                bp_cnt <= bp_low ? $urandom_range(BP_GAP_MAX_C, 1)
                                 : $urandom_range(BP_LOW_MAX_C, 1);
            end
        end
    end
end

// Record a failed check. Never ends the simulation: the verdict at the end
// of the run has to report it.
// fail_count is the count for the current phase; total_fails is the count for
// the run. clear_counts resets the first one only.
function automatic void fail_check(input string msg);
    fail_count++;
    total_fails++;
    $display("[TB] CHECK FAIL: %s", msg);
endfunction

function automatic void check_that(input bit cond, input string msg);
    if (cond !== 1'b1)
        fail_check(msg);
endfunction

// A failed check that also stops the stimulus.
function automatic void abort_check(input string msg);
    fail_check(msg);
    test_aborted = 1'b1;
endfunction

// Verdict for a phase that has no polynomial to compare, such as the
// protocol checks around a reset. Clears fail_count for the next phase.
task automatic report_phase(input string label);
    total_phases++;
    if (fail_count == 0)
        $display("[TB] %s phase %0d (%s): PASS", test_name, total_phases, label);
    else
        $display("[TB] %s phase %0d (%s): FAIL, %0d check(s)",
                 test_name, total_phases, label, fail_count);
    fail_count = 0;
endtask

task automatic clear_counts();
    num_expected                 = 0;
    num_collected                = 0;
    input_beats_accepted         = 0;
    hold_violations              = 0;
    early_valid_count            = 0;
    ready_tied_violations        = 0;
    input_ready_stall_violations   = 0;
    mid_poly_gap_count           = 0;
    fail_count                   = 0;
    check_early_valid            = 1'b0;
    check_ready_tied             = 1'b0;
    first_input_done             = 1'b0;
    directed_stall_done          = 1'b0;
    directed_stall_seen          = 1'b0;
    out_a                        = 0;
    out_b                        = POLYNOMIAL_LENGTH / 2;
    poly_asm                     = '0;
endtask

task automatic release_reset();
    x_in   = '0;
    y_in   = '0;
    repeat (3) @(ev_ready_settled);
    reset_n = 1'b1;
    @(ev_ready_settled);
endtask

task automatic hold_reset(input int cycles);
    reset_n = 1'b0;
    x_in    = '0;
    y_in    = '0;
    repeat (cycles) @(ev_ready_settled);
endtask

task automatic drive_polynomial(
    input  polynomial_t x,
    input  polynomial_t y,
    output bit          completed
);
    int a, b, step, spins, sent;
    step      = NUM_COEFS_PER_STAGE / 2;
    a         = 0;
    b         = POLYNOMIAL_LENGTH / 2;
    sent      = 0;
    spins     = 0;
    completed = 1'b0;
    if (test_aborted)
        return;
    while (a < POLYNOMIAL_LENGTH / 2) begin
        @(ev_ready_settled);
        spins++;
        if (spins > CYCLE_TIMEOUT) begin
            abort_check($sformatf("%s: timeout while driving inputs", test_name));
            return;
        end
        if (reset_n == 1'b0) begin
            x_in.valid  = 1'b0;
            y_in.valid  = 1'b0;
            poly_active = 1'b0;
            return;
        end
        if (input_ready) begin
            x_in.valid = 1'b1;
            y_in.valid = 1'b1;
            for (int i = 0; i < step; i++) begin
                x_in.coefs[2 * i]     = x[a + i];
                x_in.coefs[2 * i + 1] = x[b + i];
                y_in.coefs[2 * i]     = y[a + i];
                y_in.coefs[2 * i + 1] = y[b + i];
            end
            a += step;
            b += step;
            sent++;
            input_beats_accepted++;
            poly_active = (a < POLYNOMIAL_LENGTH / 2);
            if (a >= POLYNOMIAL_LENGTH / 2) begin
                completed        = 1'b1;
                first_input_done = 1'b1;
                poly_active      = 1'b0;
            end
        end
    end
endtask

task automatic record_and_drive(
    input polynomial_t x,
    input polynomial_t y
);
    bit done;
    if (test_aborted)
        return;
    if (num_expected >= MAX_PAIRS) begin
        abort_check($sformatf("%s: more than %0d pairs", test_name, MAX_PAIRS));
        return;
    end
    x_bank[num_expected] = x;
    y_bank[num_expected] = y;
    num_expected++;
    drive_polynomial(x, y, done);
    if (!done && !test_aborted)
        abort_check($sformatf("%s: drive aborted before the polynomial was accepted",
                              test_name));
endtask

task automatic idle_cycles(input int n);
    int got, spins;
    got   = 0;
    spins = 0;
    if (test_aborted)
        return;
    while (got < n) begin
        @(ev_ready_settled);
        spins++;
        if (spins > CYCLE_TIMEOUT) begin
            abort_check($sformatf("%s: timeout while idle", test_name));
            return;
        end
        if (reset_n == 1'b0)
            return;
        if (input_ready) begin
            x_in = '0;
            y_in = '0;
            got++;
        end
    end
endtask

// Drop valid and wait n clocks. The first wait is the cycle after the last
// presented beat, so that beat is still sampled. n = 0 is back-to-back.
task automatic idle_clocks(input int n);
    if (test_aborted)
        return;
    for (int i = 0; i < n; i++) begin
        @(ev_ready_settled);
        x_in = '0;
        y_in = '0;
    end
endtask

task automatic begin_test(input string name);
    test_name  = name;
    stall_mode = STALL_OFF;
`ifdef BP_ENABLE
    // sanity_bp compiles with this define and expects the random test to stall.
    stall_mode = STALL_RANDOM;
`endif
    clear_counts();
    // No output beat is legal until the first polynomial has been accepted.
    check_early_valid = 1'b1;
    $display("[TB] --- %s ---", name);
    release_reset();
endtask

task automatic finish_and_check(input int n);
    int guard;
    int shown;
    polynomial_t ref_poly;
    bit directed_required;

    total_phases++;

    if (test_aborted) begin
        if (fail_count == 0)
            fail_check($sformatf("%s: stimulus aborted", test_name));
        $display("Summary: 0 passed, %0d failed", fail_count);
        $display("[TB] %s phase %0d: FAIL (stimulus aborted)", test_name, total_phases);
        return;
    end

    idle_cycles(1);

    guard = 0;
    while (num_collected < n && guard < CYCLE_TIMEOUT) begin
        @(ev_ready_settled);
        guard++;
    end
    if (num_collected < n)
        fail_check($sformatf("collected %0d / %0d outputs before the timeout",
                             num_collected, n));

    // Inputs are idle. A second product must not appear.
    guard = num_collected;
    repeat (20) @(ev_ready_settled);
    if (num_collected != guard)
        fail_check($sformatf("extra output after the expected %0d polynomials", n));

    for (int p = 0; p < n && p < num_collected; p++) begin
        ref_poly = ref_poly_mul_ring(x_bank[p], y_bank[p]);
        shown = 0;
        for (int k = 0; k < POLYNOMIAL_LENGTH; k++) begin
            if (out_bank[p][k] !== ref_poly[k]) begin
                if (shown == 0)
                    $display("[TB] FAIL pair %0d", p);
                if (shown < 8) begin
                    $display("  coeff[%0d] dut=%0d ref=%0d",
                             k, out_bank[p][k], ref_poly[k]);
                end
                shown++;
            end
        end
        if (shown != 0) begin
            $display("  %0d coefficient mismatch(es)", shown);
            fail_check($sformatf("pair %0d does not match the reference", p));
        end else begin
            $display("[TB] PASS pair %0d", p);
        end
    end

    if (hold_violations != 0)
        fail_check($sformatf("%0d backpressure hold violation(s)", hold_violations));
    if (input_ready_stall_violations != 0)
        fail_check("input_ready stayed high while the output was stalled");
    if (mid_poly_gap_count != 0)
        fail_check($sformatf("%0d idle cycle(s) inside a polynomial", mid_poly_gap_count));
    if (check_early_valid && early_valid_count != 0)
        fail_check($sformatf("output valid before the first polynomial was accepted (%0d cycles)",
                             early_valid_count));
    if (check_ready_tied && ready_tied_violations != 0)
        fail_check("input_ready fell while output_ready was tied high");

    directed_required = (stall_mode == STALL_FIRST) ||
                        (stall_mode == STALL_LAST)  ||
                        (stall_mode == STALL_LONG);
    if (directed_required && !directed_stall_seen)
        fail_check("the directed stall never happened");

    if (fail_count == 0) begin
        $display("Summary: %0d passed, 0 failed", n);
        $display("[TB] polynomial multiply results match reference.");
        $display("[TB] %s phase %0d: PASS", test_name, total_phases);
    end else begin
        $display("Summary: 0 passed, %0d failed", fail_count);
        $display("[TB] %s phase %0d: FAIL", test_name, total_phases);
    end
endtask

// One verdict for the whole run. Every test reaches this, pass or fail.
task automatic report_test_result();
    $display("==========================================");
    if (total_phases == 0) begin
        $display("[TB] %s checked nothing", test_name);
        $display("TEST RESULT: FAIL (%s, no checks ran)", test_name);
    end else if (total_fails == 0) begin
        $display("TEST RESULT: PASS (%s, %0d phase(s))", test_name, total_phases);
    end else begin
        $display("TEST RESULT: FAIL (%s, %0d failed check(s))", test_name, total_fails);
    end
    $display("==========================================");
endtask

// Last resort. The per-task timeouts end a stuck test first; this one covers a
// wait that never completes, so a hung run still reports a verdict.
initial begin
    repeat (4 * CYCLE_TIMEOUT) @(posedge clk);
    fail_check($sformatf("%s: global timeout after %0d cycles", test_name, 4 * CYCLE_TIMEOUT));
    report_test_result();
    $fatal(1, "[TB] %s failed", test_name);
end
