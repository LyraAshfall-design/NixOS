#!/usr/bin/env bash

# Requires:
#   curl
#   jq
#   imagemagick (identify + magick), awk
#   swaymsg
#
# Finds a random suitable wallpaper from Reddit or Wallhaven,
# avoids recently used images, saves it locally, and applies it
# directly to all Sway outputs.

# Theme tuning: 0-100 minimum score; higher means stricter. Debug also prints
# passing scores. Sampling is only for analysis; the downloaded image is kept.
THEME_MIN_SCORE=${THEME_MIN_SCORE:-60}
THEME_SAMPLE_SIZE=${THEME_SAMPLE_SIZE:-32}
THEME_DEBUG=${THEME_DEBUG:-0}
MAX_THEME_ATTEMPTS=${MAX_THEME_ATTEMPTS:-40}
MAX_SOURCE_ATTEMPTS=${MAX_SOURCE_ATTEMPTS:-4}
MAX_REDDIT_ATTEMPTS=${MAX_REDDIT_ATTEMPTS:-6}
MAX_SOURCE_REQUESTS=${MAX_SOURCE_REQUESTS:-16}
CURL_CONNECT_TIMEOUT=${CURL_CONNECT_TIMEOUT:-5}
CURL_MAX_TIME=${CURL_MAX_TIME:-25}

