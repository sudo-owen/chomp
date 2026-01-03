#!/usr/bin/env python3
"""
Script to create spritesheets from 96x96 GIF files and generate JSON metadata.

This script:
1. Finds all 96x96 GIF files in a target directory
2. Extracts all frames from each GIF
3. Creates an optimized main spritesheet (spritesheet.png)
4. Generates morph animations for switch in/out effects
5. Creates a separate switch animation spritesheet (switch.png)
6. Generates a JSON file with frame positions for all animations
"""

import os
import sys
import json
import math
import random
import re
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


def extract_all_frames(gif_path: str) -> Tuple[List[Image.Image], int]:
    """
    Extract all frames from a GIF file.

    Returns:
        Tuple of (frames, frame_rate_ms) where frame_rate_ms is duration per frame in milliseconds
    """
    frames = []
    frame_rate_ms = 100  # Default to 100ms if not specified

    try:
        with Image.open(gif_path) as img:
            # Get frame duration from the first frame
            if 'duration' in img.info:
                frame_rate_ms = img.info['duration']

            # Iterate through all frames
            for frame_num in range(img.n_frames):
                img.seek(frame_num)
                # Convert to RGBA to preserve transparency
                frame = img.convert('RGBA')
                frames.append(frame.copy())
    except Exception as e:
        print(f"Error extracting frames from {gif_path}: {e}")

    return frames, frame_rate_ms


def calculate_optimal_grid(total_frames: int) -> Tuple[int, int]:
    """Calculate optimal grid dimensions (columns, rows) for the spritesheet."""
    # Try to make it as square as possible
    cols = math.ceil(math.sqrt(total_frames))
    rows = math.ceil(total_frames / cols)
    return cols, rows


def create_white_frame(original_frame: Image.Image) -> Image.Image:
    """Convert frame to white pixels with transparent background."""
    # Create a new RGBA image with transparent background
    width, height = original_frame.size
    white_frame = Image.new('RGBA', (width, height), (0, 0, 0, 0))

    # Get pixel data
    original_data = original_frame.getdata()
    new_data = []

    for pixel in original_data:
        # If pixel has alpha channel
        if len(pixel) == 4:
            a = pixel[3]  # Only need alpha channel
            # Keep transparent pixels transparent, make all others white
            if a == 0:  # Fully transparent
                new_data.append((0, 0, 0, 0))  # Keep transparent
            else:
                new_data.append((255, 255, 255, 255))  # Make white, opaque
        else:  # RGB mode - assume all GIFs have transparency, so convert to RGBA
            # All non-transparent pixels become white
            new_data.append((255, 255, 255, 255))  # White, opaque

    white_frame.putdata(new_data)
    return white_frame


