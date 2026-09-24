# Cat-café wallpapers

`wallpaper-next` (Super+Shift+W in Sway) selects a warm, dark cat-café world.
It uses Wallhaven, Reddit, Wikimedia Commons, Cleveland Museum of Art,
Rijksmuseum, and a manually approved local collection. Pixabay is not used.

## Subject first

Every automated candidate must establish a subject tier **before** SFW, rights,
image eligibility, or palette scoring. A warm color score cannot establish a
subject or rescue an unrelated image.

- **A, preferred:** café/coffeehouse/coffee-shop scenes, coffee/espresso, book
  cafés, café paintings/illustration, and cats in clearly warm/cozy interiors.
- **B, supporting:** bookstores, libraries, tea rooms, bakeries, reading rooms,
  cats in interiors/windows/shops, and rooms clearly associated with books/tea.
- **C, rejected:** generic streets, forests, cabins, mountains, landscapes,
  sunsets, anime scenery, and historical/Dutch interiors without an A/B subject.

Tier B candidates are held until the bounded search has tried available Tier A
candidates. There are no broader museum or atmosphere-only fallback queries.
New manually approved Tier A art also gets a chance before Tier B.

The gate is conservative metadata matching, not image understanding. It uses
subject titles and explicit subject tags; free-form descriptions need an explicit
"depicts/shows/portrays/features" sentence. Short Commons captions can also supply
subject evidence. Artist biographies, institution names, collection provenance,
medium, subreddit names, and category membership do not qualify an image.
Ambiguous records are skipped. Some relevant images will therefore be missed;
mislabeled metadata is still possible. Review those images into the local
collection instead of weakening the subject gate.

## Sources

- **Wallhaven:** subject-first queries, General/Anime and SFW search filters,
  landscape/minimum size, then detail-tag confirmation. Existing previews and
  exact-hash history remain in use.
- **Reddit:** narrow searches within wallpapers, wallpaper, CozyPlaces, and
  ImaginaryInteriors replace broad landscape/space/city feeds. Post titles must
  establish A/B; over-18, spoiler, and video posts are rejected. Direct image
  posts only. A moderate preview is scored first when available. Without one,
  direct-image download remains supported after the subject/SFW gates; the
  decoded full image must still pass resolution and palette checks. HTTP access
  failures skip Reddit rather than bypassing service restrictions.
- **Commons:** official MediaWiki API, identifying User-Agent, cat-café category
  tree discovery followed by narrow supporting searches. File title/caption
  evidence is mandatory regardless of category. MIME type, pixel dimensions,
  license, restriction metadata, and thumbnail availability are checked. The
  generated 640-pixel thumbnail precedes the original download.
- **Cleveland:** official JSON API, narrow searches only, explicit CC0 rights and
  scene-oriented artwork types. Title/depiction evidence is required; the
  collection description or artist biography cannot qualify a record. Web
  previews precede print/original downloads. The selected larger asset's pixel
  dimensions are checked before transfer.
- **Rijksmuseum:** current keyless Search API and Linked Art object → VisualItem →
  DigitalObject chain. Primary titles/depiction text establish relevance before
  resolving images. Reuse rights are read from the linked visual record, plus
  any explicit object/image rights. Conflicting or unknown rights are rejected.
  IIIF image info supplies dimensions and maximum output constraints. A 640-pixel
  preview precedes the permitted maximum rendition. The downloaded pixels must
  still meet the minimum resolution.

Only Public Domain/CC0/CC BY/CC BY-SA license URLs are accepted from the new
Commons/Rijksmuseum sources. Cleveland requires CC0. Clear rights metadata is
mandatory; API access is not a reuse license. Wallhaven/Reddit keep their existing
provider-download behavior, with no new claim that their content is openly
licensed. SFW exclusions inspect relevant metadata, including Commons categories;
open access/public domain itself does not mean SFW.

## Manually approved art

Place reviewed files directly in:

```
~/Pictures/wallpapers/coffee-approved/
```

