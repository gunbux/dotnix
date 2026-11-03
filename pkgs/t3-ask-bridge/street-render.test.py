import base64
import io
import json
import subprocess
import sys
from PIL import Image

source = Image.new('RGB', (256, 256), 'red')
# Asymmetric stripe proves crop translation rather than just dimensions.
source.paste('blue', (80, 0, 100, 256))
buf = io.BytesIO()
source.save(buf, format='PNG')
data = {'width': 280, 'height': 200, 'tiles': [
    {'dx': -30, 'dy': 0, 'png': base64.b64encode(buf.getvalue()).decode()}]}
out = subprocess.check_output([sys.executable, 'street-render.py'], input=json.dumps(data).encode())
image = Image.open(io.BytesIO(out)).convert('RGB')
assert image.size == (280, 200)
assert image.getpixel((55, 50)) == (0, 0, 255)
assert image.getpixel((20, 50)) == (255, 0, 0)
assert image.getpixel((279, 50)) == (238, 238, 238)
assert image.getpixel((0, 190)) == (255, 255, 255)
assert any(image.getpixel((x, y)) != (255, 255, 255) for x in range(40, 240) for y in range(182, 198))
print('renderer dimensions, crop translation and visible attribution: passed')
