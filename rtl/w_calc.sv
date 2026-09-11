`timescale 1ns/1ps

import ntt_pkg::*;
import modulus_funcs_pkg::*;

module w_calc #(
    parameter STAGE_INDEX,
    parameter FWD_INV,
    parameter BF_INDEX = 0
) (
    input  logic [PHI_S1_CNT_WIDTH-1:0] w_cnt,
    output logic [MODULUS_WIDTH-1:0]     comb_w_calc
);

    localparam int LAYER_INDEX =
        (FWD_INV == 0) ? STAGE_INDEX : (TOTAL_NUM_STAGES - 1 - STAGE_INDEX);

    localparam logic [PHI_S1_CNT_WIDTH-1:0] KYBER_HALF_STEP =
        PHI_HALF_LENGTH >> (LAYER_INDEX + 1);

    logic [PHI_S1_CNT_WIDTH-1:0] cnt_inverted_shifted;
    logic [PHI_S1_CNT_WIDTH-1:0] zeta_index;
    logic [2*MODULUS_WIDTH-1:0]  shifted_w_comb;
    logic [MODULUS_WIDTH-1:0]    comb_w_reduced;

    always_comb begin
        logic [PHI_S1_CNT_WIDTH-1:0] bf_counter;
        bf_counter = w_cnt + BF_INDEX;

        if (FWD_INV == 0) begin
            for (int p = 0; p < PHI_S1_CNT_WIDTH; p++) begin
                cnt_inverted_shifted[p] = bf_counter[(PHI_S1_CNT_WIDTH-1)-p];
            end
        end
        else begin
            for (int p = 0; p < PHI_S1_CNT_WIDTH; p++) begin
                cnt_inverted_shifted[p] = bf_counter[(PHI_S1_CNT_WIDTH-1)-p];
            end
        end

        zeta_index = cnt_inverted_shifted + KYBER_HALF_STEP;

        comb_w_reduced = 1;
        for (int k = 0; k < zeta_index; k++) begin
            shifted_w_comb = (FWD_INV == 0)
                ? fwd_w0_multiply(comb_w_reduced)
                : inv_w0_multiply(comb_w_reduced);

            comb_w_reduced = barret_reduce(shifted_w_comb);
        end

        comb_w_calc = comb_w_reduced;
    end

endmodule
