#!/usr/bin/env python3
"""Integration tests for inspect_image and core/image_describe.gd: reading an
image file as numbers and ASCII (no vision required), the expectations that gate
the exit code, frame-sequence consistency, and the text renderer.

PNGs are written with the stdlib (struct + zlib) so the tests need no image
library and no `--import` pass — which is also how the op is meant to be used on
freshly generated art."""
from __future__ import annotations

import base64
import json
import shutil
import struct
import subprocess
import tempfile
import zlib
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
FIXTURE_ROOT = REPO_ROOT / "tests/fixtures/minimal_project"
DISPATCHER = REPO_ROOT / "skill/godot/scripts/core/dispatcher.gd"

TRANSPARENT = (0, 0, 0, 0)
RED = (255, 0, 0, 255)

# 64x64 black JPEG (quality 90, 4:2:0 chroma) with a red 16x16 square at (32, 8):
# the same picture write_square() draws, so the lossy and lossless answers can
# be compared directly.
JPEG_SQUARE_B64 = (
    "/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAMCAgMCAgMDAwMEAwMEBQgFBQQEBQoHBwYIDAoMDAsKCwsNDhIQDQ4RDgsLEBYQERMUFRUVDA8XGBYUGBIUFRT/"
    "2wBDAQMEBAUEBQkFBQkUDQsNFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBT/wAARCABAAEADASIAAhEBAxEB/8QA"
    "HwAAAQUBAQEBAQEAAAAAAAAAAAECAwQFBgcICQoL/8QAtRAAAgEDAwIEAwUFBAQAAAF9AQIDAAQRBRIhMUEGE1FhByJxFDKBkaEII0KxwRVS0fAkM2JyggkK"
    "FhcYGRolJicoKSo0NTY3ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXG"
    "x8jJytLT1NXW19jZ2uHi4+Tl5ufo6erx8vP09fb3+Pn6/8QAHwEAAwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQoL/8QAtREAAgECBAQDBAcFBAQAAQJ3AAEC"
    "AxEEBSExBhJBUQdhcRMiMoEIFEKRobHBCSMzUvAVYnLRChYkNOEl8RcYGRomJygpKjU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6goOE"
    "hYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsrO0tba3uLm6wsPExcbHyMnK0tPU1dbX2Nna4uPk5ebn6Onq8vP09fb3+Pn6/9oADAMBAAIRAxEAPwD8qqKKKACi"
    "iigAor7Kor4b/Wf/AKc/+Tf/AGp/VP8AxAz/AKmX/lL/AO6nxrRRRX3J/KwUUUUAFFFFAH2VRXxrRXw3+rH/AE+/8l/+2P6p/wCI5/8AUt/8q/8A3IKKKK+5"
    "P5WCiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooA//2Q=="
)


def main() -> None:
    if shutil.which("godot") is None:
        print("SKIP: godot is not on PATH; skipping inspect_image tests.")
        return
    test_blank_image()
    test_sprite_geometry_and_palette()
    test_ascii_rendering()
    test_compare_to()
    test_expect_gates_exit_code()
    test_image_paths_mode()
    test_text_format()
    test_large_image_samples_colors_but_not_the_bbox()
    test_lossy_jpeg_background_tolerance()
    test_input_errors()
    print("All inspect_image tests passed.")


def test_lossy_jpeg_background_tolerance() -> None:
    """JPEG ringing must not stretch content_bbox over the chroma-bleed block:
    .jpg defaults to background_tolerance 0.12, everything else stays exact."""
    with fixture_project() as project:
        (project / "art").mkdir(parents=True, exist_ok=True)
        (project / "art/square.jpg").write_bytes(base64.b64decode(JPEG_SQUARE_B64))
        write_square(project / "art/square.png")

        lossy = dispatch(project, "inspect_image", {"image_path": "art/square.jpg"})
        assert lossy["background_tolerance"] == 0.12, lossy["background_tolerance"]
        bbox = lossy["content_bbox"]
        # A one-pixel halo next to the edge is real codec output; the 16-row
        # chroma bleed above the sprite is not content.
        assert abs(bbox["x"] - 32) <= 1 and abs(bbox["y"] - 8) <= 1, bbox
        assert abs(bbox["w"] - 16) <= 2 and abs(bbox["h"] - 16) <= 2, bbox
        assert lossy["quadrants"]["top_right"] > 0.9, lossy["quadrants"]

        exact = dispatch(project, "inspect_image", {"image_path": "art/square.jpg", "background_tolerance": 0})
        assert exact["background_tolerance"] == 0, exact["background_tolerance"]
        assert exact["content_bbox"]["y"] == 0 and exact["content_bbox"]["h"] >= 24, exact["content_bbox"]

        lossless = dispatch(project, "inspect_image", {"image_path": "art/square.png"})
        assert lossless["background_tolerance"] == 0, lossless["background_tolerance"]
        assert lossless["content_bbox"] == {"x": 32, "y": 8, "w": 16, "h": 16}, lossless["content_bbox"]

        both = dispatch(project, "inspect_image", {
            "image_paths": ["art/square.png", "art/square.jpg"], "background_tolerance": 0.2})
        assert [entry["background_tolerance"] for entry in both["images"]] == [0.2, 0.2], both["images"]
        assert both["images"][1]["content_bbox"] == {"x": 32, "y": 8, "w": 16, "h": 16}, both["images"][1]["content_bbox"]

        bad = dispatch_raw(project, "inspect_image", {
            "image_path": "art/square.jpg", "background_tolerance": 3}, expected_returncode=1)
        assert "background_tolerance must be a number from 0" in bad.stderr, bad.stderr


