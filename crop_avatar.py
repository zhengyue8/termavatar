#!/usr/bin/env python3
"""Crop an image to a circle with transparent background."""

import sys
from PIL import Image, ImageDraw

def crop_circle(input_path, output_path, size=512):
    img = Image.open(input_path).convert("RGBA")

    # Center-crop to square
    w, h = img.size
    side = min(w, h)
    left = (w - side) // 2
    top = (h - side) // 2
    img = img.crop((left, top, left + side, top + side))

    # Resize
    img = img.resize((size, size), Image.LANCZOS)

    # Apply circular mask
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).ellipse((0, 0, size, size), fill=255)
    img.putalpha(mask)

    img.save(output_path, "PNG")

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: crop_avatar.py <input> <output> [size]", file=sys.stderr)
        sys.exit(1)

    input_path = sys.argv[1]
    output_path = sys.argv[2]
    size = int(sys.argv[3]) if len(sys.argv) > 3 else 512

    try:
        crop_circle(input_path, output_path, size)
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)
