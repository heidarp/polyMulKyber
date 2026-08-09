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

// Product in the NTT domain == negacyclic poly multiply after INTT. Kyber's transform is
// incomplete, so each "point" is a degree-1 residue rather than a scalar: basemul pairs
// consecutive beats of a lane, and the two lanes of a quad share a gamma magnitude with
// the odd lane taking -gamma.
generate
    if (NUM_BUTFLY_PER_STAGE != 1) begin: unsupported_parallelism
        $error("poly_mul: basemul pairs coefficients across beats, which only holds for NUM_BUTFLY_PER_STAGE == 1");
    end

    for (genvar gv_i = 0; gv_i < NUM_COEFS_PER_STAGE; gv_i++) begin: point_muls
        basemul u_basemul(
            fwd_ntt_res_x.coefs[gv_i],
            fwd_ntt_res_y.coefs[gv_i],
            point_mul_reseult.coefs[gv_i],
            (fwd_ntt_res_x.valid && fwd_ntt_res_y.valid),
            point_mul_res_valid_per_coef[gv_i],
            clk,
            reset_n,
            (gv_i % 2 == 1)
        );
    end
endgenerate

assign point_mul_reseult.valid = &point_mul_res_valid_per_coef;

poly_type intt_result;

inverse_ntt u_inverse_ntt(
    point_mul_reseult,
    intt_result,
    clk,
    reset_n
);

// The INTT butterflies never halve, so each coefficient leaves 2^TOTAL_NUM_STAGES too large.
// SCALER is n^{-1} mod q, applied here as a constant modular multiply per lane; inverse_ntt
// itself stays an unnormalized transform. Only ever apply this once along the path -- the
// SCALER folded into SCALED_INV_PHI_INIT_VALS reaches the datapath through phi_gen, which is
// instantiated-out for Kyber.
logic [NUM_COEFS_PER_STAGE-1:0] scaler_mul_res_valid;

generate
    for (genvar gv_i = 0; gv_i < NUM_COEFS_PER_STAGE; gv_i++) begin: scaler_muls
        mod_mul u_scaler_mul(
            intt_result.coefs[gv_i],
            MODULUS_WIDTH'(SCALER),
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
// >>>>>>>>>>>>>>>>>>>> DEBUG PROBE - delete this whole block >>>>>>>>>>>>>>>>>>>>
// Taps every stage boundary for ntt_debug_probe.sv / check_ntt_stages.py.
// fntt.stage[k+1] is the output of forward stage k; the last stage drives
// fwd_ntt_res_* directly. Same shape for the inverse side.
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
// <<<<<<<<<<<<<<<<<<<< DEBUG PROBE - delete this whole block <<<<<<<<<<<<<<<<<<<<
`endif

endmodule
