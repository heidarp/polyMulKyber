// Utility functions for primitive root calculation
package primitive_root_pkg;
  /*  
    // Function to compute integer square root
    function automatic int sqrt(input int n);
        int i = 1;
        int result = 0;
        
        if (n < 0) begin
            $error("sqrt: negative argument");
            return 0;
        end
        
        // Find highest power of 2 <= sqrt(n)
        while (i * i <= n) begin
            i = i << 1;  // multiply by 2
        end
        
        // Binary search for square root
        result = 0;
        while (i > 0) begin
            if ((result + i) * (result + i) <= n) begin
                result = result + i;
            end
            i = i >> 1;  // divide by 2
        end
        
        return result;
    endfunction
    
    // Function to check if number is prime
    function automatic bit is_prime(input int n);
        int limit;
        
        if (n <= 1) begin
            $error("is_prime: argument must be > 1");
            return 0;
        end
        
        limit = sqrt(n);
        for (int i = 2; i <= limit; i++) begin
            if (n % i == 0) begin
                return 0;
            end
        end
        
        return 1;
    endfunction
    
    // Function to get unique prime factors
    function automatic void unique_prime_factors(
        input int n,
        output int factors[10],  // Assuming max 10 prime factors
        output int num_factors
    );
        int temp_n = n;
        int i = 2;
        int end_val;
        
        num_factors = 0;
        
        if (n < 1) begin
            $error("unique_prime_factors: argument must be >= 1");
            return;
        end
        
        end_val = sqrt(temp_n);
        
        while (i <= end_val) begin
            if (temp_n % i == 0) begin
                temp_n = temp_n / i;
                factors[num_factors] = i;
                num_factors++;
                
                // Remove all factors of i
                while (temp_n % i == 0) begin
                    temp_n = temp_n / i;
                end
                
                end_val = sqrt(temp_n);
            end
            i++;
        end
        
        if (temp_n > 1) begin
            factors[num_factors] = temp_n;
            num_factors++;
        end
    endfunction
    
    // Function to check if a value is a generator
    function automatic bit is_generator(
        input int val,
        input int totient,
        input int mod
    );
        int prime_factors[10];
        int num_factors;
        
        if (!(0 <= val && val < mod)) begin
            $error("is_generator: val out of range");
            return 0;
        end
        
        if (!(1 <= totient && totient < mod)) begin
            $error("is_generator: totient out of range");
            return 0;
        end
        
        // Check if val^totient ≡ 1 (mod mod)
        if (pow_mod(val, totient, mod) != 1) begin
            return 0;
        end
        
        // Get unique prime factors of totient
        unique_prime_factors(totient, prime_factors, num_factors);
        
        // Check val^(totient/p) ≠ 1 for all prime factors p
        for (int i = 0; i < num_factors; i++) begin
            if (pow_mod(val, totient / prime_factors[i], mod) == 1) begin
                return 0;
            end
        end
        
        return 1;
    endfunction
    
    // Function to find a generator
    function automatic int find_generator(
        input int totient,
        input int mod
    );
        if (!(1 <= totient && totient < mod)) begin
            $error("find_generator: invalid arguments");
            return -1;
        end
        
        for (int i = 1; i < mod; i++) begin
            if (is_generator(i, totient, mod)) begin
                return i;
            end
        end
        
        $error("find_generator: No generator exists");
        return -1;
    endfunction
    
    // Modular exponentiation function
    function automatic int pow_mod(
        input int base,
        input int exponent,
        input int modulus
    );
        int result = 1;
        int b = base % modulus;
        int e = exponent;
        
        while (e > 0) begin
            if (e & 1) begin
                result = (result * b) % modulus;
            end
            b = (b * b) % modulus;
            e = e >> 1;
        end
        
        return result;
    endfunction
    
    // Function to find modulus
    function automatic int find_modulus(
        input int veclen,
        input int minimum
    );
        int start;
        int n;
        
        // Input validation
        if (veclen < 1 || minimum < 1) begin
            $error("find_modulus: veclen and minimum must be >= 1");
            return -1;
        end
        
        // Calculate starting point: ceil((minimum - 1) / veclen)
        // Using integer math: (a + b - 1) / b for ceiling division
        start = (minimum - 1 + veclen - 1) / veclen;
        if (start < 1) start = 1;
        
        // Search for n such that n = i * veclen + 1 is prime
        for (int i = start; i < start + 1000; i++) begin  // Limit search to prevent infinite loop
            n = i * veclen + 1;
            
            // Check if n meets minimum requirement
            if (n < minimum) continue;
            
            // Check if n is prime
            if (is_prime(n)) begin
                return n;
            end
        end
        
        $error("find_modulus: No suitable modulus found within search limit");
        return -1;
    endfunction

    // Main function: find primitive root
    function automatic int find_primitive_root(
        input int degree,
        input int totient,
        input int mod
    );
        int gen;
        int root;
        
        // Input validation
        if (!(1 <= degree && degree <= totient && totient < mod)) begin
            $error("find_primitive_root: invalid arguments - degree=%0d, totient=%0d, mod=%0d", 
                   degree, totient, mod);
            return -1;
        end
        
        if (totient % degree != 0) begin
            $error("find_primitive_root: totient must be divisible by degree");
            return -1;
        end
        
        // Find a generator
        gen = find_generator(totient, mod);
        if (gen == -1) begin
            return -1;
        end
        
        // Calculate primitive root: generator^(totient/degree) mod mod
        root = pow_mod(gen, totient / degree, mod);
        
        return root;
    endfunction
*/ 











