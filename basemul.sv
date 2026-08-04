`timescale 1ns/1ps

import ntt_pkg::*;

// Point-wise multiply for Kyber's incomplete NTT. The transform stops one layer early,
// so a "point" is a degree-1 residue and the product is taken modulo (X^2 - gamma):
//     c0 = a0*b0 + gamma*a1*b1
//     c1 = a0*b1 + a1*b0
// Karatsuba trades the fourth multiplier for two modular subtractions:
//     c1 = (a0+a1)*(b0+b1) - a0*b0 - a1*b1
//
// One coefficient enters per beat, a0 before a1, and the two results leave the same way.
// The forward NTT emits its stream in quads whose two lanes share a gamma magnitude, the
// second lane using -gamma (is_negate selects it), so gamma follows exactly the sequence
// the last forward stage already consumes and the same w_gen produces it. Pairing and
// gamma order are the ones checked by basemul_pairing_check.py.
//
// This is the serial (NUM_BUTFLY_PER_STAGE == 1) arrangement: one instance per lane,
// pairs formed across consecutive beats.
module basemul(
    input [MODULUS_WIDTH-1:0] x,y,
    output wire [MODULUS_WIDTH-1:0] r,
    input input_valid,
    output output_valid,
    input clk, reset_n, is_negate
);

////////////////////////////////////////////////////////////////////////////////
// Operand pairing: fifo[1] holds a0 and fifo[0] holds a1 once both beats are in
////////////////////////////////////////////////////////////////////////////////

logic  [1:0] [MODULUS_WIDTH-1:0] fifo_x;
logic  [1:0] [MODULUS_WIDTH-1:0] fifo_y;

// 0: the next valid beat carries a0,  1: it carries a1 and completes the pair.
logic R_pair_phase;
logic R_pair_valid;

always @(posedge clk) begin
    if (reset_n == 1'b0) begin
        fifo_x       <= '0;
        fifo_y       <= '0;
        R_pair_phase <= 1'b0;
        R_pair_valid <= 1'b0;
    end
    else begin
        if (input_valid) begin
            fifo_x[0]    <= x;
            fifo_y[0]    <= y;
            fifo_x[1]    <= fifo_x[0];
            fifo_y[1]    <= fifo_y[0];
            R_pair_phase <= ~R_pair_phase;
        end
        R_pair_valid <= input_valid & R_pair_phase;
    end
end

////////////////////////////////////////////////////////////////////////////////
// Karatsuba products
////////////////////////////////////////////////////////////////////////////////

logic [MODULUS_WIDTH:0]   sa,sb;
logic [MODULUS_WIDTH-1:0] sa_reduced,sb_reduced;

// The operand sums must re-enter [0, q) before the multiply: mod_mul only reduces
// products of two residues.
always_comb begin
    sa = fifo_x[0] + fifo_x[1];
    sb = fifo_y[0] + fifo_y[1];

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

logic [MODULUS_WIDTH-1:0] p00,p11,s01;

logic p00_out_valid;
logic p11_out_valid;
logic s01_out_valid;

logic karatsuba_muls_output_valid;

mod_mul u_mod_mul_p00 (fifo_x[1], fifo_y[1], p00, R_pair_valid, p00_out_valid, clk, reset_n);
mod_mul u_mod_mul_p11 (fifo_x[0], fifo_y[0], p11, R_pair_valid, p11_out_valid, clk, reset_n);
mod_mul u_mod_mul_s01 (sa_reduced, sb_reduced, s01, R_pair_valid, s01_out_valid, clk, reset_n);

assign karatsuba_muls_output_valid = p00_out_valid & p11_out_valid & s01_out_valid;

////////////////////////////////////////////////////////////////////////////////
// Gamma generation
////////////////////////////////////////////////////////////////////////////////

logic  [NUM_BUTFLY_PER_STAGE-1:0] [MODULUS_WIDTH-1:0] generated_w;

logic generate_new_w;

// Advancing on the cycle the products land leaves gamma settled on the next cycle,
// which is when the gamma multiplier samples it.
assign generate_new_w = karatsuba_muls_output_valid;

// 64 residue pairs per lane, driven by the twiddles of the last forward stage.
w_gen #(
    .CNT_RST_VALUE(2**(TOTAL_NUM_STAGES-1)),
    .STAGE_INDEX(TOTAL_NUM_STAGES-1),
    .FWD_INV(0),
    .NUM_W_GENS(1)
) u_w_gen(generated_w, generate_new_w, clk, reset_n);

logic [MODULUS_WIDTH-1:0] gamma;

// The odd lane of every quad needs -gamma; q - gamma still fits in MODULUS_WIDTH.
assign gamma = is_negate ? MODULUS_WIDTH'(MODULUS - generated_w[0]) : generated_w[0];

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

logic [MODULUS_WIDTH:0]   c1_sub_p00,c1_sub_p11;
logic [MODULUS_WIDTH-1:0] c1_no_p00,c1_comb;

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
logic R_res_valid, R_res_valid_dly;

always @(posedge clk) begin
    if (reset_n == 1'b0) begin
        R_p00           <= '0;
        R_p11           <= '0;
        R_s01           <= '0;
        R_p00_dly       <= '0;
        R_kara_valid    <= 1'b0;
        R_c0            <= '0;
        R_c1            <= '0;
        R_c1_dly        <= '0;
        R_res_valid     <= 1'b0;
        R_res_valid_dly <= 1'b0;
    end
    else begin
        //clk1
        if (karatsuba_muls_output_valid) begin
            R_p00 <= p00;
            R_p11 <= p11;
            R_s01 <= s01;
        end
        R_kara_valid <= karatsuba_muls_output_valid;

        //clk2 - c1 is finished while its three operands are live; p00 waits for gamma*p11
        if (R_kara_valid) begin
            R_c1      <= c1_comb;
            R_p00_dly <= R_p00;
        end

        //clk3
        if (gamma_mul_valid) begin
            R_c0     <= c0_comb;
            R_c1_dly <= R_c1;
        end
        R_res_valid     <= gamma_mul_valid;
        R_res_valid_dly <= R_res_valid;
    end
end

// Pairs are two beats apart, so the two result flags never overlap: c0 goes out on the
// pair's first output beat and c1 on the second.
assign output_valid = R_res_valid | R_res_valid_dly;
assign r = R_res_valid ? R_c0 : R_c1_dly;

endmodule
