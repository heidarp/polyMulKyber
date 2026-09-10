`timescale 1ns/1ps

import ntt_pkg::*;
import modulus_funcs_pkg::*;



//module barret_reduce_mod  (
//    input  logic [2*MODULUS_WIDTH-1:0] shifted_in,
//    output logic [MODULUS_WIDTH-1:0]   barret_reduce
//);

//    // Stage 1: t = floor(inp*5039 / 2^24), computed with 4 guard bits.
//    // Shift amounts are 12,14,18,20,24 minus 4 guard bits -> 8,10,14,16,20.
//    logic signed [17:0] s;
//    logic signed [13:0] t;
//    logic        [12:0] tl;
//    logic        [12:0] r13;
//    logic [12:0] temp1, temp2, temp3;
//always_comb begin
//    // Stage 1: All unsigned operations
//    s = {2'b0, shifted_in[23:8]}     // inp >> 8
//      + {4'b0, shifted_in[23:10]}    // inp >> 10
//      - {8'b0, shifted_in[23:14]}    // inp >> 14
//      - {10'b0, shifted_in[23:16]}  // inp >> 16
//      - {14'b0, shifted_in[23:20]}   // inp >> 20
//      - 18'd3;                        // truncation bias (no sign extension needed)

//    t = s >>> 4;                      // Logical shift right (unsigned)
//    tl = t[12:0];

//    // Stage 2: res13 = inp - t*3329, evaluated mod 2^13
//    r13 = shifted_in[12:0]
//        - {tl[0],   12'b0}            // (t<<12) mod 2^13
//        + {tl[2:0], 10'b0}            // (t<<10) mod 2^13
//        - {tl[4:0],  8'b0}            // (t<<8)  mod 2^13
//        - tl;

//    barret_reduce = (r13 >= 13'd3329) ? (r13 - 13'd3329) : r13[MODULUS_WIDTH-1:0];
//end

// Pipelined Barrett reduction for q = 3329, used by every datapath reduce
// (mod_mul, scaler_mod). Flat barret_reduce() in modulus_funcs_pkg stays behind
// for w_calc, whose reduce chain is unrolled at elaboration and must stay small
// rather than fast.
//
// Two clocks: stage 1 forms t = floor(x*mu / 2^24) as a shift-add tree, stage 2
// evaluates x - t*q mod 2^13 and applies the single conditional correction.
// Both halves are multi-operand carry chains; keeping them in one clock was a
// 13-logic-level path from the product register to the next multiplier.
//
// Registering between the two halves makes each one look like a pipelined
// multi-operand add, which synthesis will otherwise absorb into DSP48 ALUs at a
// cost of ~2 DSPs per instance. Only the product in mod_mul/scaler_mod belongs
// in a DSP, so keep this module in fabric.
(* use_dsp = "no" *)
module barret_reduce_mod  (
    input  logic                       clk,
    input  logic                       reset,
    input  logic [2*MODULUS_WIDTH-1:0] shifted_in,
    output logic [MODULUS_WIDTH-1:0]   reduced
);

// Stage 1: mu = 2^24/q as 1 + 2^-2 - 2^-6 - 2^-8, so the quotient is a sum of shifts.
logic [2*MODULUS_WIDTH-1:0] tmp_a;

always_comb begin
    tmp_a = shifted_in
          + shifted_in[2*MODULUS_WIDTH-1:2]
          - shifted_in[2*MODULUS_WIDTH-1:6]
          - shifted_in[2*MODULUS_WIDTH-1:8];
end

reg [MODULUS_WIDTH-1:0] R_tl;
reg [MODULUS_WIDTH:0]   R_shifted_in_low;
reg [MODULUS_WIDTH-1:0] R_reduced;

// Stage 2: q = 2^12 - 2^10 + 2^8 + 1, so t*q is also a sum of shifts. Only the low
// 13 bits of x - t*q matter; t is off by at most one q, fixed by the correction below.
logic [MODULUS_WIDTH:0] tl;
logic [MODULUS_WIDTH:0] r13_n_mod;

always_comb begin
    tl = {1'b0, R_tl};

    r13_n_mod = R_shifted_in_low
              - {tl[0],   12'b0}              // (t<<12) mod 2^13
              + {tl[2:0], 10'b0}              // (t<<10) mod 2^13
              - {tl[4:0],  8'b0}              // (t<<8)  mod 2^13
              - tl;
end

always @(posedge clk) begin
    if (reset == 1'b0) begin
        R_tl             <= '0;
        R_shifted_in_low <= '0;
        R_reduced        <= '0;
    end
    else begin
        R_tl             <= tmp_a[2*MODULUS_WIDTH-1:MODULUS_WIDTH];
        R_shifted_in_low <= shifted_in[MODULUS_WIDTH:0];

        // MSB set => under-subtracted; add q back into range.
        case (r13_n_mod[MODULUS_WIDTH])
            1:       R_reduced <= MODULUS_WIDTH'(r13_n_mod + MODULUS_BIN);
            default: R_reduced <= r13_n_mod[MODULUS_WIDTH-1:0];
        endcase
    end
end

assign reduced = R_reduced;

endmodule












module mod_mul(oprnd_x, oprnd_y, mul_reduced, input_valid, output_valid, clk, reset);

input clk, reset, input_valid;
output output_valid;
input [MODULUS_WIDTH-1:0] oprnd_x, oprnd_y;
output wire [MODULUS_WIDTH-1:0] mul_reduced;

reg [2*MODULUS_WIDTH-1:0]   R_mul_res_wide;
reg [MUL_PIPE_DEPTH-1:0]    R_out_valid_dly;

assign output_valid = R_out_valid_dly[MUL_PIPE_DEPTH-1];

always @(posedge clk) begin
    if (reset == 1'b0) begin
        R_out_valid_dly <= '0;
    end
    else begin
        R_out_valid_dly[0] <= input_valid;
        for (int i = 0; i < (MUL_PIPE_DEPTH-1); i++) begin
            R_out_valid_dly[i+1] <= R_out_valid_dly[i];
        end
    end
end

always @(posedge clk) begin
    if (reset == 1'b0) begin
        R_mul_res_wide <= '0;
    end
    else begin
        R_mul_res_wide <= oprnd_x * oprnd_y;
    end
end

barret_reduce_mod u_barret_reduce (
    .clk        (clk),
    .reset      (reset),
    .shifted_in (R_mul_res_wide),
    .reduced    (mul_reduced)
);


endmodule