def test_blank_image() -> None:
    """An all-black capture is the 'nothing rendered' case the whole feature
    exists to catch."""
    with fixture_project() as project:
        write_flat_png(project / "art/black.png", 32, 32, (0, 0, 0, 255))
        result = dispatch(project, "inspect_image", {"image_path": "art/black.png"})
        assert result["blank"] is True, result
        assert result["width"] == 32 and result["height"] == 32, result
        assert result["has_alpha"] is False, result
        assert result["opaque_ratio"] == 1.0, result
        assert result["unique_colors"] == 1, result
        assert result["content_bbox"] is None, result
        assert result["content_bbox_normalized"] is None, result
        assert result["mean_color"] == "#000000", result
        assert result["image_path"] == "res://art/black.png", result

        # A fully transparent canvas is blank too, and has no content box.
        write_flat_png(project / "art/empty.png", 16, 16, TRANSPARENT)
        empty = dispatch(project, "inspect_image", {"image_path": "art/empty.png"})
        assert empty["blank"] is True, empty
        assert empty["opaque_ratio"] == 0.0, empty
        assert empty["content_bbox"] is None, empty


def test_sprite_geometry_and_palette() -> None:
    """Where the sprite is, how big it is, and what colours it uses - read as
    numbers off a 16x16 red square at (32, 8) in a 64x64 transparent canvas."""
    with fixture_project() as project:
        write_square(project / "art/square.png")
        result = dispatch(project, "inspect_image", {"image_path": "art/square.png"})
        assert result["blank"] is False, result
        assert result["has_alpha"] is True, result
        assert result["opaque_ratio"] == 0.0625, result
        assert result["content_bbox"] == {"x": 32, "y": 8, "w": 16, "h": 16}, result
        assert result["content_bbox_normalized"] == {"x": 0.5, "y": 0.125, "w": 0.25, "h": 0.25}, result
        assert result["quadrants"]["top_right"] == 1.0, result
        assert result["quadrants"]["top_left"] == 0.0, result
        assert result["quadrants"]["bottom_left"] == 0.0, result
        assert result["quadrants"]["bottom_right"] == 0.0, result
        assert result["dominant_colors"][0]["hex"] == "#ff0000", result
        assert result["dominant_colors"][0]["ratio"] == 1.0, result
        assert result["unique_colors"] == 1, result
        assert result["mean_color"] == "#ff0000", result
        assert result["background_transparent"] is True, result
        assert result["sampled"] is False, result
        assert result["expect_results"] == [] and result["expect_passed"] is True, result


def test_ascii_rendering() -> None:
    with fixture_project() as project:
        write_square(project / "art/square.png")
        result = dispatch(project, "inspect_image", {
            "image_path": "art/square.png", "ascii": True, "ascii_color": True})
        rows = result["ascii"]
        # Character cells are ~2:1 tall, so 64 columns of a square image is 32 rows.
        assert len(rows) == 32, rows
        assert all(len(row) == 64 for row in rows), rows
        inked = [index for index, row in enumerate(rows) if row.strip()]
        assert inked == list(range(4, 12)), inked
        for index in inked:
            assert set(rows[index][32:48]) <= set("@#"), rows[index]
            assert rows[index][:32].strip() == "", rows[index]
            assert rows[index][48:].strip() == "", rows[index]
        for index in set(range(32)) - set(inked):
            assert rows[index] == " " * 64, (index, rows[index])

        colors = result["ascii_color"]
        assert len(colors) == 32, colors
        assert set(colors[4][32:48]) == {"R"}, colors[4]
        assert colors[0] == " " * 64, colors[0]

        # ascii_width drives the grid, and the aspect correction follows it.
        narrow = dispatch(project, "inspect_image", {
            "image_path": "art/square.png", "ascii": True, "ascii_width": 16})
        assert len(narrow["ascii"]) == 8, narrow["ascii"]
        assert all(len(row) == 16 for row in narrow["ascii"]), narrow["ascii"]
        assert "ascii_color" not in narrow, narrow


