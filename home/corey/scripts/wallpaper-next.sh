#!/usr/bin/env bash

# A warm, dark cat-cafe world. Subject evidence is mandatory BEFORE scoring.
# Runtime dependencies stay Bash + curl/jq/ImageMagick/coreutils/awk/flock/Sway.
umask 077
THEME_MIN_SCORE=${THEME_MIN_SCORE:-60}
THEME_SAMPLE_SIZE=${THEME_SAMPLE_SIZE:-32}
THEME_DEBUG=${THEME_DEBUG:-0}
MAX_THEME_ATTEMPTS=${MAX_THEME_ATTEMPTS:-40}
MAX_SOURCE_ATTEMPTS=${MAX_SOURCE_ATTEMPTS:-4}
MAX_REDDIT_ATTEMPTS=${MAX_REDDIT_ATTEMPTS:-6}
# Includes linked metadata/IIIF calls. Museums need more calls than Wallhaven.
MAX_SOURCE_REQUESTS=${MAX_SOURCE_REQUESTS:-32}
MAX_LOCAL_ATTEMPTS=${MAX_LOCAL_ATTEMPTS:-100}
CURL_CONNECT_TIMEOUT=${CURL_CONNECT_TIMEOUT:-5}
CURL_MAX_TIME=${CURL_MAX_TIME:-25}
MIN_WIDTH=${MIN_WIDTH:-1920}
MIN_HEIGHT=${MIN_HEIGHT:-1080}
WALLPAPER_USER_AGENT=${WALLPAPER_USER_AGENT:-"CatCafeWallpaper/2.0 (personal Sway wallpaper selector; contact: $USER@$(hostname))"}
# This also makes offline/manual source-specific validation straightforward.
WALLPAPER_SOURCES=${WALLPAPER_SOURCES:-wallhaven,reddit,commons,cleveland,rijksmuseum,curated}

