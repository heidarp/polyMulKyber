"""Static verification of the Kyber_Mul RTL constants and twiddle schedules.

Rebuilds, from the parameters baked into the RTL, the exact sequence of twiddles
each stage emits, then runs the whole forward/basemul/inverse chain against a
plain negacyclic convolution.
"""

Q = 3329
ZETA = 17
N = 256
CNT_W = 7  # PHI_S1_CNT_WIDTH = clog2(128)

# ---- constants read out of ntt_pkg.sv / mul.sv / scalled.sv -------------------
INITIAL_VALUE_W = [2580, 2642, 1062, 296, 289, 17]          # fwd stages 1..6
INITIAL_VALUE_WINV = [1175, 2419, 2508, 1583, 2481, 40, 1600]  # inv stages 0..6
STAGE0_W = 1729          # hardcoded in stage0_fntt.sv
BASEMUL_INITIAL_W = INITIAL_VALUE_W[5]   # mul.sv passes INITIAL_VALUE_W[5]
SCALLED_CONST = 3303     # scalled.sv
BARRETT_U, BARRETT_K = 5039, 24


def br(x, bits=CNT_W):
    return int(format(x, f"0{bits}b")[::-1], 2)


# reference Kyber zetas: zetas[k] = 17^br7(k)
zetas = [pow(ZETA, br(k), Q) for k in range(128)]


def w_gen(initial_w, cnt_rst, fwd):
    """Model of w_gen.sv: initial_w * base^br7(cnt) for cnt = 0..cnt_rst-1."""
    base = ZETA if fwd else pow(ZETA, -1, Q)
    return [initial_w * pow(base, br(c), Q) % Q for c in range(cnt_rst)]


ok = True


def check(name, cond, extra=""):
    global ok
    ok &= bool(cond)
    print(f"{'PASS' if cond else 'FAIL'}  {name}{('  ' + extra) if extra else ''}")


print("=== primitive constants ===")
check("17 has order 256 mod 3329", pow(ZETA, 128, Q) == Q - 1 and pow(ZETA, 256, Q) == 1)
check("no 512th root of unity mod 3329", (Q - 1) % 512 != 0, f"q-1 = {Q-1} = 2^8*13")
check("3303 == 128^-1 mod 3329", SCALLED_CONST == pow(128, -1, Q))
check("Barrett U == floor(2^24/3329)", BARRETT_U == (1 << BARRETT_K) // Q)
check("shift-add 5039", (1 << 13) - (1 << 11) - (1 << 10) - (1 << 6) - (1 << 4) - 1 == 5039)
check("shift-add 3329", (1 << 12) - (1 << 10) + (1 << 8) + 1 == 3329)
check("shift-add 17", (1 << 4) + 1 == 17)
check("shift-add 1175 == 17^-1",
      (1 << 11) - (1 << 9) - (1 << 8) - (1 << 6) - (1 << 5) - (1 << 3) - 1 == pow(ZETA, -1, Q))

print("\n=== forward twiddle schedule vs reference zetas ===")
check("stage0 constant 1729 == zetas[1]", STAGE0_W == zetas[1], f"zetas[1]={zetas[1]}")
FWD_W = [[STAGE0_W]]
for s in range(1, 7):
    seq = w_gen(INITIAL_VALUE_W[s - 1], 2 ** s, fwd=True)
    ref = zetas[2 ** s: 2 ** (s + 1)]
    check(f"stage {s} twiddles == zetas[{2**s}:{2**(s+1)}]", seq == ref)
    FWD_W.append(seq)

print("\n=== basemul (mul.sv) zetas ===")
bm = w_gen(BASEMUL_INITIAL_W, 64, fwd=True)
check("mul.sv w sequence == zetas[64:128]", bm == zetas[64:128])
check("mul.sv w[i] == 17^(2*br6(i)+1)",
      all(bm[i] == pow(ZETA, 2 * br(i, 6) + 1, Q) for i in range(64)))

print("\n=== inverse twiddle schedule ===")
INV_W = []
for s in range(7):
    INV_W.append(w_gen(INITIAL_VALUE_WINV[s], 2 ** (6 - s), fwd=False))
# reference invntt consumes zetas[k--] from 127 and computes zeta*(b-a);
# the RTL computes (a-b)*w, so it should hold w == -zetas[k]
k = 127
for s in range(7):
    exp = [(-zetas[k - b]) % Q for b in range(2 ** (6 - s))]
    check(f"inv stage {s} twiddles == -zetas[{k}..{k - 2**(6-s) + 1}]", INV_W[s] == exp)
    k -= 2 ** (6 - s)


# ---- full algebraic chain ----------------------------------------------------
def fwd_ntt(a):
    r = list(a)
    length, s = 128, 0
    while length >= 2:
        b, start = 0, 0
        while start < N:
            w = FWD_W[s][b]
            for j in range(start, start + length):
                t = w * r[j + length] % Q
                r[j + length] = (r[j] - t) % Q
                r[j] = (r[j] + t) % Q
            start += 2 * length
            b += 1
        length //= 2
        s += 1
    return r


def basemul(a, b):
    r = [0] * N
    for i in range(64):
        for half in range(2):
            j = 4 * i + 2 * half
            g = bm[i] if half == 0 else (-bm[i]) % Q   # is_negate on lane 1
            a0, a1, b0, b1 = a[j], a[j + 1], b[j], b[j + 1]
            r[j] = (a0 * b0 + g * a1 * b1) % Q
            r[j + 1] = (a0 * b1 + a1 * b0) % Q
    return r


def inv_ntt(a):
    r = list(a)
    length, s = 2, 0
    while length <= 128:
        b, start = 0, 0
        while start < N:
            w = INV_W[s][b]
            for j in range(start, start + length):
                t = r[j]
                r[j] = (t + r[j + length]) % Q
                r[j + length] = (t - r[j + length]) * w % Q
            start += 2 * length
            b += 1
        length *= 2
        s += 1
    return [x * SCALLED_CONST % Q for x in r]


def negacyclic(x, y):
    r = [0] * N
    for i in range(N):
        for j in range(N):
            k, sgn = (i + j) % N, 1 if i + j < N else -1
            r[k] = (r[k] + sgn * x[i] * y[j]) % Q
    return r


print("\n=== end-to-end: INTT(basemul(NTT(x), NTT(y))) vs negacyclic convolution ===")
import random
random.seed(1)
for trial in range(3):
    x = [random.randrange(Q) for _ in range(N)]
    y = [random.randrange(Q) for _ in range(N)]
    check(f"random trial {trial}",
          inv_ntt(basemul(fwd_ntt(x), fwd_ntt(y))) == negacyclic(x, y))

# also with the testbench's own vectors
try:
    def load(p):
        with open(p) as f:
            v = [int(line.strip(), 2) for line in f if line.strip()]
        return v[:N]
    xr = load("/home/elechi/Desktop/tmp/fixed/Kyber_Mul/mem_files/xram.mem")
    yr = load("/home/elechi/Desktop/tmp/fixed/Kyber_Mul/mem_files/yram.mem")
    exp = negacyclic(xr, yr)
    got = inv_ntt(basemul(fwd_ntt(xr), fwd_ntt(yr)))
    check("testbench vectors xram.mem/yram.mem", got == exp)
    print(f"      first 8 expected coefficients: {exp[:8]}")
except Exception as e:
    print(f"      (could not use tb vectors: {e})")

print("\n" + ("ALL CHECKS PASSED" if ok else "SOME CHECKS FAILED"))
