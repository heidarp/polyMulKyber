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
            localparam DELAY_CALC =
                POLYNOMIAL_LENGTH/((2**(TOTAL_NUM_STAGES - gv_i + 1))*NUM_BUTFLY_PER_STAGE);
            localparam STAGE_DELAY_CLOCKS = (DELAY_CALC < 1) ? 1 : DELAY_CALC;
            localparam ST_NUM_W_CALC = 2**(TOTAL_NUM_STAGES-1-gv_i);
            localparam NUM_W_GENS_CALC =
                ((2**(TOTAL_NUM_STAGES-gv_i + $clog2(NUM_BUTFLY_PER_STAGE)) / POLYNOMIAL_LENGTH) < 1)
                ? 1
                : (2**(TOTAL_NUM_STAGES-gv_i + $clog2(NUM_BUTFLY_PER_STAGE)) / POLYNOMIAL_LENGTH);

            if (gv_i == 0) begin: first_inv_ntt_stage
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

    assign output_poly = inv_phi_input_poly;

endmodule
