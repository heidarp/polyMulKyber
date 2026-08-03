`timescale 1ns/1ps

import ntt_pkg::*;

module poly_mul(input_poly_x, input_poly_y, output_poly, clk, reset_n);
input  clk, reset_n;
input  poly_type input_poly_x;
input  poly_type input_poly_y;
output poly_type output_poly;

poly_type fwd_ntt_res_x;
poly_type fwd_ntt_res_y;

forward_ntt u_fwd_ntt_x(input_poly_x, fwd_ntt_res_x, clk, reset_n);
forward_ntt u_fwd_ntt_y(input_poly_y, fwd_ntt_res_y, clk, reset_n);

poly_type point_mul_reseult;
logic [NUM_COEFS_PER_STAGE-1:0] point_mul_res_valid_per_coef;

// Pointwise product in NTT domain == circular/negacyclic poly multiply after INTT.
generate
    for (genvar gv_i = 0; gv_i < NUM_COEFS_PER_STAGE; gv_i++) begin: point_muls
        mod_mul u_mod_mul(
            fwd_ntt_res_x.coefs[gv_i],
            fwd_ntt_res_y.coefs[gv_i],
            point_mul_reseult.coefs[gv_i],
            (fwd_ntt_res_x.valid && fwd_ntt_res_y.valid),
            point_mul_res_valid_per_coef[gv_i],
            clk,
            reset_n
        );
    end
endgenerate

assign point_mul_reseult.valid = &point_mul_res_valid_per_coef;

inverse_ntt u_inverse_ntt(
    point_mul_reseult,
    output_poly,
    clk,
    reset_n
);

endmodule
