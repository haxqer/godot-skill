#!/usr/bin/env python3
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

try:
    import numpy as np
    from PIL import Image
except ImportError as exc:  # pragma: no cover - exercised through CLI
    print(
        "Missing dependency: create a virtualenv and install Pillow and NumPy, for example:\n"
        "python3 -m venv .godot-skill-venv\n"
        ". .godot-skill-venv/bin/activate\n"
        "python -m pip install pillow numpy",
        file=sys.stderr,
    )
    raise SystemExit(1) from exc


SUPPORTED_SUFFIXES = {".png", ".webp", ".jpg", ".jpeg"}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Remove a flat chroma-key background from one image or a directory of frames "
            "and write RGBA PNG outputs."
        )
    )
    parser.add_argument("--input", required=True, help="Input image file or directory of frames.")
    parser.add_argument("--output", help="Output path for a single input image.")
    parser.add_argument("--output-dir", help="Output directory for directory input.")
    parser.add_argument(
        "--bg-color",
        default="auto",
        help="Background color hex (for example ff00ff) or `auto` to sample image corners.",
    )
    parser.add_argument(
        "--tolerance",
        type=float,
        default=12.0,
        help="Euclidean RGB distance treated as definite background.",
    )
    parser.add_argument(
        "--feather",
        type=float,
        default=10.0,
        help="Additional RGB distance range used for soft alpha edges.",
    )
    crop_group = parser.add_mutually_exclusive_group()
    crop_group.add_argument(
        "--keep-canvas",
        dest="keep_canvas",
        action="store_true",
        help="Preserve the original canvas size. This is the default behavior.",
    )
    crop_group.add_argument(
        "--tight-crop",
        dest="keep_canvas",
        action="store_false",
        help="Crop output to the non-transparent bounds after cutout.",
    )
    parser.set_defaults(keep_canvas=True)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    input_path = Path(args.input).expanduser().resolve()
    if not input_path.exists():
        raise SystemExit(f"Input path does not exist: {input_path}")

    if input_path.is_dir():
        if args.output:
            raise SystemExit("--output is only valid for a single input image.")
        output_dir = Path(args.output_dir).expanduser().resolve() if args.output_dir else input_path / "cutout"
        output_dir.mkdir(parents=True, exist_ok=True)
        outputs = process_directory(
            input_path=input_path,
            output_dir=output_dir,
            bg_color_spec=args.bg_color,
            tolerance=args.tolerance,
            feather=args.feather,
            keep_canvas=args.keep_canvas,
        )
    else:
        if args.output_dir:
            raise SystemExit("--output-dir is only valid for directory input.")
        output_path = (
            Path(args.output).expanduser().resolve()
            if args.output
            else input_path.with_name(f"{input_path.stem}-cutout.png")
        )
        outputs = [
            process_image(
                input_path=input_path,
                output_path=output_path,
                bg_color_spec=args.bg_color,
                tolerance=args.tolerance,
                feather=args.feather,
                keep_canvas=args.keep_canvas,
            )
        ]

    for output in outputs:
        print(output)


def process_directory(
    *,
    input_path: Path,
    output_dir: Path,
    bg_color_spec: str,
    tolerance: float,
    feather: float,
    keep_canvas: bool,
) -> list[Path]:
    outputs: list[Path] = []
    frame_paths = sorted(
        (
            path
            for path in input_path.iterdir()
            if path.is_file() and path.suffix.lower() in SUPPORTED_SUFFIXES
        ),
        key=natural_sort_key,
    )
    if not frame_paths:
        raise SystemExit(f"No supported image files found in {input_path}")

    resolved_bg_color = sample_bg_color_from_path(frame_paths[0]) if bg_color_spec.lower() == "auto" else None
    for frame_path in frame_paths:
        output_path = output_dir / f"{frame_path.stem}.png"
        outputs.append(
            process_image(
                input_path=frame_path,
                output_path=output_path,
                bg_color_spec=bg_color_spec,
                resolved_bg_color=resolved_bg_color,
                tolerance=tolerance,
                feather=feather,
                keep_canvas=keep_canvas,
            )
        )
    return outputs


def process_image(
    *,
    input_path: Path,
    output_path: Path,
    bg_color_spec: str,
    resolved_bg_color: np.ndarray | None = None,
    tolerance: float,
    feather: float,
    keep_canvas: bool,
) -> Path:
    image = Image.open(input_path).convert("RGBA")
    rgba = np.array(image, dtype=np.uint8)
    bg_color = resolved_bg_color if resolved_bg_color is not None else resolve_bg_color(rgba, bg_color_spec)
    result = apply_cutout(rgba, bg_color=bg_color, tolerance=tolerance, feather=feather)

    output_image = Image.fromarray(result, mode="RGBA")
    if not keep_canvas:
        bbox = output_image.getbbox()
        output_image = output_image.crop(bbox) if bbox else Image.new("RGBA", (1, 1), (0, 0, 0, 0))

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_image.save(output_path, format="PNG")
    return output_path.resolve()


def resolve_bg_color(rgba: np.ndarray, bg_color_spec: str) -> np.ndarray:
    if bg_color_spec.lower() == "auto":
        return sample_corner_color(rgba)
    return np.array(parse_hex_color(bg_color_spec), dtype=np.float32)

def sample_bg_color_from_path(input_path: Path) -> np.ndarray:
    image = Image.open(input_path).convert("RGBA")
    rgba = np.array(image, dtype=np.uint8)
    return sample_corner_color(rgba)


def sample_corner_color(rgba: np.ndarray) -> np.ndarray:
    height, width = rgba.shape[:2]
    corners = np.array(
        [
            rgba[0, 0, :3],
            rgba[0, width - 1, :3],
            rgba[height - 1, 0, :3],
            rgba[height - 1, width - 1, :3],
        ],
        dtype=np.float32,
    )
    return corners.mean(axis=0)


def parse_hex_color(raw_value: str) -> tuple[int, int, int]:
    value = raw_value.strip().lower()
    if value.startswith("#"):
        value = value[1:]
    if len(value) != 6 or any(char not in "0123456789abcdef" for char in value):
        raise SystemExit(f"Invalid --bg-color value: {raw_value}")
    return tuple(int(value[index : index + 2], 16) for index in (0, 2, 4))


def natural_sort_key(path: Path) -> tuple[tuple[int, object, int], ...]:
    parts: list[tuple[int, object, int]] = []
    for chunk in re.findall(r"\d+|\D+", path.name.lower()):
        if chunk.isdigit():
            parts.append((0, int(chunk), len(chunk)))
        else:
            parts.append((1, chunk, len(chunk)))
    return tuple(parts)


def apply_cutout(
    rgba: np.ndarray,
    *,
    bg_color: np.ndarray,
    tolerance: float,
    feather: float,
) -> np.ndarray:
    rgb = rgba[..., :3].astype(np.float32)
    alpha = rgba[..., 3].astype(np.float32)

    distances = np.linalg.norm(rgb - bg_color.reshape((1, 1, 3)), axis=2)
    if feather <= 0:
        factor = np.where(distances <= tolerance, 0.0, 1.0)
    else:
        factor = np.clip((distances - tolerance) / feather, 0.0, 1.0)

    rgba[..., 3] = np.clip(alpha * factor, 0, 255).astype(np.uint8)
    return rgba


if __name__ == "__main__":
    main()
