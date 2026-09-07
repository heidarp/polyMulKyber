#!/usr/bin/env python3
# =============================================================================
#  DEBUG-ONLY TOOL - not part of the design. Safe to delete together with
#  ntt_debug_probe.sv, the `NTT_DEBUG_PROBE` block in poly_mul.sv and the
#  "DEBUG PROBE" block in the Makefile.
# =============================================================================
"""Stage-by-stage checker for the Kyber poly_mul RTL.

Reads the trace written by ntt_debug_probe.sv during a VCS run and compares
every pipeline stage against a software Kyber model:

    forward NTT (x)   stage 1 .. 7
    forward NTT (y)   stage 1 .. 7
    pointwise (basemul) result
    inverse NTT       stage 1 .. 7
    final scaled output vs. the negacyclic product x*y mod (X^256 + 1)

The RTL streams two coefficients per clock and the stream order of every stage
differs from the natural coefficient order of the software model, so each stage
is checked as a *set* of values first and the beat -> coefficient mapping is
then solved for and required to be a single consistent bijection across all
polynomials in the run.  That separates the two failure modes:

    values wrong      -> arithmetic / twiddle bug
    values right,
    mapping unstable  -> ordering / FIFO / valid-alignment bug

Trace values are reduced mod q before compare.  Intermediate taps sometimes
dump q (3329) where the residue is 0; the final scaler path usually emits 0,
which is why a stage can look wrong while the end result still passes.
"""

import argparse
import os
import sys
from collections import Counter, defaultdict

if sys.version_info < (3, 6):
    sys.exit("check_ntt_stages.py requires Python 3.6 or newer")


def modinv(a, m):
    """a^-1 mod m. Works on Python 3.6+ (pow(..., -1, m) needs 3.8+)."""
    if sys.version_info >= (3, 8):
        return pow(a, -1, m)
    a %= m
    t, newt = 0, 1
    r, newr = m, a
    while newr:
        q = r // newr
        t, newt = newt, t - q * newt
        r, newr = newr, r - q * newr
    if r != 1:
        raise ValueError("modinv: not invertible")
    return t % m


# ---------------------------------------------------------------------------
# Kyber parameters (must match ntt_pkg.sv)
# ---------------------------------------------------------------------------

Q = 3329
N = 256
ROOT = 17           # W_VALUE: primitive 256-th root of unity mod q
NUM_STAGES = 7      # TOTAL_NUM_STAGES = log2(N) - 1, incomplete NTT
BRV_BITS = 7        # PHI_S1_CNT_WIDTH
SCALER = modinv(1 << NUM_STAGES, Q)   # 3303 == 128^-1 mod q


def normalize_residue(v):
    """Map RTL dump values into [0, q). Some taps emit q instead of 0."""
    r = v % Q
    return r


def brv(i: int, bits: int = BRV_BITS) -> int:
    r = 0
    for b in range(bits):
        r = (r << 1) | ((i >> b) & 1)
    return r


ZETAS = [pow(ROOT, brv(k), Q) for k in range(1 << BRV_BITS)]
INV_ZETAS = [modinv(z, Q) for z in ZETAS]


# ---------------------------------------------------------------------------
# Reference model
# ---------------------------------------------------------------------------

