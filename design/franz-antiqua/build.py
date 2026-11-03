#!/usr/bin/env python3
"""Franz Antiqua – a high-contrast Didone display face for the web.

The glyphs are drawn parametrically: every letter is a set of skeleton strokes
(lines, Bézier curves, elliptic arcs) that are expanded with a pointed-pen
model (vertical stress: vertical strokes thick, horizontal strokes hairline),
plus hairline serifs with small brackets and ball terminals.
All shapes are merged with skia-pathops and written as TTF + WOFF2.

    pip install fonttools skia-pathops brotli
    python3 build.py            # writes ./fonts/*.ttf, *.woff2
"""
import math
import os
import sys

import pathops
from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.pens.reverseContourPen import ReverseContourPen
from fontTools.feaLib.builder import addOpenTypeFeaturesFromString
from fontTools.misc.timeTools import timestampNow

FAMILY = "Franz Antiqua"
UPM = 1000
CAP, XH, ASC, DESC, OV = 700, 450, 740, -220, 12

WEIGHTS = {
    # name: (cap stem, lowercase stem, hairline, usWeightClass)
    "Light": (58, 54, 11, 300),
    "Regular": (90, 82, 17, 400),
}


def ss(x):
    x = max(0.0, min(1.0, x))
    return x * x * (3 - 2 * x)


# ---------------------------------------------------------------- primitives
class Stroke:
    """Polyline skeleton with per-point optional width cap."""

    def __init__(self, g, closed=False):
        self.g, self.pts, self.caps, self.closed = g, [], [], closed
        self.fixed = None  # fixed width

    def _add(self, p, cap):
        if self.pts and math.dist(self.pts[-1], p) < 0.5:
            return
        self.pts.append(p)
        self.caps.append(cap)

    def move(self, x, y):
        self._add((x, y), None)
        return self

    def line(self, x, y, cap=None, n=None):
        x0, y0 = self.pts[-1]
        n = n or max(2, int(math.dist((x0, y0), (x, y)) / 10))
        for i in range(1, n + 1):
            u = i / n
            self._add((x0 + (x - x0) * u, y0 + (y - y0) * u), cap(u) if cap else None)
        return self

    def curve(self, c1, c2, p, cap=None):
        p0 = self.pts[-1]
        L = math.dist(p0, c1) + math.dist(c1, c2) + math.dist(c2, p)
        n = max(6, int(L / 7))
        for i in range(1, n + 1):
            t = i / n
            a, b, c, d = (1 - t) ** 3, 3 * t * (1 - t) ** 2, 3 * t * t * (1 - t), t ** 3
            q = (a * p0[0] + b * c1[0] + c * c2[0] + d * p[0],
                 a * p0[1] + b * c1[1] + c * c2[1] + d * p[1])
            self._add(q, cap(t) if cap else None)
        return self

    def arc(self, cx, cy, rx, ry, a0, a1, cap=None):
        n = max(8, int(abs(a1 - a0) / 2.5))
        for i in range(0, n + 1):
            u = i / n
            a = math.radians(a0 + (a1 - a0) * u)
            self._add((cx + rx * math.cos(a), cy + ry * math.sin(a)), cap(u) if cap else None)
        return self

    def done(self):
        self.g.strokes.append(self)
        return self


def taper(a0=0.0, a1=0.0, lo=None):
    """Width cap that forces a hairline at the start (fraction a0) / end (a1)."""

    def f(u, lo=lo):
        k = 1.0
        if a0 > 0:
            k = min(k, ss(u / a0))
        if a1 > 0:
            k = min(k, ss((1 - u) / a1))
        return ("taper", k)

    return f