def test_compare_to() -> None:
    with fixture_project() as project:
        write_square(project / "art/square.png")
        write_square(project / "art/square_copy.png")
        write_square(project / "art/square_shifted.png", left=20)
        write_flat_png(project / "art/small.png", 32, 32, RED)

        same = dispatch(project, "inspect_image", {
            "image_path": "art/square.png", "compare_to": "art/square_copy.png"})
        assert same["diff_ratio"] == 0.0, same

        moved = dispatch(project, "inspect_image", {
            "image_path": "art/square.png", "compare_to": "art/square_shifted.png"})
        # 24 of 64 columns differ over the 16 rows of the square: 384 / 4096.
        assert moved["diff_ratio"] == 0.09375, moved

        # Comparing captures of different sizes is a mistake, not a measurement.
        mismatch = dispatch(project, "inspect_image", {
            "image_path": "art/square.png", "compare_to": "art/small.png"}, expected_returncode=1)
        assert "diff_ratio" not in mismatch, mismatch
        assert "32x32" in mismatch["diff_error"] and "64x64" in mismatch["diff_error"], mismatch


def test_expect_gates_exit_code() -> None:
    with fixture_project() as project:
        write_square(project / "art/square.png")
        write_square(project / "art/square_copy.png")
        write_flat_png(project / "art/black.png", 32, 32, (0, 0, 0, 255))

        passing = dispatch(project, "inspect_image", {
            "image_path": "art/square.png",
            "compare_to": "art/square_copy.png",
            "expect": {"not_blank": True, "min_opaque_ratio": 0.05, "max_unique_colors": 32,
                       "has_alpha": True, "width": 64, "height": 64, "max_diff_ratio": 0.01},
        })
        assert passing["expect_passed"] is True, passing
        assert [check["check"] for check in passing["expect_results"]] == [
            "not_blank", "min_opaque_ratio", "max_unique_colors", "has_alpha",
            "width", "height", "max_diff_ratio"], passing
        assert all(check["passed"] for check in passing["expect_results"]), passing

        failing = dispatch_raw(project, "inspect_image", {
            "image_path": "art/black.png",
            "expect": {"not_blank": True, "has_alpha": True, "width": 64},
        }, expected_returncode=1)
        assert "expect.not_blank failed" in failing.stderr, failing.stderr
        assert "expect.has_alpha failed" in failing.stderr, failing.stderr
        assert "expect.width failed" in failing.stderr, failing.stderr
        payload = last_json(failing)
        assert payload["expect_passed"] is False, payload
        assert [check["passed"] for check in payload["expect_results"]] == [False, False, False], payload

        # A blank image can also be the expectation.
        blank_ok = dispatch(project, "inspect_image", {
            "image_path": "art/black.png", "expect": {"not_blank": False}})
        assert blank_ok["expect_passed"] is True, blank_ok

        # max_diff_ratio without compare_to is a mistake, and says so.
        no_reference = dispatch_raw(project, "inspect_image", {
            "image_path": "art/square.png", "expect": {"max_diff_ratio": 0.1}}, expected_returncode=1)
        assert "pass compare_to" in no_reference.stderr, no_reference.stderr

        # An invented expect key is rejected with the list of real ones.
        unknown = dispatch_raw(project, "inspect_image", {
            "image_path": "art/square.png", "expect": {"is_pretty": True}}, expected_returncode=1)
        assert "Unknown inspect_image expect key: is_pretty" in unknown.stderr, unknown.stderr
        assert "not_blank" in unknown.stderr, unknown.stderr

        # Output keys must not be accepted as parameters.
        bad_param = dispatch_raw(project, "inspect_image", {
            "image_path": "art/square.png", "width": 64}, expected_returncode=1)
        assert "Unknown parameter for inspect_image: width" in bad_param.stderr, bad_param.stderr


