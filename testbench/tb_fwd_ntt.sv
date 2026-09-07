`timescale 1ns / 1ps

import ntt_pkg::*;
import primitive_root_pkg::*;

module tb_fwd_ntt  ; 
parameter CLK_PERIOD = 10;


logic			 clk;
logic	[1:0]    st='0;
logic            reset_n=0;

poly_type x_in;

poly_type c_out;


int error_count = 0;
int test_count = 0;

mailbox #(bit [POLYNOMIAL_LENGTH-1:0][MODULUS_WIDTH-1:0]) expected_results_mb = new();

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
            polys_ret[i][j] = $urandom_range(0, MODULUS-1);
        end
    end
    return polys_ret;
endfunction



logic output_valid;
integer addr_a=0;
integer addr_b=POLYNOMIAL_LENGTH/2;

forward_ntt u_forward_ntt (  x_in  , c_out ,   clk, reset_n);

integer wait_counter ;



poly_bank_t rndPolyBank;




polynomial_t testPoly ;



integer testPolyIndex ;
integer wait_constant =0;
initial begin 
#50 
reset_n =0;
#100 
reset_n =1;
end


// Declare the wait constants array - use packed array syntax or simpler declaration
int wait_constants[0:num_poly_test-1];

// Function to generate random wait constants for each test polynomial
function automatic void generate_wait_constants(
    input int num_poly_test,
    input int maxWaitConstant, 
    input int minWaitConstant
);
    for (int i = 0; i < num_poly_test; i++) begin
        // Generate random wait constant between 0 and maxWaitConstant
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










initial begin 
    rndPolyBank = generate_test_polys(num_poly_test);
    clk = 1'b0;
    wait_counter = '0;
    testPolyIndex = '0;
    testPoly = rndPolyBank[testPolyIndex];
    generate_wait_constants(num_poly_test, maxWaitConstant,minWaitConstant);
    forever begin
        #10 clk = !clk; 
        
        if (reset_n == 0) begin
                x_in.valid = '0;
                x_in.coefs = '0;
        end
        else if ((clk == 1'b0) ) begin
           //if (addr_a == POLYNOMIAL_LENGTH/NUM_COEFS_PER_STAGE ) begin
                
           //end
           if (testPolyIndex < num_poly_test) begin
                 if (addr_a < POLYNOMIAL_LENGTH/2) begin
                    x_in.valid = '1;
                    for (int i = 0; i < NUM_COEFS_PER_STAGE/2; i++) begin
                        x_in.coefs[2*i]     = testPoly[addr_a + i];
                        x_in.coefs[2*i + 1] = testPoly[addr_b + i];
                    end
                    addr_a = addr_a + NUM_COEFS_PER_STAGE/2;
                    addr_b = addr_b + NUM_COEFS_PER_STAGE/2;
                 end
                 else if (testPolyIndex < num_poly_test - 1) begin
                    if (wait_counter < wait_constants[testPolyIndex]) begin
                        x_in.valid = '0;
                        x_in.coefs = '0;
                        wait_counter = wait_counter + 1;
                    end
                    else begin
                        wait_counter = '0;
                        testPolyIndex = testPolyIndex + 1;
                        testPoly = rndPolyBank[testPolyIndex];
                        addr_a = 0;
                        addr_b = POLYNOMIAL_LENGTH/2;
                        x_in.valid = '1;
                        for (int i = 0; i < NUM_COEFS_PER_STAGE/2; i++) begin
                            x_in.coefs[2*i]     = testPoly[addr_a + i];
                            x_in.coefs[2*i + 1] = testPoly[addr_b + i];
                        end
                        addr_a = addr_a + NUM_COEFS_PER_STAGE/2;
                        addr_b = addr_b + NUM_COEFS_PER_STAGE/2;
                    end
                 end
                 else begin
                    x_in.valid = '0;
                    x_in.coefs = '0;
                 end
            end
            else begin
                x_in.valid = '0;
                x_in.coefs = '0;
            end
         end
    end    
end






logic output_collection_done = 0;

polynomial_t poly_out ;
polynomial_t output_polys [0:num_poly_test-1];
integer output_index = 0;
integer output_poly_number = 0;
logic last_valid =0;

// Collect DUT NTT outputs as c_out.valid streams coefficient chunks.
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
            end else if (output_index + NUM_COEFS_PER_STAGE == POLYNOMIAL_LENGTH/2) begin
                // DUT delivers lower half then upper half; restart index for coeffs [128:255].
                output_index = POLYNOMIAL_LENGTH/2;
            end else begin
                output_index = output_index + NUM_COEFS_PER_STAGE;
            end
        end
    end
end

integer fail_count, pass_count, total_polys_tested;

// Top-level twiddle root for ntt256_verifier (same as nttg_tb example).
localparam int NTT_REF_ROOT = 462262;

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

function automatic void longint_quotient_to_poly(
    input longint quotient[],
    output polynomial_t p
);
    longint v;
    for (int i = 0; i < POLYNOMIAL_LENGTH; i++) begin
        v = quotient[i] % MODULUS;
        if (v < 0) begin
            v += MODULUS;
        end
        p[i] = v[MODULUS_WIDTH-1:0];
    end
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

// Compare reference NTTs (from rndPolyBank via ntt256_verifier) against collected HDL outputs.
// Coefficient order may differ between reference and DUT; comparison is multiset (sorted coeffs).
task automatic compare_results(
    input poly_bank_t    input_bank,
    input polynomial_t dut_outputs [0:num_poly_test-1],
    input int            num_dut_collected
);
    longint x[];
    longint quotient[];
    polynomial_t ref_poly;
    polynomial_t ref_sorted;
    polynomial_t dut_sorted;
    bit          dut_matched [0:num_poly_test-1];
    int          r;
    int          mod;
    bit          found;
    int          matched_dut;

    fail_count         = 0;
    pass_count         = 0;
    total_polys_tested = 0;

    r   = NTT_REF_ROOT;
    mod = MODULUS;
    x   = new[POLYNOMIAL_LENGTH];

    for (int d = 0; d < num_poly_test; d++) begin
        dut_matched[d] = 0;
    end

    $display("\n========================================");
    $display("NTT reference comparison (coeff multiset, order ignored)");
    $display("  modulus = %0d, root r = %0d", mod, r);
    $display("  DUT polynomials collected: %0d / %0d", num_dut_collected, num_poly_test);
    $display("========================================");

    if (num_dut_collected != num_poly_test) begin
        $error("compare_results: expected %0d DUT outputs, got %0d",
               num_poly_test, num_dut_collected);
    end

    for (int poly_idx = 0; poly_idx < num_poly_test; poly_idx++) begin
        for (int j = 0; j < POLYNOMIAL_LENGTH; j++) begin
            x[j] = input_bank[poly_idx][j];
        end

        ntt256_verifier::ntt256(x, r, mod, quotient);
        longint_quotient_to_poly(quotient, ref_poly);

        $display("----------------------------------------");
        $display("Comparing input_bank[%0d]:", poly_idx);
        display_polynomial("  reference NTT", poly_idx, ref_poly);

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
            $display("PASS: input_bank[%0d] matches output_polys[%0d] (coefficients)",
                     poly_idx, matched_dut);
            display_polynomial("  matched DUT NTT", matched_dut, dut_outputs[matched_dut]);
            pass_count++;
        end else begin
            $display("FAIL: input_bank[%0d] - no matching DUT output", poly_idx);
            fail_count++;
        end
    end

    for (int d = 0; d < num_dut_collected; d++) begin
        if (!dut_matched[d]) begin
            $warning("output_polys[%0d] did not match any reference NTT", d);
        end
    end

    $display("----------------------------------------");
    $display("Summary: %0d passed, %0d failed / %0d tested",
             pass_count, fail_count, total_polys_tested);
    $display("========================================\n");

    if (fail_count != 0) begin
        $error("NTT comparison failed for %0d polynomial(s)", fail_count);
    end
endtask

// Allow enough time for pipelined NTT (6 polys); was 15 us / 100 us before compare could run.
localparam time SIM_COMPARE_TIMEOUT = 5ms;

initial begin
    $display("[TB] Started at %0t ns, waiting for %0d NTT outputs...",
             $time, num_poly_test);

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
    compare_results(rndPolyBank, output_polys, output_poly_number);

    if (output_poly_number >= num_poly_test && fail_count == 0) begin
        $display("[TB] All %0d NTT results match reference.", pass_count);
    end

    #100;
    $finish;
end

initial begin
    $fsdbDumpfile("waveform.fsdb");
    $fsdbDumpvars(0, tb_fwd_ntt);
end
endmodule

