#!/usr/bin/env python3
"""Create spritesheets from attack animation PNG files with JSON metadata."""

import hashlib
import json
import math
import subprocess
import sys
from pathlib import Path
from PIL import Image

FRAME_SIZE = 96

# Special case: gachachacha variants share many frames
GACHACHACHA_VARIANTS = ["gachachacha_bunnies", "gachachacha_carrots", "gachachacha_skulls"]

# Special case: files that need vertical flip applied to each frame
VERTICAL_FLIP_FILES = {"stat_boost_enemy"}

# Output files to exclude from input scanning
OUTPUT_FILES = {"attack_spritesheet.png"}


def find_valid_attack_pngs(directory: str) -> list[tuple[str, int, int]]:
    """Find all PNG files whose dimensions are evenly divisible by 96.

    Returns list of (path, cols, rows) tuples.
    """
    result = []
    for f in sorted(Path(directory).glob("*.png")):
        if f.name in OUTPUT_FILES:
            continue
        try:
            with Image.open(f) as img:
                w, h = img.size
                if w % FRAME_SIZE == 0 and h % FRAME_SIZE == 0:
                    cols = w // FRAME_SIZE
                    rows = h // FRAME_SIZE
                    result.append((str(f), cols, rows))
                else:
                    print(f"⚠ Skipping {f.name}: {w}x{h} not divisible by {FRAME_SIZE}")
        except Exception as e:
            print(f"Warning: Could not read {f}: {e}")
    return result


def extract_frames_from_spritesheet(
    png_path: str, cols: int, rows: int, vertical_flip: bool = False
) -> list[Image.Image]:
    """Extract all 96x96 frames from a spritesheet PNG (left-to-right, top-to-bottom)."""
    frames = []
    with Image.open(png_path) as img:
        img = img.convert('RGBA')
        for row in range(rows):
            for col in range(cols):
                x = col * FRAME_SIZE
                y = row * FRAME_SIZE
                frame = img.crop((x, y, x + FRAME_SIZE, y + FRAME_SIZE))
                if vertical_flip:
                    frame = frame.transpose(Image.FLIP_TOP_BOTTOM)
                frames.append(frame.copy())
    return frames


def frame_hash(frame: Image.Image) -> str:
    """Compute a hash for a frame to detect duplicates."""
    return hashlib.md5(frame.tobytes()).hexdigest()


def process_gachachacha_variants(
    variant_data: list[tuple[str, int, int]]
) -> tuple[list[Image.Image], dict[str, list[int]]]:
    """Process gachachacha variants, deduplicating shared frames.

    Returns:
        - List of unique frames (shared frames first, then unique frames per variant)
        - Dict mapping variant name to list of frame indices
    """
    # Extract frames from all variants
    variant_frames: dict[str, list[Image.Image]] = {}
    for png_path, cols, rows in variant_data:
        name = Path(png_path).stem
        variant_frames[name] = extract_frames_from_spritesheet(png_path, cols, rows)
        print(f"Extracted {len(variant_frames[name])} frames from {Path(png_path).name} ({cols}x{rows} grid)")

    # All variants should have same frame count
    frame_count = len(next(iter(variant_frames.values())))
    variant_names = list(variant_frames.keys())

    # Identify shared vs unique frames by comparing hashes
    unique_frames: list[Image.Image] = []
    frame_hash_to_index: dict[str, int] = {}
    variant_indices: dict[str, list[int]] = {name: [] for name in variant_names}

    for frame_idx in range(frame_count):
        # Get frames and hashes for this position across all variants
        frames_at_pos = [(name, variant_frames[name][frame_idx]) for name in variant_names]
        hashes_at_pos = [(name, frame_hash(frame)) for name, frame in frames_at_pos]

        # Check if all variants have the same frame at this position
        all_same = len(set(h for _, h in hashes_at_pos)) == 1

        if all_same:
            # Shared frame - use first variant's frame, reuse index for all
            h = hashes_at_pos[0][1]
            if h not in frame_hash_to_index:
                frame_hash_to_index[h] = len(unique_frames)
                unique_frames.append(frames_at_pos[0][1])
            idx = frame_hash_to_index[h]
            for name in variant_names:
                variant_indices[name].append(idx)
        else:
            # Different frames - add each variant's unique frame
            for name, frame in frames_at_pos:
                h = frame_hash(frame)
                if h not in frame_hash_to_index:
                    frame_hash_to_index[h] = len(unique_frames)
                    unique_frames.append(frame)
                variant_indices[name].append(frame_hash_to_index[h])

    total_original = frame_count * len(variant_names)
    print(f"  → Deduplicated: {total_original} frames -> {len(unique_frames)} unique frames")

    return unique_frames, variant_indices