Placing a file there asserts that you have reviewed its A/B subject, SFW status,
quality, and permission to use it. This supports anime, digital painting,
concept/environment art, and manually obtained artwork without a new API.
It does not approve generic off-theme scenery.

Files still undergo decoding, landscape/minimum-resolution, warm/dark scoring,
and duplicate checks. JPEG, PNG, WebP, and TIFF are supported. No upscaling.

Optional sidecar metadata is named **exactly** `IMAGE_FILENAME.json`; for example,
`book-cafe.png.json` alongside `book-cafe.png`:

```json
{
  "title": "Book café with sleeping cat",
  "creator": "Artist name",
  "license": "Artist permission for personal wallpaper use",
  "page": "https://example.org/original-artwork",
  "tier": "A"
}
```

Tier defaults to A for manually approved files; use B for supporting material.
Only A/B values are accepted. A malformed sidecar causes that file to be skipped.
Sidecars are optional; no database or manifest generator is needed.

## Visual checks, provenance, history, and fallback

Palette scoring retains the existing per-pixel dark/warm/muted-color model and
penalties for cold blue/purple, neon saturation, and excessive brightness. It
scores an approximate center-fill crop at the configured desktop aspect ratio.
The upper sample row receives a small brightness penalty, never an independent
hard rejection. Full-resolution downloads are decoded and scored again.

Accepted remote images retain content-addressed names in `coffee-cache/`.
`.provenance/HASH.json` records source, subject tier, score, stable item identity,
title, creator, rights, source page, and optional date/image-service details.
Keep these records with the images, especially where attribution is required.
`.history` retains 500 image hashes; `.source-history` additionally tracks recent
provider/object IDs or a hash of the curated file path. Sway must report success
before updating `current` or history. Locking prevents overlapping selections.

When remote discovery fails, use approved files and cache entries with current
subject provenance, preferring unseen files, then permitting older repeats other
than the displayed image. If only the approved current image qualifies, leave it
in place. Otherwise keep the current image unchanged and exit unsuccessfully.
Never relax subject requirements into Tier C.

Legacy downloads in the parent directory and old cache files without current
subject provenance are excluded. To adopt one, review it and put it in
`coffee-approved/`. Existing files are not deleted or migrated automatically.

## Tuning and validation

- `THEME_DEBUG=1` prints passing visual scores; rejects are always concise.
- `THEME_MIN_SCORE=60` (0–100), `THEME_SAMPLE_SIZE=32` (1–128).
- `MIN_WIDTH=1920`, `MIN_HEIGHT=1080` define minimum resolution and scoring crop
  ratio; width must exceed height.
- `MAX_THEME_ATTEMPTS=40`, `MAX_SOURCE_ATTEMPTS=4`, `MAX_REDDIT_ATTEMPTS=6`.
- `MAX_SOURCE_REQUESTS=32` includes search/detail/Linked Art/IIIF requests. This
  replaces the earlier 16-request default to accommodate linked museum records.
- `MAX_LOCAL_ATTEMPTS=100` bounds local image analyses.
- Curl connection/total limits remain `CURL_CONNECT_TIMEOUT=5` and
  `CURL_MAX_TIME=25` seconds. No automatic retry loops. Repeated API calls,
  including failed calls, are cached only within that run.
- `WALLPAPER_USER_AGENT` overrides the identifying user/host default. When making
  repeated public API requests, set it to a descriptive value with your public
  contact URL/email as requested by the provider.
- `WALLPAPER_SOURCES` is a comma-separated subset of
  `wallhaven,reddit,commons,cleveland,rijksmuseum,curated`. It controls new-source
  discovery; the provenance-checked remote cache remains available for fallback.

From the repository, inside Sway, test the current source without rebuilding:

```sh
THEME_DEBUG=1 bash home/corey/scripts/wallpaper-next.sh
```

For an entirely local manual run, add `WALLPAPER_SOURCES=curated`.
Offline integration tests use isolated temporary homes and fake network/Sway
commands, with real jq, ImageMagick, palette checks, provenance, and histories:

```sh
python3 tests/wallpaper-next.py
```
