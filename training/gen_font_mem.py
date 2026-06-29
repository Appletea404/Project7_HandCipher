"""
16x16 ASCII font bitmap generator for VGA font_rom.mem.

Output: training/exported/font_rom.mem

Format: 2048 lines, each line is 4 hex digits.
  - ASCII 0~31  : control chars -> 16 rows of 0000
  - ASCII 32~127: rendered 16x16 bitmap
  - addr formula: addr = char_code * 16 + row_in_char
  - bit order   : bit15 = leftmost pixel, bit0 = rightmost pixel
"""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

FONT_PATH = "/usr/share/fonts/truetype/ubuntu/UbuntuMono-R.ttf"
FONT_SIZE = 16
GLYPH_W = 16
GLYPH_H = 16
OUT_PATH = Path(__file__).parent / "exported/font_rom.mem"


def load_font() -> ImageFont.FreeTypeFont:
    """Load the monospace font used for VGA text rendering."""
    return ImageFont.truetype(FONT_PATH, FONT_SIZE)


def render_char(font: ImageFont.FreeTypeFont, code: int) -> list[int]:
    """Render one ASCII code into sixteen 16-bit bitmap rows."""
    ch = chr(code)
    img = Image.new("L", (GLYPH_W, GLYPH_H), 0)
    draw = ImageDraw.Draw(img)

    # textbbox may have negative offsets depending on the font. Use it to center
    # the visible glyph inside the 16x16 cell instead of assuming (0, 0).
    bbox = draw.textbbox((0, 0), ch, font=font)
    text_w = bbox[2] - bbox[0]
    text_h = bbox[3] - bbox[1]
    x = (GLYPH_W - text_w) // 2 - bbox[0]
    y = (GLYPH_H - text_h) // 2 - bbox[1]

    draw.text((x, y), ch, fill=255, font=font)

    rows: list[int] = []
    for row in range(GLYPH_H):
        bits = 0
        for col in range(GLYPH_W):
            if img.getpixel((col, row)) > 127:
                bits |= 1 << (15 - col)
        rows.append(bits)
    return rows


def main() -> None:
    font = load_font()

    lines: list[str] = []
    for code in range(128):
        if code < 32:
            rows = [0] * GLYPH_H
        else:
            rows = render_char(font, code)

        for row_bits in rows:
            lines.append(f"{row_bits:04x}")

    expected = 128 * GLYPH_H
    assert len(lines) == expected, f"expected {expected} lines, got {len(lines)}"

    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    OUT_PATH.write_text("\n".join(lines) + "\n")
    print(f"generated: {OUT_PATH} ({len(lines)} lines, {GLYPH_W}x{GLYPH_H})")


if __name__ == "__main__":
    main()
