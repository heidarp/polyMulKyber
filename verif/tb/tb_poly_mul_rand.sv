`timescale 1ns/1ps

// Top for the poly_mul suite. The scenario lives in verif/tests/test_<name>.sv.
// The driver and scoreboard live in verif/common/.
//
//   make test TEST=unit
//   make regression

import ntt_pkg::*;

module tb_poly_mul_rand;

    localparam int CLK_PERIOD = 10;

    logic clk;
    logic reset_n;

    poly_type x_in;
    poly_type y_in;
    poly_type y_to_dut;
    poly_type c_out;

    logic output_ready;
    logic input_ready;

    typedef logic [POLYNOMIAL_LENGTH-1:0][MODULUS_WIDTH-1:0] polynomial_t;

    initial clk = 1'b0;
    always #(CLK_PERIOD / 2) clk = ~clk;

`ifdef SKIP_Y_FWD_NTT
    // y bypasses the DUT forward NTT. This copy gives y the same latency
    // as x and stalls on the same input_ready, so the two streams stay aligned.
    poly_type y_ntt_out;
    forward_ntt u_tb_fwd_ntt_y(y_in, y_ntt_out, clk, reset_n, input_ready);
    assign y_to_dut = y_ntt_out;
`else
    assign y_to_dut = y_in;
`endif

    poly_mul u_poly_mul (
        x_in,
        y_to_dut,
        c_out,
        clk,
        reset_n,
        output_ready,
        input_ready
    );

`include "ref_model.svh"
`include "harness.svh"
`include "all_tests.svh"
`include "run_test.svh"

`ifdef FSDB_DUMP
    initial begin
        $fsdbDumpfile("waveform.fsdb");
        $fsdbDumpvars(0, tb_poly_mul_rand);
        $fsdbDumpMDA();
    end
`endif

endmodule
