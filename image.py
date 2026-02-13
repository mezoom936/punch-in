import PIL
import os
from PIL import Image

input_folder = r"C:/Users/mizo2/sharepoint/oldimages"
output_folder = r"C:/Users/mizo2/sharepoint/newimages"

# Create output folder if it doesn't exist
os.makedirs(output_folder, exist_ok=True)

for filename in os.listdir(input_folder):
    if filename.lower().endswith((".png", ".jpg", ".jpeg", ".bmp", ".gif")):
        input_path = os.path.join(input_folder, filename)
        output_path = os.path.join(output_folder, filename)

        with Image.open(input_path) as img:
            resized_img = img.resize((294, 221))
            resized_img.save(output_path)

        print(f"Resized: {filename}")

print("All images resized.")