// Function to compute integer square root
function automatic int sqrt(input int n);
    int i = 1;
    int result = 0;
    
    if (n < 0) begin
        $error("sqrt: negative argument");
        return 0;
    end
    
    // Find highest power of 2 <= sqrt(n)
    while (i * i <= n) begin
        i = i << 1;  // multiply by 2
    end
    
    // Binary search for square root
    result = 0;
    while (i > 0) begin
        if ((result + i) * (result + i) <= n) begin
            result = result + i;
        end
        i = i >> 1;  // divide by 2
    end
    
    return result;
endfunction

// Function to check if number is prime
function automatic bit is_prime(input int n);
    int limit;
    
    if (n <= 1) begin
        $error("is_prime: argument must be > 1");
        return 0;
    end
    
    limit = sqrt(n);
    for (int i = 2; i <= limit; i++) begin
        if (n % i == 0) begin
            return 0;
        end
    end
    
    return 1;
endfunction

// Function to get unique prime factors
function automatic void unique_prime_factors(
    input int n,
    output int factors[10],  // Assuming max 10 prime factors
    output int num_factors
);
    int temp_n = n;
    int i = 2;
    int end_val;
    
    num_factors = 0;
    
    if (n < 1) begin
        $error("unique_prime_factors: argument must be >= 1");
        return;
    end
    
    end_val = sqrt(temp_n);
    
    while (i <= end_val) begin
        if (temp_n % i == 0) begin
            factors[num_factors] = i;
            num_factors++;
            
            // Remove all factors of i
            while (temp_n % i == 0) begin
                temp_n = temp_n / i;
            end
            
            end_val = sqrt(temp_n);
        end
        i++;
    end
    
    if (temp_n > 1) begin
        factors[num_factors] = temp_n;
        num_factors++;
    end
endfunction

// Modular exponentiation function with 64-bit arithmetic to prevent overflow
function automatic int pow_mod(
    input int base,
    input int exponent,
    input int modulus
);
    int result = 1;
    int b = base % modulus;
    int e = exponent;
    longint mult_result;  // Use 64-bit for intermediate calculations
    
    while (e > 0) begin
        if (e & 1) begin
            mult_result = longint'(result) * longint'(b);
            result = int'(mult_result % modulus);
        end
        mult_result = longint'(b) * longint'(b);
        b = int'(mult_result % modulus);
        e = e >> 1;
    end
    
    return result;
endfunction

// Function to check if a value is a generator of the multiplicative group modulo p
function automatic bit is_generator(
    input int val,
    input int p_minus_1,  // This should be p-1 for prime p
    input int mod
);
    int prime_factors[10];
    int num_factors;
    
    if (!(1 < val && val < mod)) begin  // val must be > 1 and < mod
        return 0;
    end
    
    // Get unique prime factors of p-1
    unique_prime_factors(p_minus_1, prime_factors, num_factors);
    
    // Check val^((p-1)/q) ≠ 1 mod p for all prime factors q of p-1
    for (int i = 0; i < num_factors; i++) begin
        if (pow_mod(val, p_minus_1 / prime_factors[i], mod) == 1) begin
            return 0;
        end
    end
    
    return 1;
endfunction

// Function to find a generator of the multiplicative group modulo p
function automatic int find_generator(
    input int p_minus_1,  // This should be p-1 for prime p
    input int mod
);
    if (!(1 <= p_minus_1 && p_minus_1 < mod)) begin
        $error("find_generator: invalid arguments");
        return -1;
    end
    
    // Start from 2 (since 1 is never a generator)
    for (int i = 2; i < mod; i++) begin
        if (is_generator(i, p_minus_1, mod)) begin
            return i;
        end
    end
    
    $error("find_generator: No generator exists for modulus %0d", mod);
    return -1;
endfunction

// Function to find modulus (prime of form k * veclen + 1)
function automatic int find_modulus(
    input int veclen,
    input int minimum
);
    int start;
    int n;
    
    // Input validation
    if (veclen < 1 || minimum < 1) begin
        $error("find_modulus: veclen and minimum must be >= 1");
        return -1;
    end
    
    // Calculate starting point: ceil((minimum - 1) / veclen)
    start = (minimum - 1 + veclen - 1) / veclen;
    if (start < 1) start = 1;
    
    // Search for n such that n = i * veclen + 1 is prime
    for (int i = start; i < start + 10000; i++) begin
        n = i * veclen + 1;
        
        // Check if n meets minimum requirement
        if (n < minimum) continue;
        
        // Check if n is prime
        if (is_prime(n)) begin
            return n;
        end
    end
    
    $error("find_modulus: No suitable modulus found within search limit");
    return -1;
endfunction

