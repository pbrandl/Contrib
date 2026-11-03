#!/usr/bin/env python3
"""Franz Sans – a plain, highly legible grotesque for web and UI text.

Design goals (in the spirit of modern system UI faces):
  * large x-height (530/710), open apertures, round dots
  * low stroke contrast, generous spacing for small sizes
  * clear I / l / 1 distinction (l has a tail, 1 has a flag)
  * four weights: Regular, Medium, Semibold, Bold

Glyphs are drawn parametrically: skeleton strokes are expanded with a
low-contrast pen, merged with skia-pathops, converted to smooth TrueType
quadratic curves (with on-curve extrema) and autohinted with ttfautohint.

    pip install fonttools skia-pathops brotli ttfautohint-py
    python3 build.py            # writes ./fonts/*.ttf, *.woff2
"""
import io
import math
import os
import sys

import pathops
from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.pens.recordingPen import RecordingPen
from fontTools.feaLib.builder import addOpenTypeFeaturesFromString
from fontTools.misc.timeTools import timestampNow
from fontTools.ttLib import TTFont

FAMILY = "Franz Sans"
UPM = 1000
CAP, XH, ASC, DESC, OV = 710, 530, 760, -210, 11

WEIGHTS = {
    # name: (stem, horizontal/stem ratio, usWeightClass)
    "Regular": (84, 0.86, 400),
    "Medium": (100, 0.84, 500),
    "Semibold": (117, 0.81, 600),
    "Bold": (136, 0.78, 700),
}


def ss(x):
    x = max(0.0, min(1.0, x))
    return x * x * (3 - 2 * x)


# ---------------------------------------------------------------- strokes
class Stroke:
    def __init__(self, g, closed=False):
        self.g, self.pts, self.caps, self.closed = g, [], [], closed
        self.hcut = [False, False]

    def _add(self, p, cap):
        if self.pts and math.dist(self.pts[-1], p) < 0.5:
            return
        self.pts.append(p)
        self.caps.append(cap)

    def move(self, x, y):
        self._add((x, y), None)
        return self

    def line(self, x, y, cap=None):
        x0, y0 = self.pts[-1]
        n = max(2, int(math.dist((x0, y0), (x, y)) / 10))
        for i in range(1, n + 1):
            u = i / n
            self._add((x0 + (x - x0) * u, y0 + (y - y0) * u), cap(u) if cap else None)
        return self

    def curve(self, c1, c2, p, cap=None):
        p0 = self.pts[-1]
        L = math.dist(p0, c1) + math.dist(c1, c2) + math.dist(c2, p)
        n = max(8, int(L / 6))
        for i in range(1, n + 1):
            t = i / n
            a, b, c, d = (1 - t) ** 3, 3 * t * (1 - t) ** 2, 3 * t * t * (1 - t), t ** 3
            q = (a * p0[0] + b * c1[0] + c * c2[0] + d * p[0], a * p0[1] + b * c1[1] + c * c2[1] + d * p[1])
            self._add(q, cap(t) if cap else None)
        return self

    def arc(self, cx, cy, rx, ry, a0, a1, cap=None):
        n = max(8, int(abs(a1 - a0) / 2))
        angs = [a0 + (a1 - a0) * i / n for i in range(n + 1)]
        # make sure the extrema (0/90/180/270) are sampled exactly
        lo, hi = min(a0, a1), max(a0, a1)
        for k in range(int(math.floor(lo / 90)) - 1, int(math.ceil(hi / 90)) + 2):
            if lo < k * 90 < hi:
                angs.append(k * 90)
        angs = sorted(set(round(a, 6) for a in angs), reverse=a1 < a0)
        for a in angs:
            u = (a - a0) / (a1 - a0)
            r = math.radians(a)
            self._add((cx + rx * math.cos(r), cy + ry * math.sin(r)), cap(u) if cap else None)
        return self

    def cut(self, start=False, end=True):
        """Cut the stroke ends horizontally instead of perpendicular."""
        self.hcut = [start, end]
        return self

    def done(self):
        self.g.strokes.append(self)
        return self


def taper(a0=0.0, a1=0.0, lo=0.58):
    """Thin the stroke near a junction (fraction a0 at start, a1 at end) down to lo*stem."""

    def f(u):
        k = 1.0
        if a0 > 0:
            k = min(k, ss(u / a0))
        if a1 > 0:
            k = min(k, ss((1 - u) / a1))
        return (k, lo)

    return f


