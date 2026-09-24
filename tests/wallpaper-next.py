#!/usr/bin/env python3
"""Offline integration tests; never contact providers or the real Sway session."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "home/corey/scripts/wallpaper-next.sh"

# Only network and compositor boundaries are mocked. jq, ImageMagick, palette
# scoring, filesystem updates, locking and history use their real implementations.
MOCK = r'''#!/usr/bin/env python3
import json, os, pathlib, shutil, sys
root = pathlib.Path(os.environ["FIXTURES"])
a = sys.argv[1:]
with (root / "calls").open("a") as f:
    f.write(json.dumps([pathlib.Path(sys.argv[0]).name, *a]) + "\n")
if pathlib.Path(sys.argv[0]).name == "swaymsg":
    print(json.dumps([{"success": os.environ.get("SWAY_FAIL") != "1"}]))
    sys.exit(0)
url = next(x for x in a if x.startswith("https://"))
out = pathlib.Path(a[a.index("-o") + 1])
if os.environ.get("NETWORK_FAIL") == "1":
    sys.exit(22)
if url == "https://wallhaven.cc/api/v1/search":
    shutil.copyfile(root / "wallhaven-search.json", out)
elif "/api/v1/w/" in url:
    shutil.copyfile(root / "wallhaven-detail.json", out)
elif "api.reddit.com" in url:
    shutil.copyfile(root / "reddit-search.json", out)
elif "commons.wikimedia.org/w/api.php" in url:
    shutil.copyfile(root / "commons-search.json", out)
elif "openaccess-api.clevelandart.org" in url:
    shutil.copyfile(root / "cleveland-search.json", out)
elif "data.rijksmuseum.nl/search/collection" in url:
    shutil.copyfile(root / "rijks-search.json", out)
elif "data.rijksmuseum.nl/" in url:
    key = url.split("/")[-1].split("?")[0]
    shutil.copyfile(root / ("rijks-" + key + ".json"), out)
elif url.startswith("https://iiif.micr.io/"):
    if url.endswith("info.json"):
        shutil.copyfile(root / "iiif-info.json", out)
    elif "/640,/" in url:
        shutil.copyfile(root / "warm.jpg", out)
    else:
        shutil.copyfile(root / os.environ.get("IIIF_FULL", "warm.jpg"), out)
elif url.startswith("https://images.test/"):
    shutil.copyfile(root / url.rsplit("/", 1)[1], out)
else:
    raise SystemExit("Unexpected URL: " + url)
'''


class WallpaperTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        for cmd in ("bash", "jq", "magick", "identify", "flock"):
            if not shutil.which(cmd):
                raise unittest.SkipTest(f"Requires {cmd}")
        cls.images = tempfile.TemporaryDirectory()
        for name, size, color in (
            ("warm.jpg", "1920x1080", "#413631"),
            ("other.jpg", "1920x1080", "#2d2521"),
            ("cold.jpg", "1920x1080", "#0022ff"),
            ("small.jpg", "1280x720", "#413631"),
        ):
            subprocess.run(["magick", "-size", size, f"xc:{color}",
                            str(Path(cls.images.name) / name)], check=True)

    @classmethod
    def tearDownClass(cls):
        cls.images.cleanup()

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.home = self.root / "home"
        self.wallpapers = self.home / "Pictures/wallpapers"
        self.wallpapers.mkdir(parents=True)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        for cmd in ("curl", "swaymsg"):
            path = self.bin / cmd
            path.write_text(MOCK)
            path.chmod(0o755)
        for path in Path(self.images.name).iterdir():
            shutil.copy(path, self.root)
        self.write_json("wallhaven-search.json", {"data": []})
        self.write_json("wallhaven-detail.json", {"data": {}})
        self.write_json("reddit-search.json", {"data": {"children": []}})
        self.write_json("commons-search.json", {"query": {"pages": []}})
        self.write_json("cleveland-search.json", {"data": []})
        self.write_json("rijks-search.json", {"orderedItems": []})
        self.env = {k: v for k, v in os.environ.items()
                    if not k.startswith(("THEME_", "MAX_", "CURL_", "PIXABAY_", "XDG_", "WALLPAPER_", "MIN_"))}
        self.env.update(HOME=str(self.home), FIXTURES=str(self.root),
                        PATH=f"{self.bin}:{os.environ['PATH']}",
                        WALLPAPER_SOURCES="wallhaven,curated")

    def write_json(self, name, data):
        (self.root / name).write_text(json.dumps(data))

    def wallhaven(self, tags=("coffee",), preview="warm.jpg", full="warm.jpg", **extra):
        self.write_json("wallhaven-search.json", {"data": [{"id": "abc123"}]})
        data = dict(id="abc123", purity="sfw", dimension_x=1920, dimension_y=1080,
                    tags=[{"name": tag} for tag in tags],
                    path=f"https://images.test/{full}",
                    thumbs={"original": f"https://images.test/{preview}"})
        data.update(extra)
        self.write_json("wallhaven-detail.json", {"data": data})

    def commons(self, title="Cat cafe interior.jpg", description="Cat cafe interior", **extra):
        record = dict(pageid=42, title="File:" + title,
                      categories=[{"title": "Category:Cat cafés"}],
                      imageinfo=[dict(width=1920, height=1080, mime="image/jpeg",
                                      url="https://images.test/warm.jpg",
                                      thumburl="https://images.test/warm.jpg",
                                      descriptionurl="https://commons.wikimedia.org/wiki/File:Cat_cafe.jpg",
                                      extmetadata={"ImageDescription": {"value": description},
                                                   "Artist": {"value": "A Photographer"},
                                                   "LicenseShortName": {"value": "CC BY-SA 4.0"},
                                                   "LicenseUrl": {"value": "https://creativecommons.org/licenses/by-sa/4.0/"}})])
        record.update(extra)
        self.write_json("commons-search.json", {"query": {"pages": [record]}})
        return record

    def cleveland(self, title="Coffeehouse", **extra):
        asset = dict(width=1920, height=1080, url="https://images.test/warm.jpg")
        record = dict(id=123, title=title, type="Painting", description="",
                      share_license_status="CC0", images={"web": asset, "print": asset},
                      creators=[{"description": "An Artist"}], creation_date="1900",
                      url="https://www.clevelandart.org/art/123")
        record.update(extra)
        self.write_json("cleveland-search.json", {"data": [record]})
        return record

    def rijks(self, title="Coffeehouse interior", license="https://creativecommons.org/publicdomain/mark/1.0/", **info):
        self.write_json("rijks-search.json", {"orderedItems": [{"id": "https://id.rijksmuseum.nl/100"}]})
        obj = dict(id="https://id.rijksmuseum.nl/100",
                   identified_by=[dict(type="Name", content=title,
                                       classified_as=[{"id": "http://vocab.getty.edu/aat/300417200"}])],
                   classified_as=[{"notation": [{"@language": "en", "@value": "painting"}]}],
                   shows=[{"id": "https://id.rijksmuseum.nl/200"}])
        self.write_json("rijks-100.json", obj)
        self.write_json("rijks-200.json", {"subject_to": [{"classified_as": [{"id": license}]}],
                        "digitally_shown_by": [{"id": "https://id.rijksmuseum.nl/300"}]})
        self.write_json("rijks-300.json", {"access_point": [{"id": "https://iiif.micr.io/Test/full/max/0/default.jpg"}]})
        self.write_json("iiif-info.json", dict(width=4000, height=2250, **info))
        return obj

    def reddit(self, title="Warm cat cafe interior", **extra):
        record = dict(id="abc", name="t3_abc", title=title, over_18=False, is_video=False,
                      subreddit="CozyPlaces", author="Artist", permalink="/r/CozyPlaces/comments/abc/",
                      url="https://images.test/warm.jpg", preview={"images": [dict(
                          source=dict(width=1920, height=1080, url="https://images.test/warm.jpg"),
                          resolutions=[dict(width=640, height=360, url="https://images.test/warm.jpg")])]})
        record.update(extra)
        self.write_json("reddit-search.json", {"data": {"children": [{"data": record}]}})
        return record

    def run_script(self, status=0, **env):
        result = subprocess.run(["bash", str(SCRIPT)], env=self.env | env,
                                capture_output=True, text=True, timeout=20)
        self.assertEqual(result.returncode, status, result.stdout + result.stderr)
        self.assertNotIn("TEST_SECRET_KEY", result.stdout + result.stderr)
        self.assertFalse(list(self.wallpapers.glob(".wallpaper-next.*")))
        return result

    def calls(self):
        path = self.root / "calls"
        return [json.loads(line) for line in path.read_text().splitlines()] if path.exists() else []

    def image_calls(self):
        return [c for c in self.calls() if any(x.startswith("https://images.test/") for x in c)]

    def add_local(self, directory, image="warm.jpg", name="approved coffee.jpg"):
        path = self.wallpapers / directory / name
        path.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(self.root / image, path)
        return path

    def test_wallhaven_accepts_and_uses_content_hash(self):
        self.wallhaven()
        self.run_script()
        current = self.wallpapers / "current"
        expected = hashlib.sha1((self.root / "warm.jpg").read_bytes()).hexdigest()
        self.assertEqual(current.resolve(), self.wallpapers / "coffee-cache" / expected)
        self.assertEqual((self.wallpapers / ".history").read_text(), expected + "\n")
        self.assertEqual(len(self.image_calls()), 2)

    def test_unrelated_or_missing_tags_never_download_images(self):
        for tags in (("coffee table", "palette", "warm interior"), ("autumn", "landscape"), ()):
            with self.subTest(tags=tags):
                self.wallhaven(tags=tags)
                self.run_script(status=1)
                self.assertEqual(self.image_calls(), [])

    def test_non_sfw_metadata_is_rejected(self):
        self.wallhaven(purity="sketchy")
        self.run_script(status=1)
        self.assertEqual(self.image_calls(), [])

    def test_preview_rejection_avoids_full_download(self):
        self.wallhaven(preview="cold.jpg")
        self.run_script(status=1)
        self.assertEqual(len(self.image_calls()), 1)
        self.assertIn("https://images.test/cold.jpg", self.image_calls()[0])

    def test_full_image_revalidated(self):
        for image in ("cold.jpg", "small.jpg"):
            with self.subTest(image=image):
                self.wallhaven(full=image)
                self.run_script(status=1)
                self.assertFalse((self.wallpapers / "current").exists())

    def test_missing_preview_and_malformed_response(self):
        self.wallhaven(thumbs={})
        self.run_script(status=1)
        (self.root / "wallhaven-search.json").write_text("not JSON")
        self.run_script(status=1)
        self.assertEqual(self.image_calls(), [])

    def test_network_failure_uses_approved_local(self):
        path = self.add_local("coffee-approved")
        self.run_script(NETWORK_FAIL="1")
        self.assertEqual((self.wallpapers / "current").resolve(), path)

    def test_legacy_images_excluded_and_current_preserved(self):
        path = self.add_local(".")
        current = self.wallpapers / "current"
        current.symlink_to(path)
        self.run_script(status=1)
        self.assertEqual(current.resolve(), path)
        self.assertFalse(any(c[0] == "swaymsg" for c in self.calls()))

    def test_cache_repeats_allowed_but_current_excluded(self):
        old = self.add_local("coffee-cache")
        other = self.add_local("coffee-cache", "other.jpg", "other")
        (self.wallpapers / "current").symlink_to(old)
        hashes = [hashlib.sha1(p.read_bytes()).hexdigest() for p in (old, other)]
        for image_hash in hashes:
            meta = self.wallpapers / ".provenance" / f"{image_hash}.json"
            meta.parent.mkdir(exist_ok=True)
            meta.write_text(json.dumps(dict(theme_version=2, hash=image_hash, tier="A",
                                           source="wallhaven", id="wallhaven:"+image_hash,
                                           title="Coffeehouse")))
        (self.wallpapers / ".history").write_text("\n".join(hashes) + "\n")
        self.run_script()
        self.assertEqual((self.wallpapers / "current").resolve(), other)

    def test_sway_failure_does_not_change_pointer_or_history(self):
        current = self.add_local(".", "other.jpg")
        (self.wallpapers / "current").symlink_to(current)
        self.add_local("coffee-approved")
        self.run_script(status=1, SWAY_FAIL="1")
        self.assertEqual((self.wallpapers / "current").resolve(), current)
        self.assertEqual((self.wallpapers / ".history").read_text(), "")

    def test_api_budget_includes_detail_requests(self):
        self.wallhaven(tags=("wood",))
        self.run_script(status=1, MAX_SOURCE_REQUESTS="2")
        self.assertEqual(len(self.calls()), 2)

    def test_invalid_settings_stop_before_requests(self):
        self.run_script(status=1, THEME_MIN_SCORE="101")
        self.assertEqual(self.calls(), [])

    def test_cafe_and_cat_interior_tags_qualify(self):
        for tags in (("cafe",), ("cat", "interior")):
            with self.subTest(tags=tags):
                self.wallhaven(tags=tags)
                self.run_script()
                # Clear state between selections of the same fixture image.
                (self.wallpapers / "current").unlink()
                (self.wallpapers / ".history").write_text("")
                (self.wallpapers / ".source-history").write_text("")

    def test_commons_accepts_with_provenance(self):
        self.commons()
        result = self.run_script(WALLPAPER_SOURCES="commons")
        self.assertIn("tier=A", result.stdout)
        meta = json.loads(next((self.wallpapers / ".provenance").glob("*.json")).read_text())
        self.assertEqual(meta["id"], "commons:42")
        self.assertEqual(meta["creator"], "A Photographer")
        self.assertEqual(meta["license"], "CC BY-SA 4.0")
        self.assertEqual(len(self.image_calls()), 2)
        self.assertTrue(any("--user-agent" in c for c in self.calls()))

    def test_commons_category_alone_is_not_evidence(self):
        self.commons(title="Rainy street.jpg", description="Evening in Japan")
        self.run_script(status=1, WALLPAPER_SOURCES="commons")
        self.assertEqual(self.image_calls(), [])

    def test_commons_rejects_restricted_rights_and_small_images(self):
        for reason in ("rights", "size", "mime", "preview", "nsfw"):
            with self.subTest(reason=reason):
                r = self.commons()
                i = r["imageinfo"][0]
                if reason == "rights":
                    i["extmetadata"]["LicenseUrl"]["value"] = "https://creativecommons.org/licenses/by-nc/4.0/"
                elif reason == "size":
                    i["width"] = 1280
                elif reason == "mime":
                    i["mime"] = "image/svg+xml"
                elif reason == "preview":
                    i.pop("thumburl")
                else:
                    r["categories"].append({"title": "Category:Nudity"})
                self.write_json("commons-search.json", {"query": {"pages": [r]}})
                self.run_script(status=1, WALLPAPER_SOURCES="commons")
                self.assertEqual(self.image_calls(), [])

    def test_cleveland_accepts_cc0_painting(self):
        self.cleveland()
        self.run_script(WALLPAPER_SOURCES="cleveland")
        self.assertEqual((self.wallpapers / ".source-history").read_text(), "cleveland:123\n")
        self.assertEqual(len(self.image_calls()), 2)

    def test_cleveland_never_uses_biography_or_collection_as_evidence(self):
        for description in ("The artist visited cafes.", "A landscape, inspired by a coffeehouse.",
                            "This painting depicts a forest. The artist loved coffee."):
            self.cleveland(title="Landscape", description=description,
                           creators=[{"description": "Cafe artist"}],
                           provenance=["A library collection"], medium="coffee on canvas")
            self.run_script(status=1, WALLPAPER_SOURCES="cleveland")
        self.assertEqual(self.image_calls(), [])

    def test_cleveland_depiction_statement_can_establish_subject(self):
        self.cleveland(title="Evening", description="This painting depicts a cat at a window.")
        result = self.run_script(WALLPAPER_SOURCES="cleveland")
        self.assertIn("tier=B", result.stdout)

    def test_cleveland_rights_artifact_and_resolution_rejections(self):
        for extra in (dict(share_license_status="Copyrighted"), dict(type="Ceramic"),
                      dict(images={"web": {"url": "https://images.test/warm.jpg"},
                                   "print": {"width": 1280, "height": 720, "url": "https://images.test/warm.jpg"}})):
            self.cleveland(**extra)
            self.run_script(status=1, WALLPAPER_SOURCES="cleveland")
        self.assertEqual(self.image_calls(), [])

    def test_rijks_linked_rights_and_preview_before_full(self):
        self.rijks()
        self.run_script(WALLPAPER_SOURCES="rijksmuseum")
        urls = [next((a for a in c if a.startswith("https://")), "") for c in self.calls()]
        preview = "https://iiif.micr.io/Test/full/640,/0/default.jpg"
        full = "https://iiif.micr.io/Test/full/max/0/default.jpg"
        self.assertLess(urls.index(preview), urls.index(full))
        meta = json.loads(next((self.wallpapers / ".provenance").glob("*.json")).read_text())
        self.assertEqual(meta["image_service"], "https://iiif.micr.io/Test")

    def test_rijks_generic_interior_stops_before_image_resolution(self):
        self.rijks(title="Candlelit Dutch interior")
        self.run_script(status=1, WALLPAPER_SOURCES="rijksmuseum")
        self.assertFalse(any("https://data.rijksmuseum.nl/200?_profile=la-framed" in c for c in self.calls()))

    def test_rijks_rights_and_effective_iiif_resolution(self):
        for kw in (dict(license=""), dict(license="https://rightsstatements.org/vocab/InC/1.0/"),
                   dict(maxArea=1000000), dict(maxWidth=1280), dict(maxHeight=720)):
            self.rijks(**kw)
            self.run_script(status=1, WALLPAPER_SOURCES="rijksmuseum")
        self.assertFalse(any(any("/full/" in a for a in c) for c in self.calls()))

    def test_rijks_conflicting_image_rights_rejected(self):
        self.rijks()
        path = self.root / "rijks-300.json"
        data = json.loads(path.read_text())
        data["subject_to"] = [{"classified_as": [{"id": "https://rightsstatements.org/vocab/InC/1.0/"}]}]
        path.write_text(json.dumps(data))
        self.run_script(status=1, WALLPAPER_SOURCES="rijksmuseum")
        self.assertFalse(any(any("iiif.micr.io" in a for a in c) for c in self.calls()))

    def test_rijks_final_resolution_revalidated(self):
        self.rijks()
        self.run_script(status=1, WALLPAPER_SOURCES="rijksmuseum", IIIF_FULL="small.jpg")
        self.assertFalse((self.wallpapers / "current").exists())

    def test_reddit_title_and_preview(self):
        self.reddit()
        self.run_script(WALLPAPER_SOURCES="reddit")
        self.assertEqual(len(self.image_calls()), 2)

    def test_reddit_ambiguous_title_and_nsfw_rejected_before_images(self):
        for title, extra in (("Cozy evening", {}), ("Rainy Japanese street", {}),
                             ("Cat cafe", {"over_18": True})):
            self.reddit(title=title, **extra)
            self.run_script(status=1, WALLPAPER_SOURCES="reddit")
        self.assertEqual(self.image_calls(), [])

    def test_reddit_without_preview_retains_direct_image_support(self):
        self.reddit(preview={})
        self.run_script(WALLPAPER_SOURCES="reddit")
        self.assertEqual(len(self.image_calls()), 1)

    def test_tier_a_is_preferred_over_earlier_b(self):
        self.wallhaven(tags=("library",), full="other.jpg")
        self.commons()
        result = self.run_script(WALLPAPER_SOURCES="wallhaven,commons")
        self.assertIn("source=commons tier=A", result.stdout)
        self.assertFalse(any("https://images.test/other.jpg" in c for c in self.image_calls()))

    def test_curated_sidecar_provenance_and_decode_requirements(self):
        self.add_local("coffee-approved", "small.jpg", "small.jpg")
        image = self.add_local("coffee-approved", name="Digital Cafe.jpg")
        Path(str(image) + ".json").write_text(json.dumps(dict(title="Cat cafe painting", creator="Artist", tier="A", license="Permission")))
        self.run_script(WALLPAPER_SOURCES="curated")
        self.assertEqual((self.wallpapers / "current").resolve(), image)
        self.assertEqual(self.image_calls(), [])
        meta = json.loads(next((self.wallpapers / ".provenance").glob("*.json")).read_text())
        self.assertEqual(meta["creator"], "Artist")

    def test_legacy_unprovenanced_cache_is_not_subject_approval(self):
        self.add_local("coffee-cache")
        self.run_script(status=1, WALLPAPER_SOURCES="curated")
        self.assertFalse((self.wallpapers / "current").exists())

    def test_lone_approved_current_can_be_kept(self):
        image = self.add_local("coffee-approved")
        (self.wallpapers / "current").symlink_to(image)
        result = self.run_script(WALLPAPER_SOURCES="curated")
        self.assertIn("keeping the approved current", result.stdout)
        self.assertFalse(any(c[0] == "swaymsg" for c in self.calls()))

    def test_stable_id_history_prevents_new_downloads(self):
        self.commons()
        (self.wallpapers / ".source-history").write_text("commons:42\n")
        self.run_script(status=1, WALLPAPER_SOURCES="commons")
        self.assertEqual(self.image_calls(), [])

    def test_source_attempts_and_metadata_requests_are_bounded(self):
        self.rijks()
        self.run_script(status=1, WALLPAPER_SOURCES="rijksmuseum", MAX_SOURCE_REQUESTS="2")
        self.assertEqual(len(self.calls()), 2)

    def test_no_unsupported_provider_requests(self):
        self.run_script(status=1, WALLPAPER_SOURCES="wallhaven,reddit,commons,cleveland,rijksmuseum")
        self.assertFalse(any("pixabay" in str(c).lower() for c in self.calls()))


if __name__ == "__main__":
    unittest.main(verbosity=2)