// Function to find primitive root (element of order 'degree')
function automatic int find_primitive_root(
    input int degree,
    input int totient,
    input int mod
);
    int gen;
    int root;
    int prime_factors[10];
    int num_factors;
    int quotient;
    
    // Input validation
    if (!(1 <= degree && degree <= totient && totient < mod)) begin
        $error("find_primitive_root: invalid arguments - degree=%0d, totient=%0d, mod=%0d", 
               degree, totient, mod);
        return -1;
    end
    
    if (totient % degree != 0) begin
        $error("find_primitive_root: totient must be divisible by degree");
        return -1;
    end
    
    quotient = totient / degree;
    //$display("Debug: degree=%0d, totient=%0d, quotient=%0d", degree, totient, quotient);
    
    // Find a generator of the full multiplicative group
    gen = find_generator(totient, mod);
    if (gen == -1) begin
        return -1;
    end
    //$display("Debug: Found generator = %0d", gen);
    
    // Calculate element of order 'degree': generator^(totient/degree) mod mod
    root = pow_mod(gen, quotient, mod);
    //$display("Debug: root = %0d^%0d mod %0d = %0d", gen, quotient, mod, root);
    
    // Verify the order - check root^degree == 1
    if (pow_mod(root, degree, mod) != 1) begin
        $error("find_primitive_root: Failed - root^%0d mod %0d = %0d, expected 1", 
               degree, mod, pow_mod(root, degree, mod));
        return -1;
    end
    //$display("Debug: root^%0d mod %0d = 1 ✓", degree, mod);
    
    // Get prime factors of degree
    unique_prime_factors(degree, prime_factors, num_factors);
    //$display("Debug: Prime factors of %0d: ", degree);
    for (int i = 0; i < num_factors; i++) begin
        //$display("  factor[%0d] = %0d", i, prime_factors[i]);
    end
    
    // Verify that no smaller exponent (dividing degree) gives 1
    for (int i = 0; i < num_factors; i++) begin
        int test_exp = degree / prime_factors[i];
        int test_result = pow_mod(root, test_exp, mod);
        //$display("Debug: Testing root^%0d = %0d", test_exp, test_result);
        
        if (test_result == 1) begin
            $error("find_primitive_root: Element has order %0d (divides %0d), not full %0d", 
                   test_exp, degree, degree);
            return -1;
        end
    end
    
    //$display("Debug: Success! Primitive root of order %0d found: %0d", degree, root);
    return root;
endfunction

// Test code - place this in your testbench initial block
/*
initial begin
    int degree = 256;
    int mod = 1049089;
    int totient = mod - 1;
    int primitive_root;
    
    $display("========================================");
    $display("Testing primitive root finder for:");
    $display("  Modulus = %0d", mod);
    $display("  Degree = %0d", degree);
    $display("========================================");
    
    // Verify modulus is prime
    if (!is_prime(mod)) begin
        $display("ERROR: %0d is not prime!", mod);
        $finish;
    end
    $display("✓ %0d is prime", mod);
    
    // Verify degree divides totient
    if (totient % degree != 0) begin
        $display("ERROR: %0d does not divide %0d", degree, totient);
        $finish;
    end
    $display("✓ %0d divides %0d (quotient = %0d)", degree, totient, totient/degree);
    
    // Find primitive root
    primitive_root = find_primitive_root(degree, totient, mod);
    
    if (primitive_root != -1) begin
        $display("\n✓ SUCCESS: Primitive root found = %0d", primitive_root);
        
        // Final verification
        $display("Final verification: %0d^%0d mod %0d = %0d", 
                 primitive_root, degree, mod, 
                 pow_mod(primitive_root, degree, mod));
    end else begin
        $display("\n✗ FAILED: Could not find primitive root");
    end
    
    $display("========================================");
end
*/























































endpackage


class ntt2_verifier;
    // Function to compute modular exponentiation (pow(x, y, mod))
    static function longint mod_pow(input longint base, input longint exp, input longint mod);
        longint result;
        longint b;
        longint e;
        
        result = 1;
        b = base % mod;
        e = exp;
        
        if (e == 0) return 1;
        
        while (e > 0) begin
            if ((e & 1) == 1) begin  // exp is odd
                result = (result * b) % mod;
            end
            b = (b * b) % mod;
            e = e >> 1;  // exp = exp / 2
        end
        
        return result;
    endfunction
    
    // Main NTT function - matches your Python ntt2()
    static function void ntt2(
        input longint x[],
        input longint r,
        input longint mod,
        output longint result[$]
    );
        int N;
        
        longint T[$];
        longint X_even[$];
        longint X_odd[$];
        longint sme1[$];
        longint sme2[$];
        int i, k;
        longint  ts_val,t_val, s1, s2;
        
        // Clear output queue
        result.delete();
        
        N = x.size();
        
        // Separate even and odd indices
        for (i = 0; i < N; i = i + 1) begin
            if ((i % 2) == 0) begin
                X_even.push_back(x[i]);
            end else begin
                X_odd.push_back(x[i]);
            end
        end