class Glyph:
    def __init__(self, S, s, T, adv):
        self.S0, self.s0, self.T = S, s, T
        self.S = S  # active thick
        self.adv = adv
        self.strokes, self.polys = [], []
        self.xf = None

    # -- width model (pointed pen, vertical stress)
    def autow(self, dx, dy):
        L = math.hypot(dx, dy) or 1
        sn = abs(dy) / L
        return self.T + (self.S - self.T) * sn ** 2.2

    def poly(self, pts):
        self.polys.append(list(pts))

    # -- convenience shapes
    def rect(self, x0, y0, x1, y1):
        self.poly([(x0, y0), (x1, y0), (x1, y1), (x0, y1)])

    def stem(self, x, y0, y1, w=None):
        w = w or self.S
        self.rect(x - w / 2, y0, x + w / 2, y1)

    def hbar(self, x0, x1, y, w=None):
        w = w or self.T
        self.rect(x0, y - w / 2, x1, y + w / 2)

    def dot(self, x, y, r):
        self.poly([(x + r * math.cos(a / 40 * 2 * math.pi), y + r * math.sin(a / 40 * 2 * math.pi))
                   for a in range(40)])

    def ball(self, x, y, r=None):
        self.dot(x, y, r or self.S * 0.56)

    def bracket(self, xe, y, side, up, b=None):
        """Concave fillet between a stem edge (xe) and a serif surface (y)."""
        b = b if b is not None else max(6, self.S * 0.22)
        sx, sy = (1 if side == "r" else -1), (1 if up else -1)
        cx, cy = xe + sx * b, y + sy * b
        pts = [(xe, y)]
        for i in range(0, 13):
            a = math.radians(180 + 90 * i / 12) if True else 0
            # quarter circle from (xe, cy) to (cx, y), concave toward the corner
            px = cx - sx * b * math.cos(math.radians(90 * i / 12))
            py = cy - sy * b * math.sin(math.radians(90 * i / 12))
            pts.append((px, py))
        self.poly(pts)

    def serif(self, x, y, l=None, r=None, w=None, top=False):
        """Hairline serif at a vertical stem centred at x, stem width w."""
        w = w or self.S
        T = self.T * 1.15
        e = self.S * 0.78 + 6
        l = e if l is None else l
        r = e if r is None else r
        yc = y - T / 2 if top else y + T / 2
        x0, x1 = x - w / 2 - l, x + w / 2 + r
        self.hbar(x0, x1, yc, T)
        surf = y - T if top else y + T
        if l > 0:
            self.bracket(x - w / 2, surf, "l", not top)
        if r > 0:
            self.bracket(x + w / 2, surf, "r", not top)

    def beak(self, x, y0, y1, w=None):
        """Vertical hairline-to-medium beak serif (arms of E, T, Z...)."""
        w = w or max(self.T * 1.5, self.S * 0.3)
        self.rect(x - w / 2, min(y0, y1), x + w / 2, max(y0, y1))

    def diag(self, top, bot, w=None, ref=("c", "c")):
        """Straight stroke cut horizontally at both ends.
        top=(x,y), bot=(x,y); ref says whether x is the left edge, centre or right edge."""
        (xt, yt), (xb, yb) = top, bot
        dx, dy = xt - xb, yt - yb
        if w is None:
            # Didone convention: \ strokes thick, / strokes hairline
            w = self.S if dx < 0 else self.T * 1.25
        h = w / 2 * math.hypot(dx, dy) / abs(dy)
        off = {"l": h, "c": 0, "r": -h}
        xt += off[ref[0]]
        xb += off[ref[1]]
        self.poly([(xt - h, yt), (xt + h, yt), (xb + h, yb), (xb - h, yb)])
        return lambda y: xb + (xt - xb) * (y - yb) / (yt - yb)

    def oval(self, l, r, b, t, a0=0, a1=360, cap=None):
        cx, cy = (l + r) / 2, (b + t) / 2
        rx, ry = (r - l) / 2 - self.S / 2, (t - b) / 2 - self.T / 2
        st = Stroke(self, closed=(a1 - a0 == 360))
        st.arc(cx, cy, rx, ry, a0, a1, cap)
        if st.closed:
            st.pts.pop()
            st.caps.pop()
        st.done()
        return cx, cy, rx, ry

    def path(self, x, y):
        return Stroke(self).move(x, y)

    # -- build outline
    def expand(self, st):
        pts, n = st.pts, len(st.pts)
        if n < 2:
            return []
        left, right = [], []
        for i in range(n):
            if st.closed:
                a, b = pts[i - 1], pts[(i + 1) % n]
            else:
                a, b = pts[max(0, i - 1)], pts[min(n - 1, i + 1)]
            dx, dy = b[0] - a[0], b[1] - a[1]
            L = math.hypot(dx, dy) or 1
            w = self.autow(dx, dy)
            c = st.caps[i]
            if c is not None:
                kind, k = c
                w = self.T + (w - self.T) * k
            nx, ny = -dy / L * w / 2, dx / L * w / 2
            left.append((pts[i][0] + nx, pts[i][1] + ny))
            right.append((pts[i][0] - nx, pts[i][1] - ny))
        if st.closed:
            return [left, right]
        return [left + right[::-1]]

    def outline(self):
        path = pathops.Path()
        polys = list(self.polys)
        for st in self.strokes:
            ring = self.expand(st)
            if st.closed and len(ring) == 2:
                outer, inner = ring
                if area(outer) < area(inner):
                    outer, inner = inner, outer
                polys.append(orient(outer, True))
                polys.append(("hole", orient(inner, False)))
            else:
                polys.extend(ring)
        for p in polys:
            hole = isinstance(p, tuple)
            pts = p[1] if hole else orient(p, True)
            if self.xf:
                pts = [self.xf(*q) for q in pts]
                if not hole:
                    pts = orient(pts, True)
                else:
                    pts = orient(pts, False)
            path.moveTo(*pts[0])
            for q in pts[1:]:
                path.lineTo(*q)
            path.close()
        path.fillType = pathops.FillType.WINDING
        path.simplify(fix_winding=True)
        return path


def area(p):
    return 0.5 * sum(p[i - 1][0] * p[i][1] - p[i][0] * p[i - 1][1] for i in range(len(p)))


def orient(p, ccw):
    return p if (area(p) > 0) == ccw else p[::-1]


# ------------------------------------------------------------------ glyphs
G = {}


def glyph(name, uni, adv, case="lc"):
    def deco(fn):
        G[name] = (uni, adv, case, fn)
        return fn

    return deco


def comp(name, uni, base, marks):
    G[name] = (uni, None, base, marks)


# ---------- capitals
@glyph("I", "I", 310, "uc")
def _I(g):
    g.stem(155, 0, CAP); g.serif(155, 0); g.serif(155, CAP, top=True)


@glyph("H", "H", 770, "uc")
def _H(g):
    for x in (145, 625):
        g.stem(x, 0, CAP); g.serif(x, 0); g.serif(x, CAP, top=True)
    g.hbar(145, 625, 372)


@glyph("E", "E", 610, "uc")
def _E(g):
    x = 135
    g.stem(x, 0, CAP); g.serif(x, 0, r=0); g.serif(x, CAP, r=0, top=True)
    g.hbar(x, 530, CAP - g.T / 2); g.beak(522, CAP, 545)
    g.hbar(x, 475, 372); g.beak(470, 300, 440, g.T * 1.4)
    g.hbar(x, 550, g.T / 2); g.beak(543, 0, 175)


@glyph("F", "F", 570, "uc")
def _F(g):
    x = 135
    g.stem(x, 0, CAP); g.serif(x, 0, r=g.S * 0.9); g.serif(x, CAP, r=0, top=True)
    g.hbar(x, 520, CAP - g.T / 2); g.beak(512, CAP, 545)
    g.hbar(x, 460, 362); g.beak(455, 290, 430, g.T * 1.4)


@glyph("L", "L", 570, "uc")
def _L(g):
    x = 135
    g.stem(x, 0, CAP); g.serif(x, CAP, top=True); g.serif(x, 0, r=0)
    g.hbar(x, 535, g.T / 2); g.beak(528, 0, 185)


@glyph("T", "T", 630, "uc")
def _T(g):
    g.hbar(55, 575, CAP - g.T / 2); g.beak(62, CAP, 540); g.beak(568, CAP, 540)
    g.stem(315, 0, CAP); g.serif(315, 0)


@glyph("O", "O", 770, "uc")
def _O(g):
    g.oval(45, 725, -OV, CAP + OV)


@glyph("Q", "Q", 770, "uc")
def _Q(g):
    g.oval(45, 725, -OV, CAP + OV)
    p = g.path(330, 30)
    p.curve((420, -40), (520, -110), (690, -150), cap=taper(0.25, 0.2)).done()


