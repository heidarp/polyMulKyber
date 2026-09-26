// Negacyclic product in Z_q[x] / (x^256 + 1), q = 3329.
// Included inside tb_poly_mul_rand. This is the scoreboard reference.

function automatic longint pos_mod(longint v, longint mod);
    longint r;
    r = v % mod;
    if (r < 0)
        r += mod;
    return r;
endfunction

// Schoolbook multiply, then fold the high half with x^n = -1.
function automatic polynomial_t ref_poly_mul_ring(
    input polynomial_t x,
    input polynomial_t y
);
    longint conv [0:2 * POLYNOMIAL_LENGTH - 2];
    longint coeff;
    polynomial_t result;

    for (int k = 0; k < 2 * POLYNOMIAL_LENGTH - 1; k++)
        conv[k] = 0;

    for (int i = 0; i < POLYNOMIAL_LENGTH; i++) begin
        for (int j = 0; j < POLYNOMIAL_LENGTH; j++) begin
            conv[i + j] = pos_mod(
                conv[i + j] + longint'(x[i]) * longint'(y[j]),
                MODULUS
            );
        end
    end

    for (int k = 0; k < POLYNOMIAL_LENGTH; k++) begin
        coeff = conv[k];
        if (k + POLYNOMIAL_LENGTH <= 2 * POLYNOMIAL_LENGTH - 2)
            coeff = pos_mod(coeff - conv[k + POLYNOMIAL_LENGTH], MODULUS);
        result[k] = coeff[MODULUS_WIDTH-1:0];
    end
    return result;
endfunction

function automatic polynomial_t fill_poly(input int value);
    polynomial_t p;
    for (int i = 0; i < POLYNOMIAL_LENGTH; i++)
        p[i] = value[MODULUS_WIDTH-1:0];
    return p;
endfunction

function automatic polynomial_t random_poly();
    polynomial_t p;
    for (int i = 0; i < POLYNOMIAL_LENGTH; i++)
        p[i] = $urandom_range(MODULUS - 1, 0);
    return p;
endfunction

// p[i] = (i * mul + add) mod q. Readable directed data, not a special case.
function automatic polynomial_t ramp_poly(input int mul, input int add);
    polynomial_t p;
    for (int i = 0; i < POLYNOMIAL_LENGTH; i++)
        p[i] = (i * mul + add) % MODULUS;
    return p;
endfunction
