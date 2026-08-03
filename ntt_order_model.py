"""Cycle-accurate model of polyMulKyber forward_ntt, used to recover the output
ordering: which (beat, lane) of fwd_ntt_res carries which reference NTT
coefficient index, and hence which indices form each basemul pair.

Mirrors ntt_stage.sv / forward_ntt.sv / butterfly.sv / w_calc.sv.
"""

Q = 3329
N = 256          # POLYNOMIAL_LENGTH
ZETA = 17
PHI_HALF_LENGTH = 128
CNT_W = 7        # PHI_S1_CNT_WIDTH = clog2(128)
TOTAL_STAGES = 7
BF_LAT = 4       # PIPELINED_MUL_RED_DELAY = MUL_PIPE_DEPTH(1) + EXTRA(3)


def clog2(x):
    return max(0, (x - 1).bit_length())


def br7(x):
    return int(format(x & 0x7F, "07b")[::-1], 2)


# ---------------- w_calc.sv ----------------
def w_calc(stage_index, w_cnt, bf_index):
    half_step = PHI_HALF_LENGTH >> (stage_index + 1)
    bf_counter = (w_cnt + bf_index) & 0x7F
    zeta_index = br7(bf_counter) + half_step
    return pow(ZETA, zeta_index, Q)


# ---------------- ntt_pkg.sv helpers ----------------
def dpnd_fut_data(nb, stage_idx):
    threshold = {1: 8, 2: 7, 4: 6, 8: 5}.get(nb, 8)
    return 1 if stage_idx < threshold else 0


def stage_params(nb, s):
    ncps = 2 * nb
    st_num_w = 2 ** s
    if s == 0:
        delay = 1
    else:
        d = N // ((2 ** (s + 1)) * nb)
        delay = d if d >= 1 else 1
    nwg = (2 ** (s + clog2(nb) + 1)) // N
    nwg = nwg if nwg >= 1 else 1
    return dict(stage_index=s, ncps=ncps, st_num_w=st_num_w, delay=delay,
                num_w_gens=nwg, dpnd=dpnd_fut_data(nb, s), nb=nb)