def create_morphing_animation(start_frame: Image.Image, width: int, height: int, num_frames: int = 6, is_back: bool = False) -> List[Image.Image]:
    """Create a morphing animation that moves and deforms pixels to final diamond."""
    frames = []

    # For back sprites, shift diamond to lower left quadrant
    if is_back:
        center_x = width // 4  # 25% from left
        center_y = int(height * 0.65)  # 65% from top (lower portion)
    else:
        center_x = width // 2
        center_y = height // 2

    diamond_width = 8
    diamond_height = 14

    # Get all white pixels from the start frame
    start_pixels = start_frame.load()
    white_pixels = []

    for y in range(height):
        for x in range(width):
            if start_pixels[x, y][3] > 0:  # If pixel is not transparent
                white_pixels.append((x, y))

    # Calculate final diamond pixels
    final_diamond_pixels = []
    half_width = diamond_width / 2.0
    half_height = diamond_height / 2.0

    for y in range(height):
        for x in range(width):
            dx = abs(x - center_x)
            dy = abs(y - center_y)

            # Diamond shape: |x|/half_width + |y|/half_height <= 1
            if dx / half_width + dy / half_height <= 1.0:
                final_diamond_pixels.append((x, y))

    total_start_pixels = len(white_pixels)
    total_final_pixels = len(final_diamond_pixels)

    # Assign each starting pixel a target and movement pattern
    pixel_data = []
    for i, (start_x, start_y) in enumerate(white_pixels):
        # Assign target position in final diamond (some pixels won't have targets)
        if i < total_final_pixels:
            target_x, target_y = final_diamond_pixels[i]
        else:
            # Pixels that will disappear get targets near the diamond edge
            angle = random.uniform(0, 2 * math.pi)
            # Use diamond dimensions to calculate edge positions
            edge_distance = min(half_width, half_height) * 0.8
            target_x = center_x + int(edge_distance * math.cos(angle))
            target_y = center_y + int(edge_distance * math.sin(angle))

        # Add some randomness to movement path for organic feel
        control_x = (start_x + target_x) / 2 + random.uniform(-8, 8)
        control_y = (start_y + target_y) / 2 + random.uniform(-8, 8)

        pixel_data.append({
            'start': (start_x, start_y),
            'target': (target_x, target_y),
            'control': (control_x, control_y),
            'survives': i < total_final_pixels
        })

    for frame_idx in range(num_frames):
        # Create new frame
        frame = Image.new('RGBA', (width, height), (0, 0, 0, 0))
        frame_pixels = frame.load()

        # Calculate animation progress (0 to 1)
        progress = frame_idx / (num_frames - 1)

        # Add some easing for more organic movement
        eased_progress = 0.5 * (1 - math.cos(progress * math.pi))  # Smooth ease in/out

        # Calculate how many pixels should be visible
        visible_count = int(total_start_pixels * (1 - progress * 0.4) + total_final_pixels * progress * 0.4)
        visible_count = max(visible_count, total_final_pixels)

        # Add deformation effects
        deform_strength = math.sin(progress * math.pi) * 3  # Peak deformation in middle

        active_pixels = []

        for i, pixel_info in enumerate(pixel_data):
            start_x, start_y = pixel_info['start']
            target_x, target_y = pixel_info['target']
            control_x, control_y = pixel_info['control']

            # Quadratic bezier curve for smooth movement
            t = eased_progress
            current_x = (1-t)**2 * start_x + 2*(1-t)*t * control_x + t**2 * target_x
            current_y = (1-t)**2 * start_y + 2*(1-t)*t * control_y + t**2 * target_y

            # Add deformation (stretching/squeezing effect)
            dx_to_center = current_x - center_x
            dy_to_center = current_y - center_y
            distance_to_center = (dx_to_center**2 + dy_to_center**2)**0.5

            if distance_to_center > 0:
                # Add radial deformation
                deform_factor = 1 + deform_strength * math.sin(progress * 2 * math.pi) / distance_to_center
                current_x = center_x + dx_to_center * deform_factor
                current_y = center_y + dy_to_center * deform_factor

            # Round to pixel coordinates
            pixel_x = int(round(current_x))
            pixel_y = int(round(current_y))

            # Check if pixel should be visible
            should_survive = pixel_info['survives'] or i < visible_count

            if should_survive and 0 <= pixel_x < width and 0 <= pixel_y < height:
                active_pixels.append((pixel_x, pixel_y))

        # Draw pixels (handle overlaps by just overwriting)
        for x, y in active_pixels:
            frame_pixels[x, y] = (255, 255, 255, 255)

        frames.append(frame)

    return frames


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
    all_frames_data = []  # List of (filename, frame_image, frame_rate_ms)
    file_frame_rates = {}  # Store frame rate per file

    for gif_path in gif_files:
        filename = Path(gif_path).name
        frames, frame_rate_ms = extract_all_frames(gif_path)
        file_frame_rates[filename] = frame_rate_ms

        for frame in frames:
            all_frames_data.append((filename, frame))

        print(f"Extracted {len(frames)} frames from {filename} (frame rate: {frame_rate_ms}ms)")

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
    for idx, (filename, frame) in enumerate(all_frames_data):
        col = idx % cols
        row = idx // cols

        x = col * frame_size
        y = row * frame_size

        # Paste frame onto spritesheet
        spritesheet.paste(frame, (x, y))

        # Add to metadata
        if filename not in metadata:
            metadata[filename] = {
                "msPerFrame": file_frame_rates[filename],
                "frames": []
            }

        metadata[filename]["frames"].append([x, y])

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


