`timescale 1ns / 1ps

import ntt_pkg::*;

module tb_poly_mul_rand;

parameter CLK_PERIOD = 10;

logic clk;
logic reset_n;

poly_type x_in;
poly_type y_in;
poly_type c_out;

typedef logic [POLYNOMIAL_LENGTH-1:0][MODULUS_WIDTH-1:0] polynomial_t;

`ifndef NUM_POLY
parameter int num_poly_test = 6;
`else
parameter int num_poly_test = `NUM_POLY;
`endif

typedef polynomial_t poly_bank_t [0:num_poly_test-1];

function automatic poly_bank_t generate_test_polys(input int n);
    poly_bank_t polys_ret;
    for (int i = 0; i < n && i < num_poly_test; i++) begin
        for (int j = 0; j < POLYNOMIAL_LENGTH; j++) begin
            polys_ret[i][j] = $urandom_range(0, MODULUS - 1);
        end
    end
    return polys_ret;
endfunction

integer addr_a = 0;
integer addr_b = POLYNOMIAL_LENGTH / 2;

poly_mul u_poly_mul (x_in, y_in, c_out, clk, reset_n);

integer wait_counter;

poly_bank_t rndPolyBankX;
poly_bank_t rndPolyBankY;

polynomial_t testPolyX;
polynomial_t testPolyY;

integer testPolyIndex;

int wait_constants[0:num_poly_test-1];

function automatic void generate_wait_constants(
    input int num_tests,
    input int maxWaitConstant,
    input int minWaitConstant
);
    for (int i = 0; i < num_tests; i++) begin
        wait_constants[i] = $urandom_range(maxWaitConstant, minWaitConstant);
    end
endfunction

`ifndef WAIT_MAX
int maxWaitConstant = 3;
`else
int maxWaitConstant = `WAIT_MAX;
`endif
`ifndef WAIT_MIN
int minWaitConstant = 0;
`else
int minWaitConstant = `WAIT_MIN;
`endif

task automatic drive_poly_chunk(
    input polynomial_t poly,
    ref poly_type      poly_if
);
    poly_if.valid = 1'b1;
    for (int i = 0; i < NUM_COEFS_PER_STAGE / 2; i++) begin
        poly_if.coefs[2 * i]     = poly[addr_a + i];
        poly_if.coefs[2 * i + 1] = poly[addr_b + i];
    end
endtask

initial begin
    reset_n = 0;
    #50
    reset_n = 0;
    #100
    reset_n = 1;
end

initial begin
    rndPolyBankX = generate_test_polys(num_poly_test);
    rndPolyBankY = generate_test_polys(num_poly_test);
    clk = 1'b0;
    wait_counter = '0;
    testPolyIndex = '0;
    testPolyX = rndPolyBankX[testPolyIndex];
    testPolyY = rndPolyBankY[testPolyIndex];
    generate_wait_constants(num_poly_test, maxWaitConstant, minWaitConstant);

    forever begin
        #10 clk = !clk;

        if (reset_n == 0) begin
            x_in.valid = '0;
            x_in.coefs = '0;
            y_in.valid = '0;
            y_in.coefs = '0;
        end else if (clk == 1'b0) begin
            if (testPolyIndex < num_poly_test) begin
                if (addr_a < POLYNOMIAL_LENGTH / 2) begin
                    drive_poly_chunk(testPolyX, x_in);
                    drive_poly_chunk(testPolyY, y_in);
                    addr_a = addr_a + NUM_COEFS_PER_STAGE / 2;
                    addr_b = addr_b + NUM_COEFS_PER_STAGE / 2;
                end else if (testPolyIndex < num_poly_test - 1) begin
                    if (wait_counter < wait_constants[testPolyIndex]) begin
                        x_in.valid = '0;
                        x_in.coefs = '0;
                        y_in.valid = '0;
                        y_in.coefs = '0;
                        wait_counter = wait_counter + 1;
                    end else begin
                        wait_counter = '0;
                        testPolyIndex = testPolyIndex + 1;
                        testPolyX = rndPolyBankX[testPolyIndex];
                        testPolyY = rndPolyBankY[testPolyIndex];
                        addr_a = 0;
                        addr_b = POLYNOMIAL_LENGTH / 2;
                        drive_poly_chunk(testPolyX, x_in);
                        drive_poly_chunk(testPolyY, y_in);
                        addr_a = addr_a + NUM_COEFS_PER_STAGE / 2;
                        addr_b = addr_b + NUM_COEFS_PER_STAGE / 2;
                    end
                end else begin
                    x_in.valid = '0;
                    x_in.coefs = '0;
                    y_in.valid = '0;
                    y_in.coefs = '0;
                end
            end else begin
                x_in.valid = '0;
                x_in.coefs = '0;
                y_in.valid = '0;
                y_in.coefs = '0;
            end
        end
    end
end

polynomial_t poly_out;
polynomial_t output_polys [0:num_poly_test-1];
integer output_index = 0;
integer output_poly_number = 0;

initial begin
    #10;
    forever begin
        @(negedge clk);
        if (!reset_n) begin
            output_index       = 0;
            output_poly_number = 0;
        end else if (c_out.valid) begin
            for (int i = 0; i < NUM_COEFS_PER_STAGE; i++) begin
                poly_out[output_index + i] = c_out.coefs[i];
            end

            if (output_index + NUM_COEFS_PER_STAGE >= POLYNOMIAL_LENGTH) begin
                output_polys[output_poly_number] = poly_out;
                $display("[TB] Captured output_polys[%0d] at time %0t ns",
                         output_poly_number, $time);
                output_poly_number++;
                output_index = 0;
            end else if (output_index + NUM_COEFS_PER_STAGE == POLYNOMIAL_LENGTH / 2) begin
                output_index = POLYNOMIAL_LENGTH / 2;
            end else begin
                output_index = output_index + NUM_COEFS_PER_STAGE;
            end
        end
    end
end

integer fail_count, pass_count, total_polys_tested;

function automatic longint pos_mod(longint v, longint mod);
    longint r;
    r = v % mod;
    if (r < 0) begin
        r += mod;
    end
    return r;
endfunction

// Reference: negacyclic convolution in Z_MODULUS[x]/(x^n + 1), matching
// numpy flip -> polymul -> polydiv(mod x^n+1) -> flip in p_mul.py.
function automatic polynomial_t ref_poly_mul_ring(
    input polynomial_t x,
    input polynomial_t y
);
    longint conv [0:2 * POLYNOMIAL_LENGTH - 2];
    longint coeff;
    polynomial_t result;

    for (int k = 0; k < 2 * POLYNOMIAL_LENGTH - 1; k++) begin
        conv[k] = 0;
    end

    for (int i = 0; i < POLYNOMIAL_LENGTH; i++) begin
        for (int j = 0; j < POLYNOMIAL_LENGTH; j++) begin
            conv[i + j] = pos_mod(
                conv[i + j] + longint'(x[i]) * longint'(y[j]),
                MODULUS
            );
        end
    end

    for (int k = 0; k < POLYNOMIAL_LENGTH; k++) begin
        coeff = conv[k];
        if (k + POLYNOMIAL_LENGTH <= 2 * POLYNOMIAL_LENGTH - 2) begin
            coeff = pos_mod(coeff - conv[k + POLYNOMIAL_LENGTH], MODULUS);
        end
        result[k] = coeff[MODULUS_WIDTH-1:0];
    end

    return result;
endfunction

function automatic void sort_poly_coeffs(ref polynomial_t p);
    logic [MODULUS_WIDTH-1:0] tmp;
    for (int i = 0; i < POLYNOMIAL_LENGTH - 1; i++) begin
        for (int j = i + 1; j < POLYNOMIAL_LENGTH; j++) begin
            if (p[i] > p[j]) begin
                tmp  = p[i];
                p[i] = p[j];
                p[j] = tmp;
            end
        end
    end
endfunction

function automatic bit polys_coeffs_equal(
    input polynomial_t a,
    input polynomial_t b
);
    for (int i = 0; i < POLYNOMIAL_LENGTH; i++) begin
        if (a[i] !== b[i]) begin
            return 0;
        end
    end
    return 1;
endfunction

function automatic void display_polynomial(
    input string       label,
    input int          poly_idx,
    input polynomial_t p
);
    int end_idx;
    $display("%s[%0d]:", label, poly_idx);
    for (int i = 0; i < POLYNOMIAL_LENGTH; i++) begin
        if (i % 16 == 0) begin
            end_idx = (i + 15 < POLYNOMIAL_LENGTH) ? i + 15 : POLYNOMIAL_LENGTH - 1;
            $write("  [%3d:%3d]", i, end_idx);
        end
        $write(" %0d", p[i]);
        if (i % 16 == 15 || i == POLYNOMIAL_LENGTH - 1) begin
            $display("");
        end
    end
endfunction

task automatic compare_results(
    input poly_bank_t    x_bank,
    input poly_bank_t    y_bank,
    input polynomial_t   dut_outputs [0:num_poly_test-1],
    input int            num_dut_collected
);
    polynomial_t ref_poly;
    polynomial_t ref_sorted;
    polynomial_t dut_sorted;
    bit          dut_matched [0:num_poly_test-1];
    bit          found;
    int          matched_dut;

    fail_count         = 0;
    pass_count         = 0;
    total_polys_tested = 0;

    for (int d = 0; d < num_poly_test; d++) begin
        dut_matched[d] = 0;
    end

    $display("\n========================================");
    $display("Polynomial multiply reference comparison (coeff multiset, order ignored)");
    $display("  modulus = %0d, polynomial length = %0d", MODULUS, POLYNOMIAL_LENGTH);
    $display("  DUT polynomials collected: %0d / %0d", num_dut_collected, num_poly_test);
    $display("  wait range: [%0d, %0d] cycles between tests", minWaitConstant, maxWaitConstant);
    $display("========================================");

    if (num_dut_collected != num_poly_test) begin
        $error("compare_results: expected %0d DUT outputs, got %0d",
               num_poly_test, num_dut_collected);
    end

    for (int poly_idx = 0; poly_idx < num_poly_test; poly_idx++) begin
        ref_poly = ref_poly_mul_ring(x_bank[poly_idx], y_bank[poly_idx]);

        $display("----------------------------------------");
        $display("Comparing (x_bank[%0d], y_bank[%0d]):", poly_idx, poly_idx);
        display_polynomial("  reference product", poly_idx, ref_poly);

        ref_sorted = ref_poly;
        sort_poly_coeffs(ref_sorted);

        found       = 0;
        matched_dut = -1;

        for (int d = 0; d < num_dut_collected; d++) begin
            if (dut_matched[d]) begin
                continue;
            end
            dut_sorted = dut_outputs[d];
            sort_poly_coeffs(dut_sorted);
            if (polys_coeffs_equal(ref_sorted, dut_sorted)) begin
                found          = 1;
                matched_dut    = d;
                dut_matched[d] = 1;
                break;
            end
        end

        total_polys_tested++;

        if (found) begin
            $display("PASS: (x[%0d], y[%0d]) matches output_polys[%0d] (coefficients)",
                     poly_idx, poly_idx, matched_dut);
            display_polynomial("  matched DUT product", matched_dut, dut_outputs[matched_dut]);
            pass_count++;
        end else begin
            $display("FAIL: (x[%0d], y[%0d]) - no matching DUT output", poly_idx, poly_idx);
            fail_count++;
        end
    end

    for (int d = 0; d < num_dut_collected; d++) begin
        if (!dut_matched[d]) begin
            $warning("output_polys[%0d] did not match any reference product", d);
        end
    end

    $display("----------------------------------------");
    $display("Summary: %0d passed, %0d failed / %0d tested",
             pass_count, fail_count, total_polys_tested);
    $display("========================================\n");

    if (fail_count != 0) begin
        $error("Polynomial multiply comparison failed for %0d pair(s)", fail_count);
    end
endtask

localparam time SIM_COMPARE_TIMEOUT = 5ms;

`ifdef FSDB_DUMP
initial begin
    $fsdbDumpfile("waveform.fsdb");
    // depth 0: dump full TB hierarchy including u_poly_mul generate instances
    $fsdbDumpvars(0, tb_poly_mul_rand);
    $fsdbDumpMDA();
end
`else
initial begin
    $fsdbDumpfile("waveform.fsdb");
    $fsdbDumpvars(0, tb_poly_mul_rand);
end
`endif

initial begin
    $display("[TB] poly_mul_rand started at %0t ns", $time);
    $display("[TB] Driving %0d random polynomial pairs, wait [%0d:%0d]",
             num_poly_test, minWaitConstant, maxWaitConstant);
    $display("[TB] Waiting for %0d poly_mul outputs...", num_poly_test);

    fork
        begin
            wait (output_poly_number >= num_poly_test);
        end
        begin
            #(SIM_COMPARE_TIMEOUT);
            $display("[TB] TIMEOUT at %0t ns: collected %0d / %0d outputs",
                     $time, output_poly_number, num_poly_test);
        end
    join_any
    disable fork;

    #100;
    compare_results(rndPolyBankX, rndPolyBankY, output_polys, output_poly_number);

    if (output_poly_number >= num_poly_test && fail_count == 0) begin
        $display("[TB] All %0d polynomial multiply results match reference.", pass_count);
    end

    #100;
    $finish;
end

endmodule
