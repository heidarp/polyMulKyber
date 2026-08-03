`timescale 1ns/1ps

import ntt_pkg::*;

module ntt_stage #(
    parameter STAGE_INDEX,
    parameter ST_NUM_W,
    parameter DELAY_NUM_CLOCKS,
    parameter FWD_INV,
    parameter NUM_W_GENS,
    parameter DPND_FUT_DATA
) (
    input_poly,
    ouput_poly,
    clk,
    reset_n
);

input  poly_type input_poly;
output wire poly_type ouput_poly;
input  clk, reset_n;

// valid must wait for both the stage FIFO delay and the butterfly mul+reduce latency.
localparam VALID_DLY_DEPTH = DELAY_NUM_CLOCKS + PIPELINED_MUL_RED_DELAY;
localparam CNT_WIDTH = $clog2(DELAY_NUM_CLOCKS);

// Coefficient span between butterfly partners when this stage only reorders (no fut-data mux).
localparam int NEXT_COEF_LOC_NO_DPND =
    (FWD_INV == 0) ? (POLYNOMIAL_LENGTH / ST_NUM_W)
                   : ((ST_NUM_W < NUM_COEFS_PER_STAGE) ? ST_NUM_W : 0);

typedef struct packed {
    logic [DELAY_NUM_CLOCKS-1:0] [MODULUS_WIDTH-1:0] in_fifo;
} ripple_fifo_type;

ripple_fifo_type [NUM_COEFS_PER_STAGE-1:0] R_ripple_fifo;

logic [NUM_COEFS_PER_STAGE-1:0] [MODULUS_WIDTH-1:0] seleced_input_for_fifo;
logic [NUM_COEFS_PER_STAGE-1:0] [MODULUS_WIDTH-1:0] seleced_input_for_butterfly;

logic R_fifo_mux_sel;

// Swap bit 0 with bit swap_index to pair lanes that are NEXT_COEF_LOC apart.
localparam int swap_index = $clog2(NEXT_COEF_LOC_NO_DPND);
localparam int swap_mask  = (1 << swap_index) | 1;

generate
    // DPND_FUT_DATA: FIFO holds half a butterfly pair; other half comes from live/current input.
    if (DPND_FUT_DATA == 1) begin
        for (genvar gv_i = 0; gv_i < NUM_COEFS_PER_STAGE; gv_i = gv_i+2) begin: fifo_in_mux
            // Stage 0 inverts mux polarity vs later stages (different stream arrival order).
            assign seleced_input_for_fifo[gv_i] =
                ((STAGE_INDEX == 0) ? !R_fifo_mux_sel : R_fifo_mux_sel) ? input_poly.coefs[gv_i] : input_poly.coefs[gv_i+1];
            assign seleced_input_for_fifo[gv_i+1] =
                ((STAGE_INDEX == 0) ? R_fifo_mux_sel : !R_fifo_mux_sel) ? input_poly.coefs[gv_i] : input_poly.coefs[gv_i+1];
            // Alternate which FIFO lane is "a" vs "b", and whether "b" is FIFO or live input.
            assign seleced_input_for_butterfly[gv_i] =
                !R_fifo_mux_sel ? R_ripple_fifo[gv_i].in_fifo[DELAY_NUM_CLOCKS-1]
                       : R_ripple_fifo[gv_i+1].in_fifo[DELAY_NUM_CLOCKS-1];
            assign seleced_input_for_butterfly[gv_i+1] =
                !R_fifo_mux_sel ? input_poly.coefs[gv_i]
                       : R_ripple_fifo[gv_i].in_fifo[DELAY_NUM_CLOCKS-1];
        end
    end
    else begin
        // No fut-data dependency: permute coefficients into butterfly order, then delay all lanes equally.
        for (genvar gv_i = 0; gv_i < NUM_COEFS_PER_STAGE; gv_i = gv_i+1) begin : fifo_idx_swap
            localparam int gv_i_swap =
                (gv_i & ~swap_mask)
              | (gv_i[0] << swap_index)
              | gv_i[swap_index];
            assign seleced_input_for_fifo[gv_i] = input_poly.coefs[gv_i_swap];
        end

        for (genvar gv_j = 0; gv_j < NUM_BUTFLY_PER_STAGE * 2; gv_j = gv_j+1) begin: butterfly_mux
            assign seleced_input_for_butterfly[gv_j] = R_ripple_fifo[gv_j].in_fifo[DELAY_NUM_CLOCKS-1];
        end
    end
endgenerate

logic [NUM_BUTFLY_PER_STAGE-1:0] [MODULUS_WIDTH-1:0] generated_w;
logic generate_new_w;
logic [VALID_DLY_DEPTH-1:0] R_out_valid_dly;

assign ouput_poly.valid = R_out_valid_dly[VALID_DLY_DEPTH-1];

logic fifo_cnt_en;
logic fifo_cnt_rst;
logic [CNT_WIDTH-1:0] R_fifo_cnt;

generate
    // Forward: advance twiddles once per FIFO half-block (when fifo_cnt wraps).
    if (FWD_INV == 0) begin: generate_w_on_cnt_reset
        w_gen #(
            .CNT_RST_VALUE(ST_NUM_W),
            .STAGE_INDEX(STAGE_INDEX),
            .FWD_INV(0),
            .NUM_W_GENS(NUM_W_GENS)
        ) u_w_gen(generated_w, generate_new_w, clk, reset_n);
        assign generate_new_w = fifo_cnt_rst;
    end
    else begin: generate_w_each_clock_starting_from_a_delay
        // Inverse: twiddles change every valid beat; align start to FIFO fill when delayed.
        w_gen #(
            .CNT_RST_VALUE(ST_NUM_W),
            .STAGE_INDEX(STAGE_INDEX),
            .FWD_INV(1),
            .NUM_W_GENS(NUM_W_GENS)
        ) u_inv_w_gen(generated_w, generate_new_w, clk, reset_n);

        if (DPND_FUT_DATA == 0) begin
            assign generate_new_w = input_poly.valid;
        end
        else if (DELAY_NUM_CLOCKS == 1) begin
            assign generate_new_w = input_poly.valid;
        end
        else begin
            // Start W updates after FIFO has almost filled so butterflies see matching twiddles.
            assign generate_new_w = R_out_valid_dly[DELAY_NUM_CLOCKS-2];
        end
    end
endgenerate

generate
    for (genvar gv_i = 0; gv_i < NUM_COEFS_PER_STAGE; gv_i = gv_i+2) begin: bu_moduls
        butterfly u_butterfly(
            seleced_input_for_butterfly[gv_i],
            seleced_input_for_butterfly[gv_i+1],
            ouput_poly.coefs[gv_i],
            ouput_poly.coefs[gv_i+1],
            generated_w[gv_i/2],
            clk,
            reset_n
        );
    end
endgenerate

always @(posedge clk) begin
    if (reset_n == 1'b0) begin
        R_out_valid_dly <= '0;
    end
    else begin
        R_out_valid_dly[0] <= input_poly.valid;
        for (int i = 0; i < (VALID_DLY_DEPTH-1); i++) begin
            R_out_valid_dly[i+1] <= R_out_valid_dly[i];
        end
    end
end

always_comb begin
    fifo_cnt_en = input_poly.valid;
    fifo_cnt_rst = '0;
    // Count valid beats within one FIFO window; wrap marks half-block boundary.
    if (R_fifo_cnt == DELAY_NUM_CLOCKS-1 && input_poly.valid) begin
        fifo_cnt_rst = '1;
    end
    else begin
        fifo_cnt_rst = '0;
    end
end

always @(posedge clk) begin
    if (reset_n == 1'b0) begin
        R_fifo_cnt <= '0;
        R_fifo_mux_sel <= '1;
    end
    else begin
        if (fifo_cnt_rst == 1) begin
            R_fifo_cnt <= '0;
        end
        else if (fifo_cnt_en) begin
            R_fifo_cnt <= R_fifo_cnt + 1;
        end

        // Toggle pairing mux each window except stage 0 / no-dpnd (fixed mux polarity).
        if (R_fifo_cnt == DELAY_NUM_CLOCKS-1 && input_poly.valid) begin
            R_fifo_mux_sel <= (STAGE_INDEX == 0 || (DPND_FUT_DATA == 0)) ? 1 : !R_fifo_mux_sel;
        end
    end
end

always @(posedge clk) begin
    if (reset_n == 1'b0) begin
        R_ripple_fifo <= '0;
    end
    else begin
        // Even lanes always shift; odd lanes only when mux_sel so they store the alternate half-pair.
        for (int j = 0; j < NUM_COEFS_PER_STAGE; j = j+2) begin
            R_ripple_fifo[j].in_fifo[0] <= seleced_input_for_fifo[j];
            for (int i = 0; i < (DELAY_NUM_CLOCKS-1); i++) begin
                R_ripple_fifo[j].in_fifo[i+1] <= R_ripple_fifo[j].in_fifo[i];
            end
        end
            if (R_fifo_mux_sel) begin
                for (int j = 1; j < NUM_COEFS_PER_STAGE; j = j+2) begin
                    R_ripple_fifo[j].in_fifo[0] <= seleced_input_for_fifo[j];
                    for (int i = 0; i < (DELAY_NUM_CLOCKS-1); i++) begin
                        R_ripple_fifo[j].in_fifo[i+1] <= R_ripple_fifo[j].in_fifo[i];
                    end
                end
            
        end
    end
end

endmodule
