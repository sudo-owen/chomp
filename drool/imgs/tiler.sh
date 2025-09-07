#!/bin/bash

# GIF Frame Tiler Script
# Extracts first frame from each GIF and tiles them preserving original sizes
# 32x32 images stay 32x32, 96x96 images stay 96x96 (no upscaling)

# Configuration
GIF_FOLDER="${1:-.}"  # Use provided folder or current directory
OUTPUT_FILE="tiled_frames.png"
TEMP_DIR=$(mktemp -d)
MAX_SIZE="96"  # Maximum dimension - don't upscale beyond this

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}GIF Frame Tiler Script${NC}"
echo "Processing GIFs in: $GIF_FOLDER"
echo "Temporary directory: $TEMP_DIR"
echo

# Check if ImageMagick is installed
if ! command -v convert &> /dev/null; then
    echo -e "${RED}Error: ImageMagick is not installed. Please install it first.${NC}"
    echo "Ubuntu/Debian: sudo apt-get install imagemagick"
    echo "macOS: brew install imagemagick"
    echo "CentOS/RHEL: sudo yum install ImageMagick"
    exit 1
fi

# Check if the directory exists
if [ ! -d "$GIF_FOLDER" ]; then
    echo -e "${RED}Error: Directory '$GIF_FOLDER' does not exist.${NC}"
    exit 1
fi

# Find all GIF files
gif_files=("$GIF_FOLDER"/*.gif)

# Check if any GIF files exist
if [ ${#gif_files[@]} -eq 0 ] || [ ! -f "${gif_files[0]}" ]; then
    echo -e "${RED}Error: No GIF files found in '$GIF_FOLDER'.${NC}"
    rmdir "$TEMP_DIR" 2>/dev/null
    exit 1
fi

echo "Found ${#gif_files[@]} GIF files"

# Extract first frame from each GIF
counter=0
successful_extractions=0

for gif_file in "${gif_files[@]}"; do
    if [ -f "$gif_file" ]; then
        filename=$(basename "$gif_file" .gif)
        counter=$((counter + 1))
        output_frame="$TEMP_DIR/frame_$(printf "%04d" $counter).png"

        echo "Processing: $filename"

        # Extract first frame, preserving size (don't upscale small images)
        if convert "$gif_file[0]" -resize "${MAX_SIZE}x${MAX_SIZE}>" "$output_frame" 2>/dev/null; then
            successful_extractions=$((successful_extractions + 1))

            # Get and display the size of the extracted frame
            if command -v identify &> /dev/null; then
                size=$(identify -format "%wx%h" "$output_frame")
                echo "  → Extracted frame: ${size}"
            fi
        else
            echo -e "${RED}Warning: Failed to process $filename${NC}"
        fi
    fi
done

if [ $successful_extractions -eq 0 ]; then
    echo -e "${RED}Error: No frames were successfully extracted.${NC}"
    rm -rf "$TEMP_DIR"
    exit 1
fi

echo -e "${GREEN}Successfully extracted $successful_extractions frames${NC}"

# Calculate grid dimensions for square-like arrangement
total_images=$successful_extractions
cols=$(echo "sqrt($total_images)" | bc -l | cut -d. -f1)
cols=$((cols + 1))  # Round up
rows=$(((total_images + cols - 1) / cols))  # Ceiling division

echo "Creating ${cols}x${rows} grid"

# Create the tiled image with mixed sizes
echo "Creating tiled output with preserved image sizes..."
if montage "$TEMP_DIR"/frame_*.png -tile "${cols}x${rows}" -geometry "+4+4" -background white "$OUTPUT_FILE"; then
    echo -e "${GREEN}Success! Tiled image saved as: $OUTPUT_FILE${NC}"

    # Get output image dimensions
    if command -v identify &> /dev/null; then
        dimensions=$(identify -format "%wx%h" "$OUTPUT_FILE")
        echo "Output dimensions: $dimensions"
    fi
else
    echo -e "${RED}Error: Failed to create tiled image.${NC}"
    rm -rf "$TEMP_DIR"
    exit 1
fi

# Cleanup
rm -rf "$TEMP_DIR"
echo "Cleaned up temporary files"

echo -e "${GREEN}Done!${NC}"

# Display summary
echo
echo "Summary:"
echo "- Processed: $counter GIF files"
echo "- Successfully extracted: $successful_extractions frames"
echo "- Grid arrangement: ${cols}x${rows}"
echo "- Output file: $OUTPUT_FILE"
