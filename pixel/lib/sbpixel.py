"""
sbpixel - author Piskel documents from Python.

A .piskel file is JSON: {"modelVersion":2,"piskel":{name,width,height,fps,layers:[<json string>]}}
and each layer string is {"name","opacity","frameCount","chunks":[{"layout":[[i],...],"base64PNG"}]}
where base64PNG is a horizontal spritesheet of that layer's frames. Writing that directly is far
faster and far more precise than drawing in the web app, and the result opens in piskelapp.com for
hand-tweaking like any other file.

Everything here is stdlib only (zlib + struct + base64 + json). No Pillow.

Two ways to make a frame:
  * from_map(rows, palette)  - hand-authored pixel art, one character per pixel
  * a Frame you draw into    - procedural shapes, for arcs/glows/particles

Coordinates are (x, y) with y=0 at the TOP, matching how the maps read on screen.
"""

import base64, json, struct, zlib
from math import atan2, cos, hypot, pi, sin

TRANSPARENT = (0, 0, 0, 0)


# ---------------------------------------------------------------- colour ----
def hexrgb(h, a=255):
    """'#RRGGBB' or '#RGB' -> (r,g,b,a)."""
    h = h.lstrip('#')
    if len(h) == 3:
        h = ''.join(c * 2 for c in h)
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), a)


def shade(rgb, k):
    """Lighten (k>0) or darken (k<0) toward white/black. k in -1..1."""
    r, g, b, a = rgb
    if k >= 0:
        f = k
        return (round(r + (255 - r) * f), round(g + (255 - g) * f), round(b + (255 - b) * f), a)
    f = -k
    return (round(r * (1 - f)), round(g * (1 - f)), round(b * (1 - f)), a)


def ramp(base, n=4, lo=-0.45, hi=0.35):
    """A shading ramp from darkest to lightest, n steps, base sitting inside it."""
    if n == 1:
        return [base]
    return [shade(base, lo + (hi - lo) * i / (n - 1)) for i in range(n)]


def with_alpha(rgb, a):
    return (rgb[0], rgb[1], rgb[2], max(0, min(255, int(a))))


def over(dst, src):
    """Source-over alpha composite of two RGBA tuples."""
    sa = src[3] / 255.0
    if sa <= 0:
        return dst
    if sa >= 1 or dst[3] == 0:
        return src if sa >= 1 else (src[0], src[1], src[2], max(dst[3], src[3]))
    da = dst[3] / 255.0
    oa = sa + da * (1 - sa)
    return (round((src[0] * sa + dst[0] * da * (1 - sa)) / oa),
            round((src[1] * sa + dst[1] * da * (1 - sa)) / oa),
            round((src[2] * sa + dst[2] * da * (1 - sa)) / oa),
            round(oa * 255))


