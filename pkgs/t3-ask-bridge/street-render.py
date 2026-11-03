"""Bounded internal compositor. Geometry comes from street-map.mjs only."""
import base64
import io
import json
import sys
from PIL import Image, ImageDraw, ImageFont

Image.MAX_IMAGE_PIXELS = 65536
g = json.loads(sys.stdin.buffer.read(3_000_000))
assert g['width'] == 280 and g['height'] == 200 and len(g['tiles']) <= 6
image = Image.new('RGB', (280, 200), '#eeeeee')
for tile in g['tiles']:
    with Image.open(io.BytesIO(base64.b64decode(tile['png'], validate=True))) as source:
        assert source.size == (256, 256) and source.format == 'PNG'
        image.paste(source.convert('RGB'), (tile['dx'], tile['dy']))
draw = ImageDraw.Draw(image)
font = ImageFont.load_default(size=12)
draw.rectangle((0, 178, 280, 200), fill='white')
label = '© OpenStreetMap contributors'
draw.text((140, 181), label, font=font, fill='black', anchor='mt')
image.quantize(colors=16).save(sys.stdout.buffer, format='PNG')