class Glyph:
    def __init__(self, S, ratio, adv):
        self.S, self.T, self.adv = S, S * ratio, adv
        self.Tb = S * (ratio + 0.04)  # straight horizontal bars
        self.strokes, self.polys, self.xf, self.clip = [], [], None, None

    def autow(self, dx, dy):
        L = math.hypot(dx, dy) or 1
        return self.T + (self.S - self.T) * (abs(dy) / L) ** 2

    def poly(self, pts):
        self.polys.append(list(pts))

    def rect(self, x0, y0, x1, y1):
        self.poly([(x0, y0), (x1, y0), (x1, y1), (x0, y1)])

    def stem(self, x, y0, y1, w=None):
        w = w or self.S
        self.rect(x - w / 2, y0, x + w / 2, y1)

    def hbar(self, x0, x1, y, w=None):
        w = w or self.Tb
        self.rect(x0, y - w / 2, x1, y + w / 2)

    def top(self, y):  # centre of a horizontal bar whose top edge is at y
        return y - self.Tb / 2

    def dot(self, x, y, r=None):
        r = r or self.S * 0.64
        self.oval_fill(x, y, r, r)

    def oval_fill(self, x, y, rx, ry):
        self.poly([(x + rx * math.cos(math.radians(a)), y + ry * math.sin(math.radians(a))) for a in range(0, 360, 6)])

    def diag(self, top, bot, w=None, ref=("c", "c")):
        (xt, yt), (xb, yb) = top, bot
        dx, dy = xt - xb, yt - yb
        w = w or self.S * 0.93
        h = w / 2 * math.hypot(dx, dy) / abs(dy)
        off = {"l": h, "c": 0, "r": -h}
        xt += off[ref[0]]
        xb += off[ref[1]]
        self.poly([(xt - h, yt), (xt + h, yt), (xb + h, yb), (xb - h, yb)])
        return lambda y: xb + (xt - xb) * (y - yb) / (yt - yb)

    def oval(self, l, r, b, t, a0=0, a1=360, cap=None, cut=True):
        cx, cy = (l + r) / 2, (b + t) / 2
        rx, ry = (r - l) / 2 - self.S / 2, (t - b) / 2 - self.T / 2
        closed = (a1 - a0 == 360)
        st = Stroke(self, closed=closed)
        st.arc(cx, cy, rx, ry, a0, a1, cap)
        if closed:
            st.pts.pop(); st.caps.pop()
        elif cut:
            st.cut(True, True)
        st.done()
        return cx, cy, rx, ry

    def path(self, x, y):
        return Stroke(self).move(x, y)

    def expand(self, st):
        pts, n = st.pts, len(st.pts)
        left, right, tans = [], [], []
        for i in range(n):
            if st.closed:
                a, b = pts[i - 1], pts[(i + 1) % n]
            else:
                a, b = pts[max(0, i - 1)], pts[min(n - 1, i + 1)]
            dx, dy = b[0] - a[0], b[1] - a[1]
            L = math.hypot(dx, dy) or 1
            w = self.autow(dx, dy)
            if st.caps[i] is not None:
                k, lo = st.caps[i]
                lo = lo * self.S
                if w > lo:
                    w = lo + (w - lo) * k
            nx, ny = -dy / L * w / 2, dx / L * w / 2
            left.append([pts[i][0] + nx, pts[i][1] + ny])
            right.append([pts[i][0] - nx, pts[i][1] - ny])
            tans.append((dx / L, dy / L))
        if not st.closed:
            self._hcut(st, pts, left, right, tans)
        quads = []
        m = n if st.closed else n - 1
        for i in range(m):
            j = (i + 1) % n
            quads.append(hull([tuple(left[i]), tuple(left[j]), tuple(right[j]), tuple(right[i])]))
        return quads

    def _hcut(self, st, pts, left, right, tans):
        n = len(pts)
        for idx, on in ((0, st.hcut[0]), (n - 1, st.hcut[1])):
            tx, ty = tans[idx]
            if on and abs(ty) > 0.35:
                cy = pts[idx][1]
                for P in (left[idx], right[idx]):
                    s = (cy - P[1]) / ty
                    P[0] += tx * s
                    P[1] = cy

    def outline(self):
        path = pathops.Path()
        items = [(p, False) for p in self.polys]
        for st in self.strokes:
            items += [(q, False) for q in self.expand(st)]
        for pts, hole in items:
            if self.xf:
                pts = [self.xf(*q) for q in pts]
            pts = orient(pts, not hole)
            path.moveTo(*pts[0])
            for q in pts[1:]:
                path.lineTo(*q)
            path.close()
        path.fillType = pathops.FillType.WINDING
        path.simplify(fix_winding=True)
        if self.clip:
            x0, y0, x1, y1 = self.clip
            box = pathops.Path()
            box.moveTo(x0, y0); box.lineTo(x1, y0); box.lineTo(x1, y1); box.lineTo(x0, y1); box.close()
            path = pathops.op(path, box, pathops.PathOp.INTERSECTION, fix_winding=True)
        return path


def hull(points):
    pts = sorted(set(points))
    if len(pts) < 3:
        return pts

    def cross(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])

    lower, upper = [], []
    for p in pts:
        while len(lower) >= 2 and cross(lower[-2], lower[-1], p) <= 0:
            lower.pop()
        lower.append(p)
    for p in reversed(pts):
        while len(upper) >= 2 and cross(upper[-2], upper[-1], p) <= 0:
            upper.pop()
        upper.append(p)
    return lower[:-1] + upper[:-1]


def area(p):
    return 0.5 * sum(p[i - 1][0] * p[i][1] - p[i][0] * p[i - 1][1] for i in range(len(p)))


def orient(p, ccw):
    return p if (area(p) > 0) == ccw else p[::-1]


# ---------------------------------------------------------- polyline -> quadratic
def turn(a, b, c):
    a1 = math.atan2(b[1] - a[1], b[0] - a[0])
    a2 = math.atan2(c[1] - b[1], c[0] - b[0])
    d = (a2 - a1 + math.pi) % (2 * math.pi) - math.pi
    return abs(math.degrees(d))


