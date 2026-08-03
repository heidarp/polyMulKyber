`timescale 1ns/1ps

import ntt_pkg::*;
import modulus_funcs_pkg::*;

module phi_calc #(
    parameter FWD_INV,
    parameter PHI_INIT_VALS_I,
    parameter SCALED_INV_PHI_INIT_VALS_I,
    parameter PHI_INIT_VALS_ADV,
    parameter SCALED_INV_PHI_INIT_VALS_ADV
) (
    input  clk,
    input  reset_n,
    input  phi_cnt_en,
    input  phi_cnt_rst,
    output logic [MODULUS_WIDTH-1:0] advanced_phi_reduced
);

    logic [MODULUS_WIDTH-1:0]   phi_reduced_instance_a;
    logic [2*MODULUS_WIDTH-1:0] R_last_advanced_phi_instance_a;
    logic [2*MODULUS_WIDTH-1:0] next_advanced_phi_cycle_comb_a;
    logic [MODULUS_WIDTH-1:0]   R_phi_reduced_instance_a;

    logic [MODULUS_WIDTH-1:0]   phi_reduced_instance_b;
    logic [2*MODULUS_WIDTH-1:0] R_last_advanced_phi_instance_b;
    logic [2*MODULUS_WIDTH-1:0] next_advanced_phi_cycle_comb_b;
    logic [MODULUS_WIDTH-1:0]   R_phi_reduced_instance_b;

    // Ping-pong: A and B hold consecutive phi powers; R_Sel alternates which is emitted.
    logic R_Sel;

    assign phi_reduced_instance_a = barret_reduce(R_last_advanced_phi_instance_a);

    always @(posedge clk) begin
        if (reset_n == 1'b0) begin
            if (FWD_INV == 0) begin
                R_phi_reduced_instance_a <= PHI_INIT_VALS_I;
                R_last_advanced_phi_instance_a <= PHI_INIT_VALS_I;
            end
            else begin
                R_phi_reduced_instance_a <= SCALED_INV_PHI_INIT_VALS_I;
                R_last_advanced_phi_instance_a <= SCALED_INV_PHI_INIT_VALS_I;
            end
            R_Sel <= '0;
        end
        else begin

            if (phi_cnt_rst) begin
                if (FWD_INV == 0) begin
                    R_phi_reduced_instance_a <= PHI_INIT_VALS_I;
                    R_last_advanced_phi_instance_a <= PHI_INIT_VALS_I;
                end
                else begin
                    R_phi_reduced_instance_a <= SCALED_INV_PHI_INIT_VALS_I;
                    R_last_advanced_phi_instance_a <= SCALED_INV_PHI_INIT_VALS_I;
                    
                end
                R_Sel <= '0;
            end
            else if (phi_cnt_en) begin
                // Advance by ADV_*_PHI_VALUE (phi^(2*step)); emit A/B on alternate cycles.
                R_last_advanced_phi_instance_a <= next_advanced_phi_cycle_comb_a;
                R_phi_reduced_instance_a <= phi_reduced_instance_a;
                R_Sel <= !R_Sel;
            end
        end
    end

    always_comb begin
        next_advanced_phi_cycle_comb_a = R_phi_reduced_instance_a[MODULUS_WIDTH-1:0];
        if (FWD_INV == 0) begin
            next_advanced_phi_cycle_comb_a = R_phi_reduced_instance_a * ADV_PHI_VALUE;
        end
        else begin
            next_advanced_phi_cycle_comb_a = R_phi_reduced_instance_a * ADV_INV_PHI_VALUE;
        end
    end

    assign advanced_phi_reduced = R_Sel ? R_phi_reduced_instance_b : R_phi_reduced_instance_a;

    assign phi_reduced_instance_b = barret_reduce(R_last_advanced_phi_instance_b);

    always @(posedge clk) begin
        if (reset_n == 1'b0) begin
            if (FWD_INV == 0) begin
                R_phi_reduced_instance_b <= PHI_INIT_VALS_ADV;
                R_last_advanced_phi_instance_b <= PHI_INIT_VALS_ADV;
            end
            else begin
                // B seeded one phi-step ahead of A (ADV constants) so R_Sel alternation stays contiguous.
                R_phi_reduced_instance_b <= PHI_INIT_VALS_ADV;
                R_last_advanced_phi_instance_b <= SCALED_INV_PHI_INIT_VALS_ADV;
            end
        end
        else begin
            if (phi_cnt_rst) begin
                if (FWD_INV == 0) begin
                    R_phi_reduced_instance_b <= PHI_INIT_VALS_ADV;
                    R_last_advanced_phi_instance_b <= PHI_INIT_VALS_ADV;
                end
                else begin
                    R_phi_reduced_instance_b <= PHI_INIT_VALS_ADV;
                    R_last_advanced_phi_instance_b <= SCALED_INV_PHI_INIT_VALS_ADV;
                end
            end
            else if (phi_cnt_en) begin
                R_last_advanced_phi_instance_b <= next_advanced_phi_cycle_comb_b;
                R_phi_reduced_instance_b <= phi_reduced_instance_b;
            end
        end
    end

    always_comb begin
        next_advanced_phi_cycle_comb_b = R_last_advanced_phi_instance_b[MODULUS_WIDTH-1:0];
        if (FWD_INV == 0) begin
            next_advanced_phi_cycle_comb_b = R_phi_reduced_instance_b * ADV_PHI_VALUE;
        end
        else begin
            next_advanced_phi_cycle_comb_b = R_phi_reduced_instance_b * ADV_INV_PHI_VALUE;
        end
    end

endmodule
