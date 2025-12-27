#!/usr/bin/env python3
"""
Script to create a spritesheet from 96x96 GIF files and generate JSON metadata.

This script:
1. Finds all 96x96 GIF files in a target directory
2. Extracts all frames from each GIF
3. Creates an optimized spritesheet
4. Generates a JSON file with frame positions for each file
"""

import os
import sys
import json
import math
from pathlib import Path
from PIL import Image
from typing import List, Tuple


def find_96x96_gifs(directory: str) -> List[str]:
    """Find all 96x96 GIF files in the target directory."""
    gif_files = []

    for file in sorted(Path(directory).glob("*.gif")):
        try:
            with Image.open(file) as img:
                if img.size == (96, 96):
                    gif_files.append(str(file))
        except Exception as e:
            print(f"Warning: Could not read {file}: {e}")

    return gif_files


def extract_all_frames(gif_path: str) -> List[Image.Image]:
    """Extract all frames from a GIF file."""
    frames = []

    try:
        with Image.open(gif_path) as img:
            # Iterate through all frames
            for frame_num in range(img.n_frames):
                img.seek(frame_num)
                # Convert to RGBA to preserve transparency
                frame = img.convert('RGBA')
                frames.append(frame.copy())
    except Exception as e:
        print(f"Error extracting frames from {gif_path}: {e}")

    return frames


def calculate_optimal_grid(total_frames: int) -> Tuple[int, int]:
    """Calculate optimal grid dimensions (columns, rows) for the spritesheet."""
    # Try to make it as square as possible
    cols = math.ceil(math.sqrt(total_frames))
    rows = math.ceil(total_frames / cols)
    return cols, rows


def create_spritesheet_and_metadata(
    gif_files: List[str],
    output_dir: str,
    frame_size: int = 96
) -> Tuple[str, str]:
    """
    Create spritesheet and JSON metadata from GIF files.

    Returns:
        Tuple of (spritesheet_path, json_path)
    """
    # Extract all frames from all GIFs
    all_frames_data = []  # List of (filename, frame_index, frame_image)

    for gif_path in gif_files:
        filename = Path(gif_path).name
        frames = extract_all_frames(gif_path)

        for frame_idx, frame in enumerate(frames):
            all_frames_data.append((filename, frame_idx, frame))

        print(f"Extracted {len(frames)} frames from {filename}")

    total_frames = len(all_frames_data)
    if total_frames == 0:
        raise ValueError("No frames extracted from any GIF files")

    print(f"\nTotal frames to process: {total_frames}")

    # Calculate grid dimensions
    cols, rows = calculate_optimal_grid(total_frames)
    print(f"Grid dimensions: {cols} columns x {rows} rows")

    # Create spritesheet
    spritesheet_width = cols * frame_size
    spritesheet_height = rows * frame_size
    spritesheet = Image.new('RGBA', (spritesheet_width, spritesheet_height), (0, 0, 0, 0))

    # Build metadata structure
    metadata = {}

    # Place frames on spritesheet and record positions
    for idx, (filename, frame_idx, frame) in enumerate(all_frames_data):
        col = idx % cols
        row = idx // cols

        x = col * frame_size
        y = row * frame_size

        # Paste frame onto spritesheet
        spritesheet.paste(frame, (x, y))

        # Add to metadata
        if filename not in metadata:
            metadata[filename] = []

        metadata[filename].append({
            "frame": frame_idx,
            "x": x,
            "y": y
        })

    # Save spritesheet
    spritesheet_path = os.path.join(output_dir, "spritesheet.png")
    spritesheet.save(spritesheet_path, "PNG")
    print(f"\n✅ Spritesheet saved to: {spritesheet_path}")
    print(f"   Dimensions: {spritesheet_width}x{spritesheet_height}")

    # Save metadata JSON
    json_path = os.path.join(output_dir, "spritesheet.json")
    with open(json_path, 'w') as f:
        json.dump(metadata, f, indent=2)
    print(f"✅ Metadata saved to: {json_path}")

    return spritesheet_path, json_path


def main():
    """Main function to orchestrate spritesheet generation."""
    if len(sys.argv) < 2:
        print("Usage: python spritesheet.py <target_directory>")
        print("\nExample: python spritesheet.py drool/imgs")
        sys.exit(1)

    target_dir = sys.argv[1]

    if not os.path.isdir(target_dir):
        print(f"Error: Directory '{target_dir}' does not exist")
        sys.exit(1)

    print(f"Searching for 96x96 GIF files in: {target_dir}\n")

    # Find all 96x96 GIFs
    gif_files = find_96x96_gifs(target_dir)

    if not gif_files:
        print("No 96x96 GIF files found in the target directory")
        sys.exit(1)

    print(f"Found {len(gif_files)} GIF files:\n")
    for gif in gif_files:
        print(f"  - {Path(gif).name}")
    print()

    # Create spritesheet and metadata
    create_spritesheet_and_metadata(gif_files, target_dir)

    print("\n✅ Done!")


if __name__ == "__main__":
    main()