@glyph("C", "C", 690, "uc")
def _C(g):
    cx, cy, rx, ry = g.oval(45, 690, -OV, CAP + OV, 42, 318)
    for a, y0, y1 in ((42, CAP, 480), (318, 0, 220)):
        x = cx + rx * math.cos(math.radians(a)) + g.T
        g.beak(x, y0, y1, g.S * 0.42)


@glyph("G", "G", 750, "uc")
def _G(g):
    cx, cy, rx, ry = g.oval(45, 700, -OV, CAP + OV, 42, 340)
    x = cx + rx * math.cos(math.radians(42)) + g.T
    g.beak(x, CAP, 480, g.S * 0.42)
    sx = cx + rx
    g.stem(sx, 20, 300)
    g.serif(sx, 300, l=g.S * 0.9, r=g.S * 0.5, top=True)


@glyph("D", "D", 750, "uc")
def _D(g):
    x = 135
    g.stem(x, 0, CAP); g.serif(x, 0, r=0); g.serif(x, CAP, r=0, top=True)
    rx = 705 - g.S / 2 - 370
    p = g.path(x, CAP - g.T / 2).line(370, CAP - g.T / 2)
    p.arc(370, CAP / 2, rx, CAP / 2 - g.T / 2, 90, -90).line(x, g.T / 2).done()


@glyph("B", "B", 660, "uc")
def _B(g):
    x = 135
    g.stem(x, 0, CAP); g.serif(x, 0, r=0); g.serif(x, CAP, r=0, top=True)
    T = g.T
    ym = 385
    p = g.path(x, CAP - T / 2).line(345, CAP - T / 2)
    p.arc(345, (CAP - T / 2 + ym) / 2, 555 - g.S / 2 - 345, (CAP - T / 2 - ym) / 2, 90, -90).line(x, ym).done()
    p = g.path(x, ym).line(355, ym)
    p.arc(355, (ym + T / 2) / 2, 600 - g.S / 2 - 355, (ym - T / 2) / 2, 90, -90).line(x, T / 2).done()


@glyph("P", "P", 630, "uc")
def _P(g):
    x = 135
    g.stem(x, 0, CAP); g.serif(x, 0); g.serif(x, CAP, r=0, top=True)
    T, ym = g.T, 320
    p = g.path(x, CAP - T / 2).line(350, CAP - T / 2)
    p.arc(350, (CAP - T / 2 + ym) / 2, 590 - g.S / 2 - 350, (CAP - T / 2 - ym) / 2, 90, -90).line(x, ym).done()


@glyph("R", "R", 690, "uc")
def _R(g):
    x = 135
    g.stem(x, 0, CAP); g.serif(x, 0); g.serif(x, CAP, r=0, top=True)
    T, ym = g.T, 345
    p = g.path(x, CAP - T / 2).line(345, CAP - T / 2)
    p.arc(345, (CAP - T / 2 + ym) / 2, 585 - g.S / 2 - 345, (CAP - T / 2 - ym) / 2, 90, -90).line(x, ym).done()
    g.diag((345, ym + 5), (565, 0), w=g.S * 0.95)
    g.serif(565 + g.S * 0.3, 0, l=10, r=g.S * 0.55, w=g.S * 0.5)


@glyph("K", "K", 700, "uc")
def _K(g):
    x = 135
    g.stem(x, 0, CAP); g.serif(x, 0); g.serif(x, CAP, top=True)
    g.diag((585, CAP), (x + g.S / 2, 230), ref=("c", "l"))
    g.serif(585, CAP, l=g.S * 0.5, r=g.S * 0.5, w=g.T, top=True)
    g.diag((300, 445), (605, 0))
    g.serif(605, 0, l=g.S * 0.55, r=g.S * 0.55, w=g.S * 0.7)


@glyph("M", "M", 900, "uc")
def _M(g):
    T = g.T * 1.25
    g.stem(115, 0, CAP, T); g.serif(115, 0, w=T); g.serif(115, CAP, r=0, w=T, top=True)
    g.diag((115, CAP), (450, 0), ref=("l", "c"))
    g.diag((785, CAP), (450, 0), ref=("l", "c"))
    g.stem(785, 0, CAP); g.serif(785, 0); g.serif(785, CAP, l=0, top=True)


@glyph("N", "N", 770, "uc")
def _N(g):
    T = g.T * 1.25
    g.stem(125, 0, CAP, T); g.serif(125, 0, w=T); g.serif(125, CAP, r=0, w=T, top=True)
    g.diag((125, CAP), (645, 0), ref=("l", "r"))
    g.stem(645, 0, CAP, T); g.serif(645, CAP, w=T, top=True)


@glyph("U", "U", 750, "uc")
def _U(g):
    T = g.T * 1.25
    xl, xr, yb = 135, 615, 250
    p = g.path(xl, CAP).line(xl, yb)
    p.arc((xl + xr) / 2, yb, (xr - xl) / 2, yb - g.T / 2 + OV, 180, 360, cap=lambda u: ("taper", ss((1 - u) / 0.45)))
    p.done()
    g.stem(xr, yb - 5, CAP, T)
    g.serif(xl, CAP, top=True); g.serif(xr, CAP, w=T, top=True)


@glyph("V", "V", 710, "uc")
def _V(g):
    g.diag((95, CAP), (355, -5), ref=("c", "c"))
    g.diag((615, CAP), (355, -5), ref=("c", "r"))
    g.serif(95, CAP, top=True); g.serif(615, CAP, w=g.T, top=True)


@glyph("W", "W", 1000, "uc")
def _W(g):
    g.diag((80, CAP), (300, -5)); g.diag((500, CAP), (300, -5), ref=("c", "r"))
    g.diag((500, CAP), (720, -5)); g.diag((920, CAP), (720, -5), ref=("c", "r"))
    g.serif(80, CAP, top=True); g.serif(920, CAP, w=g.T, top=True)
    g.serif(500, CAP, w=g.T, top=True)


@glyph("X", "X", 710, "uc")
def _X(g):
    g.diag((115, CAP), (595, 0)); g.diag((595, CAP), (115, 0))
    for x in (115, 595):
        g.serif(x, CAP, w=g.S * 0.6, top=True); g.serif(x, 0, w=g.S * 0.6)