if [[ ! "$THEME_MIN_SCORE" =~ ^[0-9]{1,3}$ ]] ||
  (( 10#$THEME_MIN_SCORE > 100 )) ||
  [[ ! "$THEME_SAMPLE_SIZE" =~ ^[0-9]{1,3}$ ]] ||
  (( 10#$THEME_SAMPLE_SIZE < 1 || 10#$THEME_SAMPLE_SIZE > 128 )); then
  echo 'Invalid theme settings: score must be 0-100, sample size 1-128.'
  exit 1
fi
THEME_MIN_SCORE=$((10#$THEME_MIN_SCORE))
THEME_SAMPLE_SIZE=$((10#$THEME_SAMPLE_SIZE))
for setting in MAX_THEME_ATTEMPTS MAX_SOURCE_ATTEMPTS MAX_REDDIT_ATTEMPTS MAX_SOURCE_REQUESTS MAX_LOCAL_ATTEMPTS CURL_CONNECT_TIMEOUT CURL_MAX_TIME MIN_WIDTH MIN_HEIGHT; do
  if [[ ! "${!setting}" =~ ^[1-9][0-9]{0,3}$ ]]; then
    echo "Invalid $setting: expected a positive integer up to 9999."
    exit 1
  fi
done
(( MIN_WIDTH > MIN_HEIGHT )) || { echo 'Minimum dimensions must be landscape.'; exit 1; }
for cmd in curl jq identify magick awk sha1sum shuf swaymsg mktemp flock; do
  command -v "$cmd" &>/dev/null || { echo "Missing dependency: $cmd"; exit 1; }
done
IFS=, read -r -a ENABLED_SOURCES <<<"$WALLPAPER_SOURCES"
for provider in "${ENABLED_SOURCES[@]}"; do
  case "$provider" in
    wallhaven|reddit|commons|cleveland|rijksmuseum|curated) ;;
    *) echo "Unknown wallpaper source: $provider"; exit 1 ;;
  esac
done

DIR="$HOME/Pictures/wallpapers"
APPROVED="$DIR/coffee-approved"
CACHE="$DIR/coffee-cache"
PROVENANCE="$DIR/.provenance"
mkdir -p "$APPROVED" "$CACHE" "$PROVENANCE" || exit 1
exec 9>"$DIR/.lock"
flock -n 9 || { echo 'Wallpaper selection is already running.'; exit 0; }
HISTORY="$DIR/.history"
SOURCE_HISTORY="$DIR/.source-history"
CURRENT="$DIR/current"
touch "$HISTORY" "$SOURCE_HISTORY"
WORK=$(mktemp -d "$DIR/.wallpaper-next.XXXXXX") || exit 1
TMP="$WORK/full"
PREVIEW="$WORK/preview"
trap 'rm -f -- "$WORK"/*; rmdir -- "$WORK"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
CURL_ARGS=(--fail --silent --show-error --location --proto '=https' --proto-redir '=https'
  --connect-timeout "$CURL_CONNECT_TIMEOUT" --max-time "$CURL_MAX_TIME"
  --user-agent "$WALLPAPER_USER_AGENT")
ATTEMPTS=0 SOURCE_REQUESTS=0 REDDIT_ATTEMPTS=0 LOCAL_ATTEMPTS=0
LAST_SCORE=unknown
CANDIDATE='{}'
TIER=''
declare -A API_CACHE=() SEEN_IDS=() SEEN_URLS=()
: >"$WORK/tier-b"

reject() { printf 'reject: %s\n' "$*"; }
enabled() { [[ ",$WALLPAPER_SOURCES," == *",$1,"* ]]; }

# Cache success AND failure for this run; never repeat an identical API request.
# Call directly, not in a subshell, so the global request budget stays accurate.
api_request() {
  local key file
  key=$(printf '%s\0' "$@" | sha1sum | awk '{print $1}')
  file="$WORK/api-$key"
  if [[ -n "${API_CACHE[$key]:-}" ]]; then
    [[ "${API_CACHE[$key]}" == ok ]] || return 1
    cp "$file" "$WORK/response.json"
    return
  fi
  (( SOURCE_REQUESTS < MAX_SOURCE_REQUESTS )) || return 1
  ((SOURCE_REQUESTS += 1))
  API_CACHE[$key]=failed
  if ! curl "${CURL_ARGS[@]}" "$@" -o "$file" 2>"$WORK/curl-error"; then
    reject 'metadata request failed'
    return 1
  fi
  jq -e 'type == "object"' "$file" >/dev/null 2>&1 || return 1
  API_CACHE[$key]=ok
  cp "$file" "$WORK/response.json"
}

# A shared conservative subject gate. Only subject-bearing fields are supplied
# by adapters: never artist biographies, provenance, medium, or museum names.
# Categories/subreddit/search queries are discovery hints, not subject evidence.
# Descriptions need an explicit depiction statement; unrelated prose fails closed.
cat >"$WORK/subject.jq" <<'JQ'
def clean:
  if type != "string" then "" else
    ascii_downcase | gsub("<[^>]*>"; " ") | gsub("&[^;]+;"; " ") |
    gsub("[éèê]"; "e") | gsub("[_-]"; " ") | gsub("\\s+"; " ")
  end;
def word($r): test("(^|[^a-z])(" + $r + ")([^a-z]|$)");
def irrelevant_context:
  word("biography|biographical|collected by|collection of|gift of|donated|exhibited|exhibition|published|publisher|inspired by|inspiration|influenced|artist s|artist was|artist visited|photographer|photo by|reminds|reminded|named after|owner of|cafe owner|born|museum|no cats?|without cats?|no coffee|without coffee");
def tier:
  clean |
  if irrelevant_context or word("coffee table|coffee coloured|coffee colored|coffee color|coffee colour|coffee brown|coffee toned|coffee stain|cafe racer|library of congress") then "C"
  elif word("cafes?|coffee ?houses?|coffee shops?|espresso|cappuccino|macchiato|latte|coffee|koffiehuis|koffiehuizen|koffie|katzencafe") then "A"
  elif word("cats?|kittens?|kat|poes") and word("interior|room|indoors|window|interieur|kamer|raam|venster")
       and word("warm|cozy|cosy|sunlit|lamplit|fireplace") then "A"
  elif word("book ?stores?|book ?shops?|libraries|library|tea ?rooms?|bakeries|bakery|reading rooms?|bibliotheek|boekwinkel|leeszaal|theehuis|bakkerij") then "B"
  elif word("cats?|kittens?|kat|poes") and word("interior|room|indoors|window|windowsill|interieur|kamer|raam|venster|shop") then "B"
  elif word("interior|room|reading nook") and word("books?|tea|reading") then "B"
  elif word("shop") and word("intimate|small") and word("warm lit|warmly lit|lamplit") then "B"
  else "C" end;
. as $c |
# Exact Wallhaven subject tags may combine cat + interior; free prose never gets
# joined across unrelated fields/sentences to invent a relationship.
([$c.title // ""] + ($c.subjects // []) +
 [($c.description // "" | clean | split(".")[] |
   select(test("^( *)(this (painting|image|photograph|print|illustration) )?(depicts|shows|portrays|features)\\b")))] +
 (if $c.source == "wallhaven" and
     any($c.subjects[]?; clean | test("^(cat|cats|kitten|kittens)$")) and
     any($c.subjects[]?; clean | test("^(interior|indoors|window|windowsill|room)$"))
  then ["cat in interior"] else [] end)) |
map(tier) | if index("A") != null then "A" elif index("B") != null then "B" else "C" end
JQ
subject_eligible() {
  TIER=$(jq -r -f "$WORK/subject.jq" <<<"$CANDIDATE") || return 1
  [[ "$TIER" == A || "$TIER" == B ]] || { reject 'subject not Tier A/B'; return 1; }
  CANDIDATE=$(jq -c --arg tier "$TIER" '. + {tier:$tier, theme_version:2}' <<<"$CANDIDATE")
}

sfw_eligible() {
  # These services have no image-content classifier. Narrow subject evidence plus
  # conservative metadata exclusions; no claim that museum/public-domain == SFW.
  jq -e '
    .sfw != false and
    ([.title, .description, (.subjects[]?), (.categories[]?)] |
     map(select(type == "string")) | join(" ") |
     test("(^|[^a-z])(nsfw|nudes?|nudity|naked|erotic|sexual|sex|porn|hentai|ecchi|lingerie|gore|suicide|nakedness|watermarks?|logos?|signage|advertisements?|graffiti|posters?|diagrams?)([^a-z]|$)"; "i") | not)
  ' <<<"$CANDIDATE" >/dev/null 2>&1 || { reject 'SFW/quality metadata not eligible'; return 1; }
}

rights_eligible() {
  local source
  source=$(jq -r '.source' <<<"$CANDIDATE")
  case "$source" in
    wallhaven|reddit) return 0 ;; # Existing providers; no new license inference.
    cleveland)
      jq -e '.license == "CC0"' <<<"$CANDIDATE" >/dev/null && return 0 ;;
    commons|rijksmuseum)
      jq -e '
        def open_url: type == "string" and
          test("^https?://creativecommons\\.org/(publicdomain/(zero|mark)/1\\.0|licenses/by(-sa)?/[1-4]\\.0)/?$");
        (.license_url | open_url) and (.rights_conflict != true)
      ' <<<"$CANDIDATE" >/dev/null 2>&1 && return 0 ;;
  esac
  reject 'rights not eligible'
  return 1
}

metadata_suitable() {
  jq -e --argjson w "$MIN_WIDTH" --argjson h "$MIN_HEIGHT" '
    (.width | type == "number") and (.height | type == "number") and
    .width >= $w and .height >= $h and .width > .height and
    (.mime | IN("image/jpeg", "image/png", "image/webp", "image/tiff"))
  ' <<<"$CANDIDATE" >/dev/null 2>&1 || { reject 'insufficient resolution or unsuitable image type'; return 1; }
}
theme_compatible() {
  local wallpaper="$1" source="$2" report sample_height
  sample_height=$(( THEME_SAMPLE_SIZE * MIN_HEIGHT / MIN_WIDTH ))
  (( sample_height > 0 )) || sample_height=1

  # Average per-pixel statistics instead of the average color: blue/purple and
  # orange regions must not cancel out and disguise a cold or neon image.
  # Scores: +35 darkness, +25 warmth, +30 palette proximity, +10 mutedness;
  # penalties: -35 cold coverage, -25 neon coverage, -25 very bright coverage.
  # Luminance uses weighted sRGB as a cheap visual heuristic (not linear light).
  # Palette proximity uses nearest RGB distance, fading to zero at 0.30.
  if ! report=$(
    set -o pipefail
    magick "${wallpaper}[0]" -background '#171311' -alpha remove -alpha off \
      -colorspace sRGB -resize "${THEME_SAMPLE_SIZE}x${sample_height}^" \
      -gravity center -extent "${THEME_SAMPLE_SIZE}x${sample_height}" \
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
          split($1, position, ",")
          if (position[2]+0 == 0) top_count++
          pixel = $0
          sub(/^[^(]*\(/, "", pixel); sub(/\).*/, "", pixel)
          split(pixel, c, ",")
          r = c[1]/255; g = c[2]/255; b = c[3]/255
          hi = r > g ? r : g; hi = hi > b ? hi : b
          lo = r < g ? r : g; lo = lo < b ? lo : b
          saturation = hi > 0 ? (hi-lo)/hi : 0
          luminance = 0.2126*r + 0.7152*g + 0.0722*b
          if (position[2]+0 == 0) top_bright += clamp(luminance/0.72)
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
          # A small soft penalty for the top sample row (roughly the bar area).
          # Never reject on top-edge brightness alone.
          if (top_count) score -= 3*top_bright/top_count
          score = 100*clamp(score/100)
          printf "%s score=%.1f/%s dark=%.0f warm=%.0f palette=%.0f muted=%.0f cold=%.0f neon=%.0f bright=%.0f", \
            score >= minimum ? "PASS" : "FAIL", score, minimum, \
            100*dark/count, 100*warm/count, 100*matchScore/count, 100*muted/count, \
            100*cold/count, 100*neon/count, 100*bright/count
        }
      '
  ); then
    reject "$source: image analysis failed"
    return 1
  fi

  LAST_SCORE=${report#*score=}
  LAST_SCORE=${LAST_SCORE%%/*}
  if [[ "$report" == FAIL* ]]; then
    reject "$source: theme score $LAST_SCORE < $THEME_MIN_SCORE"
    return 1
  fi
  if [[ "$THEME_DEBUG" == 1 ]]; then
    echo "Theme accept ($source): ${report#PASS }"
  fi
  return 0
}


# Each adapter emits the same compact candidate record. Search queries and
# category membership deliberately do not become qualifying subject evidence.
wallhaven_metadata() {
  local id
  id=$(jq -r '.id // empty' <<<"$1")
  [[ "$id" =~ ^[a-z0-9]+$ ]] || return 1
  api_request "https://wallhaven.cc/api/v1/w/$id" || return 1
  CANDIDATE=$(jq -c '.data | {
    source:"wallhaven", id:("wallhaven:" + .id), title:((.tags // [] | map(.name) | join(", "))),
    subjects:[.tags[]?.name], description:"", sfw:(.purity == "sfw"),
    width:.dimension_x, height:.dimension_y, mime:(.file_type // "image/jpeg"),
    url:.path, preview:(.thumbs.original // .thumbs.large // .thumbs.small),
    page:("https://wallhaven.cc/w/" + .id), creator:(.uploader.username // ""),
    license:"provider download; reuse rights not asserted"
  }' "$WORK/response.json") || return 1
  # Tags are inspected individually; their concatenation is display-only.
  local display_title="$CANDIDATE"
  CANDIDATE=$(jq -c '.title=""' <<<"$CANDIDATE")
  subject_eligible || return 1
  CANDIDATE=$(jq -c --arg title "$(jq -r '.title' <<<"$display_title")" '.title=$title' <<<"$CANDIDATE")
}

reddit_metadata() {
  # Keep direct-image posts only. Gallery/video extraction is intentionally out
  # of scope. No subreddit name alone qualifies an ambiguous title.
  CANDIDATE=$(jq -c '
    def unescape: if type == "string" then gsub("&amp;"; "&") else "" end;
    (.preview.images[0] // {}) as $p |
    {source:"reddit", id:("reddit:" + (.name // .id // "")), title:(.title // ""),
     description:"", subjects:[], subreddit:.subreddit,
     sfw:(.over_18 == false and .spoiler != true and .is_video != true),
     width:($p.source.width // 0), height:($p.source.height // 0), mime:"image/jpeg",
     url:((.url_overridden_by_dest // .url) | unescape),
     preview:(([$p.resolutions[]? | select(.width >= 320 and .width <= 960)] |
       sort_by(.width) | last | .url // "") | unescape),
     page:("https://www.reddit.com" + (.permalink // "")), creator:(.author // ""),
     license:"provider download; reuse rights not asserted"}
  ' <<<"$1") || return 1
  subject_eligible || return 1
  jq -e '.url | test("^https://[^?]+\\.(jpg|jpeg|png|webp)(\\?.*)?$"; "i")' \
    <<<"$CANDIDATE" >/dev/null || { reject 'Reddit post is not a direct image'; return 1; }
}

commons_metadata() {
  CANDIDATE=$(jq -c '
    def plain: if type == "string" then gsub("<[^>]*>"; " ") else "" end;
    . as $p | .imageinfo[0] as $i | $i.extmetadata as $m |
    {source:"commons", id:("commons:" + ($p.pageid|tostring)),
     title:($p.title | sub("^File:"; "") | sub("\\.[^.]+$"; "")),
     description:($m.ImageDescription.value | plain), subjects:[],
     categories:[$p.categories[]?.title],
     width:$i.width, height:$i.height, mime:$i.mime,
     preview:$i.thumburl, url:$i.url, page:$i.descriptionurl,
     creator:($m.Artist.value | plain), license:($m.LicenseShortName.value // ""),
     license_url:($m.LicenseUrl.value //
       (if $m.LicenseShortName.value == "Public domain" and $m.Copyrighted.value == "False"
        then "https://creativecommons.org/publicdomain/mark/1.0/" else "" end)),
     attribution:($m.Attribution.value | plain),
     date:($m.DateTimeOriginal.value | plain),
     rights_conflict:(($m.Restrictions.value // "") != "")}
  ' <<<"$1") || return 1
  # A caption may itself be the subject label; use it only when short and not
  # prose about institutions/authors. Category strings never enter subjects.
  CANDIDATE=$(jq -c '.subjects = [(.description | split(".")[0] | select(length <= 180))]' <<<"$CANDIDATE")
  subject_eligible
}

cleveland_metadata() {
  CANDIDATE=$(jq -c '
    . as $a | (.images.print // .images.original // {}) as $full |
    {source:"cleveland", id:("cleveland:" + (.id|tostring)), title:(.title // ""),
     description:(.description // ""), subjects:[], artwork_type:.type,
     width:($full.width | tonumber? // 0), height:($full.height | tonumber? // 0),
     mime:(if ($full.url // "" | test("\\.tiff?$";"i")) then "image/tiff" else "image/jpeg" end),
     preview:.images.web.url, url:$full.url, page:(.url // ("https://openaccess-api.clevelandart.org/api/artworks/" + (.id|tostring))),
     creator:([.creators[]?.description] | join("; ")), date:(.creation_date // ""),
     license:(.share_license_status // "")}
  ' <<<"$1") || return 1
  subject_eligible || return 1
  # Reject photographed coffee vessels, furniture, book bindings etc. The
  # intended museum contribution is depicted scenes, not isolated artifacts.
  jq -e '.artwork_type | strings | test("^(Painting|Print|Drawing|Photograph|Miniature|Illustration|Watercolor|Album)$";"i")' \
    <<<"$CANDIDATE" >/dev/null || { reject 'museum object is not a scene image'; return 1; }
}

rijks_record() {
  local id="$1"
  [[ "$id" =~ ^https://(id|data)\.rijksmuseum\.nl/[0-9]+$ ]] || return 1
  api_request "${id/\/\/id./\/\/data.}?_profile=la-framed"
}

rijksmuseum_metadata() {
  local id visual image_id image_url service rights info
  id=$(jq -r '.id // empty' <<<"$1")
  rijks_record "$id" || return 1
  cp "$WORK/response.json" "$WORK/rijks-object"
  CANDIDATE=$(jq -c --arg id "$id" '
    def primary: any(.classified_as[]?; .id == "http://vocab.getty.edu/aat/300417200");
    [.identified_by[]? | select(.type == "Name" and primary) | .content] as $titles |
    {source:"rijksmuseum", id:("rijksmuseum:" + ($id|split("/")|last)),
     page:$id, title:($titles | join(" / ")), subjects:$titles,
     description:([.referred_to_by[]? |
       select(any(.classified_as[]?; .id == "http://vocab.getty.edu/aat/300435452")) |
       .content // empty] | join(". ")),
     creator:([.produced_by.referred_to_by[]?.content] | unique | join("; ")),
     date:([.produced_by.timespan.identified_by[]?.content] | unique | join(" / ")),
     artwork_types:[.classified_as[]?.notation[]?["@value"]]}
  ' "$WORK/rijks-object") || return 1
  # Fail closed before further metadata/image requests on unrelated art.
  subject_eligible || return 1
  jq -e 'any(.artwork_types[]?; test("^(painting|print|drawing|photograph|watercolour|schilderij|prent|tekening|foto)$";"i"))' \
    <<<"$CANDIDATE" >/dev/null || { reject 'museum object is not a scene image'; return 1; }
  sfw_eligible || return 1
  visual=$(jq -r '.shows[0].id // empty' "$WORK/rijks-object")
  rijks_record "$visual" || return 1
  cp "$WORK/response.json" "$WORK/rijks-visual"
  image_id=$(jq -r '.digitally_shown_by[0].id // empty' "$WORK/rijks-visual")
  rijks_record "$image_id" || return 1
  cp "$WORK/response.json" "$WORK/rijks-image"
  # Actual current schema: reuse rights live on VisualItem.subject_to; also
  # inspect any artwork/image-specific rights to catch contradictory restrictions.
  rights=$(jq -sc '[.[] | .subject_to[]? | .classified_as[]?.id] | unique' \
    "$WORK/rijks-object" "$WORK/rijks-visual" "$WORK/rijks-image") || return 1
  CANDIDATE=$(jq -c --argjson rights "$rights" '
    def open_url: test("^https?://creativecommons\\.org/(publicdomain/(zero|mark)/1\\.0|licenses/by(-sa)?/[1-4]\\.0)/?$");
    . + {license:($rights | join("; ")), license_url:($rights[0] // ""),
         rights_conflict:(any($rights[]; open_url | not))}
  ' <<<"$CANDIDATE") || return 1
  rights_eligible || return 1
  image_url=$(jq -r '.access_point[0].id // empty' "$WORK/rijks-image")
  [[ "$image_url" =~ ^https://iiif\.micr\.io/[a-zA-Z0-9_-]+/full/ ]] || return 1
  service=${image_url%%/full/*}
  api_request "$service/info.json" || return 1
  info=$(jq -c '
    select(.width > 0 and .height > 0) |
    . as $i | ([1, ((.maxWidth // .width)/.width), ((.maxHeight // .height)/.height),
       (((.maxArea // (.width*.height))/(.width*.height))|sqrt)] | min) as $scale |
    {width:((.width*$scale)|floor), height:((.height*$scale)|floor)}
  ' "$WORK/response.json")
  [[ -n "$info" ]] || return 1
  CANDIDATE=$(jq -c --arg service "$service" --arg image "$image_id" --argjson info "$info" '
    . + $info + {image_service:$service, image_id:$image, mime:"image/jpeg",
      preview:($service + "/full/640,/0/default.jpg"),
      url:($service + "/full/max/0/default.jpg")}
  ' <<<"$CANDIDATE")
}

search_source() {
  local provider="$1" query="$2"
  case "$provider" in
    wallhaven)
      api_request --get --data-urlencode "q=$query -neon -cyberpunk" \
        --data-urlencode 'categories=110' --data-urlencode 'purity=100' \
        --data-urlencode 'sorting=random' --data-urlencode "atleast=${MIN_WIDTH}x${MIN_HEIGHT}" \
        --data-urlencode 'ratios=landscape' 'https://wallhaven.cc/api/v1/search' || return 1
      jq -c '.data[]?' "$WORK/response.json" >"$WORK/results" ;;
    reddit)
      (( REDDIT_ATTEMPTS < MAX_REDDIT_ATTEMPTS )) || return 1
      api_request --get --data-urlencode "q=$query" --data-urlencode 'restrict_sr=on' \
        --data-urlencode 'sort=relevance' --data-urlencode 't=all' \
        --data-urlencode 'include_over_18=off' --data-urlencode 'limit=25' \
        'https://api.reddit.com/r/wallpapers+wallpaper+CozyPlaces+ImaginaryInteriors/search' || return 1
      jq -c '.data.children[]?.data' "$WORK/response.json" >"$WORK/results" ;;
    commons)
      api_request --get --data-urlencode 'action=query' --data-urlencode 'format=json' \
        --data-urlencode 'formatversion=2' --data-urlencode 'generator=search' \
        --data-urlencode "gsrsearch=$query filetype:bitmap" --data-urlencode 'gsrnamespace=6' \
        --data-urlencode 'gsrlimit=12' --data-urlencode 'prop=imageinfo|categories' \
        --data-urlencode 'cllimit=50' --data-urlencode 'iiprop=url|size|mime|extmetadata' \
        --data-urlencode 'iiurlwidth=640' --data-urlencode 'iiextmetadatalanguage=en' \
        'https://commons.wikimedia.org/w/api.php' || return 1
      jq -c '.query.pages[]?' "$WORK/response.json" >"$WORK/results" ;;
    cleveland)
      api_request --get --data-urlencode "q=$query" --data-urlencode 'cc0=1' \
        --data-urlencode 'has_image=1' --data-urlencode 'limit=20' \
        'https://openaccess-api.clevelandart.org/api/artworks/' || return 1
      jq -c '.data[]?' "$WORK/response.json" >"$WORK/results" ;;
    rijksmuseum)
      api_request --get --data-urlencode "title=$query" --data-urlencode 'imageAvailable=true' \
        'https://data.rijksmuseum.nl/search/collection' || return 1
      jq -c '.orderedItems[]?' "$WORK/response.json" >"$WORK/results" ;;
  esac
}

image_suitable() {
  local width height format
  read -r width height format < <(identify -format '%w %h %m\n' "${1}[0]" 2>/dev/null)
  [[ "$width" =~ ^[0-9]+$ && "$height" =~ ^[0-9]+$ && "$format" =~ ^(JPEG|PNG|WEBP|TIFF)$ ]] || {
    reject 'image decoding/type failed'; return 1;
  }
  (( width >= MIN_WIDTH && height >= MIN_HEIGHT && width > height )) || {
    reject 'insufficient resolution'; return 1;
  }
  theme_compatible "$1" "$2"
}

apply_wallpaper() {
  local wallpaper="$1" hash="$2" identity="$3"
  # A failed Sway command must not replace the restore pointer or either history.
  swaymsg -r output '*' bg "$wallpaper" fill >"$WORK/sway.json" || return 1
  jq -e 'type == "array" and length > 0 and all(.[]; .success == true)' \
    "$WORK/sway.json" >/dev/null 2>&1 || return 1
  ln -sfn "$wallpaper" "$CURRENT" || return 1
  { tail -n 499 "$HISTORY"; printf '%s\n' "$hash"; } >"$WORK/history"
  mv "$WORK/history" "$HISTORY" || return 1
  { tail -n 499 "$SOURCE_HISTORY"; printf '%s\n' "$identity"; } >"$WORK/source-history"
  mv "$WORK/source-history" "$SOURCE_HISTORY"
}

accepted_log() {
  jq -r --arg score "$LAST_SCORE" '
    "accept: source=\(.source) tier=\(.tier) score=\($score) title=\(.title // .id) page=\(.page // "")" |
    gsub("[\u0000-\u001f\u007f]"; " ")
  ' <<<"$CANDIDATE"
}

save_provenance() {
  local hash="$1"
  jq --arg hash "$hash" --arg score "$LAST_SCORE" \
    '. + {hash:$hash, visual_score:($score|tonumber), theme_version:2}' \
    <<<"$CANDIDATE" >"$WORK/provenance" || return 1
  mv "$WORK/provenance" "$PROVENANCE/$hash.json"
}

try_remote() {
  local url preview id provider hash final
  id=$(jq -r '.id' <<<"$CANDIDATE")
  provider=$(jq -r '.source' <<<"$CANDIDATE")
  url=$(jq -r '.url // ""' <<<"$CANDIDATE")
  preview=$(jq -r '.preview // ""' <<<"$CANDIDATE")
  [[ "$url" == https://* ]] || return 1
  if grep -Fxq "$id" "$SOURCE_HISTORY" || [[ -n "${SEEN_URLS[$url]:-}" ]]; then
    reject 'duplicate/history'; return 1
  fi
  SEEN_URLS[$url]=1
  if [[ "$preview" == https://* ]]; then
    curl "${CURL_ARGS[@]}" "$preview" -o "$PREVIEW" 2>"$WORK/curl-error" || {
      reject 'preview unavailable'; return 1;
    }
    theme_compatible "$PREVIEW" "$provider preview" || return 1
  elif [[ "$provider" != reddit ]]; then
    reject 'no usable preview'; return 1
  fi
  # Reddit retains its old direct-image fallback when no useful preview exists.
  # Its subject/SFW gates still run before this download; final checks are strict.
  curl "${CURL_ARGS[@]}" "$url" -o "$TMP" 2>"$WORK/curl-error" || {
    reject 'full image unavailable'; return 1;
  }
  image_suitable "$TMP" "$provider" || return 1
  hash=$(sha1sum "$TMP" | awk '{print $1}')
  if grep -Fxq "$hash" "$HISTORY" ||
     { [[ -f "$CURRENT" ]] && [[ "$hash" == "$(sha1sum "$CURRENT" | awk '{print $1}')" ]]; }; then
    reject 'duplicate/history'; return 1
  fi
  final="$CACHE/$hash"
  mv "$TMP" "$final" || return 1
  save_provenance "$hash" || return 1
  apply_wallpaper "$final" "$hash" "$id" || return 1
  accepted_log
}

prepare_candidate() {
  local provider="$1" raw="$2" id
  case "$provider" in
    wallhaven) wallhaven_metadata "$raw" || return 1 ;;
    reddit) reddit_metadata "$raw" || return 1 ;;
    commons) commons_metadata "$raw" || return 1 ;;
    cleveland) cleveland_metadata "$raw" || return 1 ;;
    rijksmuseum) rijksmuseum_metadata "$raw" || return 1 ;;
    *) return 1 ;;
  esac
  id=$(jq -r '.id // empty' <<<"$CANDIDATE")
  [[ -n "$id" && -z "${SEEN_IDS[$id]:-}" ]] || return 1
  SEEN_IDS[$id]=1
  sfw_eligible && rights_eligible || return 1
  # Reddit can lack size metadata; then only the final decoded dimensions count.
  if [[ "$provider" != reddit ]] || jq -e '.width > 0 and .height > 0' <<<"$CANDIDATE" >/dev/null; then
    metadata_suitable || return 1
  fi
  if [[ "$TIER" == B ]]; then
    printf '%s\n' "$CANDIDATE" >>"$WORK/tier-b"
    return 1
  fi
  try_remote
}

# Existing approved directory is the manual source. Optional IMAGE.json sidecars
# preserve title/artist/license/page/tier; putting a file here is manual approval.
# Cached downloads need current subject provenance: old anonymous caches cannot
# silently bypass the stricter relevance gate. They can be reviewed and moved to
# coffee-approved explicitly.
curated_metadata() {
  local file="$1" hash="$2" sidecar="${1}.json"
  if [[ "$file" == "$CACHE/"* ]]; then
    [[ -f "$PROVENANCE/$hash.json" ]] || return 1
    jq -e --arg hash "$hash" '.theme_version == 2 and .hash == $hash and (.tier == "A" or .tier == "B")' \
      "$PROVENANCE/$hash.json" >/dev/null 2>&1 || return 1
    CANDIDATE=$(jq -c '.' "$PROVENANCE/$hash.json")
  else
    local metadata='{}' path_id
    path_id=$(printf '%s' "$file" | sha1sum | awk '{print $1}')
    if [[ -f "$sidecar" ]]; then
      metadata=$(jq -ce 'select(type == "object")' "$sidecar") || return 1
    fi
    CANDIDATE=$(jq -cn --argjson meta "$metadata" --arg path "$file" --arg path_id "$path_id" --arg name "${file##*/}" '
      {source:"curated", id:("curated:" + $path_id), local_path:$path,
       title:($meta.title // $name), creator:($meta.creator // ""),
       license:($meta.license // "manually approved; rights reviewed by owner"),
       page:($meta.page // ""), date:($meta.date // ""), tier:($meta.tier // "A"), theme_version:2}
      | select(.tier == "A" or .tier == "B")')
    [[ -n "$CANDIDATE" ]] || return 1
  fi
}

try_local() {
  local desired_tier="$1" allow_repeat="$2" file hash id seen
  local files=()
  shopt -s nullglob
  if enabled curated; then files+=("$APPROVED"/*); fi
  # New remote cache is always a fallback, independently of enabled sources.
  if [[ "$allow_repeat" != fresh ]]; then files+=("$CACHE"/*); fi
  (( ${#files[@]} )) || return 1
  while IFS= read -r -d '' file; do
    (( LOCAL_ATTEMPTS < MAX_LOCAL_ATTEMPTS )) || return 1
    [[ -f "$file" && "$file" != *.json && ! "$file" -ef "$CURRENT" ]] || continue
    hash=$(sha1sum "$file" | awk '{print $1}')
    [[ -f "$CURRENT" ]] && [[ "$hash" == "$(sha1sum "$CURRENT" | awk '{print $1}')" ]] && continue
    curated_metadata "$file" "$hash" || continue
    [[ "$(jq -r '.tier' <<<"$CANDIDATE")" == "$desired_tier" ]] || continue
    id=$(jq -r '.id' <<<"$CANDIDATE")
    seen=0
    if grep -Fxq "$hash" "$HISTORY" || grep -Fxq "$id" "$SOURCE_HISTORY"; then seen=1; fi
    if [[ "$allow_repeat" == fresh || "$allow_repeat" == 0 ]]; then
      (( seen == 0 )) || continue
    else
      (( seen == 1 )) || continue
    fi
    ((LOCAL_ATTEMPTS += 1))
    image_suitable "$file" 'approved local' || continue
    save_provenance "$hash" || continue
    apply_wallpaper "$file" "$hash" "$id" || continue
    accepted_log
    return 0
  done < <(printf '%s\0' "${files[@]}" | shuf -z)
  return 1
}

# Subject-first queries only. Style/atmosphere is never a standalone query.
# Museums are supplementary and use a small, deliberately narrow search pool.
mapfile -t QUERIES_A < <(printf '%s\n' 'cafe' 'coffeehouse' 'cat cafe' 'coffee' 'book cafe' 'cat warm interior' | shuf)
mapfile -t QUERIES_B < <(printf '%s\n' 'bookstore' 'library interior' 'tea room' 'reading room' 'cat window' 'bakery' | shuf)
for round in 0 1; do
  for provider in wallhaven reddit commons curated cleveland rijksmuseum; do
    enabled "$provider" || continue
    if [[ "$provider" == curated ]]; then
      try_local A fresh && exit 0
      continue
    fi
    (( ATTEMPTS < MAX_THEME_ATTEMPTS && SOURCE_REQUESTS < MAX_SOURCE_REQUESTS )) || continue
    if (( round == 0 )); then query=${QUERIES_A[0]}; else query=${QUERIES_B[0]}; fi
    # The root category is small, so include its country/individual-cafe tree.
    if [[ "$provider" == commons && "$round" == 0 ]]; then
      query='deepcat:"Cat cafés"'
    fi
    # Museum title searches stay simple (not all providers tokenize phrases alike).
    if [[ "$provider" == cleveland || "$provider" == rijksmuseum ]]; then
      if (( round == 0 )); then
        query=$(printf '%s\n' cafe café coffeehouse coffee koffiehuis | shuf -n 1)
      else
        query=$(printf '%s\n' library bookstore 'tea room' 'reading room' 'cat window' | shuf -n 1)
      fi
    fi
    printf 'Trying %s: %s\n' "$provider" "$query"
    search_source "$provider" "$query" || continue
    source_attempts=0
    while IFS= read -r raw; do
      (( ATTEMPTS < MAX_THEME_ATTEMPTS && source_attempts < MAX_SOURCE_ATTEMPTS )) || break
      if [[ "$provider" == reddit ]]; then
        (( REDDIT_ATTEMPTS < MAX_REDDIT_ATTEMPTS )) || break
        ((REDDIT_ATTEMPTS += 1))
      fi
      ((ATTEMPTS += 1, source_attempts += 1))
      prepare_candidate "$provider" "$raw" && exit 0
    done < <(shuf "$WORK/results")
  done
done

# All discovered Tier A candidates (including new approved art) get first chance.
while IFS= read -r CANDIDATE; do
  try_remote && exit 0
done <"$WORK/tier-b"
try_local B fresh && exit 0

# Prefer unseen approved/cache images; then repeats excluding the current image.
for allow_repeat in 0 1; do
  for tier in A B; do
    try_local "$tier" "$allow_repeat" && exit 0
  done
done
# A lone approved current wallpaper can simply remain in place. Never adopt an
# unrelated legacy download solely because it is currently displayed.
if [[ -f "$CURRENT" ]]; then
  file=$(readlink -f "$CURRENT")
  hash=$(sha1sum "$file" | awk '{print $1}')
  if [[ "$file" == "$APPROVED/"* || "$file" == "$CACHE/"* ]] &&
    curated_metadata "$file" "$hash" && image_suitable "$file" 'current approved'; then
    echo 'No new candidate qualified; keeping the approved current wallpaper.'
    exit 0
  fi
fi
echo "No suitable cat-cafe wallpaper after $ATTEMPTS candidates / $SOURCE_REQUESTS API requests; current wallpaper unchanged."
exit 1
