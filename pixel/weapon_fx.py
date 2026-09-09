"""Weapon VFX: the swing arcs, flashes and rune circles that play on each weapon's attacks.

Every effect is authored facing RIGHT. The game mirrors by facing, so there is one asset per
effect, not two. Frame counts line up with the active windows in data/weapons/*.js.
"""
import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), 'lib'))
from sbpixel import *
from math import pi, cos, sin, hypot

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'out', 'fx')
os.makedirs(OUT, exist_ok=True)


def sweep(size, frames, r, a0, a1, thick, colours, tail=0.55, cx=None, cy=None):
    """A blade arc sweeping a0 -> a1 over `frames`, drawn as one continuous ribbon per frame.

    The ribbon runs from the tail angle to the head angle and is subdivided finely enough that the
    segments overlap, so it reads as a single swipe rather than a string of beads. Thickness,
    brightness and alpha all ramp from tail to head.
    """
    W, H = size
    cx = W * 0.14 if cx is None else cx
    cy = H * 0.5 if cy is None else cy
    total = a1 - a0
    out = []
    for i in range(frames):
        f = Frame(W, H)
        k = i / max(1, frames - 1)
        head = a0 + total * k
        tail_a = a0 + total * max(0.0, k - tail)
        span = head - tail_a
        # Frame 0 would otherwise be a single pixel. Every frame gets at least a short ribbon so the
        # swing reads from the first frame it is on screen.
        min_span = abs(total) * 0.18
        if abs(span) < min_span:
            span = min_span if total > 0 else -min_span
            tail_a = head - span
        N = max(8, int(abs(span) / 0.045))
        for n in range(N):
            t = n / (N - 1) if N > 1 else 1.0                  # 0 at the tail, 1 at the head
            a = tail_a + span * t
            half = max(abs(span) / N * 0.95, 0.035)            # overlap: no gaps between segments
            th = thick * (0.30 + 0.70 * t)
            ci = min(len(colours) - 1, int(t * (len(colours) - 1) + 0.5))
            alpha = int(255 * (0.12 + 0.88 * t * t))
            f.arc(cx, cy, r, th, a - half, a + half, with_alpha(colours[ci], alpha), blend=True)
        out.append(f)
    return out


def star(size, frames, colours, spikes=6, r0=3.0, r1=None):
    """Muzzle flash: a spiked burst that blooms and collapses."""
    W, H = size
    cx, cy = W * 0.32, H * 0.5
    r1 = r1 or W * 0.42
    out = []
    for i in range(frames):
        f = Frame(W, H)
        k = i / max(1, frames - 1)
        grow = sin(min(1.0, k * 1.35) * pi * 0.5)            # fast bloom, slower fade
        fade = 1.0 - k * 0.85
        R = r0 + (r1 - r0) * grow
        for sp in range(spikes):
            a = sp * 2 * pi / spikes + 0.25
            ln = R * (1.0 if sp % 2 == 0 else 0.55)
            f.line(cx, cy, cx + cos(a) * ln, cy - sin(a) * ln, with_alpha(colours[1], int(230 * fade)))
        f.line(cx, cy, cx + R * 1.5, cy, with_alpha(colours[1], int(230 * fade)))   # along the barrel
        f.disc(cx, cy, max(1.0, R * 0.42), with_alpha(colours[0], int(220 * fade)), blend=True)
        f.disc(cx, cy, max(1.0, R * 0.24), with_alpha(colours[2], int(255 * fade)), blend=True)
        out.append(f)
    return out