if [[ ! "$THEME_MIN_SCORE" =~ ^[0-9]{1,3}$ ]] ||
  (( 10#$THEME_MIN_SCORE > 100 )) ||
  [[ ! "$THEME_SAMPLE_SIZE" =~ ^[0-9]{1,3}$ ]] ||
  (( 10#$THEME_SAMPLE_SIZE < 1 || 10#$THEME_SAMPLE_SIZE > 128 )); then
  echo "Invalid theme settings: score must be 0-100, sample size 1-128."
  exit 1
fi

for setting in MAX_THEME_ATTEMPTS MAX_SOURCE_ATTEMPTS MAX_REDDIT_ATTEMPTS MAX_SOURCE_REQUESTS CURL_CONNECT_TIMEOUT CURL_MAX_TIME; do
  if [[ ! "${!setting}" =~ ^[1-9][0-9]{0,3}$ ]]; then
    echo "Invalid $setting: expected a positive integer up to 9999."
    exit 1
  fi
done

for cmd in curl jq identify magick awk sha1sum shuf swaymsg mktemp; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "Missing dependency: $cmd"
    exit 1
  fi
done

DIR="$HOME/Pictures/wallpapers"
mkdir -p "$DIR"

HISTORY="$DIR/.history"
touch "$HISTORY"

CURRENT="$DIR/current"
# Private temporary files also prevent concurrent invocations sharing downloads.
WORK=$(mktemp -d "$DIR/.wallpaper-next.XXXXXX") || exit 1
TMP="$WORK/full.jpg"
PREVIEW="$WORK/preview.jpg"
trap 'rm -f -- "$TMP" "$PREVIEW"; rmdir -- "$WORK"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
CURL_ARGS=(--fail --silent --show-error --location
  --connect-timeout "$CURL_CONNECT_TIMEOUT" --max-time "$CURL_MAX_TIME")
ATTEMPTS=0
REDDIT_ATTEMPTS=0
SOURCE_REQUESTS=0
declare -A SEEN_URLS=()

# ---------------------------------------------------------------------------
# Reddit sources
# ---------------------------------------------------------------------------

SUBREDDITS=(
  wallpapers
  wallpaper
  UltraHighResWallpapers
  wallpaperdump
  EarthPorn
  CityPorn
  SkyPorn
  WaterPorn
  VillagePorn
  BeachPorn
  AutumnPorn
  SpringPorn
  SummerPorn
  MountainPorn
  DesertPorn
  LakePorn
  AnimeWallpaper
  DigitalArt
  Art
  AbstractArt
  ImaginaryLandscapes
  ImaginaryCityscapes
)

# ---------------------------------------------------------------------------
# Wallhaven search tags
#
# No API key:
#   categories=110 -> General + Anime
#   purity=100     -> SFW
# ---------------------------------------------------------------------------

WH_TAGS=(
  nature
  landscape
  mountains
  forest
  desert
  city
  night
  abstract
  anime
  fantasy
  architecture
  canyon
  lake
  waterfall
  autumn
  coffee
  cozy
  wood
  candlelight
  cafe
  cabin
  lantern
  "rainy street"
  "Japanese street"
  "golden hour"
  sunset
  brown
  amber
)

# Wallhaven accepts a fixed color vocabulary, not arbitrary palette hex values.
# Browns/terracotta, amber, olive, cream-like neutral and black are first-stage
# hints; the local score still decides whether an image is actually compatible.
WH_COLORS=(663300 996633 cc6633 ff9900 ffcc33 666600 336600 cccccc 000000)

# ---------------------------------------------------------------------------
# Build and shuffle each source list independently
# ---------------------------------------------------------------------------

mapfile -t REDDIT_SHUFFLED < <(printf 'reddit:%s\n' "${SUBREDDITS[@]}" | shuf)
mapfile -t WH_SHUFFLED < <(printf 'wallhaven:%s\n' "${WH_TAGS[@]}" | shuf)

# Interleave:
# Wallhaven first: cheap previews before Reddit full-resolution downloads.
SOURCES=()

MAX=$(( ${#REDDIT_SHUFFLED[@]} > ${#WH_SHUFFLED[@]} \
  ? ${#REDDIT_SHUFFLED[@]} \
  : ${#WH_SHUFFLED[@]} ))

for ((i = 0; i < MAX; i++)); do
  [ "$i" -lt "${#WH_SHUFFLED[@]}" ] &&
    SOURCES+=("${WH_SHUFFLED[$i]}")

  [ "$i" -lt "${#REDDIT_SHUFFLED[@]}" ] &&
    SOURCES+=("${REDDIT_SHUFFLED[$i]}")
done

# ---------------------------------------------------------------------------
# Helper: score a small sRGB sample against the warm/dark palette
# ---------------------------------------------------------------------------

theme_compatible() {
  local wallpaper="$1" source="$2" report

  # Average per-pixel statistics instead of the average color: blue/purple and
  # orange regions must not cancel out and disguise a cold or neon image.
  # Scores: +35 darkness, +25 warmth, +30 palette proximity, +10 mutedness;
  # penalties: -35 cold coverage, -25 neon coverage, -25 very bright coverage.
  # Luminance uses weighted sRGB as a cheap visual heuristic (not linear light).
  # Palette proximity uses nearest RGB distance, fading to zero at 0.30.
  if ! report=$(
    set -o pipefail
    magick "${wallpaper}[0]" -background '#171311' -alpha remove -alpha off \
      -colorspace sRGB -thumbnail "${THEME_SAMPLE_SIZE}x${THEME_SAMPLE_SIZE}!" \
      -depth 8 -type TrueColor txt:- 2>/dev/null |
      LC_ALL=C awk -v minimum="$THEME_MIN_SCORE" '
        function clamp(x) { return x < 0 ? 0 : (x > 1 ? 1 : x) }
        BEGIN {
          # Espresso, cocoa, wood, oat cream, caramel, terracotta, sage, honey, rose.
          n = split("23,19,17 33,27,24 45,37,33 65,54,49 232,220,203 201,184,164 209,154,102 201,123,99 158,170,131 214,181,109 201,130,134", colors, " ")
          for (i = 1; i <= n; i++) {
            split(colors[i], c, ",")
            pr[i] = c[1]/255; pg[i] = c[2]/255; pb[i] = c[3]/255
          }
        }
        /^[0-9]+,[0-9]+:/ {
          pixel = $0
          sub(/^[^(]*\(/, "", pixel); sub(/\).*/, "", pixel)
          split(pixel, c, ",")
          r = c[1]/255; g = c[2]/255; b = c[3]/255
          hi = r > g ? r : g; hi = hi > b ? hi : b
          lo = r < g ? r : g; lo = lo < b ? lo : b
          saturation = hi > 0 ? (hi-lo)/hi : 0
          luminance = 0.2126*r + 0.7152*g + 0.0722*b
          dark += clamp(1-luminance/0.65)
          warm += clamp((r-b)/0.20) * (r >= 0.9*g ? 1 : 0.5)
          muted += 1-saturation
          cold += ((b > r+0.035 && b > g-0.04) || (b > g+0.06 && b > 0.65*r))
          neon += (saturation > 0.72 && hi > 0.72)
          bright += (luminance > 0.72)
          nearest = 3
          for (i = 1; i <= n; i++) {
            distance = ((r-pr[i])^2 + (g-pg[i])^2 + (b-pb[i])^2)/3
            if (distance < nearest) nearest = distance
          }
          matchScore += clamp(1-sqrt(nearest)/0.30)
          count++
        }
        END {
          if (!count) exit 1
          score = (35*dark + 25*warm + 30*matchScore + 10*muted - 35*cold - 25*neon - 25*bright)/count
          score = 100*clamp(score/100)
          printf "%s score=%.1f/%s dark=%.0f warm=%.0f palette=%.0f muted=%.0f cold=%.0f neon=%.0f bright=%.0f", \
            score >= minimum ? "PASS" : "FAIL", score, minimum, \
            100*dark/count, 100*warm/count, 100*matchScore/count, 100*muted/count, \
            100*cold/count, 100*neon/count, 100*bright/count
        }
      '
  ); then
    echo "Theme reject ($source): image analysis failed."
    return 1
  fi

  if [[ "$report" == FAIL* ]]; then
    echo "Theme reject ($source): ${report#FAIL }"
    return 1
  fi
  if [[ "$THEME_DEBUG" == 1 ]]; then
    echo "Theme accept ($source): ${report#PASS }"
  fi
  return 0
}

# ---------------------------------------------------------------------------
# Helper: apply wallpaper
# ---------------------------------------------------------------------------

apply_wallpaper() {
  local wallpaper="$1"

  # Keep a stable pointer to the current wallpaper so it can be restored
  # automatically on the next Sway login.
  ln -sfn "$wallpaper" "$CURRENT"

  # Apply to every connected Sway output.
  swaymsg output "*" bg "$wallpaper" fill >/dev/null
}

# ---------------------------------------------------------------------------
# Main loop
# ---------------------------------------------------------------------------

for SRC in "${SOURCES[@]}"; do
  (( ATTEMPTS >= MAX_THEME_ATTEMPTS || SOURCE_REQUESTS >= MAX_SOURCE_REQUESTS )) && break
  TYPE="${SRC%%:*}"
  VALUE="${SRC##*:}"
  SOURCE_ATTEMPTS=0

  if [[ "$TYPE" == reddit ]] && (( REDDIT_ATTEMPTS >= MAX_REDDIT_ATTEMPTS )); then
    continue
  fi
  ((SOURCE_REQUESTS += 1))

  echo "Trying $SRC..."

  # -------------------------------------------------------------------------
  # Reddit
  # -------------------------------------------------------------------------

  if [ "$TYPE" = "reddit" ]; then
    TIME=$(shuf -e day week month | head -n1)

    JSON=$(
      curl "${CURL_ARGS[@]}" \
        -A "Mozilla/5.0 (X11; Linux x86_64)" \
        -H "Accept: application/json" \
        "https://api.reddit.com/r/${VALUE}/top?t=${TIME}&limit=30"
    ) || continue

    echo "$JSON" | jq -e '.data.children | type == "array"' >/dev/null 2>&1 || continue

    COUNT=$(echo "$JSON" | jq '.data.children | length')

    for i in $(seq 0 $((COUNT - 1))); do
      (( ATTEMPTS >= MAX_THEME_ATTEMPTS || SOURCE_ATTEMPTS >= MAX_SOURCE_ATTEMPTS || REDDIT_ATTEMPTS >= MAX_REDDIT_ATTEMPTS )) && break
      URL=$(
        echo "$JSON" |
          jq -r \
            ".data.children[$i].data.url_overridden_by_dest // .data.children[$i].data.url"
      )

      if [[ "$URL" =~ \.(jpg|jpeg|png)$ ]]; then
        [[ -n "${SEEN_URLS[$URL]:-}" ]] && continue
        SEEN_URLS[$URL]=1
        ((ATTEMPTS += 1, SOURCE_ATTEMPTS += 1, REDDIT_ATTEMPTS += 1))

        curl "${CURL_ARGS[@]}" "$URL" -o "$TMP" || {
          rm -f "$TMP"
          continue
        }

        read -r WIDTH HEIGHT <<<"$(
          identify -format "%w %h" "$TMP" 2>/dev/null || echo "0 0"
        )"

        if [ "$WIDTH" -ge 1920 ] &&
          [ "$HEIGHT" -ge 1080 ] &&
          [ "$WIDTH" -gt "$HEIGHT" ]; then

          HASH=$(sha1sum "$TMP" | awk '{print $1}')

          if grep -q "$HASH" "$HISTORY"; then
            rm -f "$TMP"
            continue
          fi

          if ! theme_compatible "$TMP" "$SRC"; then
            rm -f "$TMP"
            continue
          fi

          FINAL="$DIR/wallpaper_$(date +%Y%m%d)_${VALUE}.jpg"
          mv "$TMP" "$FINAL"

          echo "$HASH" >>"$HISTORY"

          tail -n 500 "$HISTORY" >"$HISTORY.tmp" &&
            mv "$HISTORY.tmp" "$HISTORY"

          apply_wallpaper "$FINAL"

          echo "Set wallpaper from r/$VALUE: $URL"
          exit 0
        else
          rm -f "$TMP"
        fi
      fi
    done

  # -------------------------------------------------------------------------
  # Wallhaven
  # -------------------------------------------------------------------------

  elif [ "$TYPE" = "wallhaven" ]; then
    SORTING=random
    COLOR=$(shuf -e "${WH_COLORS[@]}" | head -n1)

    JSON=$(
      curl "${CURL_ARGS[@]}" --get \
        -A "Mozilla/5.0 (X11; Linux x86_64)" \
        --data-urlencode "q=${VALUE} -neon -cyberpunk -winter" \
        --data-urlencode "colors=$COLOR" \
        --data-urlencode "categories=110" --data-urlencode "purity=100" \
        --data-urlencode "sorting=$SORTING" --data-urlencode "atleast=1920x1080" \
        --data-urlencode "ratios=landscape" \
        "https://wallhaven.cc/api/v1/search"
    ) || continue

    echo "$JSON" | jq -e '.data | type == "array"' >/dev/null 2>&1 || continue

    COUNT=$(echo "$JSON" | jq '.data | length')

    for i in $(seq 0 $((COUNT - 1))); do
      (( ATTEMPTS >= MAX_THEME_ATTEMPTS || SOURCE_ATTEMPTS >= MAX_SOURCE_ATTEMPTS )) && break
      # Reject unsuitable metadata without transferring either image.
      echo "$JSON" | jq -e --argjson i "$i" '
        .data[$i] | .dimension_x >= 1920 and .dimension_y >= 1080
        and .dimension_x > .dimension_y and .purity == "sfw"
      ' >/dev/null 2>&1 || continue
      URL=$(echo "$JSON" | jq -r ".data[$i].path")

      if [[ "$URL" =~ \.(jpg|jpeg|png)$ ]]; then
        [[ -n "${SEEN_URLS[$URL]:-}" ]] && continue
        SEEN_URLS[$URL]=1
        ((ATTEMPTS += 1, SOURCE_ATTEMPTS += 1))
        PREVIEW_URL=$(echo "$JSON" | jq -r ".data[$i].thumbs.original // .data[$i].thumbs.large // .data[$i].thumbs.small // empty")
        if [[ ! "$PREVIEW_URL" =~ ^https:// ]]; then
          echo "Theme reject ($SRC): no usable preview."
          continue
        fi
        curl "${CURL_ARGS[@]}" "$PREVIEW_URL" -o "$PREVIEW" || continue
        if ! theme_compatible "$PREVIEW" "$SRC preview"; then
          rm -f "$PREVIEW"
          continue
        fi
        rm -f "$PREVIEW"

        # Only promising previews justify a full download. Validate the actual
        # image again below, including dimensions, SHA1 history and theme score.
        curl "${CURL_ARGS[@]}" "$URL" -o "$TMP" || {
          rm -f "$TMP"
          continue
        }

        read -r WIDTH HEIGHT <<<"$(
          identify -format "%w %h" "$TMP" 2>/dev/null || echo "0 0"
        )"

        if [ "$WIDTH" -ge 1920 ] &&
          [ "$HEIGHT" -ge 1080 ] &&
          [ "$WIDTH" -gt "$HEIGHT" ]; then

          HASH=$(sha1sum "$TMP" | awk '{print $1}')

          if grep -q "$HASH" "$HISTORY"; then
            rm -f "$TMP"
            continue
          fi

          if ! theme_compatible "$TMP" "$SRC"; then
            rm -f "$TMP"
            continue
          fi

          FINAL="$DIR/wallpaper_$(date +%Y%m%d)_wallhaven_${VALUE}.jpg"
          mv "$TMP" "$FINAL"

          echo "$HASH" >>"$HISTORY"

          tail -n 500 "$HISTORY" >"$HISTORY.tmp" &&
            mv "$HISTORY.tmp" "$HISTORY"

          apply_wallpaper "$FINAL"

          echo "Set wallpaper from Wallhaven ($VALUE, $SORTING): $URL"
          exit 0
        else
          rm -f "$TMP"
        fi
      fi
    done
  fi
done

echo "No suitable wallpaper found after $ATTEMPTS candidates / $SOURCE_REQUESTS sources (minimum theme score $THEME_MIN_SCORE)."
exit 1
