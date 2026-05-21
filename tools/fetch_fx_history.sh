#!/usr/bin/env bash
#
# fetch_fx_history.sh — regenerate assets/fx_history.csv from ECB data.
#
# This is a DEVELOPMENT tool. It is not shipped in the app and is not run at
# runtime. It produced the bundled `assets/fx_history.csv`; re-run it to extend
# the dataset's date range when the bundled history starts to fall behind.
#
# WHAT IT DOES
#   The app's BTC price history (`assets/btc_history.csv`) is USD-only. To draw
#   that chart in EUR/GBP/AUD/CAD/CHF/JPY with historically-accurate rates,
#   each day's USD price is multiplied by that day's USD->fiat rate. This
#   script builds the daily USD->fiat table.
#
#   Source: ECB daily reference rates (free, public, no API key). ECB quotes
#   every currency against EUR, so USD->XXX is derived as a cross-rate:
#       usdToXXX = (EUR->XXX) / (EUR->USD)
#   ECB publishes nothing on weekends/holidays, so the last known rate is
#   forward-filled to give every calendar date a value.
#
# OUTPUT
#   assets/fx_history.csv, columns: date,EUR,GBP,AUD,CAD,CHF,JPY
#   (no USD column — USD->USD is always 1.0). One row per calendar day.
#
# CAVEAT — NOT a byte-for-byte reproduction
#   ECB occasionally revises historical rates, and a fresh run also extends the
#   range to today. So re-running produces an UPDATED, equivalent dataset, not
#   an identical copy of the current file. This is the intended behavior for
#   "extend the history"; it is not a checksum for the existing asset.
#
# USAGE
#   tools/fetch_fx_history.sh [START_DATE] [END_DATE]
#   Defaults: START_DATE=2010-07-18 (start of btc_history.csv),
#             END_DATE=today. Dates are ISO (YYYY-MM-DD).
#
#   Set FX_OUT to write somewhere other than assets/fx_history.csv — useful for
#   a dry run that must not clobber the bundled asset, e.g.
#       FX_OUT=/tmp/fx_test.csv tools/fetch_fx_history.sh 2026-05-08 2026-05-14
#
# REQUIREMENTS: bash, curl, awk, date (GNU coreutils).

set -euo pipefail

# --- config -----------------------------------------------------------------
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${FX_OUT:-$REPO_ROOT/assets/fx_history.csv}"

START_DATE="${1:-2010-07-18}"
END_DATE="${2:-$(date +%F)}"

# Output column order after `date`. USD is omitted (always 1.0). Must stay in
# sync with `_fxColumns` in lib/data/fx_history.dart.
COLUMNS=(EUR GBP AUD CAD CHF JPY)

# ECB EXR series: D (daily) . <currency> . EUR . SP00 . A (reference rate).
ECB_URL="https://data-api.ecb.europa.eu/service/data/EXR/D.USD+GBP+JPY+CAD+AUD+CHF.EUR.SP00.A"

# --- fetch ------------------------------------------------------------------
echo "Fetching ECB reference rates ${START_DATE} .. ${END_DATE} ..." >&2
RAW="$(mktemp)"
trap 'rm -f "$RAW"' EXIT

curl -fsS \
  "${ECB_URL}?startPeriod=${START_DATE}&endPeriod=${END_DATE}&format=csvdata" \
  -o "$RAW"

# --- transform --------------------------------------------------------------
# The ECB csvdata response is one row per (currency, date). Relevant columns:
#   CURRENCY (col 3), TIME_PERIOD (col 7), OBS_VALUE (col 8).
# awk pivots that into one row per date with all 6 EUR-> rates, derives the
# USD-> cross-rates, then forward-fills across every calendar day in range.
awk -v start="$START_DATE" -v end="$END_DATE" '
  BEGIN { FS=","; OFS="," }

  # Convert a YYYY-MM-DD date to a day count for iteration via mktime.
  function epoch_day(d,    y,m,dd,spec) {
    y = substr(d,1,4); m = substr(d,6,2); dd = substr(d,9,2)
    spec = y " " m " " dd " 12 0 0"
    return int(mktime(spec) / 86400)
  }
  function day_to_date(n,    s) {
    s = strftime("%Y-%m-%d", n*86400 + 43200, 1)
    return s
  }

  # Skip the header row; index every (date,currency) -> rate.
  NR > 1 {
    cur = $3; period = $7; val = $8
    if (period == "" || val == "" || val + 0 <= 0) next
    eur[period "," cur] = val + 0
    seen[period] = 1
  }

  END {
    ncols = split("EUR GBP AUD CAD CHF JPY", out, " ")
    print "date,EUR,GBP,AUD,CAD,CHF,JPY"

    sd = epoch_day(start); ed = epoch_day(end)
    # `have_*` holds the last known value for forward-fill.
    for (d = sd; d <= ed; d++) {
      day = day_to_date(d)
      eurUsd = eur[day ",USD"]
      if (eurUsd != "" && eurUsd > 0) {
        # New ECB observation for this day: refresh the carried rates.
        last_eurUsd = eurUsd
        last["EUR"] = 1.0 / eurUsd
        for (i = 1; i <= ncols; i++) {
          c = out[i]
          if (c == "EUR") continue
          v = eur[day "," c]
          if (v != "" && v > 0) last[c] = v / eurUsd
        }
      }
      # Emit only once we have a full set (guards the very first days if the
      # range start predates the first ECB observation — should not happen for
      # 2010+, but keeps the output well-formed if it does).
      if (last["EUR"] == "") continue
      line = day
      for (i = 1; i <= ncols; i++) line = line OFS sprintf("%.6f", last[out[i]])
      print line
    }
  }
' "$RAW" > "$OUT.tmp"

mv "$OUT.tmp" "$OUT"

ROWS="$(($(wc -l < "$OUT") - 1))"
echo "Wrote ${ROWS} rows to ${OUT}" >&2
echo "Range: $(sed -n '2p' "$OUT" | cut -d, -f1) .. $(tail -1 "$OUT" | cut -d, -f1)" >&2