@glyph("Y", "Y", 690, "uc")
def _Y(g):
    f = g.diag((100, CAP), (345, 330)); g.diag((590, CAP), (345, 330))
    g.stem(345, 0, 345); g.serif(345, 0)
    g.serif(100, CAP, top=True); g.serif(590, CAP, w=g.T, top=True)


@glyph("Z", "Z", 630, "uc")
def _Z(g):
    g.hbar(85, 545, CAP - g.T / 2); g.beak(92, CAP, 545)
    g.diag((545, CAP), (85, 0), w=g.S, ref=("r", "l"))
    g.hbar(85, 565, g.T / 2); g.beak(558, 0, 185)


@glyph("J", "J", 430, "uc")
def _J(g):
    x = 285
    p = g.path(x, CAP).line(x, 170)
    p.arc(x - 115, 170, 115, 170 - g.T / 2 + OV, 0, -150, cap=taper(0, 0.3)).done()
    g.ball(x - 205, 95, g.S * 0.5)
    g.serif(x, CAP, top=True)


@glyph("S", "S", 580, "uc")
def _S(g):
    draw_s(g, 55, 525, CAP, g.S)


def draw_s(g, x0, x1, h, S):
    W, T = x1 - x0, g.T
    X = lambda u: x0 + u * W
    Y = lambda v: v * h
    top, bot = h + OV - T / 2, -OV + T / 2
    p = g.path(X(0.88), Y(0.90))
    p.curve((X(0.80), Y(0.99)), (X(0.66), top), (X(0.50), top))
    p.curve((X(0.25), top), (X(S / 2 / W + 0.03), Y(0.88)), (X(S / 2 / W + 0.03), Y(0.74)))
    p.curve((X(S / 2 / W + 0.03), Y(0.55)), (X(0.40), Y(0.52)), (X(0.55), Y(0.46)))
    p.curve((X(0.80), Y(0.37)), (X(1 - S / 2 / W), Y(0.33)), (X(1 - S / 2 / W), Y(0.22)))
    p.curve((X(1 - S / 2 / W), Y(0.06)), (X(0.75), bot), (X(0.50), bot))
    p.curve((X(0.30), bot), (X(0.16), Y(0.03)), (X(0.08), Y(0.13))).done()
    bw = max(T * 1.6, S * 0.34)
    g.beak(X(0.88) + bw * 0.1, Y(1.0), Y(0.76), bw)
    g.beak(X(0.08) + bw * 0.3, Y(0.0), Y(0.26), bw)


# ---------- figures (lining, tabular 570)
FW = 570


@glyph("zero", "0", FW, "uc")
def _0(g):
    g.oval(55, 515, -OV, CAP + OV)


@glyph("one", "1", FW, "uc")
def _1(g):
    g.stem(300, 0, CAP); g.serif(300, 0, l=95, r=95)
    g.diag((300 - g.S / 2 + 6, CAP), (150, 545), w=g.T * 1.4, ref=("c", "l"))


@glyph("two", "2", FW, "uc")
def _2(g):
    T = g.T
    p = g.path(120, 560)
    p.curve((135, 650), (205, CAP + OV - T / 2), (285, CAP + OV - T / 2))
    p.curve((395, CAP + OV - T / 2), (470, 625), (470, 520))
    p.curve((470, 380), (330, 280), (95, 8), cap=lambda u: ("taper", 1.0)).done()
    g.ball(135, 545)
    g.hbar(85, 495, T * 0.75, T * 1.5); g.beak(488, 0, 160)


@glyph("three", "3", FW, "uc")
def _3(g):
    T = g.T
    p = g.path(125, 575)
    p.curve((150, 660), (210, CAP + OV - T / 2), (285, CAP + OV - T / 2))
    p.curve((390, CAP + OV - T / 2), (445, 630), (445, 545))
    p.curve((445, 450), (375, 400), (250, 400)).done()
    p = g.path(250, 400)
    p.curve((400, 400), (480, 320), (480, 205))
    p.curve((480, 75), (385, -OV + T / 2), (275, -OV + T / 2))
    p.curve((175, -OV + T / 2), (105, 50), (90, 140)).done()
    g.ball(135, 565); g.ball(120, 130)


@glyph("four", "4", FW, "uc")
def _4(g):
    g.stem(395, 0, CAP); g.serif(395, 0, l=60, r=60)
    g.diag((395 - g.S / 2 + 4, CAP), (60, 215), w=g.T * 1.4, ref=("c", "l"))
    g.hbar(60, 515, 215 + g.T * 0.6, g.T * 1.2)


@glyph("five", "5", FW, "uc")
def _5(g):
    T = g.T
    g.hbar(150, 470, CAP - T / 2, T * 1.3)
    g.diag((155, CAP), (140, 380), w=g.S * 0.42)
    p = g.path(140, 385)
    p.curve((200, 430), (250, 445), (295, 445))
    p.curve((420, 445), (485, 360), (485, 230))
    p.curve((485, 85), (390, -OV + T / 2), (275, -OV + T / 2))
    p.curve((175, -OV + T / 2), (105, 50), (90, 140)).done()
    g.ball(120, 130)


@glyph("six", "6", FW, "uc")
def _6(g):
    g.oval(60, 510, -OV, 450)
    p = g.path(60 + g.S / 2, 220)
    p.curve((60 + g.S / 2, 520), (170, CAP + OV - g.T / 2), (320, CAP + OV - g.T / 2))
    p.curve((380, CAP + OV - g.T / 2), (420, 690), (440, 660), cap=taper(0, 0.3)).done()
    g.ball(425, 620)


@glyph("nine", "9", FW, "uc")
def _9(g):
    _6(g)
    g.xf = lambda x, y: (FW - x, CAP - y)


@glyph("seven", "7", FW, "uc")
def _7(g):
    g.hbar(75, 505, CAP - g.T * 0.7, g.T * 1.4); g.beak(82, CAP, 540)
    p = g.path(505, CAP - 10)
    p.curve((400, 520), (300, 300), (270, 0)).done()


@glyph("eight", "8", FW, "uc")
def _8(g):
    g.oval(105, 465, 372, CAP + OV)
    g.oval(70, 500, -OV, 395)


