`timescale 1ns/1ps

import ntt_pkg::*;

module inverse_ntt(input_poly, output_poly, clk, reset_n);
input  clk, reset_n;
input  poly_type input_poly;
output poly_type output_poly;

ntt_int_type intt;

assign intt.stage[0].coefs = input_poly.coefs;
assign intt.stage[0].valid = input_poly.valid;

poly_type inv_phi_input_poly;

parameter FWD_INV = 1;
generate
    for (genvar gv_i = 0; gv_i < TOTAL_NUM_STAGES; gv_i++) begin: inv_ntt_stage
        // Inverse stage order: delay grows toward the end (mirror of forward shrink).
        localparam DELAY_CALC =
            POLYNOMIAL_LENGTH/((2**(TOTAL_NUM_STAGES - gv_i + 1))*NUM_BUTFLY_PER_STAGE);
        localparam STAGE_DELAY_CLOCKS = (DELAY_CALC < 1) ? 1 : DELAY_CALC;
        localparam ST_NUM_W_CALC = 2**(gv_i);
        localparam NUM_W_GENS_CALC =
            (ST_NUM_W_CALC < NUM_BUTFLY_PER_STAGE)
            ? ST_NUM_W_CALC
            : NUM_BUTFLY_PER_STAGE;

        if (gv_i == 0) begin: first_inv_ntt_stage
            ntt_stage #(
                .STAGE_INDEX(gv_i),
                .ST_NUM_W(2**(gv_i)),
                .DELAY_NUM_CLOCKS(1),
                .FWD_INV(FWD_INV),
                .NUM_W_GENS(1),
                .DPND_FUT_DATA(inv_calc_dpnd_fut_data(gv_i))
            ) u_ntt_stage (
                intt.stage[gv_i],
                intt.stage[gv_i+1],
                clk,
                reset_n
            );
        end
        else if (gv_i == TOTAL_NUM_STAGES-1) begin: last_inv_ntt_stage
            ntt_stage #(
                .STAGE_INDEX(gv_i),
                .ST_NUM_W(ST_NUM_W_CALC),
                .DELAY_NUM_CLOCKS(STAGE_DELAY_CLOCKS),
                .FWD_INV(FWD_INV),
                .NUM_W_GENS(NUM_W_GENS_CALC),
                .DPND_FUT_DATA(inv_calc_dpnd_fut_data(gv_i))
            ) u_ntt_stage (
                intt.stage[gv_i],
                inv_phi_input_poly,
                clk,
                reset_n
            );
        end
        else begin: other_inv_stages
            ntt_stage #(
                .STAGE_INDEX(gv_i),
                .ST_NUM_W(ST_NUM_W_CALC),
                .DELAY_NUM_CLOCKS(STAGE_DELAY_CLOCKS),
                .FWD_INV(FWD_INV),
                .NUM_W_GENS(NUM_W_GENS_CALC),
                .DPND_FUT_DATA(inv_calc_dpnd_fut_data(gv_i))
            ) u_ntt_stage (
                intt.stage[gv_i],
                intt.stage[gv_i+1],
                clk,
                reset_n
            );
        end
    end
endgenerate

//poly_type generated_phi;
//assign generated_phi.valid = inv_phi_input_poly.valid;

// Post-INTT: multiply by scaled inverse-phi (includes n^{-1}) to undo phi-twist + normalize.
//phi_gen #(.FWD_INV(1)) u_phi_gen(generated_phi.coefs, generated_phi.valid, clk, reset_n);

//logic [NUM_COEFS_PER_STAGE-1:0] inv_phi_mul_res_valid;
//generate
//    for (genvar gv_i = 0; gv_i < NUM_COEFS_PER_STAGE; gv_i++) begin: inv_phi_modules
//        mod_mul u_inv_phi_mul(
//            inv_phi_input_poly.coefs[gv_i],
//            generated_phi.coefs[gv_i],
//            output_poly.coefs[gv_i],
//            inv_phi_input_poly.valid,
//            inv_phi_mul_res_valid[gv_i],
//            clk,
//            reset_n
//        );
//    end
//endgenerate

//assign output_poly.valid = &inv_phi_mul_res_valid;

// Kyber needs no phi untwist, but the stages above are unscaled and grow every coefficient
// by 2^TOTAL_NUM_STAGES, so the n^{-1} half of that path stays as a constant multiply.
// Restoring the phi path would apply it twice: SCALER is already folded into
// SCALED_INV_PHI_INIT_VALS.
logic [NUM_COEFS_PER_STAGE-1:0] scaler_mul_res_valid;

generate
    for (genvar gv_i = 0; gv_i < NUM_COEFS_PER_STAGE; gv_i++) begin: scaler_muls
        mod_mul u_scaler_mul(
            inv_phi_input_poly.coefs[gv_i],
            MODULUS_WIDTH'(SCALER),
            output_poly.coefs[gv_i],
            inv_phi_input_poly.valid,
            scaler_mul_res_valid[gv_i],
            clk,
            reset_n
        );
    end
endgenerate

assign output_poly.valid = &scaler_mul_res_valid;

endmodule
