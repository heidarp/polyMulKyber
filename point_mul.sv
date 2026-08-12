`timescale 1ns/1ps

import ntt_pkg::*;

// Product in the NTT domain == negacyclic poly multiply after INTT. Kyber's transform is
// incomplete, so each "point" is a degree-1 residue rather than a scalar.
//
// The last forward stage emits the 128 degree-1 residues in a fixed interleaved order that
// depends on NUM_BUTFLY_PER_STAGE:
//
//   NBF=1 : beat 2k carries (c[4k], c[4k+2]), beat 2k+1 carries (c[4k+1], c[4k+3]).
//           Each lane therefore needs two consecutive beats to form one residue pair;
//           the two lanes of a quad share a gamma magnitude (odd lane takes -gamma).
//
//   NBF>=2: every beat already holds whole quads
//           [c[4q], c[4q+2], c[4q+1], c[4q+3]] for q = beat*(NBF/2) .. .
//           Pairing is done within the beat (coefs[4g+s] with coefs[4g+2+s]), and
//           NBF/2 distinct gammas are consumed per beat.
//
// A gamma is needed once per pair, not once per coefficient. The pulse into w_gen is
// delayed until that pair's Karatsuba products land inside basemul, which leaves gamma
// settled on the next cycle, when the gamma multiplier samples it.
module point_mul(fwd_ntt_res_x, fwd_ntt_res_y, point_mul_reseult, clk, reset_n);
input  clk, reset_n;
input  poly_type fwd_ntt_res_x;
input  poly_type fwd_ntt_res_y;
output poly_type point_mul_reseult;

logic point_mul_input_valid;
assign point_mul_input_valid = fwd_ntt_res_x.valid && fwd_ntt_res_y.valid;

generate
if (NUM_BUTFLY_PER_STAGE == 1) begin : serial_pairs

    // -------------------------------------------------------------------------
    // Pair assembly across two consecutive beats
    // -------------------------------------------------------------------------

    logic [NUM_COEFS_PER_STAGE-1:0][1:0][MODULUS_WIDTH-1:0] fifo_x, fifo_y;

    // 0: the next valid beat carries a0; 1: it carries a1 and completes the pair.
    logic R_pair_phase;
    logic R_pair_valid;

    always @(posedge clk) begin
        if (reset_n == 1'b0) begin
            fifo_x       <= '0;
            fifo_y       <= '0;
            R_pair_phase <= 1'b0;
            R_pair_valid <= 1'b0;
        end
        else begin
            if (point_mul_input_valid) begin
                for (int i = 0; i < NUM_COEFS_PER_STAGE; i++) begin
                    fifo_x[i][0] <= fwd_ntt_res_x.coefs[i];
                    fifo_y[i][0] <= fwd_ntt_res_y.coefs[i];
                    fifo_x[i][1] <= fifo_x[i][0];
                    fifo_y[i][1] <= fifo_y[i][0];
                end
                R_pair_phase <= ~R_pair_phase;
            end
            R_pair_valid <= point_mul_input_valid & R_pair_phase;
        end
    end

    // -------------------------------------------------------------------------
    // Twiddle generator: one gamma per pair, delayed to meet the gamma multiply
    // -------------------------------------------------------------------------

    logic [PIPELINED_MUL_RED_EXTRA-1:0] R_generate_new_w;

    always @(posedge clk) begin
        if (reset_n == 1'b0) begin
            R_generate_new_w <= '0;
        end
        else begin
            // Advance on the beat that opens a new pair (phase 0), not the one that closes it.
            R_generate_new_w[0] <= point_mul_input_valid & ~R_pair_phase;
            for (int i = 0; i < PIPELINED_MUL_RED_EXTRA-1; i++) begin
                R_generate_new_w[i+1] <= R_generate_new_w[i];
            end
        end
    end

    logic [NUM_BUTFLY_PER_STAGE-1:0] [MODULUS_WIDTH-1:0] generated_w;

    // 64 residue pairs per lane, driven by the twiddles of the last forward stage.
    w_gen #(
        .CNT_RST_VALUE(2**(TOTAL_NUM_STAGES-1)),
        .STAGE_INDEX(TOTAL_NUM_STAGES-1),
        .FWD_INV(0),
        .NUM_W_GENS(1)
    ) u_w_gen(generated_w, R_generate_new_w[PIPELINED_MUL_RED_EXTRA-1], clk, reset_n);

    // -------------------------------------------------------------------------
    // Basemuls + two-beat serialiser (c0 on the first result beat, c1 on the next)
    // -------------------------------------------------------------------------

    logic [NUM_COEFS_PER_STAGE-1:0][MODULUS_WIDTH-1:0] bm_r0, bm_r1;
    logic [NUM_COEFS_PER_STAGE-1:0]                    bm_valid;
    logic [NUM_COEFS_PER_STAGE-1:0][MODULUS_WIDTH-1:0] R_r1_hold;
    logic                                             R_ser_phase;

    for (genvar gv_i = 0; gv_i < NUM_COEFS_PER_STAGE; gv_i++) begin: point_muls
        basemul u_basemul(
            fifo_x[gv_i],
            fifo_y[gv_i],
            generated_w[0],
            bm_r0[gv_i],
            bm_r1[gv_i],
            R_pair_valid,
            bm_valid[gv_i],
            clk,
            reset_n,
            (gv_i % 2 == 1)
        );
    end

    always @(posedge clk) begin
        if (reset_n == 1'b0) begin
            R_r1_hold   <= '0;
            R_ser_phase <= 1'b0;
        end
        else begin
            // Pairs are two beats apart, so the two result flags never overlap.
            if (bm_valid[0]) begin
                for (int i = 0; i < NUM_COEFS_PER_STAGE; i++) begin
                    R_r1_hold[i] <= bm_r1[i];
                end
            end
            R_ser_phase <= bm_valid[0];
        end
    end

    always_comb begin
        for (int i = 0; i < NUM_COEFS_PER_STAGE; i++) begin
            point_mul_reseult.coefs[i] = bm_valid[0] ? bm_r0[i] : R_r1_hold[i];
        end
    end

    assign point_mul_reseult.valid = bm_valid[0] | R_ser_phase;

end
else begin : parallel_pairs

    // -------------------------------------------------------------------------
    // Capture the whole beat; every quad is already a ready pair of residues
    // -------------------------------------------------------------------------

    logic [NUM_COEFS_PER_STAGE-1:0][MODULUS_WIDTH-1:0] R_x, R_y;
    logic                                             R_pair_valid;

    always @(posedge clk) begin
        if (reset_n == 1'b0) begin
            R_x          <= '0;
            R_y          <= '0;
            R_pair_valid <= 1'b0;
        end
        else begin
            if (point_mul_input_valid) begin
                for (int i = 0; i < NUM_COEFS_PER_STAGE; i++) begin
                    R_x[i] <= fwd_ntt_res_x.coefs[i];
                    R_y[i] <= fwd_ntt_res_y.coefs[i];
                end
            end
            R_pair_valid <= point_mul_input_valid;
        end
    end

    // -------------------------------------------------------------------------
    // Twiddle generator: NBF/2 distinct gammas per beat
    // -------------------------------------------------------------------------

    // Input capture already contributes one cycle of delay, so the advance chain is
    // one shorter than the serial path: gamma still meets R_kara_valid inside basemul.
    localparam int W_ADV_DEPTH = PIPELINED_MUL_RED_EXTRA - 1;

    logic [W_ADV_DEPTH-1:0] R_generate_new_w;

    always @(posedge clk) begin
        if (reset_n == 1'b0) begin
            R_generate_new_w <= '0;
        end
        else begin
            R_generate_new_w[0] <= point_mul_input_valid;
            for (int i = 0; i < W_ADV_DEPTH-1; i++) begin
                R_generate_new_w[i+1] <= R_generate_new_w[i];
            end
        end
    end

    logic [NUM_BUTFLY_PER_STAGE-1:0] [MODULUS_WIDTH-1:0] generated_w;

    // Last forward stage needs NBF/2 distinct twiddles per beat (one gamma per quad).
    w_gen #(
        .CNT_RST_VALUE(2**(TOTAL_NUM_STAGES-1)),
        .STAGE_INDEX(TOTAL_NUM_STAGES-1),
        .FWD_INV(0),
        .NUM_W_GENS(NUM_BUTFLY_PER_STAGE/2)
    ) u_w_gen(generated_w, R_generate_new_w[W_ADV_DEPTH-1], clk, reset_n);

    // -------------------------------------------------------------------------
    // One basemul per residue pair; both results land in the same beat
    // -------------------------------------------------------------------------

    // NUM_BUTFLY_PER_STAGE pairs per beat (two per quad).
    logic [NUM_BUTFLY_PER_STAGE-1:0][MODULUS_WIDTH-1:0] bm_r0, bm_r1;
    logic [NUM_BUTFLY_PER_STAGE-1:0]                    bm_valid;

    for (genvar gv_g = 0; gv_g < NUM_BUTFLY_PER_STAGE/2; gv_g++) begin: quads
        for (genvar gv_s = 0; gv_s < 2; gv_s++) begin: sides
            // Lane layout of a quad: [c0, c2, c1, c3]. Side s pairs
            // coefs[4g+s] (= a0) with coefs[4g+2+s] (= a1). basemul wants
            // fifo[1]=a0 and fifo[0]=a1, matching the serial path's shift register.
            logic [1:0][MODULUS_WIDTH-1:0] pair_x, pair_y;
            assign pair_x[1] = R_x[4*gv_g + gv_s];
            assign pair_x[0] = R_x[4*gv_g + 2 + gv_s];
            assign pair_y[1] = R_y[4*gv_g + gv_s];
            assign pair_y[0] = R_y[4*gv_g + 2 + gv_s];

            basemul u_basemul(
                pair_x,
                pair_y,
                point_mul_w[2*gv_g],
                bm_r0[2*gv_g + gv_s],
                bm_r1[2*gv_g + gv_s],
                R_pair_valid,
                bm_valid[2*gv_g + gv_s],
                clk,
                reset_n,
                (gv_s == 1)
            );

            assign point_mul_reseult.coefs[4*gv_g + gv_s]     = bm_r0[2*gv_g + gv_s];
            assign point_mul_reseult.coefs[4*gv_g + 2 + gv_s] = bm_r1[2*gv_g + gv_s];
        end
    end

    assign point_mul_reseult.valid = &bm_valid;

end
endgenerate

endmodule
