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

    point_mul u_point_mul(fwd_ntt_res_x, fwd_ntt_res_y, point_mul_reseult, clk, reset_n);

    poly_type intt_result;

    inverse_ntt u_inverse_ntt(
        point_mul_reseult,
        intt_result,
        clk,
        reset_n
    );

    logic [NUM_COEFS_PER_STAGE-1:0] scaler_mul_res_valid;

    generate
        for (genvar gv_i = 0; gv_i < NUM_COEFS_PER_STAGE; gv_i++) begin: scaler_muls
            scaler_mod u_scaler_mul(
                intt_result.coefs[gv_i],
                output_poly.coefs[gv_i],
                intt_result.valid,
                scaler_mul_res_valid[gv_i],
                clk,
                reset_n
            );
        end
    endgenerate

    assign output_poly.valid = &scaler_mul_res_valid;

`ifdef NTT_DEBUG_PROBE
    poly_type [TOTAL_NUM_STAGES-1:0] dbg_fwd_x, dbg_fwd_y, dbg_inv;

    generate
        for (genvar gv_d = 0; gv_d < TOTAL_NUM_STAGES-1; gv_d++) begin: dbg_stage_taps
            assign dbg_fwd_x[gv_d] = u_fwd_ntt_x.fntt.stage[gv_d+1];
            assign dbg_fwd_y[gv_d] = u_fwd_ntt_y.fntt.stage[gv_d+1];
            assign dbg_inv[gv_d]   = u_inverse_ntt.intt.stage[gv_d+1];
        end
    endgenerate

    assign dbg_fwd_x[TOTAL_NUM_STAGES-1] = fwd_ntt_res_x;
    assign dbg_fwd_y[TOTAL_NUM_STAGES-1] = fwd_ntt_res_y;
    assign dbg_inv[TOTAL_NUM_STAGES-1]   = intt_result;

    ntt_debug_probe u_ntt_debug_probe(
        clk,
        reset_n,
        input_poly_x,
        input_poly_y,
        dbg_fwd_x,
        dbg_fwd_y,
        point_mul_reseult,
        dbg_inv,
        output_poly
    );
`endif

endmodule