def create_switch_spritesheet_and_metadata(
    gif_files: List[str],
    output_dir: str,
    frame_size: int = 96,
    num_morph_frames: int = 6
) -> Tuple[str, str]:
    """
    Create switch animation spritesheet and JSON metadata from GIF files.

    For each 96x96 GIF, generates a morph animation (forward pass only).
    The animation can be reversed in the spritesheet JSON as needed for switch in/out.

    Returns:
        Tuple of (spritesheet_path, json_path)
    """
    # Generate morph animations for all GIFs
    all_switch_frames_data = []  # List of (filename, frame_image)
    file_metadata = {}  # Store metadata per file

    for gif_path in gif_files:
        filename = Path(gif_path).name

        # Detect if this is a back sprite (contains "back" or "Back" in filename)
        is_back = "back" in filename.lower()

        # Extract first frame from GIF
        try:
            with Image.open(gif_path) as img:
                first_frame = img.copy()

                # Convert to RGBA to support transparency
                if first_frame.mode != 'RGBA':
                    first_frame = first_frame.convert('RGBA')

                # Create white frame
                white_frame = create_white_frame(first_frame)

                # Create morphing animation frames
                morph_frames = create_morphing_animation(
                    white_frame,
                    frame_size,
                    frame_size,
                    num_frames=num_morph_frames,
                    is_back=is_back
                )

                # Store all frames for this GIF
                frame_start_idx = len(all_switch_frames_data)
                for frame in morph_frames:
                    all_switch_frames_data.append((filename, frame))

                # Initialize metadata for this file
                # We'll populate the actual frame coordinates after placing them on the spritesheet
                file_metadata[filename] = {
                    "frame_start_idx": frame_start_idx,
                    "num_frames": len(morph_frames)
                }

                print(f"Generated {len(morph_frames)} switch frames for {filename}")

        except Exception as e:
            print(f"Error processing {filename}: {e}")
            continue

    total_frames = len(all_switch_frames_data)
    if total_frames == 0:
        raise ValueError("No switch frames generated from any GIF files")

    print(f"\nTotal switch frames to process: {total_frames}")

    # Calculate grid dimensions
    cols, rows = calculate_optimal_grid(total_frames)
    print(f"Grid dimensions: {cols} columns x {rows} rows")

    # Create spritesheet
    spritesheet_width = cols * frame_size
    spritesheet_height = rows * frame_size
    spritesheet = Image.new('RGBA', (spritesheet_width, spritesheet_height), (0, 0, 0, 0))

    # Place frames on spritesheet and record positions
    frame_positions = []  # Store all frame positions
    for idx, (filename, frame) in enumerate(all_switch_frames_data):
        col = idx % cols
        row = idx // cols

        x = col * frame_size
        y = row * frame_size

        # Paste frame onto spritesheet
        spritesheet.paste(frame, (x, y))

        # Record position
        frame_positions.append([x, y])

    # Build final metadata with switchIn and switchOut
    final_metadata = {}
    for filename, meta in file_metadata.items():
        start_idx = meta["frame_start_idx"]
        num_frames = meta["num_frames"]

        # Get frame coordinates for this file
        frames = frame_positions[start_idx:start_idx + num_frames]

        # switchOut: start with sprite, end with diamond (forward order)
        # switchIn: start with diamond, end with sprite (reverse order)
        final_metadata[filename] = {
            "switchOut": {
                "msPerFrame": 100,
                "frames": frames
            },
            "switchIn": {
                "msPerFrame": 100,
                "frames": list(reversed(frames))
            }
        }

    # Save spritesheet
    spritesheet_path = os.path.join(output_dir, "switch.png")
    spritesheet.save(spritesheet_path, "PNG")
    print(f"\n✅ Switch spritesheet saved to: {spritesheet_path}")
    print(f"   Dimensions: {spritesheet_width}x{spritesheet_height}")

    # Update the main spritesheet.json with switch animation data
    json_path = os.path.join(output_dir, "spritesheet.json")

    # Load existing metadata if it exists
    existing_metadata = {}
    if os.path.exists(json_path):
        with open(json_path, 'r') as f:
            existing_metadata = json.load(f)

    # Add switch animation data to existing metadata
    for filename, switch_data in final_metadata.items():
        if filename not in existing_metadata:
            existing_metadata[filename] = {}
        existing_metadata[filename]["switchIn"] = switch_data["switchIn"]
        existing_metadata[filename]["switchOut"] = switch_data["switchOut"]

    # Save updated metadata JSON with compact arrays
    with open(json_path, 'w') as f:
        json.dump(existing_metadata, f, indent=2, separators=(',', ': '))

    # Post-process to make arrays compact (no newlines within arrays)
    with open(json_path, 'r') as f:
        content = f.read()

    # Replace arrays that span multiple lines with compact single-line arrays
    # Match pattern: [\n      number,\n      number\n    ]
    content = re.sub(r'\[\s*\n\s*(\d+),\s*\n\s*(\d+)\s*\n\s*\]', r'[\1, \2]', content)

    with open(json_path, 'w') as f:
        f.write(content)

    print(f"✅ Switch metadata added to: {json_path}")

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

    # Create main spritesheet and metadata
    print("=" * 60)
    print("Creating main spritesheet...")
    print("=" * 60)
    create_spritesheet_and_metadata(gif_files, target_dir)

    # Create switch animation spritesheet and metadata
    print("\n" + "=" * 60)
    print("Creating switch animation spritesheet...")
    print("=" * 60)
    create_switch_spritesheet_and_metadata(gif_files, target_dir)

    print("\n✅ Done!")


if __name__ == "__main__":
    main()
