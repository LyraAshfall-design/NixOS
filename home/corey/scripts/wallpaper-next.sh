#!/usr/bin/env bash

# Requires:
#   curl
#   jq
#   imagemagick (for identify)
#   swaymsg
#
# Finds a random suitable wallpaper from Reddit or Wallhaven,
# avoids recently used images, saves it locally, and applies it
# directly to all Sway outputs.

for cmd in curl jq identify sha1sum shuf swaymsg; do
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

# ---------------------------------------------------------------------------
# Reddit sources
# ---------------------------------------------------------------------------

SUBREDDITS=(
  wallpapers
  wallpaper
  UltraHighResWallpapers
  wallpaperdump
  EarthPorn
  SpacePorn
  CityPorn
  SkyPorn
  WaterPorn
  VillagePorn
  BeachPorn
  WinterPorn
  AutumnPorn
  SpringPorn
  SummerPorn
  MountainPorn
  DesertPorn
  LakePorn
  AnimeWallpaper
  AnimePhoneWallpapers
  Amoledbackgrounds
  DigitalArt
  Art
  AbstractArt
  Cyberpunk
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
  ocean
  desert
  city
  night
  space
  abstract
  anime
  fantasy
  scifi
  architecture
  aurora
  canyon
  lake
  waterfall
  winter
  autumn
)

# ---------------------------------------------------------------------------
# Build and shuffle each source list independently
# ---------------------------------------------------------------------------

REDDIT_SHUFFLED=($(printf 'reddit:%s\n' "${SUBREDDITS[@]}" | shuf))
WH_SHUFFLED=($(printf 'wallhaven:%s\n' "${WH_TAGS[@]}" | shuf))

# Interleave:
# reddit, wallhaven, reddit, wallhaven...
SOURCES=()

MAX=$(( ${#REDDIT_SHUFFLED[@]} > ${#WH_SHUFFLED[@]} \
  ? ${#REDDIT_SHUFFLED[@]} \
  : ${#WH_SHUFFLED[@]} ))

for ((i = 0; i < MAX; i++)); do
  [ "$i" -lt "${#REDDIT_SHUFFLED[@]}" ] &&
    SOURCES+=("${REDDIT_SHUFFLED[$i]}")

  [ "$i" -lt "${#WH_SHUFFLED[@]}" ] &&
    SOURCES+=("${WH_SHUFFLED[$i]}")
done

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
  TYPE="${SRC%%:*}"
  VALUE="${SRC##*:}"

  echo "Trying $SRC..."

  # -------------------------------------------------------------------------
  # Reddit
  # -------------------------------------------------------------------------

  if [ "$TYPE" = "reddit" ]; then
    TIME=$(shuf -e day week month | head -n1)

    JSON=$(
      curl -sL \
        -A "Mozilla/5.0 (X11; Linux x86_64)" \
        -H "Accept: application/json" \
        "https://api.reddit.com/r/${VALUE}/top?t=${TIME}&limit=100"
    ) || continue

    echo "$JSON" | jq . >/dev/null 2>&1 || continue

    COUNT=$(echo "$JSON" | jq '.data.children | length')

    for i in $(seq 0 $((COUNT - 1))); do
      URL=$(
        echo "$JSON" |
          jq -r \
            ".data.children[$i].data.url_overridden_by_dest // .data.children[$i].data.url"
      )

      if [[ "$URL" =~ \.(jpg|jpeg|png)$ ]]; then
        TMP="$DIR/tmp_wallpaper.jpg"

        curl -sL "$URL" -o "$TMP" || {
          rm -f "$TMP"
          continue
        }

        read WIDTH HEIGHT <<<"$(
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
    SORTING=$(shuf -e toplist hot random | head -n1)

    JSON=$(
      curl -sL \
        -A "Mozilla/5.0 (X11; Linux x86_64)" \
        "https://wallhaven.cc/api/v1/search?q=${VALUE}&categories=110&purity=100&sorting=${SORTING}&atleast=1920x1080&ratios=landscape&limit=24"
    ) || continue

    echo "$JSON" | jq . >/dev/null 2>&1 || continue

    COUNT=$(echo "$JSON" | jq '.data | length')

    for i in $(seq 0 $((COUNT - 1))); do
      URL=$(echo "$JSON" | jq -r ".data[$i].path")

      if [[ "$URL" =~ \.(jpg|jpeg|png)$ ]]; then
        TMP="$DIR/tmp_wallpaper.jpg"

        curl -sL "$URL" -o "$TMP" || {
          rm -f "$TMP"
          continue
        }

        read WIDTH HEIGHT <<<"$(
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

echo "No suitable wallpaper found"
exit 1
