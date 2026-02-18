#!/usr/bin/env python3
"""Round corners of icon for macOS app"""
import sys
import subprocess

try:
    from PIL import Image, ImageDraw
except ImportError:
    print("Installing Pillow...")
    subprocess.check_call([sys.executable, "-m", "pip", "install", "--break-system-packages", "Pillow"])
    from PIL import Image, ImageDraw

def round_corners(image_path, output_path, radius_percent=22):
    """Add rounded corners to an image (macOS style)"""
    img = Image.open(image_path).convert("RGBA")
    
    # Create mask with rounded corners
    width, height = img.size
    radius = int(min(width, height) * radius_percent / 100)
    
    mask = Image.new('L', (width, height), 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle([(0, 0), (width, height)], radius=radius, fill=255)
    
    # Apply mask
    output = Image.new('RGBA', (width, height), (0, 0, 0, 0))
    output.paste(img, (0, 0))
    output.putalpha(mask)
    
    output.save(output_path, 'PNG')
    print(f"✓ Rounded corners applied: {output_path}")

if __name__ == "__main__":
    input_file = "/Volumes/Untitled/Auto staff Ai 2/AppIcons/appstore.png"
    output_file = "/Volumes/Untitled/Auto staff Ai 2/AppIcons/appstore-rounded.png"
    
    round_corners(input_file, output_file, radius_percent=22)
