`timescale 1ns/1ps

import ntt_pkg::*;

module w_gen #(
    parameter CNT_RST_VALUE,
    parameter STAGE_INDEX,
    parameter FWD_INV,
    parameter NUM_W_GENS
) (
    generated_w,
    input_valid,
    clk,
    reset_n
);

output [NUM_BUTFLY_PER_STAGE-1:0] [MODULUS_WIDTH-1:0] generated_w;
input clk, input_valid, reset_n;

logic w_cnt_en;
logic w_cnt_rst;
logic [PHI_S1_CNT_WIDTH-1:0] R_w_cnt;

always_comb begin
    w_cnt_en = input_valid;
    w_cnt_rst = '0;
    // Wrap after issuing CNT_RST_VALUE distinct twiddle indices (stepped by NUM_W_GENS).
    if ((R_w_cnt == CNT_RST_VALUE - NUM_W_GENS) && input_valid) begin
        w_cnt_rst = '1;
    end
    else begin
        w_cnt_rst = '0;
    end
end

always @(posedge clk) begin
    if (reset_n == 1'b0) begin
        // Prefill so the first valid beat lands on twiddle index 0 after +NUM_W_GENS.
        R_w_cnt <= '1 - NUM_W_GENS + 1;
    end
    else begin
        if (w_cnt_rst == 1) begin
            R_w_cnt <= 0;
        end
        else if (w_cnt_en) begin
            R_w_cnt <= R_w_cnt + NUM_W_GENS;
        end
    end
end

logic [NUM_W_GENS-1:0][MODULUS_WIDTH-1:0] comb_w_calc;

generate
    for (genvar bf = 0; bf < NUM_W_GENS; bf++) begin : gen_w
        w_calc #(
            .STAGE_INDEX(STAGE_INDEX),
            .FWD_INV(FWD_INV),
            .BF_INDEX(bf)
        ) u_w_calc (
            .w_cnt(R_w_cnt),
            .comb_w_calc(comb_w_calc[bf])
        );
    end
endgenerate

generate
    if (NUM_W_GENS == 1) begin
        // Single generator: every parallel butterfly shares the same twiddle this beat.
        for (genvar w_i = 0; w_i < NUM_BUTFLY_PER_STAGE; w_i++) begin : replicate_generated_ws
            assign generated_w[w_i] =  comb_w_calc[0];
        end
    end
    else begin
        if (FWD_INV == 0) begin
            // Forward: contiguous butterfly groups share one of the NUM_W_GENS values.
            for (genvar bf = 0; bf < NUM_W_GENS; bf++) begin : multiple_generated_ws
                for (genvar w_i = bf*NUM_BUTFLY_PER_STAGE/NUM_W_GENS;
                     w_i < (1+bf)*NUM_BUTFLY_PER_STAGE/NUM_W_GENS;
                     w_i++) begin : replicate_generated_ws
                    assign generated_w[w_i] = comb_w_calc[bf];
                end
            end
        end
        else begin
            // Inverse: stride mapping — twiddle bf goes to butterflies bf, bf+NUM_W_GENS, ...
            for (genvar bf = 0; bf < NUM_W_GENS; bf++) begin : multiple_generated_ws_fwd
                for (genvar w_i = bf; w_i < NUM_BUTFLY_PER_STAGE; w_i += NUM_W_GENS) begin : stride_generated_ws
                    assign generated_w[w_i] = comb_w_calc[bf];
                end
            end
        end
    end
endgenerate

endmodule
