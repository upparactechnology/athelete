import os
from PIL import Image

def crop_image(image_path):
    if not os.path.exists(image_path):
        print(f"File {image_path} does not exist")
        return
    
    try:
        img = Image.open(image_path)
        if img.mode != 'RGBA':
            img = img.convert('RGBA')
        
        # Get the bounding box of non-zero (non-transparent) areas in the image
        bbox = img.getbbox()
        if bbox:
            cropped_img = img.crop(bbox)
            cropped_img.save(image_path)
            print(f"Successfully cropped {image_path} from {img.size} to {cropped_img.size}")
        else:
            print(f"No non-transparent bounding box found for {image_path}")
    except Exception as e:
        print(f"Error processing {image_path}: {e}")

logos_dir = r"c:\xampp\htdocs\athelete\logos"
for logo_file in ["dark.png", "logo-name.png", "logo.png", "name.png"]:
    crop_image(os.path.join(logos_dir, logo_file))
