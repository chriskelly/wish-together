#!/bin/bash
# Verifies captured App Store screenshots without a human looking at them:
# dimensions, alpha, OCR text and dominant colour.
#
#   ./verify.sh [directory]        # defaults to the current directory
#
# Fails loudly (non-zero) when a check does not hold. Run it before uploading.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
TARGET="${1:-.}"
cd "$TARGET" || exit 2
mkdir -p ocr
status=0

# The full set, in upload order. A partial set must fail: uploading five of six
# is a listing bug that no per-file check would catch.
EXPECTED=(
  01-the-carters
  02-the-knowles-family
  03-home
  04-sasha-birthday
  05-shawns-birthday
  06-shawns-birthday-spoiler-free
)

# Expected strings per file, separated by |. These come from the seed cast in
# scripts/seed-demo.mjs; update them with the capture if the demo data changes.
expect() {
  case "$1" in
    01-the-carters.png) echo "The Carters|Shared Wishlists|Members|Blue's Birthday|Tina's Kitchen" ;;
    02-the-knowles-family.png) echo "The Knowles Family|Angie's Travel Kit" ;;
    03-home.png) echo "My Wishlists|My Groups|Rumi and Sir's Birthday|The Crew" ;;
    04-sasha-birthday.png) echo "Sasha's Birthday|Perfume: oud|You claimed this" ;;
    05-shawns-birthday.png) echo "Shawn's Birthday|Cashmere|Available|2 of 3 claimed" ;;
    06-shawns-birthday-spoiler-free.png) echo "Shawn's Birthday|Cashmere" ;;
  esac
}

BANNED=("Dev session" "Exception" "Something went wrong" "Retry")

colour_near() { # colour_near <observed-hex> <target-hex>: every channel within 9
  local dr=$((16#${2:1:2} - 16#${1:1:2}))
  local dg=$((16#${2:3:2} - 16#${1:3:2}))
  local db=$((16#${2:5:2} - 16#${1:5:2}))
  ((dr >= -9 && dr <= 9 && dg >= -9 && dg <= 9 && db >= -9 && db <= 9))
}

has() { # has <text> <literal>: true when the literal appears in the text
  printf '%s' "$1" | grep -qF -- "$2"
}

for name in "${EXPECTED[@]}"; do
  file="${name}.png"
  echo "=== $file"

  if [ ! -f "$file" ]; then
    echo "MISSING: $file"
    status=1
    continue
  fi

  dims=$(sips -g pixelWidth -g pixelHeight "$file" |
    awk '/pixelWidth/{w=$2}/pixelHeight/{h=$2}END{print w"x"h}')
  if [ "$dims" = "1206x2622" ]; then
    echo "dimensions OK: $dims"
  else
    echo "dimensions FAIL: $dims (the required iPhone slot is 1206x2622)"
    status=1
  fi

  alpha=$(sips -g hasAlpha "$file" | awk '/hasAlpha/{print $2}')
  if [ "$alpha" = "no" ]; then
    echo "alpha OK: none"
  else
    echo "alpha FAIL: $alpha (App Store Connect rejects transparency)"
    status=1
  fi

  # Keep the OCR text next to the captures for a human, but surface a broken
  # toolchain instead of reporting it as five missing strings.
  if ! swift "$HERE/ocr.swift" "$file" >"ocr/${name}.txt" 2>"ocr/${name}.err"; then
    echo "ocr FAILED: $(head -1 "ocr/${name}.err")"
    status=1
    continue
  fi
  rm -f "ocr/${name}.err"
  text=$(cat "ocr/${name}.txt")

  IFS='|' read -r -a wanted <<<"$(expect "$file")"
  for want in "${wanted[@]}"; do
    if has "$text" "$want"; then
      echo "ocr OK: $want"
    else
      echo "ocr MISS: $want"
      status=1
    fi
  done

  # The spoiler-free shot must not leak claim state.
  if [ "$file" = "06-shawns-birthday-spoiler-free.png" ]; then
    for absent in "Available" "Claimed" "2 of 3 claimed"; do
      if has "$text" "$absent"; then
        echo "ocr SHOULD BE ABSENT: $absent"
        status=1
      fi
    done
  fi

  for bad in "${BANNED[@]}"; do
    if has "$text" "$bad"; then
      echo "ocr BANNED PRESENT: $bad"
      status=1
    fi
  done

  colours=$(swift "$HERE/colors.swift" "$file" 2>/dev/null)
  if [ -z "$colours" ]; then
    echo "colours FAIL: colors.swift produced nothing"
    status=1
    continue
  fi
  echo "$colours"

  # A design-regression guard, not a general rule: the Holly & Brass canvas is
  # #F6F0DC and item cards sit on #FFFCF0. Update these when the palette
  # changes; the point is to catch a stale theme or the old blue returning.
  top_hex=$(printf '%s\n' "$colours" | awk 'NR==2{print $1}')
  if colour_near "$top_hex" "#F6F0DC"; then
    echo "canvas OK: dominant $top_hex is cream #F6F0DC"
  elif colour_near "$top_hex" "#FFFCF0"; then
    echo "canvas OK: dominant $top_hex is the brand surface #FFFCF0"
  else
    echo "canvas FAIL: dominant $top_hex is neither canvas nor brand surface"
    status=1
  fi

  # The canvas fills most of every screen, so it must appear among the top
  # colours even when the cards dominate. Compare numerically: colors.swift
  # quantises, and an exact string match would break on a one-step shift.
  canvas_seen=0
  for hex in $(printf '%s\n' "$colours" | awk 'NR>1{print $1}'); do
    if colour_near "$hex" "#F6F0DC"; then
      canvas_seen=1
      break
    fi
  done
  if [ "$canvas_seen" -eq 0 ]; then
    echo "canvas FAIL: #F6F0DC is not among the top colours"
    status=1
  fi

  # colors.swift truncates each channel to a multiple of 8, so these are the
  # quantised forms of Material Blue 500 (#2196F3) and Blue 700 (#1976D2).
  for blue in "#2090F0" "#1870D0"; do
    if printf '%s\n' "$colours" | grep -q "^$blue "; then
      echo "old blue present: $blue"
      status=1
    fi
  done
done

# A file outside the set is a stale capture from an earlier run; uploading it
# by mistake is as bad as leaving one out.
for extra in 0*.png; do
  [ -f "$extra" ] || continue
  known=0
  for name in "${EXPECTED[@]}"; do
    if [ "$extra" = "${name}.png" ]; then known=1; fi
  done
  if [ "$known" -eq 0 ]; then
    echo "UNEXPECTED: $extra"
    status=1
  fi
done

if [ -f 05-shawns-birthday.png ] && [ -f 06-shawns-birthday-spoiler-free.png ] &&
  cmp -s 05-shawns-birthday.png 06-shawns-birthday-spoiler-free.png; then
  echo "the two claim-state shots are byte-identical: the state change did not happen"
  status=1
fi

if [ "$status" -eq 0 ]; then echo "ALL CHECKS PASSED"; else echo "CHECKS FAILED"; fi
exit "$status"
