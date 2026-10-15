"""Export the project-authored SVG app mark to platform icon formats."""
from pathlib import Path
import xml.etree.ElementTree as ET

from PIL import Image, ImageDraw

root = Path(__file__).resolve().parents[1]
source = root / "upstream/assets/modern/app_mark.svg"
document = ET.parse(source).getroot()
rect, polygon = list(document)
scale = 4
image = Image.new("RGBA", (512 * scale, 512 * scale))
draw = ImageDraw.Draw(image)
draw.rounded_rectangle((0, 0, 512 * scale - 1, 512 * scale - 1), radius=int(rect.attrib["rx"]) * scale, fill=rect.attrib["fill"])
points = [tuple(int(value) * scale for value in pair.split(",")) for pair in polygon.attrib["points"].split()]
draw.polygon(points, fill=polygon.attrib["fill"])
image = image.resize((512, 512), Image.Resampling.LANCZOS)
image.save(root / "upstream/windows/runner/resources/modern_app_icon.ico", sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
image.save(root / "upstream/web/modern_app_icon.png")
square = Image.new("RGBA", image.size, rect.attrib["fill"])
square.alpha_composite(image)
square.save(root / "upstream/web/modern_app_maskable.png")
print("Exported app mark to native ICO and web PNG icons.")