def rune(size, frames, colours, points=6):
    """Grimoire cast: a ring draws itself in, snaps to full, then flares out."""
    W, H = size
    cx, cy = W * 0.5, H * 0.5
    R = W * 0.36
    out = []
    for i in range(frames):
        f = Frame(W, H)
        k = i / max(1, frames - 1)
        if k < 0.6:                                          # drawing in
            p = max(0.04, k / 0.6)
            f.arc(cx, cy, R, 1.4, -pi / 2, -pi / 2 + 2 * pi * p - 0.001,
                  with_alpha(colours[2], 220), blend=True)
            f.arc(cx, cy, R * 0.62, 1.0, pi / 2, pi / 2 + 2 * pi * p - 0.001,
                  with_alpha(colours[1], 170), blend=True)
            n = int(points * p)
            for s in range(n):
                a = s * 2 * pi / points - pi / 2
                f.disc(cx + cos(a) * R, cy - sin(a) * R, 1.2, colours[3])
        else:                                                # flare out
            p = (k - 0.6) / 0.4
            a_ = int(235 * (1 - p * 0.82))          # never fades to a completely empty frame
            f.ring(cx, cy, R * (1 + p * 0.55), 1.4, with_alpha(colours[2], a_), blend=True)
            f.ring(cx, cy, R * 0.62 * (1 + p * 0.9), 1.0, with_alpha(colours[1], a_), blend=True)
            for s in range(points):
                a = s * 2 * pi / points - pi / 2 + p * 0.6
                rr = R * (1 + p * 0.75)
                f.disc(cx + cos(a) * rr, cy - sin(a) * rr, max(0.6, 1.4 * (1 - p)),
                       with_alpha(colours[3], a_))
            f.disc(cx, cy, R * 0.3 * (1 - p), with_alpha(colours[3], a_), blend=True)
        out.append(f)
    return out


STEEL = ramp(hexrgb('#CFE9FF'), 4, -0.35, 0.6)
VIOLET = ramp(hexrgb('#C79BFF'), 4, -0.4, 0.55)
AMBER = ramp(hexrgb('#FFD37A'), 4, -0.3, 0.6)
ARCANE = ramp(hexrgb('#9FD9FF'), 4, -0.4, 0.6)

# name -> (doc size, fps, frames, layer name)
EFFECTS = {
    # Sword: a tight overhead-to-forward cut. Pivot near the left edge, blade sweeping right.
    'sword_slash':   ((40, 48), 20, lambda: sweep((40, 48), 6, 26, pi * 0.36, -pi * 0.36, 5.0, STEEL,
                                                  tail=0.62, cx=6, cy=24)),
    # Sword aerial spin: a full revolution around the fighter.
    'sword_spin':    ((48, 48), 20, lambda: sweep((48, 48), 8, 18, pi * 1.15, -pi * 0.85, 4.5, STEEL,
                                                  tail=0.75, cx=24, cy=24)),
    # Scythe: bigger radius and a wider ribbon - it should look like it covers ground.
    'scythe_reap':   ((56, 56), 20, lambda: sweep((56, 56), 8, 34, pi * 0.28, -pi * 0.28, 6.5, VIOLET,
                                                  tail=0.7, cx=6, cy=28)),
    # Scythe hook: sweeps the other way, dragging the victim in.
    'scythe_hook':   ((56, 56), 20, lambda: sweep((56, 56), 6, 31, -pi * 0.32, pi * 0.34, 5.5, VIOLET,
                                                  tail=0.6, cx=6, cy=28)),
    # Blasters: a short bright flash, no trail.
    'blaster_flash': ((24, 24), 24, lambda: star((24, 24), 4, AMBER)),
    # Grimoire: the cast circle drawing in, then flaring out.
    'grimoire_rune': ((48, 48), 16, lambda: rune((48, 48), 10, ARCANE)),
}

if __name__ == '__main__':
    for name, (size, fps, make) in EFFECTS.items():
        frames = make()
        doc = Piskel(name, size[0], size[1], fps=fps).add('fx', frames)
        doc.save(os.path.join(OUT, f'{name}.piskel'))
        doc.save_sheet(os.path.join(OUT, f'{name}.png'))
        print(f'{name:15} {size[0]:>3}x{size[1]:<3} {len(frames)} frames  '
              f'{min(f.count_opaque() for f in frames):>4}-{max(f.count_opaque() for f in frames):<4} px')