def smooth_contour(pts):
    """Return [(x, y, on_curve)] approximating the polygon with quadratic splines."""
    # drop duplicates / collinear points
    changed = True
    while changed and len(pts) > 3:
        changed = False
        out = []
        n = len(pts)
        for i in range(n):
            a, b, c = pts[i - 1], pts[i], pts[(i + 1) % n]
            if math.dist(a, b) < 0.8 or turn(a, b, c) < 0.25:
                changed = True
                continue
            out.append(b)
        if len(out) < 3:
            break
        pts = out
    # merge micro segments left over from the stroke union
    merged = []
    for p in pts:
        if merged and math.dist(merged[-1], p) < 2.5:
            continue
        merged.append(p)
    if len(merged) > 3 and math.dist(merged[0], merged[-1]) < 2.5:
        merged.pop()
    pts = merged
    n = len(pts)

    def nb(i, step):
        d, j = 0, i
        for _ in range(n):
            j2 = (j + step) % n
            d += math.dist(pts[j], pts[j2])
            j = j2
            if d >= 7:
                break
        return pts[j]

    on = [False] * n
    for i in range(n):
        a, b, c = pts[i - 1], pts[i], pts[(i + 1) % n]
        sharp = turn(nb(i, -1), b, nb(i, 1)) > 24 and turn(a, b, c) > 12
        if sharp or math.dist(a, b) > 40 or math.dist(b, c) > 40:
            on[i] = True
    # extrema inside smooth runs (robust against micro zig-zags)
    ext = [False] * n
    for k in (0, 1):
        cand = []
        for i in range(n):
            if on[i]:
                continue
            a, c = nb(i, -1), nb(i, 1)
            v = pts[i][k]
            if (v >= a[k] and v >= c[k]) or (v <= a[k] and v <= c[k]):
                if abs(v - a[k]) + abs(v - c[k]) < 3.0:  # flat enough: tangent ~ axis aligned
                    cand.append(i)
        # keep one point per cluster: the most extreme one
        used = set()
        for i in cand:
            if i in used:
                continue
            cluster = [i]
            j = i
            while (j + 1) % n in cand and (j + 1) % n not in cluster:
                j = (j + 1) % n
                cluster.append(j)
            used.update(cluster)
            best = cluster[len(cluster) // 2]
            if not on[best] and not ext[best]:
                ext[best] = k + 1
    for i in range(n):
        if ext[i]:
            on[i] = True
    # decimate smooth points to ~28 units spacing
    keep = [True] * n
    if any(on):
        start = on.index(True)
        acc = tacc = 0
        for j in range(1, n + 1):
            i = (start + j) % n
            if on[i]:
                acc = tacc = 0
                continue
            prev = pts[(i - 1) % n]
            acc += math.dist(prev, pts[i])
            tacc = tacc + turn(pts[(i - 2) % n], prev, pts[i]) if acc else 0
            nxt_on = on[(i + 1) % n]
            if acc < 28 and tacc < 14 and not nxt_on and not on[(i - 1) % n]:
                keep[i] = False
            else:
                acc = tacc = 0
    res = [[pts[i][0], pts[i][1], on[i], ext[i]] for i in range(n) if keep[i]]
    # flatten neighbours of extrema so the curve stays smooth through them
    m = len(res)
    for i in range(m):
        if res[i][3]:
            k = res[i][3] - 1
            for j in (i - 1, (i + 1) % m):
                if not res[j][2]:
                    res[j][k] = res[i][k]
    return [(r[0], r[1], r[2]) for r in res]


def to_ttglyph(path, dx=0):
    rec = RecordingPen()
    path.draw(rec)
    contours, cur = [], []
    for op, args in rec.value:
        if op == "moveTo":
            cur = [args[0]]
        elif op == "lineTo":
            cur.append(args[0])
        elif op in ("closePath", "endPath"):
            if len(cur) > 2:
                contours.append(cur)
            cur = []
        else:
            raise ValueError(op)
    # TrueType: outer contours clockwise
    total = sum(area(c) for c in contours)
    if total > 0:
        contours = [c[::-1] for c in contours]
    pen = TTGlyphPen(None)
    for c in contours:
        sm = smooth_contour([(x + dx, y) for x, y in c])
        if not any(p[2] for p in sm):
            pen.qCurveTo(*[(p[0], p[1]) for p in sm], None)
            pen.closePath()
            continue
        k = [p[2] for p in sm].index(True)
        sm = sm[k:] + sm[:k]
        pen.moveTo(sm[0][:2])
        offs = []
        for x, y, o in sm[1:] + [sm[0]]:
            if o:
                if offs:
                    pen.qCurveTo(*offs, (x, y))
                else:
                    pen.lineTo((x, y))
                offs = []
            else:
                offs.append((x, y))
        pen.closePath()
    return pen.glyph()


# ------------------------------------------------------------------ glyphs
G = {}


def glyph(name, uni, adv, case="lc"):
    def deco(fn):
        G[name] = (uni, adv, case, fn)
        return fn
    return deco


def comp(name, uni, base, mark):
    G[name] = (uni, None, base, mark)


# ---------- capitals
@glyph("A", "A", 670, "uc")
def _A(g):
    a = g.S * 0.5
    L = g.diag((335 - a, CAP), (28, 0), ref=("l", "l"))
    R = g.diag((335 + a, CAP), (642, 0), ref=("r", "r"))
    y = 215
    g.hbar(L(y), R(y), y)
    g.rect(335 - a, CAP - 1, 335 + a, CAP)


@glyph("B", "B", 640, "uc")
def _B(g):
    x, T = 120, g.Tb
    g.stem(x, 0, CAP)
    ym = 392
    p = g.path(x, g.top(CAP)).line(345, g.top(CAP))
    p.arc(345, (g.top(CAP) + ym) / 2, 545 - g.S / 2 - 345, (g.top(CAP) - ym) / 2, 90, -90).line(x, ym).done()
    p = g.path(x, ym).line(355, ym)
    p.arc(355, (ym + T / 2) / 2, 590 - g.S / 2 - 355, (ym - T / 2) / 2, 90, -90).line(x, T / 2).done()


@glyph("C", "C", 690, "uc")
def _C(g):
    g.oval(50, 655, -OV, CAP + OV, 40, 320)


@glyph("D", "D", 720, "uc")
def _D(g):
    x, T = 120, g.Tb
    g.stem(x, 0, CAP)
    p = g.path(x, g.top(CAP)).line(355, g.top(CAP))
    p.arc(355, CAP / 2, 675 - g.S / 2 - 355, CAP / 2 - T / 2, 90, -90).line(x, T / 2).done()


@glyph("E", "E", 590, "uc")
def _E(g):
    x = 120
    g.stem(x, 0, CAP)
    g.hbar(x, 535, g.top(CAP)); g.hbar(x, 505, 372); g.hbar(x, 545, g.Tb / 2)


@glyph("F", "F", 565, "uc")
def _F(g):
    x = 120
    g.stem(x, 0, CAP)
    g.hbar(x, 530, g.top(CAP)); g.hbar(x, 495, 362)


@glyph("G", "G", 725, "uc")
def _G(g):
    cx, cy, rx, ry = g.oval(50, 680, -OV, CAP + OV, 38, 360)
    xr = cx + rx
    g.stem(xr, 60, cy)
    g.hbar(385, xr + g.S / 2, cy - 10 + g.Tb / 2 - g.Tb / 2)


@glyph("H", "H", 715, "uc")
def _H(g):
    g.stem(120, 0, CAP); g.stem(595, 0, CAP); g.hbar(120, 595, 372)


@glyph("I", "I", 260, "uc")
def _I(g):
    g.stem(130, 0, CAP)


@glyph("J", "J", 520, "uc")
def _J(g):
    x = 405
    p = g.path(x, CAP).line(x, 230)
    p.arc(x - 160, 230, 160, 230 - g.T / 2 + OV, 0, -170).cut(False, True).done()


@glyph("K", "K", 645, "uc")
def _K(g):
    x = 120
    g.stem(x, 0, CAP)
    arm = g.diag((622, CAP), (x, 170), ref=("r", "c"))
    g.clip = (x - g.S / 2, -100, 1000, 1000)
    g.diag((arm(400), 400), (630, 0), ref=("c", "r"))


@glyph("L", "L", 545, "uc")
def _L(g):
    g.stem(120, 0, CAP); g.hbar(120, 530, g.Tb / 2)


@glyph("M", "M", 850, "uc")
def _M(g):
    xl, xr = 115, 735
    g.stem(xl, 0, CAP); g.stem(xr, 0, CAP)
    w = g.S * 0.86
    g.diag((xl - g.S / 2, CAP), (425, 0), w=w, ref=("l", "c"))
    g.diag((xr + g.S / 2, CAP), (425, 0), w=w, ref=("r", "c"))


@glyph("N", "N", 715, "uc")
def _N(g):
    xl, xr = 120, 595
    g.stem(xl, 0, CAP); g.stem(xr, 0, CAP)
    g.diag((xl - g.S / 2, CAP), (xr + g.S / 2, 0), w=g.S * 0.95, ref=("l", "r"))


@glyph("O", "O", 760, "uc")
def _O(g):
    g.oval(50, 710, -OV, CAP + OV)


@glyph("P", "P", 610, "uc")
def _P(g):
    x = 120
    g.stem(x, 0, CAP)
    ym = 300
    p = g.path(x, g.top(CAP)).line(345, g.top(CAP))
    p.arc(345, (g.top(CAP) + ym) / 2, 570 - g.S / 2 - 345, (g.top(CAP) - ym) / 2, 90, -90).line(x, ym).done()


@glyph("Q", "Q", 760, "uc")
def _Q(g):
    g.oval(50, 710, -OV, CAP + OV)
    g.diag((470, 170), (690, -50), w=g.S * 0.95)


@glyph("R", "R", 640, "uc")
def _R(g):
    x = 120
    g.stem(x, 0, CAP)
    ym = 318
    p = g.path(x, g.top(CAP)).line(345, g.top(CAP))
    p.arc(345, (g.top(CAP) + ym) / 2, 570 - g.S / 2 - 345, (g.top(CAP) - ym) / 2, 90, -90).line(x, ym).done()
    g.diag((340, ym + 10), (600, 0), ref=("c", "r"))


def draw_s(g, x0, x1, h):
    W, T, S = x1 - x0, g.T, g.S
    X = lambda u: x0 + u * W
    Y = lambda v: v * h
    top, bot = h + OV - T / 2, -OV + T / 2
    e = S / 2 / W
    p = g.path(X(0.90), Y(0.80))
    p.curve((X(0.84), Y(0.95)), (X(0.70), top), (X(0.50), top))
    p.curve((X(0.24), top), (X(e), Y(0.90)), (X(e), Y(0.73)))
    p.curve((X(e), Y(0.52)), (X(0.30), Y(0.49)), (X(0.52), Y(0.44)))
    p.curve((X(0.80), Y(0.38)), (X(1 - e), Y(0.31)), (X(1 - e), Y(0.21)))
    p.curve((X(1 - e), Y(0.05)), (X(0.76), bot), (X(0.50), bot))
    p.curve((X(0.28), bot), (X(0.12), Y(0.06)), (X(0.06), Y(0.21))).cut(True, True).done()


@glyph("S", "S", 610, "uc")
def _S(g):
    draw_s(g, 45, 565, CAP)


@glyph("T", "T", 600, "uc")
def _T(g):
    g.hbar(35, 565, g.top(CAP)); g.stem(300, 0, CAP)


@glyph("U", "U", 705, "uc")
def _U(g):
    xl, xr, yb = 118, 587, 265
    p = g.path(xl, CAP).line(xl, yb)
    p.arc((xl + xr) / 2, yb, (xr - xl) / 2, yb - g.T / 2 + OV, 180, 360).line(xr, CAP).done()


@glyph("V", "V", 645, "uc")
def _V(g):
    g.diag((25, CAP), (322, 0), ref=("l", "c"))
    g.diag((620, CAP), (322, 0), ref=("r", "c"))
    g.rect(322 - g.S * 0.45, 0, 322 + g.S * 0.45, 1)


@glyph("W", "W", 950, "uc")
def _W(g):
    w = g.S * 0.9
    g.diag((25, CAP), (250, 0), w=w, ref=("l", "c")); g.diag((475, CAP), (250, 0), w=w)
    g.diag((475, CAP), (700, 0), w=w); g.diag((925, CAP), (700, 0), w=w, ref=("r", "c"))


@glyph("X", "X", 640, "uc")
def _X(g):
    g.diag((40, CAP), (600, 0), ref=("l", "r")); g.diag((600, CAP), (40, 0), ref=("r", "l"))


@glyph("Y", "Y", 625, "uc")
def _Y(g):
    g.diag((25, CAP), (312, 320), ref=("l", "c")); g.diag((600, CAP), (312, 320), ref=("r", "c"))
    g.stem(312, 0, 340)


@glyph("Z", "Z", 610, "uc")
def _Z(g):
    g.hbar(55, 555, g.top(CAP))
    g.diag((555, CAP - g.Tb + 2), (55, g.Tb - 2), w=g.S, ref=("r", "l"))
    g.hbar(50, 565, g.Tb / 2)


# ---------- figures (tabular)
FW = 590


@glyph("zero", "0", FW, "uc")
def _0(g):
    g.oval(60, 530, -OV, CAP + OV)


@glyph("one", "1", FW, "uc")
def _1(g):
    x = 330
    g.stem(x, 0, CAP)
    g.diag((x - g.S / 2 + 2, CAP), (130, 560), w=g.S * 0.85, ref=("l", "c"))


@glyph("two", "2", FW, "uc")
def _2(g):
    T = g.T
    top = CAP + OV - T / 2
    p = g.path(88, 520)
    p.curve((95, 640), (185, top), (295, top))
    p.curve((410, top), (490, 630), (490, 525))
    p.curve((490, 420), (420, 350), (330, 270))
    p.line(80, g.Tb).cut(True, False).done()
    g.hbar(70, 515, g.Tb / 2)


@glyph("three", "3", FW, "uc")
def _3(g):
    T = g.T
    top = CAP + OV - T / 2
    p = g.path(85, 535)
    p.curve((100, 650), (190, top), (290, top))
    p.curve((405, top), (475, 640), (475, 545))
    p.curve((475, 450), (395, 400), (270, 400)).cut(True, False).done()
    p = g.path(270, 400)
    p.curve((410, 400), (500, 330), (500, 210))
    p.curve((500, 75), (405, -OV + T / 2), (290, -OV + T / 2))
    p.curve((180, -OV + T / 2), (90, 50), (78, 175)).cut(False, True).done()


@glyph("four", "4", FW, "uc")
def _4(g):
    x = 420
    g.stem(x, 0, CAP)
    g.diag((x + g.S / 2, CAP), (55, 205), w=g.S * 0.9, ref=("r", "l"))
    g.hbar(55, 545, 205 + g.Tb / 2)


@glyph("five", "5", FW, "uc")
def _5(g):
    T = g.T
    g.hbar(145, 490, g.top(CAP))
    g.diag((150, CAP), (128, 365), w=g.S * 0.92, ref=("c", "c"))
    p = g.path(128, 380)
    p.curve((185, 440), (245, 460), (305, 460))
    p.curve((430, 460), (510, 370), (510, 235))
    p.curve((510, 85), (410, -OV + T / 2), (290, -OV + T / 2))
    p.curve((180, -OV + T / 2), (95, 50), (78, 170), cap=None).cut(False, True).done()


@glyph("six", "6", FW, "uc")
def _6(g):
    g.oval(60, 525, -OV, 465)
    T = g.T
    p = g.path(60 + g.S / 2, 230)
    p.curve((60 + g.S / 2, 540), (170, CAP + OV - T / 2), (315, CAP + OV - T / 2))
    p.curve((400, CAP + OV - T / 2), (460, 670), (482, 590)).cut(False, True).done()


@glyph("nine", "9", FW, "uc")
def _9(g):
    _6(g)
    g.xf = lambda x, y: (FW - x, CAP - y)


@glyph("seven", "7", FW, "uc")
def _7(g):
    g.hbar(65, 520, g.top(CAP))
    p = g.path(520, CAP - g.Tb + 5)
    p.curve((410, 520), (300, 300), (250, 0)).cut(True, True).done()


@glyph("eight", "8", FW, "uc")
def _8(g):
    g.oval(90, 500, 380, CAP + OV)
    g.oval(65, 525, -OV, 405)


# ---------- lowercase
def arch(g, xl, xr, h=XH):
    T = g.T
    top = h + OV - T / 2
    p = g.path(xl + 1, h - 150)
    p.curve((xl + 25, h - 40), (xl + 95, top), ((xl + xr) / 2 + 10, top), cap=taper(0.45, 0, lo=0.55))
    p.curve((xr - 25, top), (xr, h - 60), (xr, h - 170)).line(xr, 0).done()


def bowl(g, xs, xr, b=-OV, t=XH + OV):
    """Bowl attached to the right of a stem at xs (b, p; mirrored for d, q)."""
    cx = (xs + xr) / 2 - 8
    rx = xr - g.S / 2 - cx
    ry = (t - b) / 2 - g.T / 2
    cy = (t + b) / 2
    g.path(xs, cy + ry * 0.68).arc(cx, cy, rx, ry, 132, -132, cap=taper(0.2, 0.2, lo=0.68)).done()


@glyph("a", "a", 565, "lc")
def _a(g):
    T = g.T
    xs = 455
    top = XH + OV - T / 2
    p = g.path(92, 415)
    p.curve((115, 495), (185, top), (275, top))
    p.curve((395, top), (xs, 470), (xs, 360)).line(xs, 0).cut(True, False).done()
    p = g.path(xs, 300)
    p.curve((300, 300), (65, 290), (65, 145), cap=taper(0.25, 0, lo=0.6))
    p.curve((65, 50), (135, -OV + T / 2), (220, -OV + T / 2))
    p.curve((320, -OV + T / 2), (420, 40), (xs - 2, 120), cap=taper(0, 0.45, lo=0.55)).done()


@glyph("b", "b", 605, "lc")
def _b(g):
    g.stem(115, 0, ASC); bowl(g, 115, 560)


@glyph("c", "c", 530, "lc")
def _c(g):
    g.oval(45, 505, -OV, XH + OV, 42, 318)


@glyph("d", "d", 605, "lc")
def _d(g):
    _b(g); g.xf = lambda x, y: (605 - x, y)


@glyph("e", "e", 565, "lc")
def _e(g):
    l, r = 45, 520
    cx, cy = (l + r) / 2, XH / 2
    rx, ry = (r - l) / 2 - g.S / 2, (XH + 2 * OV) / 2 - g.T / 2
    yb = 285
    a0 = math.degrees(math.asin((yb - cy) / ry))
    xr = cx + rx * math.cos(math.radians(a0))
    g.hbar(l + 20, xr + g.S / 2 - 2, yb)
    g.path(xr, yb).arc(cx, cy, rx, ry, a0, 322).cut(False, True).done()


@glyph("f", "f", 350, "lc")
def _f(g):
    T, x = g.T, 150
    top = ASC + OV - T / 2
    g.stem(x, 0, 560)
    p = g.path(x, 540)
    p.curve((x, 680), (210, top), (290, top)).line(345, top).done()
    g.hbar(35, 330, XH - g.Tb / 2)


@glyph("g", "g", 605, "lc")
def _g(g):
    # drawn as a mirrored p-shape with a descender hook
    x, T = 115, g.T
    bot = DESC - OV + T / 2
    p = g.path(x, XH).line(x, -20)
    p.curve((x, -150), (205, bot), (325, bot))
    p.curve((425, bot), (495, -170), (515, -110)).cut(False, True).done()
    bowl(g, x, 560)
    g.xf = lambda x, y: (605 - x, y)


@glyph("h", "h", 590, "lc")
def _h(g):
    g.stem(115, 0, ASC); arch(g, 115, 475)


@glyph("i", "i", 240, "lc")
def _i(g):
    g.stem(120, 0, XH); g.dot(120, XH + 155)


@glyph("dotlessi", "ı", 240, "lc")
def _dotlessi(g):
    g.stem(120, 0, XH)


@glyph("j", "j", 250, "lc")
def _j(g):
    x, T = 128, g.T
    bot = DESC - OV + T / 2
    p = g.path(x, XH).line(x, -60)
    p.curve((x, -160), (90, bot), (30, bot)).line(-15, bot).done()
    g.dot(x, XH + 155)


@glyph("k", "k", 545, "lc")
def _k(g):
    x = 115
    g.stem(x, 0, ASC)
    arm = g.diag((515, XH), (x, 110), ref=("r", "c"))
    g.clip = (x - g.S / 2, -100, 1000, 1000)
    g.diag((arm(300), 300), (530, 0), ref=("c", "r"))


@glyph("l", "l", 275, "lc")
def _l(g):
    x, T = 115, g.T
    bot = -OV + T / 2
    p = g.path(x, ASC).line(x, 120)
    p.curve((x, 30), (155, bot), (215, bot)).line(250, bot).done()


@glyph("m", "m", 900, "lc")
def _m(g):
    g.stem(115, 0, XH); arch(g, 115, 460); arch(g, 460, 795)


@glyph("n", "n", 590, "lc")
def _n(g):
    g.stem(115, 0, XH); arch(g, 115, 475)


@glyph("o", "o", 585, "lc")
def _o(g):
    g.oval(45, 540, -OV, XH + OV)


@glyph("p", "p", 605, "lc")
def _p(g):
    g.stem(115, DESC, XH); bowl(g, 115, 560)


@glyph("q", "q", 605, "lc")
def _q(g):
    _p(g); g.xf = lambda x, y: (605 - x, y)


@glyph("r", "r", 375, "lc")
def _r(g):
    T = g.T
    top = XH + OV - T / 2
    g.stem(115, 0, XH)
    p = g.path(116, XH - 150)
    p.curve((140, XH - 40), (210, top), (290, top), cap=taper(0.5, 0, lo=0.55)).line(355, top).done()


@glyph("s", "s", 505, "lc")
def _s(g):
    draw_s(g, 42, 465, XH)


@glyph("t", "t", 365, "lc")
def _t(g):
    x, T = 150, g.T
    bot = -OV + T / 2
    p = g.path(x, 665).line(x, 120)
    p.curve((x, 35), (195, bot), (260, bot)).line(330, bot).done()
    g.hbar(35, 330, XH - g.Tb / 2)


@glyph("u", "u", 590, "lc")
def _u(g):
    _n(g); g.xf = lambda x, y: (590 - x, XH - y)


@glyph("v", "v", 530, "lc")
def _v(g):
    g.diag((22, XH), (265, 0), ref=("l", "c")); g.diag((508, XH), (265, 0), ref=("r", "c"))
    g.rect(265 - g.S * 0.45, 0, 265 + g.S * 0.45, 1)


@glyph("w", "w", 800, "lc")
def _w(g):
    w = g.S * 0.9
    g.diag((22, XH), (215, 0), w=w, ref=("l", "c")); g.diag((400, XH), (215, 0), w=w)
    g.diag((400, XH), (585, 0), w=w); g.diag((778, XH), (585, 0), w=w, ref=("r", "c"))


@glyph("x", "x", 530, "lc")
def _x(g):
    g.diag((35, XH), (495, 0), ref=("l", "r")); g.diag((495, XH), (35, 0), ref=("r", "l"))


@glyph("y", "y", 535, "lc")
def _y(g):
    g.diag((22, XH), (268, 0), ref=("l", "c"))
    f = g.diag((512, XH), (268, 0), ref=("r", "c"))
    g.diag((f(0) + 1, 1), (f(DESC), DESC), ref=("c", "c"))


@glyph("z", "z", 505, "lc")
def _z(g):
    g.hbar(55, 450, g.top(XH))
    g.diag((450, XH - g.Tb + 2), (55, g.Tb - 2), w=g.S, ref=("r", "l"))
    g.hbar(50, 460, g.Tb / 2)


@glyph("germandbls", "ß", 610, "lc")
def _ss(g):
    T, x = g.T, 115
    top = ASC + OV - T / 2
    g.stem(x, 0, 560)
    p = g.path(x, 540)
    p.curve((x, 690), (200, top), (295, top))
    p.curve((410, top), (470, 680), (470, 600))
    p.curve((470, 510), (400, 455), (290, 450)).done()
    p = g.path(290, 450)
    p.curve((440, 445), (530, 370), (530, 230))
    p.curve((530, 85), (440, -OV + T / 2), (320, -OV + T / 2)).line(245, -OV + T / 2).done()


# ---------- punctuation & symbols
@glyph("space", " ", 245, "lc")
def _space(g):
    pass


@glyph("period", ".", 250, "uc")
def _period(g):
    g.dot(125, g.S * 0.64)


@glyph("comma", ",", 250, "uc")
def _comma(g):
    r = g.S * 0.64
    g.dot(125, r)
    g.diag((125 + r * 0.9, r), (75, -140), w=g.S * 0.7, ref=("r", "c"))


@glyph("colon", ":", 250, "uc")
def _colon(g):
    r = g.S * 0.64
    g.dot(125, r); g.dot(125, XH - r)


@glyph("semicolon", ";", 250, "uc")
def _semicolon(g):
    _comma(g); g.dot(125, XH - g.S * 0.64)


@glyph("exclam", "!", 260, "uc")
def _exclam(g):
    g.dot(130, g.S * 0.64)
    g.poly([(130 - g.S * 0.55, CAP), (130 + g.S * 0.55, CAP), (130 + g.S * 0.4, 210), (130 - g.S * 0.4, 210)])


@glyph("question", "?", 500, "uc")
def _question(g):
    T = g.T
    top = CAP + OV - T / 2
    g.dot(235, g.S * 0.64)
    p = g.path(65, 515)
    p.curve((75, 640), (160, top), (255, top))
    p.curve((370, top), (440, 640), (440, 545))
    p.curve((440, 430), (235, 400), (235, 270)).line(235, 205).cut(True, False).done()


@glyph("hyphen", "-", 360, "uc")
def _hyphen(g):
    g.hbar(60, 300, 285, g.Tb)


@glyph("endash", "–", 520, "uc")
def _endash(g):
    g.hbar(40, 480, 285, g.Tb)


@glyph("emdash", "—", 1000, "uc")
def _emdash(g):
    g.hbar(40, 960, 285, g.Tb)


@glyph("underscore", "_", 500, "uc")
def _us(g):
    g.hbar(20, 480, -80, g.Tb)


@glyph("slash", "/", 380, "uc")
def _slash(g):
    g.diag((350, CAP + 40), (30, -120), w=g.S * 0.9)


@glyph("bar", "|", 260, "uc")
def _bar(g):
    g.stem(130, -160, ASC + 40, g.S * 0.85)


def paren(g, x):
    p = g.path(x + 110, ASC + 30)
    p.curve((x - 50, 560), (x - 50, 20), (x + 110, -175)).done()


@glyph("parenleft", "(", 320, "uc")
def _pl(g):
    paren(g, 105)


@glyph("parenright", ")", 320, "uc")
def _pr(g):
    paren(g, 105); g.xf = lambda x, y: (320 - x, y)


@glyph("bracketleft", "[", 320, "uc")
def _bl(g):
    g.stem(120, -170, ASC + 30); g.hbar(120, 270, ASC + 30 - g.Tb / 2); g.hbar(120, 270, -170 + g.Tb / 2)


@glyph("bracketright", "]", 320, "uc")
def _br(g):
    _bl(g); g.xf = lambda x, y: (320 - x, y)


def tick(g, x, y):
    """A comma-like tick whose dot sits at (x, y)."""
    r = g.S * 0.58
    g.dot(x, y, r)
    g.diag((x + r * 0.9, y), (x - 45, y - 140), w=g.S * 0.62, ref=("r", "c"))


@glyph("quoteright", "’", 240, "uc")
def _qr(g):
    tick(g, 125, 650)


@glyph("quoteleft", "‘", 240, "uc")
def _ql(g):
    tick(g, 125, 650); g.xf = lambda x, y: (240 - x, 2 * 650 - 140 - y)


@glyph("quotedblright", "”", 395, "uc")
def _qdr(g):
    tick(g, 125, 650); tick(g, 275, 650)


@glyph("quotedblleft", "“", 395, "uc")
def _qdl(g):
    _qdr(g); g.xf = lambda x, y: (395 - x, 2 * 650 - 140 - y)


@glyph("quotedblbase", "„", 395, "uc")
def _qdb(g):
    tick(g, 125, g.S * 0.58); tick(g, 275, g.S * 0.58)


@glyph("quotesingle", "'", 220, "uc")
def _qs(g):
    g.poly([(110 - g.S * 0.42, CAP + 20), (110 + g.S * 0.42, CAP + 20), (110 + g.S * 0.3, 470), (110 - g.S * 0.3, 470)])


@glyph("quotedbl", '"', 370, "uc")
def _qd(g):
    for x in (110, 260):
        g.poly([(x - g.S * 0.42, CAP + 20), (x + g.S * 0.42, CAP + 20), (x + g.S * 0.3, 470), (x - g.S * 0.3, 470)])


@glyph("ampersand", "&", 700, "uc")
def _amp(g):
    T = g.T
    top = CAP + OV - T / 2
    p = g.path(330, 400)
    p.curve((215, 460), (150, 520), (150, 590))
    p.curve((150, 670), (225, top), (310, top))
    p.curve((400, top), (465, 670), (465, 595))
    p.curve((440, 510), (360, 465), (275, 415))
    p.curve((145, 340), (65, 285), (65, 180))
    p.curve((65, 70), (155, -OV + T / 2), (270, -OV + T / 2))
    p.curve((420, -OV + T / 2), (545, 120), (590, 340)).cut(False, True).done()
    g.diag((300, 430), (640, 0), ref=("c", "r"))


@glyph("plus", "+", 580, "uc")
def _plus(g):
    g.hbar(70, 510, 330, g.S * 0.9); g.stem(290, 110, 550, g.S * 0.9)


@glyph("equal", "=", 580, "uc")
def _eq(g):
    g.hbar(70, 510, 420, g.S * 0.9); g.hbar(70, 510, 240, g.S * 0.9)


@glyph("periodcentered", "·", 250, "uc")
def _mid(g):
    g.dot(125, 320)


@glyph("asterisk", "*", 450, "uc")
def _ast(g):
    cx, cy = 225, 570
    for a in (90, 162, 234, 306, 18):
        r = math.radians(a)
        g.path(cx, cy).line(cx + 125 * math.cos(r), cy + 125 * math.sin(r)).done()


@glyph("numbersign", "#", 640, "uc")
def _hash(g):
    w = g.S * 0.85
    g.diag((300, CAP), (205, 0), w=w); g.diag((520, CAP), (425, 0), w=w)
    g.hbar(70, 590, 470, w); g.hbar(50, 570, 240, w)


@glyph("percent", "%", 820, "uc")
def _pct(g):
    g.S *= 0.8
    g.oval(40, 330, 330, CAP + OV)
    g.oval(490, 780, -OV, 380)
    g.diag((655, CAP), (165, 0), w=g.S * 1.0)


@glyph("Euro", "€", FW, "uc")
def _euro(g):
    cx, cy, rx, ry = g.oval(85, 575, -OV, CAP + OV, 42, 318)
    g.hbar(20, 380, 425, g.Tb * 0.95); g.hbar(20, 365, 285, g.Tb * 0.95)


comp("Adieresis", "Ä", "A", "dieresis_uc")
comp("Odieresis", "Ö", "O", "dieresis_uc")
comp("Udieresis", "Ü", "U", "dieresis_uc")
comp("adieresis", "ä", "a", "dieresis")
comp("odieresis", "ö", "o", "dieresis")
comp("udieresis", "ü", "u", "dieresis")
comp("eacute", "é", "e", "acute")
comp("egrave", "è", "e", "grave")
comp("agrave", "à", "a", "grave")
comp("aacute", "á", "a", "acute")
comp("Eacute", "É", "E", "acute_uc")


def marks(g, adv, kind, base):
    cx = adv / 2
    if base in ("a",):
        cx = adv / 2 - 10
    uc = kind.endswith("uc")
    if kind.startswith("dieresis"):
        y = 860 if uc else XH + 155
        for dx in (-110, 110) if uc else (-100, 100):
            g.dot(cx + dx, y, g.S * 0.6)
    else:
        y0 = 790 if uc else XH + 85
        w = g.S * 0.8
        if kind.startswith("acute"):
            g.diag((cx + 95, y0 + 150), (cx - 20, y0), w=w)
        else:
            g.diag((cx - 95, y0 + 150), (cx + 20, y0), w=w)


# ------------------------------------------------------------------ kerning
KERN = """
languagesystem DFLT dflt;
languagesystem latn dflt;
@round = [o e c d q g a s];
feature kern {
  pos A V -55; pos A W -40; pos A T -55; pos A Y -60; pos A v -30; pos A w -22; pos A y -30;
  pos V A -55; pos W A -40; pos T A -55; pos Y A -60; pos A quoteright -50; pos quoteleft A -50;
  pos T @round -60; pos T [r u v w y z] -45; pos T [period comma hyphen] -70;
  pos V @round -40; pos W @round -28; pos Y @round -60; pos Y [period comma] -70;
  pos V [period comma] -60; pos W [period comma] -40;
  pos L T -60; pos L V -55; pos L W -40; pos L Y -65; pos L quoteright -60;
  pos P A -45; pos P [period comma] -90; pos F [period comma] -70; pos F A -35;
  pos r [period comma] -45; pos [v w y] [period comma] -40;
  pos f quoteright 20; pos f f -5;
} kern;
"""


# ------------------------------------------------------------------ build
def build(weight, outdir, hint=True):
    S, ratio, wc = WEIGHTS[weight]
    pad = round((S - 84) * 0.28)  # extra side bearing for heavier weights
    outlines, advs, cmap = {}, {}, {}
    order = [".notdef"] + list(G.keys())

    def draw(name):
        uni, adv, case, fn = G[name]
        if adv is None:
            base = case
            p = draw(base)
            badv = advs[base]
            mg = Glyph(S, ratio, badv)
            marks(mg, badv, fn, base)
            advs[name] = badv
            return pathops.op(p, mg.outline(), pathops.PathOp.UNION, fix_winding=True)
        g = Glyph(S, ratio, adv)
        fn(g)
        advs[name] = adv
        return g.outline()

    for name in G:
        outlines[name] = draw(name)
        cmap[ord(G[name][0])] = name

    fb = FontBuilder(UPM, isTTF=True)
    fb.setupGlyphOrder(order)
    fb.setupCharacterMap(cmap)
    glyphs, metrics = {}, {}
    pen = TTGlyphPen(None)
    for (x0, y0, x1, y1), rev in (((60, 0, 460, CAP), False), ((110, 50, 410, CAP - 50), True)):
        pts = [(x0, y0), (x0, y1), (x1, y1), (x1, y0)]
        pts = pts[::-1] if rev else pts
        pen.moveTo(pts[0]); [pen.lineTo(p) for p in pts[1:]]; pen.closePath()
    glyphs[".notdef"] = pen.glyph()
    for name, path in outlines.items():
        glyphs[name] = to_ttglyph(path, dx=pad)
    fb.setupGlyf(glyphs)
    glyf = fb.font["glyf"]
    metrics[".notdef"] = (520, 60)
    for name in outlines:
        gl = glyf[name]
        gl.recalcBounds(glyf)
        metrics[name] = (advs[name] + 2 * pad, gl.xMin if gl.numberOfContours else 0)
    fb.setupHorizontalMetrics(metrics)
    fb.setupHorizontalHeader(ascent=950, descent=-250)
    ps = f"FranzSans-{weight}"
    fb.setupNameTable({
        "familyName": FAMILY if weight in ("Regular", "Bold") else f"{FAMILY} {weight}",
        "styleName": weight if weight in ("Regular", "Bold") else "Regular",
        "typographicFamily": FAMILY,
        "typographicSubfamily": weight,
        "uniqueFontIdentifier": f"{ps};1.000",
        "fullName": f"{FAMILY} {weight}",
        "psName": ps,
        "version": "Version 1.000",
        "copyright": "Copyright 2026 Franzwerk",
        "licenseDescription": "This Font Software is licensed under the SIL Open Font License, Version 1.1.",
        "licenseInfoURL": "https://openfontlicense.org",
    })
    fs = 0x20 if weight == "Bold" else 0x40
    fb.setupOS2(version=4, sTypoAscender=950, sTypoDescender=-250, sTypoLineGap=0, usWinAscent=1000,
                usWinDescent=300, sxHeight=XH, sCapHeight=CAP, usWeightClass=wc, fsSelection=fs | 0x80,
                achVendID="FRZW", fsType=0)
    fb.setupPost()
    fb.setupHead(unitsPerEm=UPM, fontRevision=1.0, created=timestampNow(), modified=timestampNow(),
                 macStyle=1 if weight == "Bold" else 0)
    addOpenTypeFeaturesFromString(fb.font, KERN)
    font = fb.font
    if hint:
        import ttfautohint
        buf = io.BytesIO()
        font.save(buf)
        data = ttfautohint.ttfautohint(in_buffer=buf.getvalue(), no_info=True, hinting_range_max=50,
                                       increase_x_height=14, windows_compatibility=True)
        font = TTFont(io.BytesIO(data))
    os.makedirs(outdir, exist_ok=True)
    ttf = os.path.join(outdir, ps + ".ttf")
    font.save(ttf)
    font.flavor = "woff2"
    font.save(os.path.join(outdir, ps + ".woff2"))
    print("wrote", ttf, len(order), "glyphs")


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.abspath(__file__)), "fonts")
    for w in WEIGHTS:
        build(w, out)