# ---------- lowercase
LS = None  # stem width marker


def lstem(g, x, y0, y1, flag=True, foot=True, foot_l=None, foot_r=None):
    g.stem(x, y0, y1)
    if flag:
        g.serif(x, y1, r=0, l=g.S * 0.75, top=True)
    if foot:
        g.serif(x, y0, l=foot_l, r=foot_r)


def arch(g, xl, xr, y=XH):
    T = g.T
    top = y + OV - T / 2
    p = g.path(xl + 2, y - 120)
    p.curve((xl + 30, y - 30), (xl + 90, top), ((xl + xr) / 2 + 15, top), cap=lambda u: ("taper", 0.0))
    p.curve((xr - 30, top), (xr, y - 50), (xr, y - 140)).line(xr, 0).done()


@glyph("l", "l", 270, "lc")
def _l(g):
    lstem(g, 135, 0, ASC)


@glyph("i", "i", 270, "lc")
def _i(g):
    lstem(g, 135, 0, XH); g.ball(135, 625, g.S * 0.6)


@glyph("dotlessi", "ı", 270, "lc")
def _dotlessi(g):
    lstem(g, 135, 0, XH)


@glyph("j", "j", 270, "lc")
def _j(g):
    x = 150
    g.serif(x, XH, r=0, l=g.S * 0.75, top=True)
    p = g.path(x, XH).line(x, -90)
    p.arc(x - 95, -90, 95, 130 - g.T / 2 + OV, 0, -140, cap=taper(0, 0.35)).done()
    g.ball(x - 165, -150, g.S * 0.5)
    g.ball(x, 625, g.S * 0.6)


@glyph("h", "h", 550, "lc")
def _h(g):
    lstem(g, 115, 0, ASC)
    arch(g, 115, 435); g.serif(435, 0)


@glyph("n", "n", 550, "lc")
def _n(g):
    lstem(g, 115, 0, XH)
    arch(g, 115, 435); g.serif(435, 0)


@glyph("m", "m", 840, "lc")
def _m(g):
    lstem(g, 115, 0, XH)
    arch(g, 115, 425); g.serif(425, 0)
    arch(g, 425, 725); g.serif(725, 0)


@glyph("u", "u", 550, "lc")
def _u(g):
    T = g.T
    xl, xr = 115, 435
    g.serif(xl, XH, r=0, l=g.S * 0.75, top=True)
    p = g.path(xl, XH).line(xl, 140)
    p.curve((xl, 40), (190, -OV + T / 2), (270, -OV + T / 2))
    p.curve((350, -OV + T / 2), (400, 40), (xr - 2, 120), cap=lambda u: ("taper", 0.0)).done()
    lstem(g, xr, 0, XH, foot_l=0)


@glyph("r", "r", 390, "lc")
def _r(g):
    lstem(g, 115, 0, XH, foot_r=g.S * 0.9)
    T = g.T
    p = g.path(117, 330)
    p.curve((145, 410), (200, XH + OV - T / 2), (265, XH + OV - T / 2), cap=lambda u: ("taper", 0.0))
    p.curve((305, XH + OV - T / 2), (330, 445), (345, 425), cap=taper(0, 0.5)).done()
    g.ball(318, 392, g.S * 0.55)


def bowl_right(g, xs, xr, b=-OV, t=XH + OV):
    """Bowl attached on the right side of a stem at xs (b, p)."""
    cx = (xs + xr) / 2 - 10
    rx = xr - g.S / 2 - cx
    ry = (t - b) / 2 - g.T / 2
    cy = (t + b) / 2
    g.path(xs, cy + ry * 0.62).arc(cx, cy, rx, ry, 128, -128, cap=taper(0.18, 0.18)).done()


@glyph("b", "b", 560, "lc")
def _b(g):
    lstem(g, 115, 0, ASC, foot=False)
    bowl_right(g, 115, 515)


@glyph("p", "p", 560, "lc")
def _p(g):
    lstem(g, 115, DESC, XH)
    bowl_right(g, 115, 515)


@glyph("d", "d", 560, "lc")
def _d(g):
    # drawn as a mirrored b; flag and foot serif are placed so they land correctly
    g.stem(115, 0, ASC)
    g.serif(115, ASC, l=0, r=g.S * 0.75, top=True)
    g.serif(115, 0, r=0)
    bowl_right(g, 115, 515)
    g.xf = lambda x, y: (560 - x, y)


@glyph("q", "q", 560, "lc")
def _q(g):
    g.stem(115, DESC, XH); g.serif(115, DESC)
    bowl_right(g, 115, 515)
    g.xf = lambda x, y: (560 - x, y)


@glyph("o", "o", 530, "lc")
def _o(g):
    g.oval(40, 490, -OV, XH + OV)


@glyph("c", "c", 470, "lc")
def _c(g):
    cx, cy, rx, ry = g.oval(40, 450, -OV, XH + OV, 30, 322, cap=taper(0.12, 0))
    a = math.radians(30)
    g.ball(cx + rx * math.cos(a) - g.S * 0.42, cy + ry * math.sin(a) - g.S * 0.2, g.S * 0.55)


@glyph("e", "e", 490, "lc")
def _e(g):
    l, r = 40, 460
    cx, cy = (l + r) / 2, XH / 2
    rx, ry = (r - l) / 2 - g.S / 2, (XH + 2 * OV) / 2 - g.T / 2
    yb = 255
    a0 = math.degrees(math.asin((yb - cy) / ry))
    xr = cx + rx * math.cos(math.radians(a0))
    g.hbar(l + 10, xr + g.T, yb, g.T * 1.1)
    g.path(xr, yb).arc(cx, cy, rx, ry, a0, 322, cap=taper(0, 0.12)).done()


@glyph("a", "a", 510, "lc")
def _a(g):
    T = g.T
    xs = 400
    top = XH + OV - T / 2
    p = g.path(95, 375)
    p.curve((120, 435), (180, top), (245, top), cap=taper(0.4, 0))
    p.curve((350, top), (xs, 410), (xs, 320)).line(xs, 70)
    p.curve((xs, 25), (420, 5), (470, 20), cap=taper(0, 0.6)).done()
    g.ball(118, 365, g.S * 0.55)
    p = g.path(xs, 265)
    p.curve((300, 245), (65, 225), (65, 105), cap=taper(0.3, 0))
    p.curve((65, 30), (115, -OV + T / 2), (185, -OV + T / 2))
    p.curve((270, -OV + T / 2), (350, 30), (xs - 2, 100), cap=taper(0, 0.4)).done()


