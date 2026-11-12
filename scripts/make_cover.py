#!/bin/python3
"""生成 454x694 的书库封面（灰度 PNG）。仅在 Pillow 可用时绘制文字。"""
import os
import sys

W, H = 454, 694


def fallback():
    # 极简几何封面：无需 Pillow，白底黑框 + 黑色块。
    import struct
    import zlib

    rows = []
    for y in range(H):
        row = bytearray([255]) * W
        if y < 8 or y >= H - 8:
            for x in range(W):
                row[x] = 0
        else:
            for x in range(0, 8):
                row[x] = 0
                row[W - 1 - x] = 0
        if 500 <= y < 560:
            for x in range(40, W - 40):
                row[x] = 0
        rows.append(bytes(row))
    raw = b"".join(b"\x00" + r for r in rows)

    def chunk(tag, data):
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", W, H, 8, 0, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw, 9))
    png += chunk(b"IEND", b"")
    return png


def with_pillow(out):
    from PIL import Image, ImageDraw, ImageFont

    img = Image.new("L", (W, H), 255)
    d = ImageDraw.Draw(img)
    d.rectangle([6, 6, W - 7, H - 7], outline=0, width=3)
    # 顶部标签
    try:
        font_small = ImageFont.truetype("C:/Windows/Fonts/arial.ttf", 22)
        font_big = ImageFont.truetype("C:/Windows/Fonts/arialbd.ttf", 118)
        font_mid = ImageFont.truetype("C:/Windows/Fonts/arial.ttf", 26)
    except Exception:
        font_small = font_big = font_mid = ImageFont.load_default()
    d.text((36, 44), "PERSONAL INFORMATION PANEL", font=font_small, fill=0)
    d.text((32, 150), "KD", font=font_big, fill=0)
    d.text((36, 300), "DASH", font=font_big, fill=0)
    d.line([36, 450, W - 36, 450], fill=0, width=3)
    d.text((36, 474), "TIME / COUNTDOWN / TASKS", font=font_mid, fill=0)
    d.text((36, 512), "WEATHER / NOTES", font=font_mid, fill=0)
    d.rectangle([0, H - 96, W, H], fill=0)
    d.text((36, H - 70), "KINDLE DASHBOARD", font=font_mid, fill=255)
    img.convert("RGB").save(out, "PNG", optimize=True)
    return True


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), "..", "assets", "cover.png")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    try:
        with_pillow(out)
        print("cover written:", out)
    except Exception as e:
        sys.stderr.write("Pillow unavailable (%s); using fallback cover\n" % e)
        with open(out, "wb") as f:
            f.write(fallback())
        print("cover written (fallback):", out)


if __name__ == "__main__":
    main()