# ----------------------------------------------------------------- frame ----
class Frame:
    def __init__(self, w, h, fill=TRANSPARENT):
        self.w, self.h = w, h
        self.px = [fill] * (w * h)

    def clone(self):
        f = Frame(self.w, self.h)
        f.px = list(self.px)
        return f

    def inside(self, x, y):
        return 0 <= x < self.w and 0 <= y < self.h

    def get(self, x, y):
        return self.px[y * self.w + x] if self.inside(x, y) else TRANSPARENT

    def set(self, x, y, c):
        if self.inside(x, y) and c[3]:
            self.px[y * self.w + x] = c

    def blend(self, x, y, c):
        if self.inside(x, y) and c[3]:
            i = y * self.w + x
            self.px[i] = over(self.px[i], c)

    # --- primitives -------------------------------------------------------
    def rect(self, x, y, w, h, c):
        for j in range(y, y + h):
            for i in range(x, x + w):
                self.set(i, j, c)

    def line(self, x0, y0, x1, y1, c):
        x0, y0, x1, y1 = int(x0), int(y0), int(x1), int(y1)
        dx, dy = abs(x1 - x0), -abs(y1 - y0)
        sx, sy = (1 if x0 < x1 else -1), (1 if y0 < y1 else -1)
        err = dx + dy
        while True:
            self.set(x0, y0, c)
            if x0 == x1 and y0 == y1:
                break
            e2 = 2 * err
            if e2 >= dy:
                err += dy; x0 += sx
            if e2 <= dx:
                err += dx; y0 += sy

    def disc(self, cx, cy, r, c, blend=False):
        put = self.blend if blend else self.set
        r2 = r * r
        for j in range(int(cy - r) - 1, int(cy + r) + 2):
            for i in range(int(cx - r) - 1, int(cx + r) + 2):
                if (i - cx) ** 2 + (j - cy) ** 2 <= r2:
                    put(i, j, c)

    def ring(self, cx, cy, r, thick, c, blend=False):
        put = self.blend if blend else self.set
        ro, ri = r + thick / 2.0, r - thick / 2.0
        for j in range(int(cy - ro) - 1, int(cy + ro) + 2):
            for i in range(int(cx - ro) - 1, int(cx + ro) + 2):
                d = hypot(i - cx, j - cy)
                if ri <= d <= ro:
                    put(i, j, c)

    def arc(self, cx, cy, r, thick, a0, a1, c, blend=False):
        """Angles in radians, counter-clockwise from +x, drawn in screen space (y flipped).

        a1 must be greater than a0; the span is a1 - a0. A non-positive span draws nothing rather
        than silently wrapping into a full circle, and a span of 2*pi or more draws the full ring.
        """
        span = a1 - a0
        if span <= 1e-9:
            return
        if span >= 2 * pi:
            return self.ring(cx, cy, r, thick, c, blend)
        put = self.blend if blend else self.set
        ro, ri = r + thick / 2.0, r - thick / 2.0
        for j in range(int(cy - ro) - 1, int(cy + ro) + 2):
            for i in range(int(cx - ro) - 1, int(cx + ro) + 2):
                d = hypot(i - cx, j - cy)
                if not (ri <= d <= ro):
                    continue
                a = atan2(-(j - cy), i - cx) % (2 * pi)
                if a0 % (2 * pi) <= a1 % (2 * pi):
                    ok = a0 % (2 * pi) <= a <= a1 % (2 * pi)
                else:
                    ok = a >= a0 % (2 * pi) or a <= a1 % (2 * pi)
                if ok:
                    put(i, j, c)

    def poly(self, pts, c):
        """Filled polygon, even-odd scanline."""
        if len(pts) < 3:
            return
        ys = [p[1] for p in pts]
        for y in range(int(min(ys)), int(max(ys)) + 1):
            xs = []
            for k in range(len(pts)):
                (x0, y0), (x1, y1) = pts[k], pts[(k + 1) % len(pts)]
                if (y0 <= y < y1) or (y1 <= y < y0):
                    xs.append(x0 + (y - y0) * (x1 - x0) / float(y1 - y0))
            xs.sort()
            for k in range(0, len(xs) - 1, 2):
                for x in range(int(round(xs[k])), int(round(xs[k + 1])) + 1):
                    self.set(x, y, c)

    def outline(self, c, diagonal=False):
        """Trace a 1px border just outside every opaque pixel. Call last."""
        n4 = [(1, 0), (-1, 0), (0, 1), (0, -1)]
        n8 = n4 + [(1, 1), (1, -1), (-1, 1), (-1, -1)]
        nb = n8 if diagonal else n4
        add = []
        for y in range(self.h):
            for x in range(self.w):
                if self.get(x, y)[3]:
                    continue
                if any(self.get(x + dx, y + dy)[3] for dx, dy in nb):
                    add.append((x, y))
        for x, y in add:
            self.px[y * self.w + x] = c

    def shadow_pass(self, c, dx=1, dy=1):
        """Drop a darker copy behind the art (used for weapon icons)."""
        out = Frame(self.w, self.h)
        for y in range(self.h):
            for x in range(self.w):
                if self.get(x, y)[3]:
                    out.set(x + dx, y + dy, c)
        for y in range(self.h):
            for x in range(self.w):
                p = self.get(x, y)
                if p[3]:
                    out.px[y * self.w + x] = p
        return out

    def flip_x(self):
        f = Frame(self.w, self.h)
        for y in range(self.h):
            for x in range(self.w):
                f.px[y * self.w + (self.w - 1 - x)] = self.px[y * self.w + x]
        return f

    def paste(self, other, ox=0, oy=0):
        for y in range(other.h):
            for x in range(other.w):
                self.blend(x + ox, y + oy, other.get(x, y))

    def count_opaque(self):
        return sum(1 for p in self.px if p[3])