@glyph("g", "g", 520, "lc")
def _g(g):
    xs = 410
    T = g.T
    g.serif(xs, XH, l=0, r=g.S * 0.7, top=True)
    p = g.path(xs, XH).line(xs, -60)
    p.curve((xs, -170), (340, DESC + 5), (230, DESC + 5))
    p.curve((160, DESC + 5), (110, -195), (95, -165), cap=taper(0, 0.4)).done()
    g.ball(125, -150, g.S * 0.55)
    bowl = Glyph(g.S, g.s0, T, 0)
    g.path(xs, 330).arc((40 + xs) / 2 + 10, 225, (xs - 40) / 2 + 10 - g.S / 2 - 0, 235 - T / 2, 52, 308,
                        cap=taper(0.18, 0.18)).done()


@glyph("f", "f", 340, "lc")
def _f(g):
    T = g.T
    x = 145
    g.stem(x, 0, 560); g.serif(x, 0, r=g.S * 0.9)
    p = g.path(x, 540)
    p.curve((x, 670), (210, ASC + OV - T / 2), (290, ASC + OV - T / 2))
    p.curve((335, ASC + OV - T / 2), (365, 735), (380, 715), cap=taper(0, 0.5)).done()
    g.ball(352, 685, g.S * 0.52)
    g.hbar(50, 290, XH - T * 0.6, T * 1.2)


@glyph("t", "t", 350, "lc")
def _t(g):
    T = g.T
    x = 130
    p = g.path(x, 600).line(x, 110)
    p.curve((x, 35), (175, -OV + T / 2), (235, -OV + T / 2))
    p.curve((280, -OV + T / 2), (310, 15), (330, 55), cap=taper(0, 0.5)).done()
    g.diag((x + g.S / 2, 600), (x - g.S / 2 - 25, 470), w=g.T * 1.3, ref=("l", "l"))
    g.hbar(40, 290, XH - T * 0.6, T * 1.2)


@glyph("k", "k", 500, "lc")
def _k(g):
    lstem(g, 115, 0, ASC)
    g.diag((410, XH), (115 + g.S / 2, 150), ref=("c", "l"))
    g.serif(410, XH, l=g.S * 0.55, r=g.S * 0.45, w=g.T, top=True)
    g.diag((245, 285), (440, 0))
    g.serif(440, 0, l=g.S * 0.45, r=g.S * 0.45, w=g.S * 0.7)


@glyph("v", "v", 490, "lc")
def _v(g):
    g.diag((65, XH), (245, -5)); g.diag((425, XH), (245, -5), ref=("c", "r"))
    g.serif(65, XH, top=True); g.serif(425, XH, w=g.T, top=True)


@glyph("w", "w", 750, "lc")
def _w(g):
    g.diag((55, XH), (215, -5)); g.diag((375, XH), (215, -5), ref=("c", "r"))
    g.diag((375, XH), (535, -5)); g.diag((695, XH), (535, -5), ref=("c", "r"))
    g.serif(55, XH, top=True); g.serif(695, XH, w=g.T, top=True)
    g.serif(375, XH, w=g.T, top=True)


@glyph("x", "x", 480, "lc")
def _x(g):
    g.diag((80, XH), (405, 0)); g.diag((405, XH), (80, 0))
    for x in (80, 405):
        g.serif(x, XH, w=g.S * 0.5, top=True); g.serif(x, 0, w=g.S * 0.5)


@glyph("y", "y", 500, "lc")
def _y(g):
    g.diag((65, XH), (255, 0)); g.serif(65, XH, top=True)
    g.serif(440, XH, w=g.T, top=True)
    p = g.path(440, XH).line(200, -130)
    p.curve((175, -185), (150, -205), (110, -205)).done()
    g.ball(95, -178, g.S * 0.52)


@glyph("z", "z", 470, "lc")
def _z(g):
    g.hbar(65, 405, XH - g.T / 2); g.beak(72, XH, 345)
    g.diag((405, XH), (65, 0), w=g.S, ref=("r", "l"))
    g.hbar(65, 425, g.T / 2); g.beak(418, 0, 120)


@glyph("s", "s", 430, "lc")
def _s(g):
    draw_s(g, 45, 390, XH, g.S)


@glyph("germandbls", "ß", 560, "lc")
def _ss(g):
    T = g.T
    x = 115
    g.stem(x, 0, 560); g.serif(x, 0, r=0)
    p = g.path(x, 540)
    p.curve((x, 680), (195, ASC + OV - T / 2), (285, ASC + OV - T / 2))
    p.curve((385, ASC + OV - T / 2), (435, 670), (435, 600))
    p.curve((435, 515), (375, 470), (280, 470)).done()
    p = g.path(280, 470)
    p.curve((420, 470), (495, 380), (495, 245))
    p.curve((495, 90), (410, -OV + T / 2), (305, -OV + T / 2))
    p.curve((260, -OV + T / 2), (235, -5), (220, 10), cap=taper(0, 0.4)).done()
    g.ball(248, 48, g.S * 0.5)


# ---------- punctuation
@glyph("space", " ", 250, "lc")
def _space(g):
    pass


@glyph("period", ".", 250, "uc")
def _period(g):
    g.dot(125, 52, 52)


@glyph("comma", ",", 250, "uc")
def comma(g, x=125, y=52):
    g.dot(x, y, 52)
    p = g.path(x + 40, y + 10)
    p.curve((x + 50, y - 60), (x - 10, y - 140), (x - 45, y - 170), cap=taper(0, 0.8)).done()


@glyph("colon", ":", 250, "uc")
def _colon(g):
    g.dot(125, 52, 52); g.dot(125, XH - 52, 52)


@glyph("semicolon", ";", 250, "uc")
def _semicolon(g):
    comma(g); g.dot(125, XH - 52, 52)


