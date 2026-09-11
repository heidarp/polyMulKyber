`timescale 1ns/1ps

import ntt_pkg::*;

module forward_ntt(input_poly, output_poly, clk, reset_n);

    input  clk, reset_n;
    input  poly_type input_poly;
    output poly_type output_poly;

    ntt_int_type fntt;

    assign fntt.stage[0].coefs = input_poly.coefs;
    assign fntt.stage[0].valid = input_poly.valid;

    parameter FWD_INV = 0;

    generate
        for (genvar gv_i = 0; gv_i < TOTAL_NUM_STAGES; gv_i++) begin: first_ntt_stage
            localparam DELAY_CALC = POLYNOMIAL_LENGTH/((2**(gv_i+1))*NUM_BUTFLY_PER_STAGE);
            localparam STAGE_DELAY_CLOCKS = (DELAY_CALC < 1) ? 1 : DELAY_CALC;
            localparam NUM_W_GENS_CALC =
                ((2**(gv_i + $clog2(NUM_BUTFLY_PER_STAGE) + 1) / POLYNOMIAL_LENGTH) < 1)
                ? 1
                : (2**(gv_i + $clog2(NUM_BUTFLY_PER_STAGE) + 1) / POLYNOMIAL_LENGTH);

            if (gv_i == 0) begin: first_ntt_stage
                ntt_stage #(
                    .STAGE_INDEX(gv_i),
                    .ST_NUM_W(2**(gv_i)),
                    .DELAY_NUM_CLOCKS(1),
                    .FWD_INV(FWD_INV),
                    .NUM_W_GENS(NUM_W_GENS_CALC),
                    .DPND_FUT_DATA(calc_dpnd_fut_data(gv_i))
                ) u_ntt_stage (
                    fntt.stage[gv_i],
                    fntt.stage[gv_i+1],
                    clk,
                    reset_n
                );
            end
            else if (gv_i == TOTAL_NUM_STAGES-1) begin: last_ntt_stage
                ntt_stage #(
                    .STAGE_INDEX(gv_i),
                    .ST_NUM_W(2**(gv_i)),
                    .DELAY_NUM_CLOCKS(STAGE_DELAY_CLOCKS),
                    .FWD_INV(FWD_INV),
                    .NUM_W_GENS(NUM_W_GENS_CALC),
                    .DPND_FUT_DATA(calc_dpnd_fut_data(gv_i))
                ) u_ntt_stage (
                    fntt.stage[gv_i],
                    output_poly,
                    clk,
                    reset_n
                );
            end
            else begin: other_stages
                ntt_stage #(
                    .STAGE_INDEX(gv_i),
                    .ST_NUM_W(2**(gv_i)),
                    .DELAY_NUM_CLOCKS(STAGE_DELAY_CLOCKS),
                    .FWD_INV(FWD_INV),
                    .NUM_W_GENS(NUM_W_GENS_CALC),
                    .DPND_FUT_DATA(calc_dpnd_fut_data(gv_i))
                ) u_ntt_stage (
                    fntt.stage[gv_i],
                    fntt.stage[gv_i+1],
                    clk,
                    reset_n
                );
            end
        end
    endgenerate

endmodule
