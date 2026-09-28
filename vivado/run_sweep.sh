#!/usr/bin/env bash
# Out-of-context Vivado sweep of poly_mul.
# Eight runs: NUM_BUTFLY_PER_STAGE in {1,2,4,8} x SKIP_Y_FWD_NTT in {0,1}.
#
# Usage:
#   vivado/run_sweep.sh
#   FORCE=1 vivado/run_sweep.sh                  # rerun finished configs
#   BF_LIST="1" SKIP_LIST="1" vivado/run_sweep.sh
#   RESULTS_DIR=/path/to/out vivado/run_sweep.sh
#
# A finished run is one whose folder contains status.txt equal to PASS.
# Reports for each run are left in RESULTS_DIR/bf<N>_skip_y<S>/ so
# vivado/postprocess_sweep.py can rebuild the table later.

set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VIVADO_SETTINGS="${VIVADO_SETTINGS:-$HOME/tools/Xilinx/2025.1/Vivado/settings64.sh}"
RESULTS_DIR="${RESULTS_DIR:-$HOME/vivado_projects/polymulkyber/sweep_results}"
XDC="${XDC:-$HOME/vivado_projects/polymulkyber/polymulkyber.srcs/constrs_1/new/clk.xdc}"
PART="${PART:-xc7a100tiftg256-1L}"
BF_LIST="${BF_LIST:-1 2 4 8}"
SKIP_LIST="${SKIP_LIST:-0 1}"
FORCE="${FORCE:-0}"
THREADS="${THREADS:-$(nproc)}"

if [[ ! -f "$VIVADO_SETTINGS" ]]; then
    echo "Vivado settings not found: $VIVADO_SETTINGS" >&2
    exit 1
fi
if [[ ! -f "$XDC" ]]; then
    echo "Clock XDC not found: $XDC" >&2
    exit 1
fi

# shellcheck disable=SC1090
source "$VIVADO_SETTINGS"

mkdir -p "$RESULTS_DIR"
cp -f "$XDC" "$RESULTS_DIR/clk.xdc"

fail=0
for bf in $BF_LIST; do
    case "$bf" in
        1|2|4|8) ;;
        *) echo "unsupported butterfly count: $bf" >&2; exit 1 ;;
    esac
    for skip in $SKIP_LIST; do
        case "$skip" in
            0|1) ;;
            *) echo "skip_y must be 0 or 1, got: $skip" >&2; exit 1 ;;
        esac

        run="$RESULTS_DIR/bf${bf}_skip_y${skip}"
        mkdir -p "$run"
        cp -f "$XDC" "$run/clk.xdc"

        if [[ "$FORCE" != 1 && -f "$run/status.txt" && "$(cat "$run/status.txt")" == PASS ]]; then
            echo "=== skip bf=$bf skip_y=$skip (already PASS) ==="
            continue
        fi

        echo "=== bf=$bf skip_y=$skip  $(date) ==="
        rm -f "$run/status.txt" "$run/metrics.txt" "$run/error.txt"
        if ! BF="$bf" \
            SKIP_Y="$skip" \
            RUN_DIR="$run" \
            RTL_DIR="$ROOT/rtl" \
            XDC="$run/clk.xdc" \
            PART="$PART" \
            THREADS="$THREADS" \
            vivado -mode batch -notrace \
                -log "$run/vivado.log" \
                -journal "$run/vivado.jou" \
                -source "$ROOT/vivado/sweep_one.tcl"
        then
            echo "FAIL bf=$bf skip_y=$skip (see $run/vivado.log)" >&2
            if [[ ! -f "$run/status.txt" ]]; then
                echo FAIL > "$run/status.txt"
            fi
            fail=1
        fi
    done
done

python3 "$ROOT/vivado/postprocess_sweep.py" "$RESULTS_DIR"
exit "$fail"
