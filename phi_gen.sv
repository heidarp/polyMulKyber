`timescale 1ns/1ps

import ntt_pkg::*;

module phi_gen #(
    parameter FWD_INV
) (
    generated_phis,
    input_valid,
    clk,
    reset_n
);

output [NUM_COEFS_PER_STAGE-1:0] [MODULUS_WIDTH-1:0] generated_phis;
input input_valid, clk, reset_n;

logic phi_cnt_en;
logic phi_cnt_rst;
logic [PHI_S1_CNT_WIDTH-1:0] R_phi_cnt;

always_comb begin
    phi_cnt_rst = '0;
    // End of half-polynomial (N/2 - lane_offset); reload phi seeds for next poly block.
    if (R_phi_cnt == PHI_S1_DELAY_NUM_CLOCKS) begin
        phi_cnt_rst = '1;
    end
    else begin
        phi_cnt_rst = '0;
    end
end

assign phi_cnt_en = input_valid;

always @(posedge clk) begin
    if (reset_n == 1'b0) begin
        R_phi_cnt <= '0;
    end
    else begin
        if (phi_cnt_rst == 1) begin
            R_phi_cnt <= '0;
        end
        else if (phi_cnt_en) begin
            // Half of the streamed coeffs are "new" phi steps this beat (A/B ping-pong covers rest).
            R_phi_cnt <= R_phi_cnt + NUM_COEFS_PER_STAGE/2;
        end
    end
end

logic [NUM_COEFS_PER_STAGE-1:0] [MODULUS_WIDTH-1:0] current_phi_reduced;

generate
    for (genvar gv_i = 0; gv_i < NUM_COEFS_PER_STAGE; gv_i++) begin : phi_calc_modules
        phi_calc #(
            .FWD_INV(FWD_INV),
            .PHI_INIT_VALS_I(PHI_INIT_VALS[gv_i]),
            .SCALED_INV_PHI_INIT_VALS_I(SCALED_INV_PHI_INIT_VALS[gv_i]),
            .PHI_INIT_VALS_ADV(PHI_INIT_VALS_ADVANNCED[gv_i]),
            .SCALED_INV_PHI_INIT_VALS_ADV(SCALED_INV_PHI_INIT_VALS_ADVANNCED[gv_i])
        ) u_phi_calc (
            .clk(clk),
            .phi_cnt_en(phi_cnt_en),
            .phi_cnt_rst(phi_cnt_rst),
            .reset_n(reset_n),
            .advanced_phi_reduced(current_phi_reduced[gv_i])
        );
    end
endgenerate

generate
    for (genvar gv_i = 0; gv_i < NUM_COEFS_PER_STAGE; gv_i++) begin: assign_phis_to_output
        assign generated_phis[gv_i] = current_phi_reduced[gv_i];
    end
endgenerate

endmodule