/*
        $write("X_odd: [");
        for (i = 0; i < X_odd.size(); i = i + 1) begin
            $write("%0d", X_odd[i]);
            if (i != (T.size() - 1)) $write(", ");
        end
        $write("]\n");
        $write("X_even: [");
        for (i = 0; i < X_even.size(); i = i + 1) begin
            $write("%0d", X_even[i]);
            if (i != (T.size() - 1)) $write(", ");
        end
        $write("]\n");
        */
        
        // Calculate T = r^k mod mod for k = 0 to N/2-1
        for (k = 0; k < (N/2); k = k + 1) begin
            ts_val = mod_pow(r, k, mod);
            t_val = (ts_val * X_odd[k]) % mod;
            T.push_back(t_val);
        end
        
  

        /*
        $write("T: [");
        for (i = 0; i < T.size(); i = i + 1) begin
            $write("%0d", T[i]);
            if (i != (T.size() - 1)) $write(", ");
        end
        $write("]\n");
        */


        



     
        // Calculate sme1 and sme2
        for (k = 0; k < (N/2); k = k + 1) begin
            s1 = (X_even[k] + T[k]) % mod;
            
            // Handle negative modulo (Python-style)
            s2 = (X_even[k] - T[k]) % mod;
            if (s2 < 0) begin
                s2 = s2 + mod;
            end
            
            sme1.push_back(s1);
            sme2.push_back(s2);
        end
        //$display("sme1 = %0d, sme2 = %0d", sme1, sme2);
        // Combine results
        /*$write("sme1: [");
        for (i = 0; i < sme1.size(); i = i + 1) begin
            $write("%0d", sme1[i]);
            if (i != (sme1.size() - 1)) $write(", ");
        end
        $write("]\n");*/
        

        for (i = 0; i < sme1.size(); i = i + 1) begin
            result.push_back(sme1[i]);
        end
        
        for (i = 0; i < sme2.size(); i = i + 1) begin
            result.push_back(sme2[i]);
        end
        
        // Final modulo (just in case)
        for (i = 0; i < result.size(); i = i + 1) begin
            result[i] = result[i] % mod;
        end
    endfunction
    
    // Helper function to print arrays for debugging
    static function void print_array(input string name, input longint arr[]);
        int i;
        $write("%s: [", name);
        for (i = 0; i < arr.size(); i = i + 1) begin
            $write("%0d", arr[i]);
            if (i != (arr.size() - 1)) $write(", ");
        end
        $write("]\n");
    endfunction
    
    // Helper function to print queues
    static function void print_queue(input string name, input longint arr[$]);
        int i;
        $write("%s: [", name);
        for (i = 0; i < arr.size(); i = i + 1) begin
            $write("%0d", arr[i]);
            if (i != (arr.size() - 1)) $write(", ");
        end
        $write("]\n");
    endfunction
endclass