@glyph("exclam", "!", 270, "uc")
def _exclam(g):
    g.dot(135, 52, 52)
    g.poly([(135 - g.S * 0.55, CAP), (135 + g.S * 0.55, CAP), (135 + g.T * 0.6, 200), (135 - g.T * 0.6, 200)])


@glyph("question", "?", 470, "uc")
def _question(g):
    T = g.T
    g.dot(230, 52, 52)
    p = g.path(85, 565)
    p.curve((105, 655), (170, CAP + OV - T / 2), (240, CAP + OV - T / 2))
    p.curve((350, CAP + OV - T / 2), (410, 630), (410, 545))
    p.curve((410, 420), (230, 380), (230, 200), cap=taper(0, 0.2)).done()
    g.ball(105, 545, g.S * 0.5)


@glyph("hyphen", "-", 330, "uc")
def _hyphen(g):
    g.hbar(55, 275, 255, g.S * 0.45)


@glyph("endash", "–", 500, "uc")
def _endash(g):
    g.hbar(0, 500, 255, g.T * 1.4)


@glyph("emdash", "—", 1000, "uc")
def _emdash(g):
    g.hbar(0, 1000, 255, g.T * 1.4)


@glyph("slash", "/", 380, "uc")
def _slash(g):
    g.diag((350, ASC), (30, -120), w=g.T * 1.6)


def paren(g, x, flip):
    p = g.path(x + 120, ASC + 20)
    p.curve((x - 40, 560), (x - 40, 0), (x + 120, -170)).done()
    if flip:
        g.xf = lambda a, b: (g.adv - a, b)


@glyph("parenleft", "(", 300, "uc")
def _pl(g):
    g.S *= 0.85; paren(g, 95, False)


@glyph("parenright", ")", 300, "uc")
def _pr(g):
    g.S *= 0.85; paren(g, 95, True)


def quote(g, x, y, down):
    g.dot(x, y, 42)
    p = g.path(x - 32, y + 10)
    p.curve((x - 40, y + 60), (x, y + 120), (x + 30, y + 140), cap=taper(0, 0.8)).done()


@glyph("quoteleft", "‘", 230, "uc")
def _ql(g):
    g.S *= 0.85; quote(g, 115, 590, False)


@glyph("quoteright", "’", 230, "uc")
def _qr(g):
    g.S *= 0.85; quote(g, 115, 590, False)
    g.xf = lambda x, y: (230 - x, 590 * 2 + 50 - y)


@glyph("quotesingle", "'", 210, "uc")
def _qs(g):
    g.poly([(105 - 30, CAP + 20), (105 + 30, CAP + 20), (105 + 8, 470), (105 - 8, 470)])


@glyph("quotedbl", '"', 330, "uc")
def _qd(g):
    for x in (105, 225):
        g.poly([(x - 30, CAP + 20), (x + 30, CAP + 20), (x + 8, 470), (x - 8, 470)])


@glyph("quotedblleft", "“", 380, "uc")
def _qdl(g):
    g.S *= 0.85; quote(g, 115, 590, False); quote(g, 265, 590, False)


@glyph("quotedblright", "”", 380, "uc")
def _qdr(g):
    g.S *= 0.85; quote(g, 115, 590, False); quote(g, 265, 590, False)
    g.xf = lambda x, y: (380 - x, 590 * 2 + 50 - y)


@glyph("quotedblbase", "„", 380, "uc")
def _qdb(g):
    g.S *= 0.85; quote(g, 115, 590, False); quote(g, 265, 590, False)
    g.xf = lambda x, y: (380 - x, 590 * 2 + 50 - y - 640)


@glyph("ampersand", "&", 760, "uc")
def _amp(g):
    T = g.T
    # upper loop
    p = g.path(330, 380)
    p.curve((230, 450), (180, 510), (180, 580))
    p.curve((180, 660), (240, CAP + OV - T / 2), (310, CAP + OV - T / 2))
    p.curve((380, CAP + OV - T / 2), (430, 660), (430, 600))
    p.curve((430, 520), (360, 470), (280, 420))
    # diagonal down to the right tail
    p.curve((150, 340), (70, 280), (70, 175))
    p.curve((70, 70), (160, -OV + T / 2), (270, -OV + T / 2))
    p.curve((420, -OV + T / 2), (560, 120), (620, 330), cap=taper(0, 0.25)).done()
    g.diag((290, 410), (600, 0), w=g.S * 0.95)
    g.serif(600, 0, l=g.S * 0.5, r=g.S * 0.5, w=g.S * 0.7)
    g.serif(625, 340, l=g.S * 0.6, r=g.S * 0.9, w=g.T, top=True)


@glyph("plus", "+", 560, "uc")
def _plus(g):
    g.hbar(70, 490, 320, g.T * 1.4); g.stem(280, 110, 530, g.T * 1.4)


@glyph("equal", "=", 560, "uc")
def _eq(g):
    g.hbar(70, 490, 400, g.T * 1.4); g.hbar(70, 490, 240, g.T * 1.4)


@glyph("periodcentered", "·", 250, "uc")
def _mid(g):
    g.dot(125, 320, 48)


@glyph("asterisk", "*", 430, "uc")
def _ast(g):
    for a in (90, 162, 234, 306, 18):
        r = math.radians(a)
        cx, cy = 215, 560
        g.path(cx, cy).line(cx + 120 * math.cos(r), cy + 120 * math.sin(r),
                            cap=lambda u: ("taper", 0.2 + 0.8 * u)).done()


@glyph("Euro", "€", FW, "uc")
def _euro(g):
    g.S *= 0.9
    cx, cy, rx, ry = g.oval(55, 540, -OV, CAP + OV, 45, 315)
    g.hbar(15, 360, 420, g.T * 1.3); g.hbar(15, 340, 285, g.T * 1.3)


# composites: base + marks
comp("Adieresis", "Ä", "A", "dieresis_uc")
comp("Odieresis", "Ö", "O", "dieresis_uc")
comp("Udieresis", "Ü", "U", "dieresis_uc")
comp("adieresis", "ä", "a", "dieresis")
comp("odieresis", "ö", "o", "dieresis")
comp("udieresis", "ü", "u", "dieresis")
comp("eacute", "é", "e", "acute")
comp("egrave", "è", "e", "grave")
comp("agrave", "à", "a", "grave")
comp("Eacute", "É", "E", "acute_uc")