def from_map(rows, palette, w=None, h=None):
    """Hand-authored art: one character per pixel. '.' and ' ' are transparent."""
    rows = [r for r in rows.split('\n') if r.strip('\r') != ''] if isinstance(rows, str) else list(rows)
    h = h or len(rows)
    w = w or max(len(r) for r in rows)
    f = Frame(w, h)
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            if ch in '. ':
                continue
            c = palette.get(ch)
            if c is None:
                raise KeyError(f"pixel map uses '{ch}' at ({x},{y}) but the palette has no such key")
            f.set(x, y, c)
    return f


# ------------------------------------------------------------------- png ----
def _chunk(tag, data):
    body = tag + data
    return struct.pack('>I', len(data)) + body + struct.pack('>I', zlib.crc32(body) & 0xffffffff)


def encode_png(w, h, pixels):
    raw = bytearray()
    for y in range(h):
        raw.append(0)
        row = pixels[y * w:(y + 1) * w]
        for p in row:
            raw += bytes(p)
    return (b'\x89PNG\r\n\x1a\n'
            + _chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 6, 0, 0, 0))
            + _chunk(b'IDAT', zlib.compress(bytes(raw), 9))
            + _chunk(b'IEND', b''))


def sheet_png(frames):
    """Frames laid out left-to-right, the layout Piskel expects inside a chunk."""
    if not frames:
        raise ValueError('no frames')
    w, h, n = frames[0].w, frames[0].h, len(frames)
    px = [TRANSPARENT] * (w * n * h)
    for i, f in enumerate(frames):
        for y in range(h):
            for x in range(w):
                px[y * (w * n) + i * w + x] = f.px[y * w + x]
    return encode_png(w * n, h, px)


# ---------------------------------------------------------------- piskel ----
class Layer:
    def __init__(self, name, frames, opacity=1.0):
        self.name, self.frames, self.opacity = name, frames, opacity


class Piskel:
    def __init__(self, name, w, h, fps=12):
        self.name, self.w, self.h, self.fps = name, w, h, fps
        self.layers = []

    def add(self, name, frames, opacity=1.0):
        if isinstance(frames, Frame):
            frames = [frames]
        for f in frames:
            if (f.w, f.h) != (self.w, self.h):
                raise ValueError(f"layer '{name}': frame is {f.w}x{f.h}, document is {self.w}x{self.h}")
        self.layers.append(Layer(name, frames, opacity))
        return self

    @property
    def frame_count(self):
        return max((len(l.frames) for l in self.layers), default=1)

    def _layer_json(self, layer):
        # Every layer must declare the document's frame count; hold the last frame if it is short.
        n = self.frame_count
        frames = list(layer.frames) + [layer.frames[-1]] * (n - len(layer.frames))
        return json.dumps({
            'name': layer.name,
            'opacity': layer.opacity,
            'frameCount': n,
            'chunks': [{
                'layout': [[i] for i in range(n)],
                'base64PNG': 'data:image/png;base64,' + base64.b64encode(sheet_png(frames)).decode(),
            }],
        })

    def to_json(self):
        return json.dumps({
            'modelVersion': 2,
            'piskel': {
                'name': self.name, 'description': '', 'fps': self.fps,
                'height': self.h, 'width': self.w,
                'layers': [self._layer_json(l) for l in self.layers],
            },
        })

    def save(self, path):
        with open(path, 'w', encoding='utf-8') as fh:
            fh.write(self.to_json())
        return path

    def flatten(self):
        """Composite all layers, for the PNG spritesheet export the game engine loads."""
        out = []
        for i in range(self.frame_count):
            f = Frame(self.w, self.h)
            for layer in self.layers:
                src = layer.frames[min(i, len(layer.frames) - 1)]
                if layer.opacity >= 1.0:
                    f.paste(src)
                else:
                    for y in range(self.h):
                        for x in range(self.w):
                            p = src.get(x, y)
                            if p[3]:
                                f.blend(x, y, with_alpha(p, p[3] * layer.opacity))
            out.append(f)
        return out

    def save_sheet(self, path):
        with open(path, 'wb') as fh:
            fh.write(sheet_png(self.flatten()))
        return path
