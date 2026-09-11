`timescale 1ns/1ps

import ntt_pkg::*;

module point_mul(fwd_ntt_res_x, fwd_ntt_res_y, point_mul_reseult, clk, reset_n);

    input  clk, reset_n;
    input  poly_type fwd_ntt_res_x;
    input  poly_type fwd_ntt_res_y;
    output poly_type point_mul_reseult;

    logic point_mul_input_valid;
    assign point_mul_input_valid = fwd_ntt_res_x.valid && fwd_ntt_res_y.valid;

    generate
        if (NUM_BUTFLY_PER_STAGE == 1) begin : serial_pairs

            basemul_poly_type [NUM_COEFS_PER_STAGE-1:0] fifo_x, fifo_y;
            logic R_pair_phase;
            logic R_pair_valid;

            always @(posedge clk) begin
                if (reset_n == 1'b0) begin
                    for (int i = 0; i < NUM_COEFS_PER_STAGE; i++) begin
                        fifo_x[i].coefs <= '0;
                        fifo_y[i].coefs <= '0;
                    end
                    R_pair_phase <= 1'b0;
                    R_pair_valid <= 1'b0;
                end
                else begin
                    if (point_mul_input_valid) begin
                        for (int i = 0; i < NUM_COEFS_PER_STAGE; i++) begin
                            fifo_x[i].coefs[0] <= fwd_ntt_res_x.coefs[i];
                            fifo_y[i].coefs[0] <= fwd_ntt_res_y.coefs[i];
                            fifo_x[i].coefs[1] <= fifo_x[i].coefs[0];
                            fifo_y[i].coefs[1] <= fifo_y[i].coefs[0];
                        end
                        R_pair_phase <= ~R_pair_phase;
                    end
                    R_pair_valid <= point_mul_input_valid & R_pair_phase;
                end
            end

            for (genvar gv_v = 0; gv_v < NUM_COEFS_PER_STAGE; gv_v++) begin
                assign fifo_x[gv_v].valid = R_pair_valid;
                assign fifo_y[gv_v].valid = R_pair_valid;
            end

            localparam int W_ADV_DEPTH = MUL_PIPE_DEPTH + 1;

            logic [W_ADV_DEPTH-1:0] R_generate_new_w;

            always @(posedge clk) begin
                if (reset_n == 1'b0) begin
                    R_generate_new_w <= '0;
                end
                else begin
                    R_generate_new_w[0] <= point_mul_input_valid & ~R_pair_phase;
                    for (int i = 0; i < W_ADV_DEPTH-1; i++) begin
                        R_generate_new_w[i+1] <= R_generate_new_w[i];
                    end
                end
            end

            logic [NUM_BUTFLY_PER_STAGE-1:0] [MODULUS_WIDTH-1:0] generated_w;

            w_gen #(
                .CNT_RST_VALUE(2**(TOTAL_NUM_STAGES-1)),
                .STAGE_INDEX(TOTAL_NUM_STAGES-1),
                .FWD_INV(0),
                .NUM_W_GENS(1)
            ) u_w_gen(generated_w, R_generate_new_w[W_ADV_DEPTH-1], clk, reset_n);

            basemul_poly_type [NUM_COEFS_PER_STAGE-1:0] basemul_result;
            logic [NUM_COEFS_PER_STAGE-1:0][MODULUS_WIDTH-1:0] R_r1_hold;
            logic R_ser_phase;

            for (genvar gv_i = 0; gv_i < NUM_COEFS_PER_STAGE; gv_i++) begin : point_muls
                basemul u_basemul(
                    fifo_x[gv_i],
                    fifo_y[gv_i],
                    generated_w[0],
                    basemul_result[gv_i],
                    clk,
                    reset_n,
                    (gv_i % 2 == 1)
                );
            end

            logic [NUM_COEFS_PER_STAGE-1:0] basemul_valid_vec;
            logic base_multiplication_results_valid;

            always_comb begin
                for (int i = 0; i < NUM_COEFS_PER_STAGE; i++) begin
                    basemul_valid_vec[i] = basemul_result[i].valid;
                end
            end

            assign base_multiplication_results_valid = &basemul_valid_vec;

            always @(posedge clk) begin
                if (reset_n == 1'b0) begin
                    R_r1_hold   <= '0;
                    R_ser_phase <= 1'b0;
                end
                else begin
                    if (base_multiplication_results_valid) begin
                        for (int i = 0; i < NUM_COEFS_PER_STAGE; i++) begin
                            R_r1_hold[i] <= basemul_result[i].coefs[1];
                        end
                    end
                    R_ser_phase <= base_multiplication_results_valid;
                end
            end

            always_comb begin
                for (int i = 0; i < NUM_COEFS_PER_STAGE; i++) begin
                    point_mul_reseult.coefs[i] = base_multiplication_results_valid
                        ? basemul_result[i].coefs[0]
                        : R_r1_hold[i];
                end
            end

            assign point_mul_reseult.valid = base_multiplication_results_valid | R_ser_phase;

        end
        else begin : parallel_pairs

            logic [NUM_COEFS_PER_STAGE-1:0][MODULUS_WIDTH-1:0] R_x, R_y;
            logic R_pair_valid;

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

            localparam int W_ADV_DEPTH = MUL_PIPE_DEPTH + 1;

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

            w_gen #(
                .CNT_RST_VALUE(2**(TOTAL_NUM_STAGES-1)),
                .STAGE_INDEX(TOTAL_NUM_STAGES-1),
                .FWD_INV(0),
                .NUM_W_GENS(NUM_BUTFLY_PER_STAGE/2)
            ) u_w_gen(generated_w, R_generate_new_w[W_ADV_DEPTH-1], clk, reset_n);

            basemul_poly_type [NUM_BUTFLY_PER_STAGE-1:0] basemul_result;

            for (genvar gv_g = 0; gv_g < NUM_BUTFLY_PER_STAGE/2; gv_g++) begin : quads
                for (genvar gv_s = 0; gv_s < 2; gv_s++) begin : sides
                    basemul_poly_type pair_x, pair_y;

                    assign pair_x.coefs[1] = R_x[4*gv_g + gv_s];
                    assign pair_x.coefs[0] = R_x[4*gv_g + 2 + gv_s];
                    assign pair_y.coefs[1] = R_y[4*gv_g + gv_s];
                    assign pair_y.coefs[0] = R_y[4*gv_g + 2 + gv_s];
                    assign pair_x.valid    = R_pair_valid;
                    assign pair_y.valid    = R_pair_valid;

                    basemul u_basemul(
                        pair_x,
                        pair_y,
                        generated_w[2*gv_g],
                        basemul_result[2*gv_g + gv_s],
                        clk,
                        reset_n,
                        (gv_s == 1)
                    );

                    assign point_mul_reseult.coefs[4*gv_g + gv_s]     = basemul_result[2*gv_g + gv_s].coefs[0];
                    assign point_mul_reseult.coefs[4*gv_g + 2 + gv_s] = basemul_result[2*gv_g + gv_s].coefs[1];
                end
            end

            always_comb begin
                point_mul_reseult.valid = 1'b1;
                for (int i = 0; i < NUM_BUTFLY_PER_STAGE; i++) begin
                    point_mul_reseult.valid &= basemul_result[i].valid;
                end
            end

        end
    endgenerate

endmodule
