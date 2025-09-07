import os
import glob
from PIL import Image

def process_gif_folder(input_folder, output_folder):
    """
    Process all GIFs in a folder according to specifications:
    1. Extract first frame
    2. Turn all pixels to white with transparent background
    3. Add second frame with centered 10px circle
    """
    
    # Create output folder if it doesn't exist
    os.makedirs(output_folder, exist_ok=True)
    
    # Find all GIF files in the input folder
    gif_files = glob.glob(os.path.join(input_folder, "*.gif"))
    
    if not gif_files:
        print(f"No GIF files found in {input_folder}")
        return
    
    print(f"Found {len(gif_files)} GIF files to process")
    
    for gif_path in gif_files:
        try:
            process_single_gif(gif_path, output_folder)
        except Exception as e:
            print(f"Error processing {os.path.basename(gif_path)}: {e}")

def process_single_gif(gif_path, output_folder):
    """Process a single GIF file"""

    # Open the original GIF
    with Image.open(gif_path) as original_gif:
        # Extract the first frame
        first_frame = original_gif.copy()

        # Convert to RGBA to support transparency
        if first_frame.mode != 'RGBA':
            first_frame = first_frame.convert('RGBA')

        # Get dimensions
        width, height = first_frame.size

        # Skip files that are not 96x96
        if width != 96 or height != 96:
            return
        
        # Create frame 1: White pixels with transparent background
        frame1 = create_white_frame(first_frame)

        # Create morphing animation frames
        animation_frames = create_morphing_animation(frame1, width, height, num_frames=5)

        # Create output filenames
        input_filename = os.path.basename(gif_path)
        base_name = os.path.splitext(input_filename)[0]  # Remove .gif extension

        switch_out_filename = f"{base_name}_switch_out.gif"
        switch_in_filename = f"{base_name}_switch_in.gif"

        switch_out_path = os.path.join(output_folder, switch_out_filename)
        switch_in_path = os.path.join(output_folder, switch_in_filename)

        # Save forward animation (switch out: initial frame -> circle)
        frame1.save(
            switch_out_path,
            save_all=True,
            append_images=animation_frames,
            duration=100,  # 100ms per frame for smooth animation
            loop=0,  # Infinite loop
            disposal=2
        )

        # Save backward animation (switch in: circle -> initial frame)
        # Reverse the frame order
        reversed_frames = animation_frames[::-1]  # Reverse the list
        reversed_frames[-1].save(  # Start with the circle (last frame of forward animation)
            switch_in_path,
            save_all=True,
            append_images=reversed_frames[:-1],
            duration=100,  # 100ms per frame for smooth animation
            loop=0,  # Infinite loop
            disposal=2
        )

def create_white_frame(original_frame):
    """Convert frame to white pixels with transparent background"""

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

def create_diamond_frame(width, height):
    # Create transparent background
    diamond_frame = Image.new('RGBA', (width, height), (0, 0, 0, 0))

    # Calculate center position for diamond
    center_x = width // 2
    center_y = height // 2
    diamond_width = 8   # 8 pixels wide
    diamond_height = 14  # 14 pixels tall

    # Create diamond using pixel-by-pixel approach
    pixels = diamond_frame.load()

    for y in range(height):
        for x in range(width):
            # Calculate relative position from center
            dx = abs(x - center_x)
            dy = abs(y - center_y)

            # Diamond shape: |x|/half_width + |y|/half_height <= 1
            half_width = diamond_width / 2.0
            half_height = diamond_height / 2.0

            if dx / half_width + dy / half_height <= 1.0:
                pixels[x, y] = (255, 255, 255, 255)  # White, opaque

    return diamond_frame

def create_morphing_animation(start_frame, width, height, num_frames=6):
    """Create a morphing animation that moves and deforms pixels to final diamond"""
    import math
    import random

    frames = []
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

def main():
    # Configuration
    input_folder = "imgs"
    output_folder = "output_gifs"
    
    # Process all GIFs in the folder
    process_gif_folder(input_folder, output_folder)

if __name__ == "__main__":
    main()