class Stage:
    def __init__(self, p):
        self.p = p
        n, d = p["ncps"], p["delay"]
        self.fifo = [[0] * d for _ in range(n)]      # fifo[lane][0..d-1]
        self.cnt = 0
        self.mux_sel = 1                              # reset value '1
        self.valid_shr = [0] * (d + BF_LAT)
        self.bf_pipe = [[0] * n for _ in range(BF_LAT)]
        # w_gen counter: reset to '1 - NUM_W_GENS + 1 over CNT_W bits
        self.w_cnt = (((1 << CNT_W) - 1) - p["num_w_gens"] + 1) & ((1 << CNT_W) - 1)

    def twiddles(self):
        p = self.p
        nwg, nb = p["num_w_gens"], p["nb"]
        vals = [w_calc(p["stage_index"], self.w_cnt, bf) for bf in range(nwg)]
        w = [0] * nb
        if nwg == 1:
            for i in range(nb):
                w[i] = vals[0]
        else:  # forward: contiguous groups
            for bf in range(nwg):
                for i in range(bf * nb // nwg, (1 + bf) * nb // nwg):
                    w[i] = vals[bf]
        return w

    def step(self, in_coefs, in_valid):
        """One clock. Returns (out_coefs, out_valid) visible after this edge."""
        p = self.p
        n, d, s = p["ncps"], p["delay"], p["stage_index"]

        # ---- combinational ----
        sel_fifo = [0] * n
        sel_bf = [0] * n
        if p["dpnd"] == 1:
            A = (not self.mux_sel) if s == 0 else bool(self.mux_sel)
            for k in range(0, n, 2):
                sel_fifo[k] = in_coefs[k] if A else in_coefs[k + 1]
                sel_fifo[k + 1] = in_coefs[k] if not A else in_coefs[k + 1]
                if not self.mux_sel:
                    sel_bf[k] = self.fifo[k][d - 1]
                    sel_bf[k + 1] = in_coefs[k]
                else:
                    sel_bf[k] = self.fifo[k + 1][d - 1]
                    sel_bf[k + 1] = self.fifo[k][d - 1]
        else:
            next_loc = N // p["st_num_w"]
            swap_index = clog2(next_loc)
            swap_mask = (1 << swap_index) | 1
            for i in range(n):
                i_swap = ((i & ~swap_mask)
                          | ((i & 1) << swap_index)
                          | ((i >> swap_index) & 1))
                sel_fifo[i] = in_coefs[i_swap]
            for j in range(n):
                sel_bf[j] = self.fifo[j][d - 1]

        w = self.twiddles()
        bf_out = [0] * n
        for k in range(0, n, 2):
            a, b = sel_bf[k], sel_bf[k + 1]
            t = w[k // 2] * b % Q
            bf_out[k] = (a + t) % Q
            bf_out[k + 1] = (a - t) % Q

        cnt_rst = (self.cnt == d - 1) and in_valid

        out_coefs = list(self.bf_pipe[BF_LAT - 1])
        out_valid = self.valid_shr[d + BF_LAT - 1]

        # ---- sequential ----
        for i in range(BF_LAT - 1, 0, -1):
            self.bf_pipe[i] = self.bf_pipe[i - 1]
        self.bf_pipe[0] = bf_out

        for i in range(len(self.valid_shr) - 1, 0, -1):
            self.valid_shr[i] = self.valid_shr[i - 1]
        self.valid_shr[0] = 1 if in_valid else 0

        # fifos shift unconditionally (even lanes) / when mux_sel (odd lanes)
        new_fifo = [list(f) for f in self.fifo]
        for j in range(0, n, 2):
            for i in range(d - 1, 0, -1):
                new_fifo[j][i] = self.fifo[j][i - 1]
            new_fifo[j][0] = sel_fifo[j]
        if self.mux_sel:
            for j in range(1, n, 2):
                for i in range(d - 1, 0, -1):
                    new_fifo[j][i] = self.fifo[j][i - 1]
                new_fifo[j][0] = sel_fifo[j]
        self.fifo = new_fifo

        if cnt_rst:
            self.cnt = 0
        elif in_valid:
            self.cnt += 1
        if cnt_rst:
            self.mux_sel = 1 if (s == 0 or p["dpnd"] == 0) else (0 if self.mux_sel else 1)

        # w_gen advances on fifo_cnt_rst (generate_new_w) for FWD
        gen_new_w = cnt_rst
        nwg = p["num_w_gens"]
        if (self.w_cnt == p["st_num_w"] - nwg) and gen_new_w:
            self.w_cnt = 0
        elif gen_new_w:
            self.w_cnt = (self.w_cnt + nwg) & ((1 << CNT_W) - 1)

        return out_coefs, out_valid


def run_forward_ntt(poly, nb, extra_clocks=400):
    ncps = 2 * nb
    stages = [Stage(stage_params(nb, s)) for s in range(TOTAL_STAGES)]
    beats = N // 2 // nb
    stim = []
    for t in range(beats):
        addr_a, addr_b = t * nb, N // 2 + t * nb
        c = [0] * ncps
        for i in range(nb):
            c[2 * i] = poly[addr_a + i]
            c[2 * i + 1] = poly[addr_b + i]
        stim.append((c, True))
    stim += [([0] * ncps, False)] * extra_clocks

    out = []
    for coefs, valid in stim:
        cur_c, cur_v = coefs, valid
        for st in stages:
            cur_c, cur_v = st.step(cur_c, cur_v)
        if cur_v:
            out.append(list(cur_c))
    return out


# ---------------- reference Kyber NTT ----------------
zetas = [pow(ZETA, br7(k), Q) for k in range(128)]


def ref_ntt(a):
    r = list(a)
    length, s = 128, 0
    while length >= 2:
        b, start = 0, 0
        while start < N:
            w = zetas[2 ** s + b]
            for j in range(start, start + length):
                t = w * r[j + length] % Q
                r[j + length] = (r[j] - t) % Q
                r[j] = (r[j] + t) % Q
            start += 2 * length
            b += 1
        length //= 2
        s += 1
    return r


def basemul_zeta(pair_index):
    """gamma for reference pair `pair_index` (0..127): zeta^(2*br7(i)+1)."""
    return pow(ZETA, 2 * br7(pair_index) + 1, Q)


if __name__ == "__main__":
    import random
    random.seed(11)

    for nb in (1, 2, 4, 8):
        ncps = 2 * nb
        print("=" * 78)
        print(f"NUM_BUTFLY_PER_STAGE = {nb}   (NUM_COEFS_PER_STAGE = {ncps})")
        print("=" * 78)
        polys = [[random.randrange(Q) for _ in range(N)] for _ in range(4)]
        runs = [run_forward_ntt(p, nb) for p in polys]
        refs = [ref_ntt(p) for p in polys]

        beats = N // 2 // nb
        print(f"  valid output beats: {len(runs[0])} (expected {beats})")
        if len(runs[0]) != beats:
            print("  !! beat count mismatch, skipping")
            continue

        # match each (beat, lane) to a reference index using all runs
        mapping = {}
        ambiguous = unmatched = 0
        for t in range(beats):
            for lane in range(ncps):
                cands = [j for j in range(N)
                         if all(runs[r][t][lane] == refs[r][j] for r in range(len(runs)))]
                if len(cands) == 1:
                    mapping[(t, lane)] = cands[0]
                elif len(cands) == 0:
                    unmatched += 1
                    mapping[(t, lane)] = None
                else:
                    ambiguous += 1
                    mapping[(t, lane)] = tuple(cands)
        print(f"  unmatched: {unmatched}   ambiguous: {ambiguous}")

        vals = [v for v in mapping.values() if isinstance(v, int)]
        print(f"  distinct reference indices covered: {len(set(vals))}/{N}")

        print("\n  (beat, lane) -> reference NTT index, first 8 beats:")
        for t in range(min(8, beats)):
            row = "  ".join(f"L{l}:{mapping[(t,l)]}" for l in range(ncps))
            print(f"    beat {t:3d}   {row}")

        # where does each reference pair (2i, 2i+1) live?
        loc = {v: k for k, v in mapping.items() if isinstance(v, int)}
        print("\n  reference pair (2i, 2i+1) locations, first 8 pairs:")
        for i in range(min(8, 128)):
            a, b = loc.get(2 * i), loc.get(2 * i + 1)
            print(f"    pair {i:3d}  gamma=zeta^{2*br7(i)+1:<4d}={basemul_zeta(i):5d}   "
                  f"c[{2*i}] at {a}   c[{2*i+1}] at {b}")