class ntt4_verifier;

    /**
     * Helper function for modular exponentiation
     * Calculates (base^exponent) % modulus
     */
    static function automatic int pow_mod(
        input int base,
        input int exponent,
        input int modulus
    );
        longint result = 1;
        longint b = base % modulus;
        int e = exponent;
        
        while (e > 0) begin
            if (e & 1) begin
                result = (result * b) % modulus;
            end
            b = (b * b) % modulus;
            e = e >> 1;
        end
        
        return int'(result);
    endfunction : pow_mod

    /**
     * NTT4 SystemVerilog function for testbench
     * Performs a 4-point (or size N) decimation-in-time NTT
     */
    static function automatic void ntt4(
        ref longint x[],              // Input array
        input int r,               // Root of unity
        input int mod,             // Modulus
        ref longint quotient[]         // Output array
    );
        // Local variables
        int totalSize;
        int halfSize;
        longint X_even[];
        longint X_odd[];
        int TS[];
        int T[];
        int sme1[];
        int sme2[];
        int modul;
        int prim_root;

        totalSize = x.size();
        halfSize  = totalSize / 2;
        
        // Dynamic array allocation
        X_even   = new[halfSize];
        X_odd    = new[halfSize];
        TS       = new[halfSize];
        T        = new[halfSize];
        sme1     = new[halfSize];
        sme2     = new[halfSize];
        
        // Extract even and odd indices (Decimation in Time)
        for (int i = 0; i < halfSize; i++) begin
            X_even[i] = x[2*i];
            X_odd[i]  = x[2*i + 1];
        end
        
        // Find parameters for the recursive NTT2 step
        // Note: Ensure find_modulus and find_primitive_root are accessible 
        // (either in primitive_root_pkg or defined in this class)
        modul     = primitive_root_pkg::find_modulus(halfSize, mod);
        prim_root = primitive_root_pkg::find_primitive_root(halfSize, modul - 1, modul);
        
        // Perform NTT2 on even and odd parts
        // Assuming ntt2_verifier is another class with a static ntt2 method

        ntt2_verifier::ntt2(X_even, prim_root, modul, X_even);
        ntt2_verifier::ntt2(X_odd, prim_root, modul, X_odd);
        
        // Butterfly operations: Combine even and odd parts with twiddle factors
        for (int k = 0; k < halfSize; k++) begin
            // Calculate T[k] = r^k * X_odd[k] mod mod
            TS[k] = pow_mod(r, k, mod);
            T[k]  = int'((longint'(TS[k]) * X_odd[k]) % mod);
            
            // Butterfly combination
            sme1[k] = (int'(X_even[k]) + T[k]) % mod;
            sme2[k] = (int'(X_even[k]) - T[k]) % mod;
            
            // Ensure positive modulo result
            if (sme2[k] < 0) sme2[k] += mod;
        end
        
        // Combine results into quotient array
        quotient = new[totalSize];
        for (int i = 0; i < halfSize; i++) begin
            quotient[i]            = sme1[i];
            quotient[i + halfSize] = sme2[i];
        end
        
    endfunction : ntt4

endclass : ntt4_verifier



class ntt8_verifier;

    /**
     * Helper function for modular exponentiation
     * Calculates (base^exponent) % modulus
     */
    static function automatic int pow_mod(
        input int base,
        input int exponent,
        input int modulus
    );
        longint result = 1;
        longint b = base % modulus;
        int e = exponent;
        
        while (e > 0) begin
            if (e & 1) begin
                result = (result * b) % modulus;
            end
            b = (b * b) % modulus;
            e = e >> 1;
        end
        
        return int'(result);
    endfunction : pow_mod

    /**
     * ntt8 SystemVerilog function for testbench
     * Performs a 4-point (or size N) decimation-in-time NTT
     */
    static function automatic void ntt8(
        ref longint x[],              // Input array
        input int r,               // Root of unity
        input int mod,             // Modulus
        ref longint quotient[]         // Output array
    );
        // Local variables
        int totalSize;
        int halfSize;
        longint X_even[];
        longint X_odd[];
        int TS[];
        int T[];
        int sme1[];
        int sme2[];
        int modul;
        int prim_root;

        totalSize = x.size();
        halfSize  = totalSize / 2;
        
        // Dynamic array allocation
        X_even   = new[halfSize];
        X_odd    = new[halfSize];
        TS       = new[halfSize];
        T        = new[halfSize];
        sme1     = new[halfSize];
        sme2     = new[halfSize];
        
        // Extract even and odd indices (Decimation in Time)
        for (int i = 0; i < halfSize; i++) begin
            X_even[i] = x[2*i];
            X_odd[i]  = x[2*i + 1];
        end
        
        // Find parameters for the recursive ntt4 step
        // Note: Ensure find_modulus and find_primitive_root are accessible 
        // (either in primitive_root_pkg or defined in this class)
        modul     = primitive_root_pkg::find_modulus(halfSize, mod);
        prim_root = primitive_root_pkg::find_primitive_root(halfSize, modul - 1, modul);
        
        // Perform ntt4 on even and odd parts
        // Assuming ntt4_verifier is another class with a static ntt4 method
        ntt4_verifier::ntt4(X_even, prim_root, modul, X_even);
        ntt4_verifier::ntt4(X_odd, prim_root, modul, X_odd);

        
        // Butterfly operations: Combine even and odd parts with twiddle factors
        for (int k = 0; k < halfSize; k++) begin
            // Calculate T[k] = r^k * X_odd[k] mod mod
            TS[k] = pow_mod(r, k, mod);
            T[k]  = int'((longint'(TS[k]) * X_odd[k]) % mod);
            
            // Butterfly combination
            sme1[k] = (int'(X_even[k]) + T[k]) % mod;
            sme2[k] = (int'(X_even[k]) - T[k]) % mod;
            
            // Ensure positive modulo result
            if (sme2[k] < 0) sme2[k] += mod;
        end
        
        // Combine results into quotient array
        quotient = new[totalSize];
        for (int i = 0; i < halfSize; i++) begin
            quotient[i]            = sme1[i];
            quotient[i + halfSize] = sme2[i];
        end
        
    endfunction : ntt8

endclass : ntt8_verifier






class ntt16_verifier;

    /**
     * Helper function for modular exponentiation
     * Calculates (base^exponent) % modulus
     */
    static function automatic int pow_mod(
        input int base,
        input int exponent,
        input int modulus
    );
        longint result = 1;
        longint b = base % modulus;
        int e = exponent;
        
        while (e > 0) begin
            if (e & 1) begin
                result = (result * b) % modulus;
            end
            b = (b * b) % modulus;
            e = e >> 1;
        end
        
        return int'(result);
    endfunction : pow_mod

    /**
     * ntt16 SystemVerilog function for testbench
     * Performs a 4-point (or size N) decimation-in-time NTT
     */
    static function automatic void ntt16(
        ref longint x[],              // Input array
        input int r,               // Root of unity
        input int mod,             // Modulus
        ref longint quotient[]         // Output array
    );
        // Local variables
        int totalSize;
        int halfSize;
        longint X_even[];
        longint X_odd[];
        int TS[];
        int T[];
        int sme1[];
        int sme2[];
        int modul;
        int prim_root;

        totalSize = x.size();
        halfSize  = totalSize / 2;
        
        // Dynamic array allocation
        X_even   = new[halfSize];
        X_odd    = new[halfSize];
        TS       = new[halfSize];
        T        = new[halfSize];
        sme1     = new[halfSize];
        sme2     = new[halfSize];
        
        // Extract even and odd indices (Decimation in Time)
        for (int i = 0; i < halfSize; i++) begin
            X_even[i] = x[2*i];
            X_odd[i]  = x[2*i + 1];
        end
        
        // Find parameters for the recursive ntt8 step
        // Note: Ensure find_modulus and find_primitive_root are accessible 
        // (either in primitive_root_pkg or defined in this class)
        modul     = primitive_root_pkg::find_modulus(halfSize, mod);
        prim_root = primitive_root_pkg::find_primitive_root(halfSize, modul - 1, modul);
        
        // Perform ntt8 on even and odd parts
        // Assuming ntt8_verifier is another class with a static ntt8 method
        ntt8_verifier::ntt8(X_even, prim_root, modul, X_even);
        ntt8_verifier::ntt8(X_odd, prim_root, modul, X_odd);



        
        // Butterfly operations: Combine even and odd parts with twiddle factors
        for (int k = 0; k < halfSize; k++) begin
            // Calculate T[k] = r^k * X_odd[k] mod mod
            TS[k] = pow_mod(r, k, mod);
            T[k]  = int'((longint'(TS[k]) * X_odd[k]) % mod);
            
            // Butterfly combination
            sme1[k] = (int'(X_even[k]) + T[k]) % mod;
            sme2[k] = (int'(X_even[k]) - T[k]) % mod;
            
            // Ensure positive modulo result
            if (sme2[k] < 0) sme2[k] += mod;
        end
        
        // Combine results into quotient array
        quotient = new[totalSize];
        for (int i = 0; i < halfSize; i++) begin
            quotient[i]            = sme1[i];
            quotient[i + halfSize] = sme2[i];
        end
        
    endfunction : ntt16

endclass : ntt16_verifier



class ntt32_verifier;

    /**
     * Helper function for modular exponentiation
     * Calculates (base^exponent) % modulus
     */
    static function automatic int pow_mod(
        input int base,
        input int exponent,
        input int modulus
    );
        longint result = 1;
        longint b = base % modulus;
        int e = exponent;
        
        while (e > 0) begin
            if (e & 1) begin
                result = (result * b) % modulus;
            end
            b = (b * b) % modulus;
            e = e >> 1;
        end
        
        return int'(result);
    endfunction : pow_mod

    /**
     * ntt32 SystemVerilog function for testbench
     * Performs a 4-point (or size N) decimation-in-time NTT
     */
    static function automatic void ntt32(
        ref longint x[],              // Input array
        input int r,               // Root of unity
        input int mod,             // Modulus
        ref longint quotient[]         // Output array
    );
        // Local variables
        int totalSize;
        int halfSize;
        longint X_even[];
        longint X_odd[];
        int TS[];
        int T[];
        int sme1[];
        int sme2[];
        int modul;
        int prim_root;

        totalSize = x.size();
        halfSize  = totalSize / 2;
        
        // Dynamic array allocation
        X_even   = new[halfSize];
        X_odd    = new[halfSize];
        TS       = new[halfSize];
        T        = new[halfSize];
        sme1     = new[halfSize];
        sme2     = new[halfSize];
        
        // Extract even and odd indices (Decimation in Time)
        for (int i = 0; i < halfSize; i++) begin
            X_even[i] = x[2*i];
            X_odd[i]  = x[2*i + 1];
        end
        
        
        // Note: Ensure find_modulus and find_primitive_root are accessible 
        // (either in primitive_root_pkg or defined in this class)
        modul     = primitive_root_pkg::find_modulus(halfSize, mod);
        prim_root = primitive_root_pkg::find_primitive_root(halfSize, modul - 1, modul);
        
 
        ntt16_verifier::ntt16(X_even, prim_root, modul, X_even);
        ntt16_verifier::ntt16(X_odd, prim_root, modul, X_odd);
        
        // Butterfly operations: Combine even and odd parts with twiddle factors
        for (int k = 0; k < halfSize; k++) begin
            // Calculate T[k] = r^k * X_odd[k] mod mod
            TS[k] = pow_mod(r, k, mod);
            T[k]  = int'((longint'(TS[k]) * X_odd[k]) % mod);
            
            // Butterfly combination
            sme1[k] = (int'(X_even[k]) + T[k]) % mod;
            sme2[k] = (int'(X_even[k]) - T[k]) % mod;
            
            // Ensure positive modulo result
            if (sme2[k] < 0) sme2[k] += mod;
        end
        
        // Combine results into quotient array
        quotient = new[totalSize];
        for (int i = 0; i < halfSize; i++) begin
            quotient[i]            = sme1[i];
            quotient[i + halfSize] = sme2[i];
        end
        
    endfunction : ntt32

endclass : ntt32_verifier



class ntt64_verifier;

    /**
     * Helper function for modular exponentiation
     * Calculates (base^exponent) % modulus
     */
    static function automatic int pow_mod(
        input int base,
        input int exponent,
        input int modulus
    );
        longint result = 1;
        longint b = base % modulus;
        int e = exponent;
        
        while (e > 0) begin
            if (e & 1) begin
                result = (result * b) % modulus;
            end
            b = (b * b) % modulus;
            e = e >> 1;
        end
        
        return int'(result);
    endfunction : pow_mod

    /**
     * ntt64 SystemVerilog function for testbench
     * Performs a 4-point (or size N) decimation-in-time NTT
     */
    static function automatic void ntt64(
        ref longint x[],              // Input array
        input int r,               // Root of unity
        input int mod,             // Modulus
        ref longint quotient[]         // Output array
    );
        // Local variables
        int totalSize;
        int halfSize;
        longint X_even[];
        longint X_odd[];
        int TS[];
        int T[];
        int sme1[];
        int sme2[];
        int modul;
        int prim_root;

        totalSize = x.size();
        halfSize  = totalSize / 2;
        
        // Dynamic array allocation
        X_even   = new[halfSize];
        X_odd    = new[halfSize];
        TS       = new[halfSize];
        T        = new[halfSize];
        sme1     = new[halfSize];
        sme2     = new[halfSize];
        
        // Extract even and odd indices (Decimation in Time)
        for (int i = 0; i < halfSize; i++) begin
            X_even[i] = x[2*i];
            X_odd[i]  = x[2*i + 1];
        end
        
       
        // Note: Ensure find_modulus and find_primitive_root are accessible 
        // (either in primitive_root_pkg or defined in this class)
        modul     = primitive_root_pkg::find_modulus(halfSize, mod);
        prim_root = primitive_root_pkg::find_primitive_root(halfSize, modul - 1, modul);
        
     
        ntt32_verifier::ntt32(X_even, prim_root, modul, X_even);
        ntt32_verifier::ntt32(X_odd, prim_root, modul, X_odd);
        
        // Butterfly operations: Combine even and odd parts with twiddle factors
        for (int k = 0; k < halfSize; k++) begin
            // Calculate T[k] = r^k * X_odd[k] mod mod
            TS[k] = pow_mod(r, k, mod);
            T[k]  = int'((longint'(TS[k]) * X_odd[k]) % mod);
            
            // Butterfly combination
            sme1[k] = (int'(X_even[k]) + T[k]) % mod;
            sme2[k] = (int'(X_even[k]) - T[k]) % mod;
            
            // Ensure positive modulo result
            if (sme2[k] < 0) sme2[k] += mod;
        end
        
        // Combine results into quotient array
        quotient = new[totalSize];
        for (int i = 0; i < halfSize; i++) begin
            quotient[i]            = sme1[i];
            quotient[i + halfSize] = sme2[i];
        end
        
    endfunction : ntt64

endclass : ntt64_verifier


class ntt128_verifier;

    /**
     * Helper function for modular exponentiation
     * Calculates (base^exponent) % modulus
     */
    static function automatic int pow_mod(
        input int base,
        input int exponent,
        input int modulus
    );
        longint result = 1;
        longint b = base % modulus;
        int e = exponent;
        
        while (e > 0) begin
            if (e & 1) begin
                result = (result * b) % modulus;
            end
            b = (b * b) % modulus;
            e = e >> 1;
        end
        
        return int'(result);
    endfunction : pow_mod

    /**
     * ntt128 SystemVerilog function for testbench
     * Performs a 4-point (or size N) decimation-in-time NTT
     */
    static function automatic void ntt128(
        ref longint x[],              // Input array
        input int r,               // Root of unity
        input int mod,             // Modulus
        ref longint quotient[]         // Output array
    );
        // Local variables
        int totalSize;
        int halfSize;
        longint X_even[];
        longint X_odd[];
        int TS[];
        int T[];
        int sme1[];
        int sme2[];
        int modul;
        int prim_root;

        totalSize = x.size();
        halfSize  = totalSize / 2;
        
        // Dynamic array allocation
        X_even   = new[halfSize];
        X_odd    = new[halfSize];
        TS       = new[halfSize];
        T        = new[halfSize];
        sme1     = new[halfSize];
        sme2     = new[halfSize];
        
        // Extract even and odd indices (Decimation in Time)
        for (int i = 0; i < halfSize; i++) begin
            X_even[i] = x[2*i];
            X_odd[i]  = x[2*i + 1];
        end
        
       
        // Note: Ensure find_modulus and find_primitive_root are accessible 
        // (either in primitive_root_pkg or defined in this class)
        modul     = primitive_root_pkg::find_modulus(halfSize, mod);
        prim_root = primitive_root_pkg::find_primitive_root(halfSize, modul - 1, modul);
        
      
        ntt64_verifier::ntt64(X_even, prim_root, modul, X_even);
        ntt64_verifier::ntt64(X_odd, prim_root, modul, X_odd);
        
        // Butterfly operations: Combine even and odd parts with twiddle factors
        for (int k = 0; k < halfSize; k++) begin
            // Calculate T[k] = r^k * X_odd[k] mod mod
            TS[k] = pow_mod(r, k, mod);
            T[k]  = int'((longint'(TS[k]) * X_odd[k]) % mod);
            
            // Butterfly combination
            sme1[k] = (int'(X_even[k]) + T[k]) % mod;
            sme2[k] = (int'(X_even[k]) - T[k]) % mod;
            
            // Ensure positive modulo result
            if (sme2[k] < 0) sme2[k] += mod;
        end
        
        // Combine results into quotient array
        quotient = new[totalSize];
        for (int i = 0; i < halfSize; i++) begin
            quotient[i]            = sme1[i];
            quotient[i + halfSize] = sme2[i];
        end
        
    endfunction : ntt128

endclass : ntt128_verifier


class ntt256_verifier;

    /**
     * Helper function for modular exponentiation
     * Calculates (base^exponent) % modulus
     */
    static function automatic int pow_mod(
        input int base,
        input int exponent,
        input int modulus
    );
        longint result = 1;
        longint b = base % modulus;
        int e = exponent;
        
        while (e > 0) begin
            if (e & 1) begin
                result = (result * b) % modulus;
            end
            b = (b * b) % modulus;
            e = e >> 1;
        end
        
        return int'(result);
    endfunction : pow_mod

    /**
     * ntt256 SystemVerilog function for testbench
     * Performs a 4-point (or size N) decimation-in-time NTT
     */
    static function automatic void ntt256(
        ref longint x[],              // Input array
        input int r,               // Root of unity
        input int mod,             // Modulus
        ref longint quotient[]         // Output array
    );
        // Local variables
        int totalSize;
        int halfSize;
        longint X_even[];
        longint X_odd[];
        int TS[];
        int T[];
        int sme1[];
        int sme2[];
        int modul;
        int prim_root;

        totalSize = x.size();
        halfSize  = totalSize / 2;
        
        // Dynamic array allocation
        X_even   = new[halfSize];
        X_odd    = new[halfSize];
        TS       = new[halfSize];
        T        = new[halfSize];
        sme1     = new[halfSize];
        sme2     = new[halfSize];
        
        // Extract even and odd indices (Decimation in Time)
        for (int i = 0; i < halfSize; i++) begin
            X_even[i] = x[2*i];
            X_odd[i]  = x[2*i + 1];
        end
        
        
        // Note: Ensure find_modulus and find_primitive_root are accessible 
        // (either in primitive_root_pkg or defined in this class)
        modul     = primitive_root_pkg::find_modulus(halfSize, mod);
        prim_root = primitive_root_pkg::find_primitive_root(halfSize, modul - 1, modul);
        
       
        ntt128_verifier::ntt128(X_even, prim_root, modul, X_even);
        ntt128_verifier::ntt128(X_odd, prim_root, modul, X_odd);
        
        // Butterfly operations: Combine even and odd parts with twiddle factors
        for (int k = 0; k < halfSize; k++) begin
            // Calculate T[k] = r^k * X_odd[k] mod mod
            TS[k] = pow_mod(r, k, mod);
            T[k]  = int'((longint'(TS[k]) * X_odd[k]) % mod);
            
            // Butterfly combination
            sme1[k] = (int'(X_even[k]) + T[k]) % mod;
            sme2[k] = (int'(X_even[k]) - T[k]) % mod;
            
            // Ensure positive modulo result
            if (sme2[k] < 0) sme2[k] += mod;
        end
        
        // Combine results into quotient array
        quotient = new[totalSize];
        for (int i = 0; i < halfSize; i++) begin
            quotient[i]            = sme1[i];
            quotient[i + halfSize] = sme2[i];
        end
        
    endfunction : ntt256

endclass : ntt256_verifier



/*
// Alternative version with dynamic array allocation inside
function automatic int unsigned ntt4_with_return(
    ref int x[],
    input int r,
    input int mod
);
    int quotient[];
    ntt4(x, r, mod, quotient);
    
    // If you need to return something, you could return the size
    return quotient.size();
endfunction : ntt4_with_return
*/
// Testbench example showing usage
// import primitive_root_pkg::*;
module nttg_tb;
    longint x[];
    longint quotient[];
    int r, mod;
    int n;
int root_found;
import primitive_root_pkg::*;
    initial begin
        // Example test
        n = 256;
        x = new[n];
            // Method 1: Using generate block to create an array
   x = '{
850417, 981190, 547755, 22656, 936473, 648349, 459590, 776277, 173531, 304801, 48070, 183171, 494912, 134513, 162584, 626621, 284587, 914713, 940605, 421366, 936300, 1007585, 669661, 846451, 50254, 884670, 303679, 850130, 986852, 822412, 477792, 839867, 344200, 639430, 5460, 561555, 319457, 317185, 133724, 719255, 224707, 660889, 1000671, 247300, 593176, 457507, 792208, 413122, 833801, 151340, 732662, 81070, 539906, 479258, 258901, 44092, 601289, 397245, 86075, 771684, 609267, 996118, 487804, 265958, 757927, 167035, 448389, 942322, 759542, 838389, 953197, 666208, 640280, 130335, 391029, 657378, 631321, 405613, 900225, 666704, 895628, 330686, 964865, 693238, 54471, 335355, 82016, 443505, 904784, 870288, 906048, 683141, 1007866, 120883, 338690, 965499, 810947, 629127, 768967, 183283, 503427, 141589, 368498, 328201, 633422, 177318, 479397, 160693, 991508, 691837, 376761, 791873, 979448, 154442, 149954, 957867, 981605, 1042429, 682865, 604860, 594653, 89560, 538996, 590322, 591251, 6423, 317418, 927255, 77383, 273545, 249130, 479924, 63656, 956117, 138921, 505184, 167507, 246938, 818891, 866535, 771444, 811089, 186568, 428569, 663948, 201841, 47903, 869264, 662761, 830674, 298173, 272633, 33654, 212746, 753819, 934313, 178744, 29971, 565439, 482278, 92018, 899071, 562169, 717052, 882265, 709203, 102146, 747440, 278500, 431988, 493331, 753176, 202773, 1026443, 114757, 745381, 16276, 987165, 314629, 51533, 211036, 1034489, 913730, 834734, 330030, 690148, 614168, 520128, 719458, 730780, 84407, 772978, 101059, 881338, 474491, 319250, 1034985, 213884, 482476, 19528, 583882, 921805, 196182, 474428, 976688, 891475, 208321, 487237, 311137, 301882, 232533, 310662, 200402, 394610, 795873, 78286, 703838, 674736, 186643, 585336, 699751, 806144, 295182, 270776, 409671, 1013177, 805058, 32460, 512204, 888659, 807042, 403811, 988593, 351140, 618851, 286074, 722058, 368166, 777253, 986408, 514155, 618406, 151787, 19856, 314936, 477570, 687941, 571011, 240329, 957893, 120560, 14235, 710087, 115861, 899704, 887222
};


        
       
        r = 462262;
        mod = 1049089;
        
       root_found =  find_primitive_root(
         n,
         mod-1,
         mod
    );

        ntt256_verifier::ntt256(x,r,  mod, quotient);
        //$display("=======================");
        //$display("root_found: %p", root_found);
        //$display("Input array: %p", x);
        //$display("r: %p", r);
        //$display("mod: %p",mod);
        //$display("NTT4 result: %p", quotient);
        
        // Verify result (example check - adjust based on your needs)
        if (quotient.size() == x.size()) begin
            //$display("Test passed: Output size matches input size");
        end else begin
            //$display("Test failed: Output size mismatch");
        end
        
        #10 $finish;
    end
    
endmodule : nttg_tb

