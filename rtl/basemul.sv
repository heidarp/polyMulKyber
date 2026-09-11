`timescale 1ns/1ps

import ntt_pkg::*;

module basemul(
    input  basemul_poly_type     pair_x, pair_y,
    input  [MODULUS_WIDTH-1:0] w,
    output basemul_poly_type     result,
    input  clk, reset_n, is_negate
);

    logic R_pair_valid;
    assign R_pair_valid = pair_x.valid && pair_y.valid;

    logic [MODULUS_WIDTH:0]   sa, sb;
    logic [MODULUS_WIDTH-1:0] sa_reduced, sb_reduced;

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

    logic [MODULUS_WIDTH-1:0] gamma;
    assign gamma = is_negate ? MODULUS_WIDTH'(MODULUS - w) : w;

    logic [MODULUS_WIDTH-1:0] R_p00, R_p11, R_s01;
    logic R_kara_valid;

    localparam int GAMMA_ALIGN_DEPTH = MUL_PIPE_DEPTH;

    logic [GAMMA_ALIGN_DEPTH-1:0] [MODULUS_WIDTH-1:0] R_p00_dly;

    logic [MODULUS_WIDTH-1:0] gamma_p11;
    logic gamma_mul_valid;

    mod_mul u_mod_mul_gamma (R_p11, gamma, gamma_p11, R_kara_valid, gamma_mul_valid, clk, reset_n);

    logic [MODULUS_WIDTH:0]   c0_sum;
    logic [MODULUS_WIDTH-1:0] c0_comb;
    logic [MODULUS_WIDTH:0]   c1_sub_p00, c1_sub_p11;
    logic [MODULUS_WIDTH-1:0] c1_no_p00, c1_comb;

    always_comb begin
        c0_sum = R_p00_dly[GAMMA_ALIGN_DEPTH-1] + gamma_p11;
        if (c0_sum >= MODULUS) begin
            c0_comb = MODULUS_WIDTH'(c0_sum - MODULUS);
        end
        else begin
            c0_comb = MODULUS_WIDTH'(c0_sum);
        end

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

    logic [MODULUS_WIDTH-1:0] R_c0, R_c1_dly;
    logic [GAMMA_ALIGN_DEPTH-1:0] [MODULUS_WIDTH-1:0] R_c1;
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
            if (karatsuba_muls_output_valid) begin
                R_p00 <= p00;
                R_p11 <= p11;
                R_s01 <= s01;
            end
            R_kara_valid <= karatsuba_muls_output_valid;

            if (R_kara_valid) begin
                R_c1[0]      <= c1_comb;
                R_p00_dly[0] <= R_p00;
            end

            for (int i = 0; i < GAMMA_ALIGN_DEPTH-1; i++) begin
                R_c1[i+1]      <= R_c1[i];
                R_p00_dly[i+1] <= R_p00_dly[i];
            end

            if (gamma_mul_valid) begin
                R_c0     <= c0_comb;
                R_c1_dly <= R_c1[GAMMA_ALIGN_DEPTH-1];
            end
            R_res_valid <= gamma_mul_valid;
        end
    end

    assign result.valid    = R_res_valid;
    assign result.coefs[0] = R_c0;
    assign result.coefs[1] = R_c1_dly;

endmodule