def build_spritesheet(frames: list[Image.Image]) -> tuple[Image.Image, list[tuple[int, int]]]:
    """Create spritesheet image and return frame positions."""
    cols = math.ceil(math.sqrt(len(frames)))
    rows = math.ceil(len(frames) / cols)
    sheet = Image.new('RGBA', (cols * FRAME_SIZE, rows * FRAME_SIZE), (0, 0, 0, 0))
    positions = []
    for i, frame in enumerate(frames):
        x, y = (i % cols) * FRAME_SIZE, (i // cols) * FRAME_SIZE
        sheet.paste(frame, (x, y))
        positions.append((x, y))
    return sheet, positions


def run_oxipng(png_path: Path) -> None:
    """Run oxipng compression on a PNG file."""
    try:
        result = subprocess.run(
            ["oxipng", "-o", "6", "--strip", "safe", str(png_path)],
            capture_output=True,
            text=True,
            timeout=300
        )
        if result.returncode == 0:
            print(f"  ✓ Compressed with oxipng")
        else:
            print(f"  ⚠ oxipng warning (non-zero exit): {result.returncode}")
    except FileNotFoundError:
        print(f"  ⚠ oxipng not found, skipping compression")
    except subprocess.TimeoutExpired:
        print(f"  ⚠ oxipng timed out")
    except Exception as e:
        print(f"  ⚠ oxipng error: {e}")


def save_and_compress_png(sheet: Image.Image, path: Path, description: str) -> None:
    """Save a PNG and run oxipng compression on it."""
    sheet.save(path, "PNG")
    print(f"✅ {description} saved: {sheet.size[0]}x{sheet.size[1]} -> {path}")
    run_oxipng(path)


def compact_json(obj, indent=2):
    """JSON with objects indented but all arrays inline."""
    def format_value(v, level):
        if isinstance(v, dict):
            if not v:
                return '{}'
            items = []
            for k, val in v.items():
                items.append(' ' * (level + indent) + json.dumps(k) + ': ' + format_value(val, level + indent))
            return '{\n' + ',\n'.join(items) + '\n' + ' ' * level + '}'
        elif isinstance(v, list):
            return json.dumps(v)
        else:
            return json.dumps(v)
    return format_value(obj, 0)


def create_attack_spritesheets(png_files: list[tuple[str, int, int]], output_dir: str):
    """Create combined attack spritesheet with metadata."""
    metadata = {}
    all_frames = []

    # Separate gachachacha variants from regular files
    gachachacha_files = []
    regular_files = []
    for png_path, cols, rows in png_files:
        name = Path(png_path).stem
        if name in GACHACHACHA_VARIANTS:
            gachachacha_files.append((png_path, cols, rows))
        else:
            regular_files.append((png_path, cols, rows))

    # Process regular files
    for png_path, cols, rows in regular_files:
        name = Path(png_path).stem
        vertical_flip = name in VERTICAL_FLIP_FILES
        frames = extract_frames_from_spritesheet(png_path, cols, rows, vertical_flip)
        flip_note = " (flipped)" if vertical_flip else ""
        print(f"Extracted {len(frames)} frames from {Path(png_path).name} ({cols}x{rows} grid){flip_note}")

        frame_start = len(all_frames)
        all_frames.extend(frames)
        metadata[name] = {"_start": frame_start, "_count": len(frames)}

    # Process gachachacha variants with deduplication
    if gachachacha_files:
        print(f"\nProcessing gachachacha variants with deduplication...")
        gacha_frames, gacha_indices = process_gachachacha_variants(gachachacha_files)
        gacha_frame_start = len(all_frames)
        all_frames.extend(gacha_frames)

        # Store indices (will be converted to positions later)
        for name, indices in gacha_indices.items():
            metadata[name] = {"_gacha_start": gacha_frame_start, "_gacha_indices": indices}

    if not all_frames:
        print("No frames extracted!")
        return

    # Build combined spritesheet
    sheet, positions = build_spritesheet(all_frames)
    output_path = Path(output_dir)

    # Save to output directory
    sheet_path = output_path / "attack_spritesheet.png"
    save_and_compress_png(sheet, sheet_path, "Attack spritesheet")

    # Determine munch output location
    base_path = Path(__file__).parent
    game_dir = base_path.parent.parent
    munch_assets_dir = game_dir / "munch" / "src" / "assets" / "attacks"

    # Copy to munch if directory exists
    if munch_assets_dir.exists():
        print(f"\n📋 Copying to munch repository: {munch_assets_dir}")
        munch_sheet_path = munch_assets_dir / "attack_spritesheet.png"
        save_and_compress_png(sheet, munch_sheet_path, "Munch attack spritesheet")
    else:
        print(f"\n⚠ Munch directory not found, skipping copy: {munch_assets_dir}")

    # Finalize metadata - convert internal indices to actual positions
    for name, data in metadata.items():
        if "_start" in data:
            # Regular attack
            start, count = data.pop("_start"), data.pop("_count")
            data["msPerFrame"] = 100
            data["frames"] = [list(positions[start + i]) for i in range(count)]
        elif "_gacha_start" in data:
            # Gachachacha variant - use deduplicated indices
            gacha_start = data.pop("_gacha_start")
            indices = data.pop("_gacha_indices")
            data["msPerFrame"] = 100
            data["frames"] = [list(positions[gacha_start + idx]) for idx in indices]

    # Save JSON
    json_path = output_path / "attack_spritesheet.json"
    json_path.write_text(compact_json(metadata))
    print(f"✅ Metadata saved to: {json_path}")


def main():
    if len(sys.argv) < 2:
        print("Usage: python createAttackSpritesheets.py <target_directory>")
        sys.exit(1)

    target_dir = sys.argv[1]
    if not Path(target_dir).is_dir():
        print(f"Error: Directory '{target_dir}' does not exist")
        sys.exit(1)

    print(f"Searching for attack PNG files in: {target_dir}\n")
    png_files = find_valid_attack_pngs(target_dir)

    if not png_files:
        print("No valid attack PNG files found (dimensions must be divisible by 96)")
        sys.exit(1)

    print(f"\nFound {len(png_files)} valid PNG files:")
    for png_path, cols, rows in png_files:
        print(f"  - {Path(png_path).name} ({cols}x{rows} = {cols * rows} frames)")

    print("\n" + "=" * 50)
    create_attack_spritesheets(png_files, target_dir)
    print("\n✅ Done!")


if __name__ == "__main__":
    main()

