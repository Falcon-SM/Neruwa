#!/usr/bin/env python3
"""Prepare lightweight iOS assets from the hand-drawn Neruwa chick."""

from __future__ import annotations

import argparse
import math
import random
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageOps


def remove_connected_white_fringe(image: Image.Image) -> Image.Image:
    """Remove only pale pixels connected to the transparent outer background."""
    image = image.convert("RGBA")
    red, green, blue, alpha = image.split()

    minimum = ImageChops.darker(ImageChops.darker(red, green), blue)
    maximum = ImageChops.lighter(ImageChops.lighter(red, green), blue)
    chroma = ImageChops.subtract(maximum, minimum)

    bright = minimum.point(lambda value: 255 if value >= 205 else 0)
    neutral = chroma.point(lambda value: 255 if value <= 52 else 0)
    pale_candidate = ImageChops.multiply(bright, neutral)
    transparent = alpha.point(lambda value: 255 if value <= 8 else 0)

    connectivity = ImageChops.lighter(transparent, pale_candidate)
    padded = ImageOps.expand(connectivity, border=1, fill=255)
    ImageDraw.floodfill(padded, (0, 0), 128, thresh=0)
    connected_to_outside = padded.crop(
        (1, 1, padded.width - 1, padded.height - 1)
    ).point(lambda value: 255 if value == 128 else 0)

    cleaned_alpha = ImageChops.subtract(alpha, connected_to_outside)
    cleaned_alpha = cleaned_alpha.point(lambda value: 0 if value < 10 else value)
    return Image.merge("RGBA", (red, green, blue, cleaned_alpha))


def alpha_bounds(image: Image.Image) -> tuple[int, int, int, int]:
    alpha = image.getchannel("A")
    bounds = alpha.getbbox()
    if bounds is None:
        raise ValueError("The rendered mascot has no visible alpha content.")
    return bounds


def fitted_mascot(render: Image.Image, size: int, padding: int) -> Image.Image:
    render = render.convert("RGBA")
    cropped = render.crop(alpha_bounds(render))
    max_side = size - padding * 2
    scale = min(max_side / cropped.width, max_side / cropped.height)
    target = (
        max(1, round(cropped.width * scale)),
        max(1, round(cropped.height * scale)),
    )
    return cropped.resize(target, Image.Resampling.LANCZOS)


def midnight_background(size: int) -> Image.Image:
    top = (7, 13, 45)
    bottom = (31, 39, 105)
    background = Image.new("RGB", (size, size))
    pixels = background.load()
    for y in range(size):
        t = y / max(1, size - 1)
        eased = 0.5 - math.cos(math.pi * t) / 2
        color = tuple(round(a + (b - a) * eased) for a, b in zip(top, bottom))
        for x in range(size):
            pixels[x, y] = color

    draw = ImageDraw.Draw(background, "RGBA")
    random.seed(365)
    for _ in range(38):
        x = random.randint(45, size - 45)
        y = random.randint(40, size - 60)
        radius = random.choice((1, 1, 2, 2, 3))
        opacity = random.randint(90, 205)
        draw.ellipse(
            (x - radius, y - radius, x + radius, y + radius),
            fill=(255, 232, 151, opacity),
        )
    return background


def compose_assets(render_path: Path, output_dir: Path) -> None:
    output_dir.mkdir(parents=True, exist_ok=True)
    render = remove_connected_white_fringe(Image.open(render_path))

    prompt_canvas = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
    prompt_mascot = fitted_mascot(render, 1024, 70)
    prompt_position = (
        (1024 - prompt_mascot.width) // 2,
        (1024 - prompt_mascot.height) // 2,
    )
    prompt_canvas.alpha_composite(prompt_mascot, prompt_position)
    prompt_canvas.save(output_dir / "ChickMascot.png", optimize=True)

    icon = midnight_background(1024).convert("RGBA")
    icon_mascot = fitted_mascot(render, 1024, 54)
    icon_position = (
        (1024 - icon_mascot.width) // 2,
        1024 - icon_mascot.height + 18,
    )
    shadow = Image.new("RGBA", icon.size, (0, 0, 0, 0))
    shadow_shape = Image.new("RGBA", icon_mascot.size, (0, 0, 0, 0))
    shadow_shape.putalpha(icon_mascot.getchannel("A"))
    shadow_shape = shadow_shape.filter(ImageFilter.GaussianBlur(24))
    shadow.alpha_composite(shadow_shape, (icon_position[0] + 2, icon_position[1] + 22))
    shadow.putalpha(shadow.getchannel("A").point(lambda value: round(value * 0.32)))
    icon.alpha_composite(shadow)
    icon.alpha_composite(icon_mascot, icon_position)
    icon.convert("RGB").save(output_dir / "AppIcon.png", optimize=True)


def main() -> None:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)
    compose = subparsers.add_parser("compose")
    compose.add_argument("render", type=Path)
    compose.add_argument("output_dir", type=Path)
    args = parser.parse_args()
    compose_assets(args.render, args.output_dir)


if __name__ == "__main__":
    main()
