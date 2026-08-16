`timescale 1ns/1ps

import ntt_pkg::*;

// Degree-1 residue multiply: (a0 + a1 X)(b0 + b1 X) mod (X^2 - gamma).
//
// Inputs arrive as a ready pair. The two result coefficients (r0, r1) leave
// together on a single output_valid pulse. For NUM_BUTFLY_PER_STAGE == 1 the
// parent serialises them across two beats; for larger parallelism both lanes
// are already available in the same beat and no serialiser is needed.
module basemul(
    input  basemul_poly_type           pair_x, pair_y,
    input  [MODULUS_WIDTH-1:0]       w,
    output basemul_poly_type           result,
    input  clk, reset_n, is_negate
);

////////////////////////////////////////////////////////////////////////////////
// Operand pairing: fifo[1] holds a0 and fifo[0] holds a1 once both beats are in
////////////////////////////////////////////////////////////////////////////////

// Pair is assembled in point_mul; input_valid means the pair is ready.
logic R_pair_valid;
assign R_pair_valid = pair_x.valid;

////////////////////////////////////////////////////////////////////////////////
// Karatsuba products
////////////////////////////////////////////////////////////////////////////////

logic [MODULUS_WIDTH:0]   sa, sb;
logic [MODULUS_WIDTH-1:0] sa_reduced, sb_reduced;

// The operand sums must re-enter [0, q) before the multiply: mod_mul only reduces
// products of two residues.
always_comb begin
    sa = pair_x.coefs[0] + pair_x.coefs[1];
    sb = pair_y.coefs[0] + pair_y.coefs[1];

    if (sa >= MODULUS) begin
        sa_reduced = MODULUS_WIDTH'(sa - MODULUS);
    end
    else begin
        sa_reduced = MODULUS_WIDTH'(sa);
    end
    if (sb >= MODULUS) begin
        sb_reduced = MODULUS_WIDTH'(sb - MODULUS);
    end
    else begin
        sb_reduced = MODULUS_WIDTH'(sb);
    end
end

logic [MODULUS_WIDTH-1:0] p00, p11, s01;

logic p00_out_valid;
logic p11_out_valid;
logic s01_out_valid;

logic karatsuba_muls_output_valid;

mod_mul u_mod_mul_p00 (pair_x.coefs[1], pair_y.coefs[1], p00, R_pair_valid, p00_out_valid, clk, reset_n);
mod_mul u_mod_mul_p11 (pair_x.coefs[0], pair_y.coefs[0], p11, R_pair_valid, p11_out_valid, clk, reset_n);
mod_mul u_mod_mul_s01 (sa_reduced, sb_reduced, s01, R_pair_valid, s01_out_valid, clk, reset_n);

assign karatsuba_muls_output_valid = p00_out_valid & p11_out_valid & s01_out_valid;

////////////////////////////////////////////////////////////////////////////////
// Gamma selection
////////////////////////////////////////////////////////////////////////////////

logic [MODULUS_WIDTH-1:0] gamma;

// w is driven by the shared generator in point_mul and must be settled on the cycle
// R_kara_valid is high, which is when the gamma multiplier samples it.
// The odd lane of every quad needs -gamma; q - gamma still fits in MODULUS_WIDTH.
assign gamma = is_negate ? MODULUS_WIDTH'(MODULUS - w) : w;

////////////////////////////////////////////////////////////////////////////////
// Recombination
////////////////////////////////////////////////////////////////////////////////

logic [MODULUS_WIDTH-1:0] R_p00, R_p11, R_s01;
logic [MODULUS_WIDTH-1:0] R_p00_dly;
logic R_kara_valid;

logic [MODULUS_WIDTH-1:0] gamma_p11;
logic gamma_mul_valid;

mod_mul u_mod_mul_gamma (R_p11, gamma, gamma_p11, R_kara_valid, gamma_mul_valid, clk, reset_n);

logic [MODULUS_WIDTH:0]   c0_sum;
logic [MODULUS_WIDTH-1:0] c0_comb;

logic [MODULUS_WIDTH:0]   c1_sub_p00, c1_sub_p11;
logic [MODULUS_WIDTH-1:0] c1_no_p00, c1_comb;

always_comb begin
    // Both terms are residues, so a single conditional subtraction lands c0 in [0, q).
    c0_sum = R_p00_dly + gamma_p11;
    if (c0_sum >= MODULUS) begin
        c0_comb = MODULUS_WIDTH'(c0_sum - MODULUS);
    end
    else begin
        c0_comb = MODULUS_WIDTH'(c0_sum);
    end

    // Bias by q ahead of each subtraction so the intermediates stay unsigned and below 2q.
    c1_sub_p00 = R_s01 + MODULUS - R_p00;
    if (c1_sub_p00 >= MODULUS) begin
        c1_no_p00 = MODULUS_WIDTH'(c1_sub_p00 - MODULUS);
    end
    else begin
        c1_no_p00 = MODULUS_WIDTH'(c1_sub_p00);
    end

    c1_sub_p11 = c1_no_p00 + MODULUS - R_p11;
    if (c1_sub_p11 >= MODULUS) begin
        c1_comb = MODULUS_WIDTH'(c1_sub_p11 - MODULUS);
    end
    else begin
        c1_comb = MODULUS_WIDTH'(c1_sub_p11);
    end
end

logic [MODULUS_WIDTH-1:0] R_c0, R_c1, R_c1_dly;
logic R_res_valid;

always @(posedge clk) begin
    if (reset_n == 1'b0) begin
        R_p00        <= '0;
        R_p11        <= '0;
        R_s01        <= '0;
        R_p00_dly    <= '0;
        R_kara_valid <= 1'b0;
        R_c0         <= '0;
        R_c1         <= '0;
        R_c1_dly     <= '0;
        R_res_valid  <= 1'b0;
    end
    else begin
        // clk1: capture the three Karatsuba products and fire the gamma multiply.
        if (karatsuba_muls_output_valid) begin
            R_p00 <= p00;
            R_p11 <= p11;
            R_s01 <= s01;
        end
        R_kara_valid <= karatsuba_muls_output_valid;

        // clk2: c1 finishes while its three operands are live; p00 waits for gamma*p11.
        // Back-to-back pairs overwrite R_c1 every cycle, so it is snapshotted into
        // R_c1_dly below when c0 lands, keeping both results aligned on output_valid.
        if (R_kara_valid) begin
            R_c1      <= c1_comb;
            R_p00_dly <= R_p00;
        end

        // clk3: gamma*p11 lands; assemble c0 and present both results together.
        if (gamma_mul_valid) begin
            R_c0     <= c0_comb;
            R_c1_dly <= R_c1;
        end
        R_res_valid <= gamma_mul_valid;
    end
end

assign result.valid     = R_res_valid;
assign result.coefs[0]  = R_c0;
assign result.coefs[1]  = R_c1_dly;

endmodule
