`timescale 1ns/1ps
`ifndef PARAMETERS_VH
`define PARAMETERS_VH
package ntt_pkg;

    // Configuration parameters
    localparam MODULUS              = 3329;
    localparam POLYNOMIAL_LENGTH    = 256;
    // Kyber base twiddle: 17 is a primitive 256-th root of unity mod 3329 (17^128 = -1).
    // No 512-th root exists mod 3329, hence the NTT stops at degree-1 pairs (see TOTAL_NUM_STAGES).
    localparam W_VALUE              = 17;
    localparam INV_W_VALUE          = 1175;   // 17^-1 mod 3329
`ifndef NUM_BUTFLY_PER_STAGE
    localparam NUM_BUTFLY_PER_STAGE = 1;
`else
    localparam NUM_BUTFLY_PER_STAGE = `NUM_BUTFLY_PER_STAGE;
`endif
    localparam MUL_PIPE_DEPTH       = 1;
    // The phi pre/post-twist path is unused for Kyber (the incomplete NTT is negacyclic by
    // construction) and is left instantiated-out in forward_ntt/inverse_ntt.
    localparam PHI_VALUE_POW_1      = 2016;
    localparam INV_PHI_VALUE_POW_1  = 998612;
    // n^{-1} incorporated into inverse-phi init so INTT scaling is free at the end.
    // 7 stages grow the coefficients by 2^7, so this is 128^-1 mod 3329.
    localparam SCALER               = 3303;
    localparam PHI_HALF_LENGTH      = 128;
    // Extra cycles past MUL_PIPE_DEPTH: butterfly add/sub + modular correction pipeline.
    localparam PIPELINED_MUL_RED_EXTRA = 3;

    // Derived parameters
    localparam MODULUS_WIDTH = $clog2(MODULUS);
    localparam [MODULUS_WIDTH-1:0] MODULUS_BIN = MODULUS;

    // Kyber's NTT is incomplete: it stops one layer early, leaving 128 degree-1 polynomials
    // instead of 256 scalars, so there are log2(N)-1 stages and only 127 distinct twiddles.
    localparam TOTAL_NUM_STAGES = $clog2(POLYNOMIAL_LENGTH) - 1;
    localparam NUM_COEFS_PER_STAGE = 2*NUM_BUTFLY_PER_STAGE;

    localparam PHI_S1_CNT_WIDTH = $clog2(PHI_HALF_LENGTH);

    localparam PIPELINED_MUL_RED_DELAY = MUL_PIPE_DEPTH + PIPELINED_MUL_RED_EXTRA;

    typedef struct packed {
        logic [NUM_BUTFLY_PER_STAGE*2-1:0] [MODULUS_WIDTH-1:0] coefs;
        logic                              valid;
    } poly_type;

    typedef struct packed {
        poly_type [TOTAL_NUM_STAGES-1:0] stage;
    } ntt_int_type;

    // Early forward stages need a FIFO+live-input mux (partners arrive DELAY clocks apart).
    // Threshold depends on parallelism: more butterflies -> fut-data mode ends sooner.
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

    // Inverse NTT stage order is reversed: late stages use fut-data mux instead of early ones.
    function automatic int inv_calc_dpnd_fut_data(input int stage_idx);
        int inv_threshold_stage;

        if (NUM_BUTFLY_PER_STAGE == 1) begin
            inv_threshold_stage = 1;
        end
        else if (NUM_BUTFLY_PER_STAGE == 2) begin
            inv_threshold_stage = 2;
        end
        else if (NUM_BUTFLY_PER_STAGE == 4) begin
            inv_threshold_stage = 3;
        end
        else if (NUM_BUTFLY_PER_STAGE == 8) begin
            inv_threshold_stage = 4;
        end
        else begin
            inv_threshold_stage = 8;
        end

        inv_calc_dpnd_fut_data = (stage_idx >= inv_threshold_stage) ? 1 : 0;
    endfunction

    `define INV_DPND_FUT_DATA(stage_idx) inv_calc_dpnd_fut_data(stage_idx)

    // Wide product before reduce; 32-bit int overflows when a,b ~ MODULUS
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

    // Per-beat phi step scales with how many coeffs are consumed each clock.
    localparam PHI_VALUE =
        (NUM_BUTFLY_PER_STAGE == 1) ? PHI_VALUE_POW_1 :
        (NUM_BUTFLY_PER_STAGE == 2) ? PHI_VALUE_POW_2 :
        (NUM_BUTFLY_PER_STAGE == 4) ? PHI_VALUE_POW_3 :
        (NUM_BUTFLY_PER_STAGE == 8) ? PHI_VALUE_POW_4 :
                                      PHI_VALUE_POW_1;

    // Ping-pong path advances by phi^(2*step) so alternating lanes stay one step apart.
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

    // Interleaved phi exponents across streaming lanes:
    // even i -> phi^(i/2), odd i -> phi^(N/2 + (i-1)/2) for negative-wrapped residues.
    function int phi_lane_exponent(input int i);
        if (i == 0)
            phi_lane_exponent = 0;
        else if (i % 2 == 1)
            phi_lane_exponent = PHI_HALF_LENGTH + ((i-1)/2);
        else
            phi_lane_exponent = i/2;
    endfunction : phi_lane_exponent

    typedef logic [NUM_COEFS_PER_STAGE-1:0] [MODULUS_WIDTH-1:0] phi_init_values_t;

    function phi_init_values_t phi_init_values();
        for (int i = 0; i < NUM_COEFS_PER_STAGE; i++) begin
            phi_init_values[i] = mod_pow(PHI_VALUE_POW_1, phi_lane_exponent(i));
        end
    endfunction : phi_init_values

    localparam [NUM_COEFS_PER_STAGE-1:0] [MODULUS_WIDTH-1:0] PHI_INIT_VALS = phi_init_values();

    localparam INV_PHI_VALUE_POW_2 = mul_mod_func(INV_PHI_VALUE_POW_1, INV_PHI_VALUE_POW_1);
    localparam INV_PHI_VALUE_POW_3 = mul_mod_func(INV_PHI_VALUE_POW_2, INV_PHI_VALUE_POW_1);
    localparam INV_PHI_VALUE_POW_4 = mul_mod_func(INV_PHI_VALUE_POW_3, INV_PHI_VALUE_POW_1);
    localparam INV_PHI_VALUE_POW_8 = mul_mod_func(INV_PHI_VALUE_POW_4, INV_PHI_VALUE_POW_4);
    localparam INV_PHI_VALUE_POW_16 = mul_mod_func(INV_PHI_VALUE_POW_8, INV_PHI_VALUE_POW_8);

    localparam INV_PHI_VALUE =
        (NUM_BUTFLY_PER_STAGE == 1) ? INV_PHI_VALUE_POW_1 :
        (NUM_BUTFLY_PER_STAGE == 2) ? INV_PHI_VALUE_POW_2 :
        (NUM_BUTFLY_PER_STAGE == 4) ? INV_PHI_VALUE_POW_3 :
        (NUM_BUTFLY_PER_STAGE == 8) ? INV_PHI_VALUE_POW_4 :
                                     INV_PHI_VALUE_POW_1;

    localparam ADV_INV_PHI_VALUE =
        (NUM_BUTFLY_PER_STAGE == 1) ? INV_PHI_VALUE_POW_2 :
        (NUM_BUTFLY_PER_STAGE == 2) ? INV_PHI_VALUE_POW_4 :
        (NUM_BUTFLY_PER_STAGE == 4) ? INV_PHI_VALUE_POW_8 :
        (NUM_BUTFLY_PER_STAGE == 8) ? INV_PHI_VALUE_POW_16 :
                                     INV_PHI_VALUE_POW_2;

    localparam ADV_INV_PHI_VALUE_STEP =
        (NUM_BUTFLY_PER_STAGE == 1) ? INV_PHI_VALUE_POW_1 :
        (NUM_BUTFLY_PER_STAGE == 2) ? INV_PHI_VALUE_POW_2 :
        (NUM_BUTFLY_PER_STAGE == 4) ? INV_PHI_VALUE_POW_4 :
        (NUM_BUTFLY_PER_STAGE == 8) ? INV_PHI_VALUE_POW_8 :
                                     INV_PHI_VALUE_POW_16;

    typedef logic [NUM_COEFS_PER_STAGE-1:0] [MODULUS_WIDTH-1:0] inv_phi_init_values_t;

    function inv_phi_init_values_t inv_phi_init_values();
        automatic longint unsigned temp;
        automatic longint unsigned scaled;
        for (int i = 0; i < NUM_COEFS_PER_STAGE; i++) begin
            // Fold n^{-1} (SCALER) into each inverse-phi seed.
            temp = mod_pow(INV_PHI_VALUE_POW_1, phi_lane_exponent(i));
            scaled = (temp * SCALER) % MODULUS;
            inv_phi_init_values[i] = scaled;
        end
    endfunction : inv_phi_init_values

    localparam [NUM_COEFS_PER_STAGE-1:0] [MODULUS_WIDTH-1:0] SCALED_INV_PHI_INIT_VALS =
        inv_phi_init_values();

    function phi_init_values_t phi_init_values_advanced();
        for (int i = 0; i < NUM_COEFS_PER_STAGE; i++) begin
            phi_init_values_advanced[i] = mul_mod_func(PHI_INIT_VALS[i], ADV_PHI_VALUE_STEP);
        end
    endfunction : phi_init_values_advanced

    localparam [NUM_COEFS_PER_STAGE-1:0] [MODULUS_WIDTH-1:0] PHI_INIT_VALS_ADVANNCED =
        phi_init_values_advanced();

    function inv_phi_init_values_t inv_phi_init_values_advanced();
        for (int i = 0; i < NUM_COEFS_PER_STAGE; i++) begin
            inv_phi_init_values_advanced[i] =
                mul_mod_func(SCALED_INV_PHI_INIT_VALS[i], ADV_INV_PHI_VALUE_STEP);
        end
    endfunction : inv_phi_init_values_advanced

    localparam [NUM_COEFS_PER_STAGE-1:0] [MODULUS_WIDTH-1:0] SCALED_INV_PHI_INIT_VALS_ADVANNCED =
        inv_phi_init_values_advanced();

    localparam PHI_S1_DELAY_NUM_CLOCKS = POLYNOMIAL_LENGTH/2 - NUM_COEFS_PER_STAGE/2;

endpackage

`endif