def test_image_paths_mode() -> None:
    """A generated frame sequence: same canvas for every frame, read in one call."""
    with fixture_project() as project:
        for index, left in ((1, 0), (2, 2), (10, 4)):
            write_square(project / f"art/frames/frame_{index}.png", size=32, left=left, top=0, square=8)
        result = dispatch(project, "inspect_image", {"image_paths": ["art/frames"]})
        assert result["count"] == 3, result
        assert result["frames_consistent"] is True, result
        assert result["frame_size"] == {"width": 32, "height": 32}, result
        # Natural order: frame_10 sorts after frame_2, not between frame_1 and frame_2.
        assert [entry["image_path"].rsplit("/", 1)[-1] for entry in result["images"]] == [
            "frame_1.png", "frame_2.png", "frame_10.png"], result
        assert [entry["content_bbox"]["x"] for entry in result["images"]] == [0, 2, 4], result

        # An explicit list mixing a directory and a file works the same way.
        write_square(project / "art/odd.png", size=16, left=0, top=0, square=8)
        mixed = dispatch(project, "inspect_image", {
            "image_paths": ["art/frames", "art/odd.png"]}, expected_returncode=0)
        assert mixed["count"] == 4, mixed
        assert mixed["frames_consistent"] is False, mixed
        assert mixed["frame_size"] is None, mixed

        gated = dispatch_raw(project, "inspect_image", {
            "image_paths": ["art/frames", "art/odd.png"],
            "expect": {"frames_consistent": True}}, expected_returncode=1)
        assert "expect.frames_consistent failed" in gated.stderr, gated.stderr
        assert "odd.png 16x16" in gated.stderr, gated.stderr
        assert last_json(gated)["expect_passed"] is False, gated.stdout

        # Per-image expectations still run over every frame.
        per_frame = dispatch_raw(project, "inspect_image", {
            "image_paths": ["art/frames"], "expect": {"width": 16}}, expected_returncode=1)
        assert per_frame.stderr.count("expect.width failed") == 3, per_frame.stderr


def test_text_format() -> None:
    with fixture_project() as project:
        write_square(project / "art/square.png")
        result = dispatch_raw(project, "inspect_image", {
            "image_path": "art/square.png", "format": "text", "ascii": True, "ascii_width": 16})
        lines = [line for line in result.stdout.splitlines() if not line.startswith("[INFO]")]
        assert "image_path: res://art/square.png" in lines, lines
        assert "size: 64x64" in lines, lines
        assert "blank: false" in lines, lines
        assert "content_bbox: x=32 y=8 w=16 h=16 (normalized x=0.500 y=0.125 w=0.250 h=0.250)" in lines, lines
        assert "unique_colors: 1" in lines, lines
        assert "quadrants: top_left=0.0% top_right=100.0% bottom_left=0.0% bottom_right=0.0%" in lines, lines
        assert "ascii:" in lines, lines
        ascii_rows = lines[lines.index("ascii:") + 1:]
        assert len(ascii_rows) == 8, ascii_rows
        assert "@" in "".join(ascii_rows), ascii_rows
        assert not any(line.startswith("{") for line in lines), lines

        multi = dispatch_raw(project, "inspect_image", {
            "image_paths": ["art/square.png"], "format": "text"})
        assert "images: 1" in multi.stdout, multi.stdout
        assert "frames_consistent: true" in multi.stdout, multi.stdout


def test_large_image_samples_colors_but_not_the_bbox() -> None:
    """Colour statistics come off a downscaled copy, but the content box is
    measured on the full image - a one-pixel change must still be located."""
    with fixture_project() as project:
        write_flat_png(project / "art/big.png", 600, 400, (0x2A, 0x5C, 0x8E, 255),
                       dots=[(321, 222, (255, 255, 255, 255))])
        result = dispatch(project, "inspect_image", {"image_path": "art/big.png"})
        assert result["sampled"] is True, result
        assert result["sample_size"] == {"width": 256, "height": 171}, result
        assert result["content_bbox"] == {"x": 321, "y": 222, "w": 1, "h": 1}, result
        assert result["blank"] is False, result
        assert result["opaque_ratio"] == 1.0, result
        assert result["mean_color"] == "#2a5c8e", result
        # Dominant colours are quantised to 4 bits per channel: 0x2A5C8E -> 0x258.
        assert result["dominant_colors"][0]["hex"] == "#225588", result
        assert result["background_transparent"] is False, result