@glyph("A", "A", 710, "uc")
def _A(g):
    thin = g.diag((352, CAP + 8), (100, 0), ref=("l", "c"))
    thick = g.diag((352, CAP + 8), (612, 0), ref=("l", "c"))
    g.hbar(thin(235), thick(235), 235 + g.T * 0.1, g.T * 1.1)
    g.serif(100, 0, w=g.T * 1.4, l=48, r=48)
    g.serif(612, 0, w=g.S * 0.8, l=50, r=50)


def marks(g, base_adv, kind):
    cx = base_adv / 2
    if kind.startswith("dieresis"):
        y = 825 if kind.endswith("uc") else 600
        for dx in (-95, 95):
            g.dot(cx + dx, y, g.S * 0.5)
    else:
        y0 = 800 if kind.endswith("uc") else 530
        if kind.startswith("acute"):
            g.diag((cx + 90, y0 + 150), (cx - 20, y0), w=g.S * 0.5, ref=("c", "c"))
        else:
            g.poly([(cx - 90 - 30, y0 + 150), (cx - 90 + 35, y0 + 150), (cx + 30, y0), (cx + 18, y0)])


# ------------------------------------------------------------------ kerning
KERN = """
languagesystem DFLT dflt;
languagesystem latn dflt;
feature kern {
  pos A V -70; pos A W -55; pos A T -55; pos A Y -60; pos A v -40; pos A w -35; pos A y -35;
  pos V A -70; pos W A -55; pos T A -55; pos Y A -60;
  pos T a -70; pos T e -70; pos T o -70; pos T r -45; pos T u -45; pos T y -45; pos T period -80; pos T comma -80;
  pos V a -55; pos V e -55; pos V o -55; pos W a -40; pos W e -40; pos W o -40;
  pos Y a -70; pos Y e -70; pos Y o -70;
  pos L T -60; pos L V -70; pos L W -55; pos L Y -70; pos P A -50; pos P period -100; pos P comma -100;
  pos F a -35; pos F e -35; pos F o -35; pos F period -80; pos F comma -80;
  pos r period -60; pos r comma -60; pos v period -50; pos w period -40; pos y period -50;
  pos f f 20; pos f quoteright 40; pos quoteleft A -60; pos A quoteright -60;
} kern;
"""


# ------------------------------------------------------------------ build
def build(weight, outdir):
    S, s, T, wc = WEIGHTS[weight]
    outlines, advs, cmap = {}, {}, {}
    order = [".notdef"] + list(G.keys())

    def draw(name):
        uni, adv, case, fn = G[name]
        if adv is None:  # composite
            base = case
            g = draw(base)
            badv = advs[base]
            mg = Glyph(S if name[0].isupper() else s, s, T, badv)
            marks(mg, badv, fn)
            p = g.outline() if isinstance(g, Glyph) else g
            p2 = pathops.op(p, mg.outline(), pathops.PathOp.UNION, fix_winding=True)
            advs[name] = badv
            return p2
        g = Glyph(S if case == "uc" else s, s, T, adv)
        fn(g)
        advs[name] = adv
        return g.outline()

    for name in G:
        outlines[name] = draw(name)
        uni = G[name][0]
        cmap[ord(uni)] = name

    fb = FontBuilder(UPM, isTTF=True)
    fb.setupGlyphOrder(order)
    fb.setupCharacterMap(cmap)
    glyphs, metrics = {}, {}
    # .notdef
    pen = TTGlyphPen(None)
    for (x0, y0, x1, y1), rev in (((50, 0, 450, CAP), False), ((90, 40, 410, CAP - 40), True)):
        pts = [(x0, y0), (x0, y1), (x1, y1), (x1, y0)]
        if rev:
            pts = pts[::-1]
        pen.moveTo(pts[0]); [pen.lineTo(p) for p in pts[1:]]; pen.closePath()
    glyphs[".notdef"] = pen.glyph()
    metrics[".notdef"] = (500, 50)
    for name, path in outlines.items():
        pen = TTGlyphPen(None)
        path.draw(ReverseContourPen(pen))  # TrueType wants clockwise outer contours
        gl = pen.glyph()
        glyphs[name] = gl
    fb.setupGlyf(glyphs)
    glyf = fb.font["glyf"]
    for name in order:
        if name == ".notdef":
            continue
        gl = glyf[name]
        gl.recalcBounds(glyf)
        metrics[name] = (advs[name], getattr(gl, "xMin", 0) if gl.numberOfContours else 0)
    fb.setupHorizontalMetrics(metrics)
    fb.setupHorizontalHeader(ascent=900, descent=-260)
    ps = f"FranzAntiqua-{weight}"
    fb.setupNameTable({
        "familyName": FAMILY,
        "styleName": weight,
        "uniqueFontIdentifier": f"{ps};1.000",
        "fullName": f"{FAMILY} {weight}",
        "psName": ps,
        "version": "Version 1.000",
        "copyright": "Copyright 2026 Franzwerk",
        "licenseDescription": "This Font Software is licensed under the SIL Open Font License, Version 1.1.",
        "licenseInfoURL": "https://openfontlicense.org",
    })
    fb.setupOS2(sTypoAscender=900, sTypoDescender=-260, sTypoLineGap=0, usWinAscent=950, usWinDescent=300,
                sxHeight=XH, sCapHeight=CAP, usWeightClass=wc, fsSelection=0x40 | 0x80,
                achVendID="FRZW", fsType=0, version=4)
    fb.setupPost()
    fb.setupHead(unitsPerEm=UPM, fontRevision=1.0, created=timestampNow(), modified=timestampNow())
    addOpenTypeFeaturesFromString(fb.font, KERN)
    os.makedirs(outdir, exist_ok=True)
    ttf = os.path.join(outdir, ps + ".ttf")
    fb.save(ttf)
    fb.font.flavor = "woff2"
    fb.font.save(os.path.join(outdir, ps + ".woff2"))
    print("wrote", ttf, len(order), "glyphs")


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.abspath(__file__)), "fonts")
    for w in WEIGHTS:
        build(w, out)