def forward_stages(poly):
    """Cooley-Tukey layers. Returns the 7 intermediate arrays, natural order.

    Layer L pairs (j, j+len) with len = 128 >> L and gives group g the twiddle
    zetas[2^L + g] -- the same exponent w_calc.sv builds as brv7(cnt) + 128>>(L+1).
    """
    r = list(poly)
    out = []
    for layer in range(NUM_STAGES):
        length = (N // 2) >> layer
        for g in range(1 << layer):
            zeta = ZETAS[(1 << layer) + g]
            start = g * 2 * length
            for j in range(start, start + length):
                t = zeta * r[j + length] % Q
                r[j + length] = (r[j] - t) % Q
                r[j] = (r[j] + t) % Q
        out.append(list(r))
    return out


def basemul_ref(a, b):
    """Degree-1 residue products: (a0 + a1 X)(b0 + b1 X) mod (X^2 - gamma)."""
    r = [0] * N
    for i in range(N // 4):
        zeta = ZETAS[64 + i]
        for off, gamma in ((4 * i, zeta), (4 * i + 2, Q - zeta)):
            a0, a1 = a[off], a[off + 1]
            b0, b1 = b[off], b[off + 1]
            r[off] = (a0 * b0 + gamma * a1 * b1) % Q
            r[off + 1] = (a0 * b1 + a1 * b0) % Q
    return r


def inverse_stages(poly):
    """Correct inverse: Gentleman-Sande layers, mirroring the forward network.

    Inverse stage s undoes forward layer 6-s, so it pairs (j, j+len) with
    len = 2^(s+1) and group g uses zetas[2^(6-s) + g]^-1 -- the same exponent
    w_calc.sv builds on its FWD_INV=1 path (2^s * (2*cnt+1), groups walked in
    bit-reversed counter order).  Unscaled: each stage doubles, so the result
    comes out 2^7 too large and poly_mul's SCALER multiply finishes the job.

    The butterfly here is (a+b, (a-b)*z^-1): CRT interpolation, which is what
    inverting an evaluation layer requires.  See inverse_stages_ct() for what
    the RTL's shared butterfly module actually computes.
    """
    r = list(poly)
    out = []
    for s in range(NUM_STAGES):
        length = 1 << (s + 1)
        m = NUM_STAGES - 1 - s
        for g in range(1 << m):
            zeta_inv = INV_ZETAS[(1 << m) + g]
            start = g * 2 * length
            for j in range(start, start + length):
                a, b = r[j], r[j + length]
                r[j] = (a + b) % Q
                r[j + length] = zeta_inv * (a - b) % Q
        out.append(list(r))
    return out


def inverse_stages_ct(poly):
    """Diagnostic model: the same layers with the RTL's Cooley-Tukey butterfly.

    butterfly.sv computes (a + b*w, a - b*w) for both directions, so this is
    what inverse_ntt.sv literally builds.  It is NOT the inverse transform --
    kept only so the checker can tell "wrong arithmetic" apart from "the RTL
    faithfully implements the wrong butterfly".
    """
    r = list(poly)
    out = []
    for s in range(NUM_STAGES):
        length = 1 << (s + 1)
        m = NUM_STAGES - 1 - s
        for g in range(1 << m):
            zeta_inv = INV_ZETAS[(1 << m) + g]
            start = g * 2 * length
            for j in range(start, start + length):
                t = zeta_inv * r[j + length] % Q
                r[j + length] = (r[j] - t) % Q
                r[j] = (r[j] + t) % Q
        out.append(list(r))
    return out


def apply_scaler(poly):
    return [v * SCALER % Q for v in poly]


def negacyclic_mul(a, b):
    """Schoolbook x*y in Z_q[X]/(X^256 + 1) -- the golden answer for poly_mul."""
    r = [0] * N
    for i, ai in enumerate(a):
        if not ai:
            continue
        for j, bj in enumerate(b):
            k = i + j
            if k < N:
                r[k] = (r[k] + ai * bj) % Q
            else:
                r[k - N] = (r[k - N] - ai * bj) % Q
    return [v % Q for v in r]


def self_test(trials: int = 4) -> bool:
    """Prove the model itself before trusting it as a reference for the RTL."""
    import random

    rng = random.Random(0xC0FFEE)
    ok = True
    for t in range(trials):
        x = [rng.randrange(Q) for _ in range(N)]
        y = [rng.randrange(Q) for _ in range(N)]

        xh = forward_stages(x)[-1]
        yh = forward_stages(y)[-1]
        got = apply_scaler(inverse_stages(basemul_ref(xh, yh))[-1])
        want = negacyclic_mul(x, y)
        if got != want:
            bad = sum(1 for u, v in zip(got, want) if u != v)
            print(f"  self-test {t}: FAIL ({bad}/{N} coefficients differ)")
            ok = False
        else:
            print(f"  self-test {t}: pass")
    return ok


# ---------------------------------------------------------------------------
# Trace parsing
# ---------------------------------------------------------------------------

class Trace:
    """tag -> list (per polynomial) of the values in emission order."""

    def __init__(self):
        self.beats = defaultdict(lambda: defaultdict(dict))  # tag -> poly -> beat -> coefs
        self.lanes = None
        self.lines = 0

    def load(self, path):
        with open(path) as fh:
            for lineno, line in enumerate(fh, 1):
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                parts = line.split()
                if len(parts) < 4:
                    raise ValueError(f"{path}:{lineno}: malformed trace line: {line!r}")
                tag = parts[0]
                poly = int(parts[1])
                beat = int(parts[2])
                coefs = [int(v) for v in parts[3:]]
                if self.lanes is None:
                    self.lanes = len(coefs)
                elif self.lanes != len(coefs):
                    raise ValueError(
                        f"{path}:{lineno}: {len(coefs)} lanes, expected {self.lanes}")
                self.beats[tag][poly][beat] = coefs
                self.lines += 1
        return self

    def stream(self, tag, poly):
        """Flat list of values for one polynomial, in (beat, lane) emission order."""
        per_beat = self.beats.get(tag, {}).get(poly)
        if not per_beat:
            return None
        values = []
        for beat in sorted(per_beat):
            values.extend(normalize_residue(v) for v in per_beat[beat])
        return values

    def unreduced_positions(self, tag, poly):
        """Stream positions where the raw trace value was >= q (typically q itself)."""
        per_beat = self.beats.get(tag, {}).get(poly)
        if not per_beat:
            return []
        out = []
        lanes = self.lanes or 1
        for beat in sorted(per_beat):
            for lane, v in enumerate(per_beat[beat]):
                if v >= Q:
                    out.append((beat, lane, v, normalize_residue(v)))
        return out

    def complete_polys(self, tag):
        """Polynomial indices for which this tag captured a full N values."""
        out = []
        for poly in sorted(self.beats.get(tag, {})):
            s = self.stream(tag, poly)
            if s is not None and len(s) == N:
                out.append(poly)
        return out


# ---------------------------------------------------------------------------
# Order-independent comparison
# ---------------------------------------------------------------------------

def match_bijection(cands):
    """Kuhn's algorithm: is there a perfect matching position -> coefficient index?"""
    n = len(cands)
    assign = [-1] * n          # coefficient index -> position

    def try_assign(pos, seen):
        for idx in cands[pos]:
            if idx in seen:
                continue
            seen.add(idx)
            if assign[idx] == -1 or try_assign(assign[idx], seen):
                assign[idx] = pos
                return True
        return False

    sys.setrecursionlimit(max(10000, sys.getrecursionlimit()))
    for pos in range(n):
        if not try_assign(pos, set()):
            return None
    perm = [0] * n
    for idx, pos in enumerate(assign):
        perm[pos] = idx
    return perm


class StageResult:
    def __init__(self, label):
        self.label = label
        self.status = "SKIP"
        self.detail = ""
        self.perm = None
        self.polys = 0
        # (poly, beat, lane, got, expected) for the first wrong stream positions
        self.mismatches = []

    @property
    def passed(self):
        return self.status == "PASS"


def beat_mismatches_for_poly(cap, ref, lanes, max_rows=10):
    """First stream positions where cap differs from model expectation."""
    rows = []
    if sorted(cap) != sorted(ref):
        ref_c = Counter(ref)
        cap_c = Counter(cap)
        missing = list((ref_c - cap_c).elements())
        budget = Counter(ref)
        mi = 0
        for i, v in enumerate(cap):
            if budget[v] > 0:
                budget[v] -= 1
            else:
                exp = missing[mi] if mi < len(missing) else "?"
                mi += 1
                rows.append((i // lanes, i % lanes, v, exp))
                if len(rows) >= max_rows:
                    break
        return rows

    pos_by_val = defaultdict(set)
    for i, v in enumerate(ref):
        pos_by_val[v].add(i)
    cands = [set(pos_by_val[v]) for v in cap]
    perm = match_bijection(cands)
    if perm is None:
        for i in range(len(cap)):
            if not cands[i]:
                rows.append((i // lanes, i % lanes, cap[i], "(ordering conflict)"))
            elif len(cands[i]) == 1:
                exp = ref[next(iter(cands[i]))]
                if cap[i] != exp:
                    rows.append((i // lanes, i % lanes, cap[i], exp))
            else:
                # Ambiguous mapping: compare against smallest candidate index.
                exp = ref[min(cands[i])]
                if cap[i] != exp:
                    rows.append((i // lanes, i % lanes, cap[i], f"{exp}?"))
            if len(rows) >= max_rows:
                break
        return rows

    for i in range(len(cap)):
        exp = ref[perm[i]]
        if cap[i] != exp:
            rows.append((i // lanes, i % lanes, cap[i], exp))
            if len(rows) >= max_rows:
                break
    return rows


def check_stage(label, captured, references, lanes=2, max_report=4,
                unreduced=None, max_mismatches=10):
    """captured/references: parallel lists (one entry per polynomial) of N values."""
    res = StageResult(label)
    res.polys = len(captured)
    if not captured:
        res.detail = "no complete polynomial captured in the trace"
        return res

    if unreduced is None:
        unreduced = [[] for _ in captured]

    # 1. Are the values right at all (ignoring order)?
    for p, (cap, ref) in enumerate(zip(captured, references)):
        if sorted(cap) != sorted(ref):
            budget = Counter(ref)
            extra = []
            for i, v in enumerate(cap):
                if budget[v] > 0:
                    budget[v] -= 1
                else:
                    extra.append((i, v))
            first = ", ".join(f"beat {i // lanes} lane {i % lanes} = {v}"
                              for i, v in extra[:max_report])
            res.status = "FAIL"
            res.detail = (f"poly {p}: {len(extra)}/{N} values are not produced by the "
                          f"model" + (f" (e.g. {first})" if first else ""))
            for beat, lane, got, exp in beat_mismatches_for_poly(
                    cap, ref, lanes, max_mismatches):
                res.mismatches.append((p, beat, lane, got, exp))
            return res

    warn = []
    for p, hits in enumerate(unreduced):
        for beat, lane, raw, reduced in hits[:max_report]:
            warn.append(f"poly {p} beat {beat} lane {lane}: raw {raw} -> {reduced}")
    if warn:
        note = "unreduced residue(s) in trace, treated as mod q: " + "; ".join(warn)
        if len(warn) < sum(len(h) for h in unreduced):
            note += "; ..."
        res.detail = note

    # 2. Values are right -- is the beat -> coefficient mapping one fixed bijection?
    cands = None
    for cap, ref in zip(captured, references):
        pos_by_val = defaultdict(set)
        for i, v in enumerate(ref):
            pos_by_val[v].add(i)
        this = [set(pos_by_val[v]) for v in cap]
        cands = this if cands is None else [a & b for a, b in zip(cands, this)]

    empty = [i for i, c in enumerate(cands) if not c]
    if empty:
        i = empty[0]
        res.status = "FAIL"
        res.detail = (f"values match per-polynomial but no single output order explains "
                      f"all {len(captured)} polynomials (first conflict at beat "
                      f"{i // lanes} lane {i % lanes})")
        p = 0
        cap, ref = captured[p], references[p]
        for beat, lane, got, exp in beat_mismatches_for_poly(
                cap, ref, lanes, max_mismatches):
            res.mismatches.append((p, beat, lane, got, exp))
        return res

    perm = match_bijection(cands)
    if perm is None:
        res.status = "FAIL"
        res.detail = "no consistent one-to-one beat -> coefficient mapping exists"
        p = 0
        cap, ref = captured[p], references[p]
        for beat, lane, got, exp in beat_mismatches_for_poly(
                cap, ref, lanes, max_mismatches):
            res.mismatches.append((p, beat, lane, got, exp))
        return res

    res.status = "PASS"
    res.perm = perm
    ambiguous = sum(1 for c in cands if len(c) > 1)
    if ambiguous:
        amb = (f"order not fully pinned down ({ambiguous} positions ambiguous, "
               f"repeated values); run more polynomials to disambiguate")
        res.detail = amb if not res.detail else f"{res.detail}; {amb}"
    return res


# ---------------------------------------------------------------------------
# Mapping description
# ---------------------------------------------------------------------------

def known_orders(lanes):
    """Stream orders worth naming when one is discovered."""
    beats = N // lanes
    orders = {}
    orders["sequential (beat*lanes + lane)"] = [b * lanes + l
                                                for b in range(beats) for l in range(lanes)]
    # What the testbench drives: coefs[2i] = c[addr_a+i], coefs[2i+1] = c[addr_b+i]
    # with addr_a starting at 0, addr_b at N/2, both advancing by lanes/2 per beat.
    orders["input order (lane0 = c[i], lane1 = c[i+128])"] = [
        b * (lanes // 2) + (l // 2) + (l % 2) * (N // 2)
        for b in range(beats) for l in range(lanes)]
    if lanes == 2:
        orders["bit-reversed residue order"] = [
            2 * brv(b, BRV_BITS) + l for b in range(beats) for l in range(lanes)]
    return orders


def describe_perm(perm, lanes):
    if perm is None:
        return "unknown"
    for name, order in known_orders(lanes).items():
        if order == perm:
            return name
    head = ", ".join(f"b{ i // lanes }l{ i % lanes }->c{ v }" for i, v in enumerate(perm[:6]))
    return f"custom ({head}, ...)"


# ---------------------------------------------------------------------------
# Driver
# ---------------------------------------------------------------------------

def reconstruct_inputs(trace, tag, lanes):
    """Undo the testbench's streaming order to recover the natural-order polynomial.

    tb_poly_mul / tb_poly_mul_rand drive coefs[2i] = c[addr_a+i] and
    coefs[2i+1] = c[addr_b+i] with addr_a from 0 and addr_b from 128.
    """
    order = known_orders(lanes)["input order (lane0 = c[i], lane1 = c[i+128])"]
    polys = {}
    for p in trace.complete_polys(tag):
        stream = trace.stream(tag, p)
        poly = [0] * N
        for pos, idx in enumerate(order):
            poly[idx] = stream[pos]
        polys[p] = poly
    return polys


def print_mismatch_table(title, result, max_rows=10):
    """Print got vs expected rows for one failed stage."""
    if not result.mismatches:
        return False
    print(f"  Wrong beats ({title} / {result.label}):")
    print(f"  {'poly':>4}  {'beat':>4}  {'lane':>4}  {'got':>6}  expected")
    print(f"  {'----':>4}  {'----':>4}  {'----':>4}  {'----':>6}  --------")
    for poly, beat, lane, got, expected in result.mismatches[:max_rows]:
        print(f"  {poly:4d}  {beat:4d}  {lane:4d}  {got:6}  {expected}")
    if len(result.mismatches) > max_rows:
        print(f"  ... {len(result.mismatches) - max_rows} more mismatch(es) not shown")
    return True


def print_mismatch_tables(groups, max_rows=10):
    """Print got vs expected for the first wrong beats of each failed stage."""
    any_rows = False
    for title, results in groups:
        for r in results:
            if r.status != "FAIL":
                continue
            if print_mismatch_table(title, r, max_rows):
                any_rows = True
            print()
    return any_rows


def report_group(title, results, out=sys.stdout, max_mismatches=10,
                 show_mismatch_table=True):
    print(f"\n{title}", file=out)
    print("-" * len(title), file=out)
    for r in results:
        line = f"  {r.label:<28} {r.status}"
        if r.detail:
            line += f"   {r.detail}"
        print(line, file=out)
        if show_mismatch_table and r.status == "FAIL":
            print_mismatch_table(title, r, max_mismatches)
    ok = all(r.passed for r in results)
    print(f"  => {title}: {'PASSED' if ok else 'FAILED'}", file=out)
    return ok


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("-t", "--trace", default="ntt_debug_trace.txt",
                    help="trace file written by ntt_debug_probe.sv")
    ap.add_argument("--selftest", action="store_true",
                    help="only validate the software model, no trace needed")
    ap.add_argument("--show-map", action="store_true",
                    help="print the discovered beat -> coefficient order per stage")
    ap.add_argument("--max-mismatches", type=int, default=10,
                    help="max wrong beats to tabulate per failed stage (default: 10)")
    ap.add_argument("--no-mismatch-table", action="store_true",
                    help="do not print got vs expected tables for failed stages")
    ap.add_argument("--max-polys", type=int, default=1,
                    help="limit how many polynomials are checked (0 = all, default: 1)")
    args = ap.parse_args(argv)

    print("Kyber NTT multiplier stage checker")
    print(f"  q={Q}  n={N}  root={ROOT}  stages={NUM_STAGES}  n^-1={SCALER}")

    print("\nSoftware model self-test")
    print("------------------------")
    if not self_test():
        print("\nThe reference model itself is inconsistent -- aborting.")
        return 2
    if args.selftest:
        return 0

    if not os.path.exists(args.trace):
        print(f"\nTrace file {args.trace!r} not found.\n"
              f"Build and run with the probe enabled, e.g.:\n"
              f"    make poly_mul DEBUG_PROBE=1\n", file=sys.stderr)
        return 2

    trace = Trace().load(args.trace)
    lanes = trace.lanes
    print(f"\nTrace: {args.trace}  ({trace.lines} beats, {lanes} coefficients/beat, "
          f"{len(trace.beats)} tapped signals)")

    if lanes is None or trace.lines == 0:
        print("\nError: trace file has no coefficient data (only headers or empty).\n"
              "The checker needs at least one valid beat from the probe.\n"
              "Common causes:\n"
              "  1. Simulation ended at time 0 ($fatal) before reset was released\n"
              "     -> read simulation.log for [TB] Failed to open or Expected N decimal values\n"
              "  2. Ran from the wrong directory (mem_files/x.txt not found)\n"
              "  3. Built without the probe: make poly_mul DEBUG_PROBE=1\n"
              "  4. Stale empty trace from a failed run; re-run the simulation\n"
              "\n"
              "Look near the end of simulation.log for:\n"
              "  [ntt_debug_probe] beats captured ...\n"
              "Every tag should show 128 beats per polynomial (256 coeffs / 2 lanes).\n"
              "Re-run: make clean && make poly_mul DEBUG_PROBE=1 NUM_POLY=1",
              file=sys.stderr)
        return 2

    beats_per_poly = N // lanes
    ragged = []
    for tag in sorted(trace.beats):
        total = sum(len(b) for b in trace.beats[tag].values())
        if total % beats_per_poly:
            ragged.append((tag, total))
    if ragged:
        print(f"\nWarning: these taps did not emit a whole number of polynomials "
              f"({beats_per_poly} beats each). A stage that asserts valid for the wrong "
              f"number of cycles shifts every later beat, so the stage checks below will "
              f"report ordering failures:")
        for tag, total in ragged:
            print(f"    {tag:<6} {total} beats "
                  f"({total // beats_per_poly} polynomials + {total % beats_per_poly})")

    xs = reconstruct_inputs(trace, "x_in", lanes)
    ys = reconstruct_inputs(trace, "y_in", lanes)
    common = sorted(set(xs) & set(ys))
    if args.max_polys:
        common = common[:args.max_polys]
    if not common:
        print("No complete input polynomial captured -- did the simulation run long "
              "enough for at least 128 valid beats?", file=sys.stderr)
        return 2
    print(f"Polynomials checked: {len(common)}  (indices {common[0]}..{common[-1]})")

    # Per-polynomial golden data.
    ref = {}
    for p in common:
        fx = forward_stages(xs[p])
        fy = forward_stages(ys[p])
        pm = basemul_ref(fx[-1], fy[-1])
        iv = inverse_stages(pm)
        ref[p] = {
            "fx": fx,
            "fy": fy,
            "pm": pm,
            "iv": iv,
            "iv_ct": inverse_stages_ct(pm),
            "out": apply_scaler(iv[-1]),
            "out_ct": apply_scaler(inverse_stages_ct(pm)[-1]),
            "gold": negacyclic_mul(xs[p], ys[p]),
        }

    # The model's own end-to-end answer must equal the schoolbook product, per input.
    for p in common:
        if ref[p]["out"] != ref[p]["gold"]:
            print(f"Model disagrees with schoolbook product for poly {p} -- aborting.",
                  file=sys.stderr)
            return 2

    def gather(tag):
        polys = [p for p in common if p in set(trace.complete_polys(tag))]
        return polys, [trace.stream(tag, p) for p in polys]

    def pick(p, key, stage):
        return ref[p][key] if stage is None else ref[p][key][stage]

    def run(tag, label, ref_key, stage=None, alt_key=None):
        polys, captured = gather(tag)
        refs = [pick(p, ref_key, stage) for p in polys]
        unreduced = [trace.unreduced_positions(tag, p) for p in polys]
        r = check_stage(label, captured, refs, lanes, unreduced=unreduced,
                        max_mismatches=args.max_mismatches)
        if not captured:
            r.detail = r.detail or f"tag {tag!r} missing from the trace"
            return r
        # A failing inverse stage is worth a second opinion: does it instead match
        # the Cooley-Tukey network the RTL's shared butterfly actually builds?
        if r.status == "FAIL" and alt_key:
            alt = check_stage(label, captured, [pick(p, alt_key, stage) for p in polys],
                              lanes, unreduced=unreduced,
                              max_mismatches=args.max_mismatches)
            if alt.passed:
                r.detail = ("matches the Cooley-Tukey butterfly the RTL builds, which is "
                            "not the inverse transform (needs Gentleman-Sande)")
        if len(polys) < len(common):
            note = f"only {len(polys)}/{len(common)} polynomials captured"
            r.detail = f"{note}; {r.detail}" if r.detail else note
        return r

    groups = []

    fwd_x = [run(f"fx{s + 1}", f"stage {s + 1}", "fx", s) for s in range(NUM_STAGES)]
    groups.append(("Forward NTT of x", fwd_x))

    fwd_y = [run(f"fy{s + 1}", f"stage {s + 1}", "fy", s) for s in range(NUM_STAGES)]
    groups.append(("Forward NTT of y", fwd_y))

    groups.append(("Pointwise multiply (basemul)",
                   [run("pm", "basemul result", "pm")]))

    inv = [run(f"in{s + 1}", f"stage {s + 1}", "iv", s, alt_key="iv_ct")
           for s in range(NUM_STAGES)]
    groups.append(("Inverse NTT", inv))

    groups.append(("Final result (x*y mod X^256+1)",
                   [run("out", "scaled output", "out", alt_key="out_ct")]))

    overall = True
    show_tables = not args.no_mismatch_table
    for title, results in groups:
        overall &= report_group(title, results, max_mismatches=args.max_mismatches,
                                show_mismatch_table=show_tables)

    print("\n==================================================")
    print(f"OVERALL: {'PASS' if overall else 'FAIL'}")
    print("==================================================")

    if args.show_map:
        print("\nDiscovered stream order per stage")
        print("---------------------------------")
        for title, results in groups:
            for r in results:
                if r.perm is not None:
                    where = f"{title} / {r.label}"
                    print(f"  {where:<46} {describe_perm(r.perm, lanes)}")

    return 0 if overall else 1


if __name__ == "__main__":
    sys.exit(main())
