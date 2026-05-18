from PIL import Image
import numpy as np

img = Image.open('/Users/mustafa700/Downloads/ChatGPT Image 17 мая 2026 г., 23_20_08.png').convert('RGB')
arr = np.array(img)
moon_region = arr[200:400, 500:750, :]
print(f"Max value in region near but not in moon (e.g. y=200:220): {moon_region[:20, :, :].max()}")