def test_input_errors() -> None:
    with fixture_project() as project:
        write_square(project / "art/square.png")
        missing = dispatch_raw(project, "inspect_image", {"image_path": "art/nope.png"}, expected_returncode=1)
        assert "Image file does not exist: res://art/nope.png" in missing.stderr, missing.stderr

        as_dir = dispatch_raw(project, "inspect_image", {"image_path": "art"}, expected_returncode=1)
        assert "is a directory" in as_dir.stderr and "image_paths" in as_dir.stderr, as_dir.stderr

        wrong_type = dispatch_raw(project, "inspect_image", {"image_path": "art/notes.txt"}, expected_returncode=1)
        assert "unsupported extension" in wrong_type.stderr, wrong_type.stderr
        assert "import artefact" not in wrong_type.stderr, wrong_type.stderr

        (project / "art/square.png-0123abcd.ctex").write_bytes(b"GST2")
        cache = dispatch_raw(project, "inspect_image", {
            "image_path": "art/square.png-0123abcd.ctex"}, expected_returncode=1)
        assert "import artefact" in cache.stderr and "res://.../name.png" in cache.stderr, cache.stderr

        no_path = dispatch_raw(project, "inspect_image", {"ascii": True}, expected_returncode=1)
        assert "requires image_path" in no_path.stderr, no_path.stderr

        empty_list = dispatch_raw(project, "inspect_image", {"image_paths": []}, expected_returncode=1)
        assert "image_paths is empty" in empty_list.stderr, empty_list.stderr

        bad_format = dispatch_raw(project, "inspect_image", {
            "image_path": "art/square.png", "format": "yaml"}, expected_returncode=1)
        assert 'format must be "json" or "text"' in bad_format.stderr, bad_format.stderr


# --- helpers ---------------------------------------------------------------

class fixture_project:
    def __enter__(self) -> Path:
        self.root = Path(tempfile.mkdtemp(prefix="godot-skill-inspect-image-"))
        self.project = self.root / "project"
        shutil.copytree(FIXTURE_ROOT, self.project)
        return self.project

    def __exit__(self, *_: object) -> None:
        shutil.rmtree(self.root, ignore_errors=True)


def _png(path: Path, width: int, height: int, raw: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)

    def chunk(tag: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data))

    header = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    path.write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header)
                     + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))


def write_flat_png(path: Path, width: int, height: int, color: tuple[int, int, int, int],
                   dots: list[tuple[int, int, tuple[int, int, int, int]]] | None = None) -> None:
    """One solid RGBA colour, optionally with individual pixels overwritten."""
    row = bytes(color) * width
    per_row: dict[int, list[tuple[int, tuple[int, int, int, int]]]] = {}
    for x, y, dot_color in dots or []:
        per_row.setdefault(y, []).append((x, dot_color))
    rows = []
    for y in range(height):
        if y in per_row:
            edited = bytearray(row)
            for x, dot_color in per_row[y]:
                edited[x * 4:x * 4 + 4] = bytes(dot_color)
            rows.append(bytes(edited))
        else:
            rows.append(row)
    _png(path, width, height, b"".join(b"\x00" + item for item in rows))


def write_square(path: Path, size: int = 64, left: int = 32, top: int = 8, square: int = 16,
                 color: tuple[int, int, int, int] = RED) -> None:
    """A transparent RGBA canvas with one opaque square - the shape every
    geometry assertion in this file is measured against."""
    empty_row = bytes(TRANSPARENT) * size
    filled_row = (bytes(TRANSPARENT) * left + bytes(color) * square
                  + bytes(TRANSPARENT) * (size - left - square))
    rows = [filled_row if top <= y < top + square else empty_row for y in range(size)]
    _png(path, size, size, b"".join(b"\x00" + item for item in rows))


def last_json(result: subprocess.CompletedProcess[str]) -> dict:
    for line in reversed(result.stdout.splitlines()):
        line = line.strip()
        if line.startswith("{") and line.endswith("}"):
            return json.loads(line)
    raise AssertionError(f"No JSON payload.\n{result.stdout}\n{result.stderr}")


def dispatch(project: Path, operation: str, params: dict, expected_returncode: int = 0) -> dict:
    return last_json(dispatch_raw(project, operation, params, expected_returncode))


def dispatch_raw(project: Path, operation: str, params: dict,
                 expected_returncode: int = 0) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(
        ["godot", "--headless", "--path", str(project), "--script", str(DISPATCHER),
         operation, json.dumps(params, separators=(",", ":"))],
        capture_output=True, text=True, check=False, timeout=120,
    )
    if result.returncode != expected_returncode:
        raise AssertionError(
            f"{operation} returned {result.returncode}, expected {expected_returncode}.\n{result.stdout}\n{result.stderr}")
    return result


if __name__ == "__main__":
    main()
