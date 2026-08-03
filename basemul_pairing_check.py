"""Verify the basemul operand pairing derived from ntt_order_model, for every
NUM_BUTFLY_PER_STAGE, using the Karatsuba form.

Rule under test
---------------
Group the forward-NTT output stream into "quads" of 4 coefficient slots. Quad g
(g = 0..63, in stream order) needs gamma = zetas[64+g] = zeta^(2*br6(g)+1), and
holds two residue pairs: one using +gamma, one using -gamma.

  NUM_COEFS_PER_STAGE == 2 : quad g = beats (2g, 2g+1) x lanes (0, 1)
        +gamma pair: a0 = coefs[0]@2g,   a1 = coefs[0]@2g+1
        -gamma pair: a0 = coefs[1]@2g,   a1 = coefs[1]@2g+1

  NUM_COEFS_PER_STAGE >= 4 : quad g = beat t, lanes (4k .. 4k+3),
                             with g = t*(NCPS/4) + k
        +gamma pair: a0 = coefs[4k],   a1 = coefs[4k+2]
        -gamma pair: a0 = coefs[4k+1], a1 = coefs[4k+3]
"""

from ntt_order_model import (Q, N, ZETA, br7, run_forward_ntt, ref_ntt, zetas)
import random

random.seed(23)


def br6(x):
    return int(format(x & 0x3F, "06b")[::-1], 2)


def karatsuba_basemul(a0, a1, b0, b1, gamma):
    p00 = a0 * b0 % Q
    p11 = a1 * b1 % Q
    s = (a0 + a1) * (b0 + b1) % Q
    c0 = (p00 + p11 * gamma) % Q
    c1 = (s - p00 - p11) % Q
    return c0, c1


def ref_basemul(fa, fb):
    r = [0] * N
    for i in range(128):
        g = pow(ZETA, 2 * br7(i) + 1, Q)
        a0, a1, b0, b1 = fa[2 * i], fa[2 * i + 1], fb[2 * i], fb[2 * i + 1]
        r[2 * i] = (a0 * b0 + g * a1 * b1) % Q
        r[2 * i + 1] = (a0 * b1 + a1 * b0) % Q
    return r


def build_map(nb, beats, ncps):
    polys = [[random.randrange(Q) for _ in range(N)] for _ in range(4)]
    runs = [run_forward_ntt(p, nb) for p in polys]
    refs = [ref_ntt(p) for p in polys]
    m = {}
    for t in range(beats):
        for lane in range(ncps):
            cands = [j for j in range(N)
                     if all(runs[r][t][lane] == refs[r][j] for r in range(len(runs)))]
            m[(t, lane)] = cands[0] if len(cands) == 1 else None
    return m


print("gamma for quad g is zetas[64+g] = zeta^(2*br6(g)+1)\n")

for nb in (1, 2, 4, 8):
    ncps, beats = 2 * nb, N // 2 // nb
    x = [random.randrange(Q) for _ in range(N)]
    y = [random.randrange(Q) for _ in range(N)]
    sx, sy = run_forward_ntt(x, nb), run_forward_ntt(y, nb)
    ref = ref_basemul(ref_ntt(x), ref_ntt(y))

    res = [[None] * ncps for _ in range(beats)]
    quads_per_beat = max(1, ncps // 4)

    if ncps == 2:
        for g in range(beats // 2):
            gp = zetas[64 + g]
            for lane, gam in ((0, gp), (1, (Q - gp) % Q)):
                c0, c1 = karatsuba_basemul(sx[2 * g][lane], sx[2 * g + 1][lane],
                                           sy[2 * g][lane], sy[2 * g + 1][lane], gam)
                res[2 * g][lane], res[2 * g + 1][lane] = c0, c1
    else:
        for t in range(beats):
            for k in range(quads_per_beat):
                g = t * quads_per_beat + k
                gp = zetas[64 + g]
                for off, gam in ((0, gp), (1, (Q - gp) % Q)):
                    la, lb = 4 * k + off, 4 * k + off + 2
                    c0, c1 = karatsuba_basemul(sx[t][la], sx[t][lb],
                                              sy[t][la], sy[t][lb], gam)
                    res[t][la], res[t][lb] = c0, c1

    m = build_map(nb, beats, ncps)
    bad = sum(1 for t in range(beats) for l in range(ncps)
              if m[(t, l)] is None or res[t][l] != ref[m[(t, l)]])
    print(f"NUM_COEFS_PER_STAGE={ncps:2d}  beats={beats:3d}  quads/beat={quads_per_beat}  "
          f"gamma per beat={quads_per_beat}  mismatches={bad}/{beats*ncps}  "
          f"{'PASS' if bad == 0 else 'FAIL'}")

print("\ngamma sequence in stream order (quads 0..7):")
print(f"  {[zetas[64 + g] for g in range(8)]}")
print(f"  = zeta^{[2*br6(g)+1 for g in range(8)]}")
print("  identical to the sequence forward stage 6 already consumes")
