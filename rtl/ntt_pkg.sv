`timescale 1ns/1ps
`ifndef PARAMETERS_VH
`define PARAMETERS_VH
package ntt_pkg;

    localparam MODULUS              = 3329;
    localparam POLYNOMIAL_LENGTH    = 256;
    localparam W_VALUE              = 17;
    localparam INV_W_VALUE          = 1175;
`ifndef NUM_BUTFLY_PER_STAGE
    localparam NUM_BUTFLY_PER_STAGE = 1;
`else
    localparam NUM_BUTFLY_PER_STAGE = `NUM_BUTFLY_PER_STAGE;
`endif
    localparam MUL_PIPE_DEPTH       = 3;
    localparam PHI_VALUE_POW_1      = 2016;
    localparam INV_PHI_VALUE_POW_1  = 998612;
    localparam SCALER               = 3303;
    localparam PHI_HALF_LENGTH      = 128;
    localparam PIPELINED_MUL_RED_EXTRA = 3;

    localparam MODULUS_WIDTH = $clog2(MODULUS);
    localparam [MODULUS_WIDTH-1:0] MODULUS_BIN = MODULUS;

    localparam TOTAL_NUM_STAGES = $clog2(POLYNOMIAL_LENGTH) - 1;
    localparam NUM_COEFS_PER_STAGE = 2*NUM_BUTFLY_PER_STAGE;

    localparam PHI_S1_CNT_WIDTH = $clog2(PHI_HALF_LENGTH);

    localparam PIPELINED_MUL_RED_DELAY = MUL_PIPE_DEPTH + PIPELINED_MUL_RED_EXTRA;

    typedef struct packed {
        logic [NUM_BUTFLY_PER_STAGE*2-1:0] [MODULUS_WIDTH-1:0] coefs;
        logic                              valid;
    } poly_type;

    typedef struct packed {
        logic [1:0] [MODULUS_WIDTH-1:0] coefs;
        logic                           valid;
    } basemul_poly_type;

    typedef struct packed {
        poly_type [TOTAL_NUM_STAGES-1:0] stage;
    } ntt_int_type;

    function automatic int calc_dpnd_fut_data(input int stage_idx);
        int threshold_stage;

        if (NUM_BUTFLY_PER_STAGE == 1) begin
            threshold_stage = 8;
        end
        else if (NUM_BUTFLY_PER_STAGE == 2) begin
            threshold_stage = 7;
        end
        else if (NUM_BUTFLY_PER_STAGE == 4) begin
            threshold_stage = 6;
        end
        else if (NUM_BUTFLY_PER_STAGE == 8) begin
            threshold_stage = 5;
        end
        else begin
            threshold_stage = 8;
        end

        calc_dpnd_fut_data = (stage_idx < threshold_stage) ? 1 : 0;
    endfunction

    `define DPND_FUT_DATA(stage_idx) calc_dpnd_fut_data(stage_idx)

    function automatic int inv_calc_dpnd_fut_data(input int stage_idx);
        int inv_threshold_stage;

        if (NUM_BUTFLY_PER_STAGE == 1) begin
            inv_threshold_stage = 1;
        end
        else if (NUM_BUTFLY_PER_STAGE == 2) begin
            inv_threshold_stage = 1;
        end
        else if (NUM_BUTFLY_PER_STAGE == 4) begin
            inv_threshold_stage = 2;
        end
        else if (NUM_BUTFLY_PER_STAGE == 8) begin
            inv_threshold_stage = 3;
        end
        else begin
            inv_threshold_stage = 8;
        end

        inv_calc_dpnd_fut_data = (stage_idx >= inv_threshold_stage) ? 1 : 0;
    endfunction

    `define INV_DPND_FUT_DATA(stage_idx) inv_calc_dpnd_fut_data(stage_idx)

    function logic [MODULUS_WIDTH-1:0] mul_mod_func(
        input logic [MODULUS_WIDTH-1:0] a,
        input logic [MODULUS_WIDTH-1:0] b
    );
        longint unsigned prod;
        prod = longint'(a) * longint'(b);
        mul_mod_func = prod % longint'(MODULUS);
    endfunction : mul_mod_func

    localparam PHI_VALUE_POW_2 = mul_mod_func(PHI_VALUE_POW_1, PHI_VALUE_POW_1);
    localparam PHI_VALUE_POW_3 = mul_mod_func(PHI_VALUE_POW_2, PHI_VALUE_POW_1);
    localparam PHI_VALUE_POW_4 = mul_mod_func(PHI_VALUE_POW_3, PHI_VALUE_POW_1);
    localparam PHI_VALUE_POW_8 = mul_mod_func(PHI_VALUE_POW_4, PHI_VALUE_POW_4);
    localparam PHI_VALUE_POW_16 = mul_mod_func(PHI_VALUE_POW_8, PHI_VALUE_POW_8);

    localparam PHI_VALUE =
        (NUM_BUTFLY_PER_STAGE == 1) ? PHI_VALUE_POW_1 :
        (NUM_BUTFLY_PER_STAGE == 2) ? PHI_VALUE_POW_2 :
        (NUM_BUTFLY_PER_STAGE == 4) ? PHI_VALUE_POW_3 :
        (NUM_BUTFLY_PER_STAGE == 8) ? PHI_VALUE_POW_4 :
                                      PHI_VALUE_POW_1;

    localparam ADV_PHI_VALUE =
        (NUM_BUTFLY_PER_STAGE == 1) ? PHI_VALUE_POW_2 :
        (NUM_BUTFLY_PER_STAGE == 2) ? PHI_VALUE_POW_4 :
        (NUM_BUTFLY_PER_STAGE == 4) ? PHI_VALUE_POW_8 :
        (NUM_BUTFLY_PER_STAGE == 8) ? PHI_VALUE_POW_16 :
                                      PHI_VALUE_POW_2;

    localparam ADV_PHI_VALUE_STEP =
        (NUM_BUTFLY_PER_STAGE == 1) ? PHI_VALUE_POW_1 :
        (NUM_BUTFLY_PER_STAGE == 2) ? PHI_VALUE_POW_2 :
        (NUM_BUTFLY_PER_STAGE == 4) ? PHI_VALUE_POW_4 :
        (NUM_BUTFLY_PER_STAGE == 8) ? PHI_VALUE_POW_8 :
                                     PHI_VALUE_POW_2;

    function logic [MODULUS_WIDTH-1:0] mod_pow(
        input logic [MODULUS_WIDTH-1:0] base,
        input int                       exp
    );
        logic [MODULUS_WIDTH-1:0] result;
        longint unsigned          prod;
        result = 1;
        for (int k = 0; k < exp; k++) begin
            prod   = longint'(result) * longint'(base);
            result = prod % longint'(MODULUS);
        end
        mod_pow = result;
    endfunction : mod_pow

    localparam PHI_S1_DELAY_NUM_CLOCKS = POLYNOMIAL_LENGTH/2 - NUM_COEFS_PER_STAGE/2;

endpackage

`endif
