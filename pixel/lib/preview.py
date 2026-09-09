"""Scale-up contact sheets so pixel art can actually be looked at."""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from sbpixel import Frame, encode_png, hexrgb, TRANSPARENT

def upscale(f, k):
    out = Frame(f.w * k, f.h * k)
    for y in range(f.h):
        for x in range(f.w):
            p = f.get(x, y)
            if p[3]:
                for j in range(k):
                    for i in range(k):
                        out.set(x * k + i, y * k + j, p)
    return out

def contact(rows, scale=6, pad=4, bg='#20242C', gap_bg='#2E3440'):
    """rows: list of lists of Frames. Returns a single Frame."""
    BG, GBG = hexrgb(bg), hexrgb(gap_bg)
    ups = [[upscale(f, scale) for f in r] for r in rows]
    cw = max(max((f.w for f in r), default=0) for r in ups)
    ch = max(max((f.h for f in r), default=0) for r in ups)
    cols = max(len(r) for r in ups)
    W = cols * (cw + pad) + pad
    H = len(ups) * (ch + pad) + pad
    out = Frame(W, H, BG)
    for ry, r in enumerate(ups):
        for cx, f in enumerate(r):
            ox, oy = pad + cx * (cw + pad), pad + ry * (ch + pad)
            out.rect(ox, oy, cw, ch, GBG)
            out.paste(f, ox + (cw - f.w) // 2, oy + (ch - f.h) // 2)
    return out

def save(frame, path):
    with open(path, 'wb') as fh:
        fh.write(encode_png(frame.w, frame.h, frame.px))
    return path
