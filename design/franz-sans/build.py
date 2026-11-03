#!/usr/bin/env python3
"""Franz Sans – a clean, lean, highly legible grotesque for web and UI text.

Every glyph is constructed from exact geometry, not traced strokes:
  * rounds are superellipse rings made of four cubic Béziers each,
    with on-curve points at every extreme,
  * stems, bars and diagonals are exact rectangles and parallelograms,
  * apertures and terminals are cut with straight lines (wedges / half-planes),
  * shapes are combined with boolean operations (skia-pathops), converted to
    TrueType quadratics with cu2qu and autohinted with ttfautohint.

Design goals: large x-height (530/710), open apertures, low contrast,
calm proportions, measured spacing, a flagged 1 and ascenders taller than caps (l vs I).

    pip install fonttools skia-pathops brotli ttfautohint-py
    python3 build.py            # writes ./fonts/*.ttf, *.woff2
"""
import io
import math
import os
import sys

import pathops
from pathops import PathOp
from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.pens.cu2quPen import Cu2QuPen
from fontTools.pens.transformPen import TransformPen
from fontTools.pens.areaPen import AreaPen
from fontTools.feaLib.builder import addOpenTypeFeaturesFromString
from fontTools.misc.timeTools import timestampNow
from fontTools.ttLib import TTFont

FAMILY = "Franz Sans"
UPM = 1000
CAP, XH, ASC, DESC, OV = 710, 530, 750, -210, 12
BIG = 4000
K_OUT, K_IN = 0.585, 0.575  # superellipse handle factors (0.552 = circle)

WEIGHTS = {
    # name: (vertical stem, horizontal stroke, usWeightClass)
    "Regular": (84, 74, 400),
    "Medium": (98, 85, 500),
    "Semibold": (113, 96, 600),
    "Bold": (130, 108, 700),
}


# ------------------------------------------------------------------ geometry
def P():
    return pathops.Path()


def U(*paths):
    out = P()
    for p in paths:
        out = pathops.op(out, p, PathOp.UNION, fix_winding=True)
    return out


def D(a, *bs):
    for b in bs:
        a = pathops.op(a, b, PathOp.DIFFERENCE, fix_winding=True)
    return a


def I(a, *bs):
    for b in bs:
        a = pathops.op(a, b, PathOp.INTERSECTION, fix_winding=True)
    return a


def poly(pts):
    p = P()
    a = sum(pts[i - 1][0] * pts[i][1] - pts[i][0] * pts[i - 1][1] for i in range(len(pts)))
    if a < 0:
        pts = pts[::-1]
    p.moveTo(*pts[0])
    for q in pts[1:]:
        p.lineTo(*q)
    p.close()
    return p


def rect(x0, y0, x1, y1):
    return poly([(x0, y0), (x1, y0), (x1, y1), (x0, y1)])


def left_of(x):
    return rect(-BIG, -BIG, x, BIG)


def right_of(x):
    return rect(x, -BIG, BIG, BIG)


def above(y):
    return rect(-BIG, y, BIG, BIG)


def below(y):
    return rect(-BIG, -BIG, BIG, y)


def se(l, r, b, t, k=K_OUT):
    """Superellipse in the box (l, r, b, t), counter-clockwise, extremes on-curve."""
    cx, cy, rx, ry = (l + r) / 2, (b + t) / 2, (r - l) / 2, (t - b) / 2
    p = P()
    p.moveTo(cx + rx, cy)
    p.cubicTo(cx + rx, cy + k * ry, cx + k * rx, cy + ry, cx, cy + ry)
    p.cubicTo(cx - k * rx, cy + ry, cx - rx, cy + k * ry, cx - rx, cy)
    p.cubicTo(cx - rx, cy - k * ry, cx - k * rx, cy - ry, cx, cy - ry)
    p.cubicTo(cx + k * rx, cy - ry, cx + rx, cy - k * ry, cx + rx, cy)
    p.close()
    return p


def ring(l, r, b, t, v, h, inner=None):
    """Round stroke: outer superellipse minus inner one (v = side, h = top/bottom thickness)."""
    il, ir, ib, it = inner if inner else (l + v, r - v, b + h, t - h)
    return D(se(l, r, b, t, K_OUT), se(il, ir, ib, it, K_IN))


def wedge(cx, cy, a0, a1):
    """Infinite pie slice from (cx, cy) between angles a0..a1 (degrees, ccw)."""
    pts = [(cx, cy)]
    n = max(2, int(abs(a1 - a0) / 10) + 1)
    for i in range(n + 1):
        a = math.radians(a0 + (a1 - a0) * i / n)
        pts.append((cx + BIG * math.cos(a), cy + BIG * math.sin(a)))
    return poly(pts)


def diag(top, bot, w, ref=("c", "c")):
    """Straight stroke with horizontal cuts. x of top/bot is the left edge,
    centre or right edge according to ref. Returns (path, centre_x(y))."""
    (xt, yt), (xb, yb) = top, bot
    dx, dy = xt - xb, yt - yb
    h = w / 2 * math.hypot(dx, dy) / abs(dy)
    off = {"l": h, "c": 0, "r": -h}
    xt += off[ref[0]]
    xb += off[ref[1]]
    p = poly([(xt - h, yt), (xt + h, yt), (xb + h, yb), (xb - h, yb)])
    return p, (lambda y: xb + (xt - xb) * (y - yb) / (yt - yb))


def dot(x, y, r):
    return se(x - r, x + r, y - r, y + r, 0.552)


def transform(path, m):
    out = P()
    path.draw(TransformPen(out.getPen(), m))
    return pathops.simplify(out, fix_winding=True)


def mirror(path, adv):
    return transform(path, (-1, 0, 0, 1, adv, 0))


def rotate180(path, adv, h):
    return transform(path, (-1, 0, 0, -1, adv, h))


def box_c(l, r, b, t):
    return (l + r) / 2, (b + t) / 2


# ------------------------------------------------------------------ glyphs
G = {}


def glyph(name, uni, adv):
    def deco(fn):
        G[name] = (uni, adv, fn)
        return fn
    return deco


class W:
    """Weight context passed to every glyph function."""

    def __init__(self, V, H):
        self.V, self.H = V, H
        self.Dw = V * 0.96  # diagonal stroke width
        self.R = V * 0.62   # dot radius


# ---------- shared constructions
def arch(w, x_stem_l, x_r, h=XH, rise=210):
    """n-shoulder: stem at x_stem_l..+V, right stem ends at x_r (outer edge)."""
    V, H = w.V, w.H
    cy = h - rise
    t = h + OV
    b = 2 * cy - t
    outer = (x_stem_l + V * 0.3, x_r, b, t)
    inner = (x_stem_l + V, x_r - V, b + H, t - H)
    arc = I(ring(*outer, V, H, inner=inner), above(cy))
    return U(arc, rect(x_r - V, 0, x_r, cy + 1))


def bowl_r(w, x_stem_l, x_r, b=-OV, t=XH + OV):
    """Bowl attached to the right side of a stem (b, p, and mirrored d, q)."""
    V, H = w.V, w.H
    outer = (x_stem_l + V * 0.3, x_r, b, t)
    inner = (x_stem_l + V, x_r - V, b + H, t - H)
    return ring(*outer, V, H, inner=inner)


def hook_down(w, x_stem_r, x_l, cy, bottom, term):
    """Descender hook: stem right edge x_stem_r, curving left to the terminal angle."""
    V, H = w.V, w.H
    t = 2 * cy - bottom
    rg = ring(x_l, x_stem_r, bottom, t, V, H)
    cx = (x_l + x_stem_r) / 2
    return D(I(rg, below(cy)), wedge(cx, cy, 180, term))


def tail_right(w, x_stem_l, R, ry, ext):
    """Foot of t: quarter ring of radius R out of the stem, then a straight
    horizontal run of length ext ending in a vertical cut."""
    V, H = w.V, w.H
    rg = ring(x_stem_l, x_stem_l + 2 * R, 0, 2 * ry, V, H)
    q = I(I(rg, below(ry)), left_of(x_stem_l + R))
    return U(q, rect(x_stem_l + R - 1, 0, x_stem_l + R + ext, H))


def hook_left(w, x_stem_r, R, top, bottom, ext):
    """Descender of j: quarter ring curving left, then a straight run of length ext."""
    V, H = w.V, w.H
    ry = (top - bottom)
    rg = ring(x_stem_r - 2 * R, x_stem_r, bottom, bottom + 2 * ry, V, H)
    q = I(I(rg, below(top)), right_of(x_stem_r - R))
    return U(q, rect(x_stem_r - R - ext, bottom, x_stem_r - R + 1, bottom + H))


def s_shape(w, x0, x1, h, ys):
    """S / s from two half rings. ys = centre of the spine."""
    V, H = w.V, w.H
    # point-symmetric construction: two congruent half rings, the lower one is
    # the upper one rotated by 180 degrees, so the letter cannot lean.
    up = (x0, x1, ys - H / 2, h + OV)
    lo = (x0, x1, -OV, ys + H / 2)
    cxu, cyu = box_c(*up)
    cxl, cyl = box_c(*lo)
    upper = D(ring(*up, V, H), wedge(cxu, cyu, -90, 28))
    lower = D(ring(*lo, V, H), wedge(cxl, cyl, 90, 208))
    return U(upper, lower)


# ---------- capitals
@glyph("A", "A", 670)
def _A(w):
    a = w.V * 0.56
    L, fl = diag((335 - a, CAP), (25, 0), w.Dw, ("l", "l"))
    R, fr = diag((335 + a, CAP), (645, 0), w.Dw, ("r", "r"))
    y = 205
    return U(L, R, rect(fl(y + w.H / 2), y, fr(y + w.H / 2), y + w.H))


@glyph("B", "B", 645)
def _B(w):
    V, H = w.V, w.H
    x = 85
    ym = 372
    up = (2 * 315 - 545, 545, ym, CAP)
    lo = (2 * 325 - 590, 590, 0, ym + H)
    return U(rect(x, 0, x + V, CAP),
             I(ring(*up, V, H), right_of(315)), I(ring(*lo, V, H), right_of(325)),
             rect(x, CAP - H, 316, CAP), rect(x, ym, 326, ym + H), rect(x, 0, 326, H))


@glyph("C", "C", 690)
def _C(w):
    box = (50, 660, -OV, CAP + OV)
    cx, cy = box_c(*box)
    return D(ring(*box, w.V, w.H), wedge(cx, cy, -40, 40))


@glyph("D", "D", 725)
def _D(w):
    V, H = w.V, w.H
    x, cx = 85, 335
    box = (2 * cx - 675, 675, 0, CAP)
    return U(rect(x, 0, x + V, CAP), I(ring(*box, V, H), right_of(cx)),
             rect(x, CAP - H, cx + 1, CAP), rect(x, 0, cx + 1, H))


@glyph("E", "E", 595)
def _E(w):
    V, H = w.V, w.H
    x = 85
    return U(rect(x, 0, x + V, CAP), rect(x, CAP - H, 535, CAP),
             rect(x, 362 - H / 2, 505, 362 + H / 2), rect(x, 0, 545, H))


@glyph("F", "F", 565)
def _F(w):
    V, H = w.V, w.H
    x = 85
    return U(rect(x, 0, x + V, CAP), rect(x, CAP - H, 525, CAP), rect(x, 350 - H / 2, 495, 350 + H / 2))


@glyph("G", "G", 730)
def _G(w):
    V, H = w.V, w.H
    box = (50, 680, -OV, CAP + OV)
    cx, cy = box_c(*box)
    rg = D(ring(*box, V, H), wedge(cx, cy, 0, 40))
    return U(rg, rect(395, cy - H, 680, cy))


@glyph("H", "H", 725)
def _H(w):
    V, H = w.V, w.H
    return U(rect(85, 0, 85 + V, CAP), rect(640 - V, 0, 640, CAP), rect(85, 362 - H / 2, 640, 362 + H / 2))


@glyph("I", "I", 270)
def _I(w):
    return rect(135 - w.V / 2, 0, 135 + w.V / 2, CAP)


@glyph("J", "J", 520)
def _J(w):
    V = w.V
    xr, cy = 440, 215
    return U(rect(xr - V, cy, xr, CAP), hook_down(w, xr, 55, cy, -OV, 200))


@glyph("K", "K", 650)
def _K(w):
    V = w.V
    x = 85
    arm, fa = diag((625, CAP), (x + V / 2, 175), w.Dw, ("r", "c"))
    leg, _ = diag((fa(395), 395), (640, 0), w.Dw, ("c", "r"))
    return U(rect(x, 0, x + V, CAP), I(arm, right_of(x)), leg)


@glyph("L", "L", 545)
def _L(w):
    return U(rect(85, 0, 85 + w.V, CAP), rect(85, 0, 525, w.H))


@glyph("M", "M", 870)
def _M(w):
    V = w.V
    xl, xr = 80, 790
    d1, _ = diag((xl, CAP), (435, 0), w.V * 0.9, ("l", "c"))
    d2, _ = diag((xr, CAP), (435, 0), w.V * 0.9, ("r", "c"))
    return U(rect(xl, 0, xl + V, CAP), rect(xr - V, 0, xr, CAP), d1, d2)


@glyph("N", "N", 725)
def _N(w):
    V = w.V
    xl, xr = 85, 640
    d, _ = diag((xl, CAP), (xr, 0), w.V * 0.98, ("l", "r"))
    return U(rect(xl, 0, xl + V, CAP), rect(xr - V, 0, xr, CAP), d)


@glyph("O", "O", 765)
def _O(w):
    return ring(50, 715, -OV, CAP + OV, w.V, w.H)


@glyph("P", "P", 615)
def _P(w):
    V, H = w.V, w.H
    x, cx, yb = 85, 330, 290
    box = (2 * cx - 570, 570, yb, CAP)
    return U(rect(x, 0, x + V, CAP), I(ring(*box, V, H), right_of(cx)),
             rect(x, CAP - H, cx + 1, CAP), rect(x, yb, cx + 1, yb + H))


@glyph("Q", "Q", 765)
def _Q(w):
    tail, _ = diag((480, 175), (705, -60), w.Dw)
    return U(ring(50, 715, -OV, CAP + OV, w.V, w.H), tail)


@glyph("R", "R", 645)
def _R(w):
    V, H = w.V, w.H
    x, cx, yb = 85, 330, 310
    box = (2 * cx - 575, 575, yb, CAP)
    leg, _ = diag((395, yb + H), (615, 0), w.Dw, ("c", "r"))
    return U(rect(x, 0, x + V, CAP), I(ring(*box, V, H), right_of(cx)),
             rect(x, CAP - H, cx + 1, CAP), rect(x, yb, cx + 1, yb + H), leg)


@glyph("S", "S", 615)
def _S(w):
    return s_shape(w, 50, 565, CAP, CAP / 2)


@glyph("T", "T", 605)
def _T(w):
    return U(rect(35, CAP - w.H, 570, CAP), rect(302 - w.V / 2, 0, 302 + w.V / 2, CAP))


@glyph("U", "U", 715)
def _U(w):
    V, H = w.V, w.H
    xl, xr, cy = 85, 630, 270
    rg = I(ring(xl, xr, -OV, 2 * cy + OV, V, H), below(cy))
    return U(rg, rect(xl, cy - 1, xl + V, CAP), rect(xr - V, cy - 1, xr, CAP))


@glyph("V", "V", 655)
def _V(w):
    a, _ = diag((25, CAP), (327, 0), w.Dw, ("l", "c"))
    b, _ = diag((630, CAP), (327, 0), w.Dw, ("r", "c"))
    return U(a, b)


@glyph("W", "W", 960)
def _W(w):
    d = w.V * 0.9
    p1, _ = diag((20, CAP), (248, 0), d, ("l", "c"))
    p2, _ = diag((480, CAP), (248, 0), d)
    p3, _ = diag((480, CAP), (712, 0), d)
    p4, _ = diag((940, CAP), (712, 0), d, ("r", "c"))
    return U(p1, p2, p3, p4)


@glyph("X", "X", 655)
def _X(w):
    a, _ = diag((35, CAP), (620, 0), w.Dw, ("l", "r"))
    b, _ = diag((620, CAP), (35, 0), w.Dw, ("r", "l"))
    return U(a, b)


@glyph("Y", "Y", 645)
def _Y(w):
    a, _ = diag((25, CAP), (322, 300), w.Dw, ("l", "c"))
    b, _ = diag((620, CAP), (322, 300), w.Dw, ("r", "c"))
    return U(a, b, rect(322 - w.V / 2, 0, 322 + w.V / 2, 320))


@glyph("Z", "Z", 615)
def _Z(w):
    H = w.H
    d, _ = diag((555, CAP - H), (55, H), w.V, ("r", "l"))
    return U(rect(60, CAP - H, 555, CAP), rect(55, 0, 565, H), d)


# ---------- figures (tabular)
FW = 590


@glyph("zero", "0", FW)
def _0(w):
    return ring(65, 525, -OV, CAP + OV, w.V, w.H)


@glyph("one", "1", FW)
def _1(w):
    V = w.V
    x = 330
    flag, _ = diag((x + V * 0.15, CAP), (125, 545), w.V * 0.92, ("c", "c"))
    flag = I(flag, left_of(x + V))
    return U(rect(x, 0, x + V, CAP), flag)


def se_lr_points(box, k, n=2000):
    """Sample the lower-right quadrant of a superellipse (bottom -> right extreme)."""
    l, r, b, t = box
    cx, cy, rx, ry = (l + r) / 2, (b + t) / 2, (r - l) / 2, (t - b) / 2
    P0, P1, P2, P3 = (cx, cy - ry), (cx + k * rx, cy - ry), (cx + rx, cy - k * ry), (cx + rx, cy)
    pts = []
    for i in range(n + 1):
        u = i / n
        a, b_, c, d = (1 - u) ** 3, 3 * u * (1 - u) ** 2, 3 * u * u * (1 - u), u ** 3
        pts.append((a * P0[0] + b_ * P1[0] + c * P2[0] + d * P3[0], a * P0[1] + b_ * P1[1] + c * P2[1] + d * P3[1]))
    return pts


def tangent_from(pt, curve):
    """Point on a convex curve whose tangent passes through pt (upper-left tangent)."""
    best, q = None, None
    for i in range(1, len(curve) - 1):
        (x0, y0), (x1, y1) = curve[i - 1], curve[i + 1]
        tx, ty = x1 - x0, y1 - y0
        cx, cy = curve[i][0] - pt[0], curve[i][1] - pt[1]
        cr = abs(cx * ty - cy * tx) / (math.hypot(tx, ty) * math.hypot(cx, cy) + 1e-9)
        if best is None or cr < best:
            best, q = cr, curve[i]
    return q


def halfplane(p, q, keep_left):
    """Big polygon on the left (or right) side of the directed line p->q."""
    dx, dy = q[0] - p[0], q[1] - p[1]
    L = math.hypot(dx, dy)
    ux, uy = dx / L * BIG, dy / L * BIG
    nx, ny = (-uy, ux) if keep_left else (uy, -ux)
    return poly([(p[0] - ux, p[1] - uy), (p[0] + ux, p[1] + uy),
                 (p[0] + ux + nx, p[1] + uy + ny), (p[0] - ux + nx, p[1] - uy + ny)])


@glyph("two", "2", FW)
def _2(w):
    V, H = w.V, w.H
    box = (70, 515, 2 * 500 - CAP - OV, CAP + OV)
    inner = (box[0] + V, box[1] - V, box[2] + H, box[3] - H)
    cx, cy = box_c(*box)
    x0 = 65
    # upper edge of the neck: from the bar's top-left corner, tangent to the inner curve
    A = (x0, H)
    Ti = tangent_from(A, se_lr_points(inner, K_IN))
    # lower edge: parallel-ish line tangent to the outer curve, ~V thick
    ang = math.atan2(Ti[1] - A[1], Ti[0] - A[0])
    outer_pts = se_lr_points(box, K_OUT)
    lo, hi = x0, x0 + 3 * V
    for _ in range(40):  # lower edge such that the neck is exactly V thick at the bar
        bx = (lo + hi) / 2
        To = tangent_from((bx, 0), outer_pts)
        dx, dy = To[0] - bx, To[1]
        dist = abs((A[0] - bx) * dy - (A[1]) * dx) / math.hypot(dx, dy)
        lo, hi = (bx, hi) if dist < V else (lo, bx)
    B = (bx, 0)
    neck = poly([(x0, 0), B, To, Ti, A])
    hood = I(ring(*box, V, H), U(above(cy), wedge(cx, cy, -80, 0)))
    hood = D(hood,
             I(halfplane(A, Ti, True), below(Ti[1])),     # counter side of the upper edge
             I(halfplane(B, To, False), below(To[1])))    # outside of the lower edge
    hood = D(hood, wedge(cx, cy, 152, 180))
    return U(hood, neck, rect(x0, 0, 530, H))


@glyph("three", "3", FW)
def _3(w):
    V, H = w.V, w.H
    ym = 368
    up = (85, 490, ym, CAP + OV)
    lo = (65, 515, -OV, ym + H)
    cu, cyu = box_c(*up)
    cl, cyl = box_c(*lo)
    return U(D(ring(*up, V, H), wedge(cu, cyu, 152, 270)),
             D(ring(*lo, V, H), wedge(cl, cyl, 90, 208)),
             rect(235, ym, max(cu, cl) + 1, ym + H))


@glyph("four", "4", FW)
def _4(w):
    V, H = w.V, w.H
    x = 395
    yb = 190
    d, _ = diag((x + V, CAP), (45, yb), w.V * 0.95, ("r", "l"))
    return U(rect(x, 0, x + V, CAP), I(d, left_of(x + V)), rect(45, yb, 550, yb + H))


@glyph("five", "5", FW)
def _5(w):
    V, H = w.V, w.H
    box = (65, 525, -OV, 470)
    cx, cy = box_c(*box)
    xv = 112
    xe = xv + V * 0.98
    bowl = D(ring(*box, V, H), wedge(cx, cy, 180, 210), I(left_of(xe), above(cy)))
    # the vertical ends exactly where it meets the inner curve of the bowl
    ib = (box[0] + V, box[1] - V, box[2] + H, box[3] - H)
    icx, icy, irx, iry = (ib[0] + ib[1]) / 2, (ib[2] + ib[3]) / 2, (ib[1] - ib[0]) / 2, (ib[3] - ib[2]) / 2
    ys = [p[1] for p in se_lr_points((2 * icx - ib[1], ib[1], ib[2], ib[3]), K_IN)]
    xs = [2 * icx - p[0] for p in se_lr_points((2 * icx - ib[1], ib[1], ib[2], ib[3]), K_IN)]
    yv = max((2 * icy - y) for x, y in zip(xs, ys) if x <= xe)  # upper-left quadrant via symmetry
    return U(bowl, rect(xv, CAP - H, 485, CAP), rect(xv, min(yv, CAP - H), xe, CAP))


@glyph("six", "6", FW)
def _6(w):
    V, H = w.V, w.H
    bowl = (60, 530, -OV, 470)
    cyb = box_c(*bowl)[1]
    big = (60, 600, 2 * cyb - CAP - OV, CAP + OV)
    cxg, cyg = box_c(*big)
    arc = D(I(ring(*big, V, H), above(cyb)), wedge(cxg, cyg, -90, 64))
    return U(ring(*bowl, V, H), arc)


@glyph("nine", "9", FW)
def _9(w):
    return rotate180(_6(w), FW, CAP)


@glyph("seven", "7", FW)
def _7(w):
    H = w.H
    d, _ = diag((525, CAP - H), (235, 0), w.Dw, ("r", "c"))
    return U(rect(60, CAP - H, 525, CAP), d)


@glyph("eight", "8", FW)
def _8(w):
    V, H = w.V, w.H
    ym = 370
    return U(ring(92, 498, ym, CAP + OV, V, H), ring(65, 525, -OV, ym + H, V, H))


# ---------- lowercase
@glyph("a", "a", 565)
def _a(w):
    V, H = w.V, w.H
    xr = 485
    cyh = XH - 175
    hood_box = (65, xr, 2 * cyh - XH - OV, XH + OV)
    cx = box_c(*hood_box)[0]
    hood = D(I(ring(*hood_box, V, H), above(cyh)), wedge(cx, cyh, 152, 180))
    btop = 300
    bowl = ring(50, xr - V * 0.3, -OV, btop, V, H, inner=(50 + V, xr - V, -OV + H, btop - H))
    return U(hood, rect(xr - V, 0, xr, cyh + 1), I(bowl, left_of(xr)))


@glyph("b", "b", 610)
def _b(w):
    return U(rect(75, 0, 75 + w.V, ASC), bowl_r(w, 75, 565))


@glyph("c", "c", 540)
def _c(w):
    box = (45, 510, -OV, XH + OV)
    cx, cy = box_c(*box)
    return D(ring(*box, w.V, w.H), wedge(cx, cy, -44, 44))


@glyph("d", "d", 610)
def _d(w):
    return mirror(_b(w), 610)


@glyph("e", "e", 570)
def _e(w):
    V, H = w.V, w.H
    box = (45, 525, -OV, XH + OV)
    cx, cy = box_c(*box)
    yb = round(XH * 0.585)  # top of the cross bar: smaller eye, fuller lower bowl
    # aperture: everything right of the centre between the bar and a cut
    # line falling at 38 degrees; the lower stroke runs well round
    rg = D(ring(*box, V, H), wedge(cx, yb - H, -38, 0))
    bar = I(rect(45 + V / 2, yb - H, 525, yb), se(*box))
    return U(rg, bar)


@glyph("f", "f", 345)
def _f(w):
    V, H = w.V, w.H
    x = 100
    cy = ASC - 145
    box = (x, x + 205 + V, 2 * cy - ASC - OV, ASC + OV)
    cx = box_c(*box)[0]
    hook = D(I(ring(*box, V, H), above(cy)), wedge(cx, cy, -90, 62))
    return U(rect(x, 0, x + V, cy + 1), hook, rect(25, XH - H, 330, XH))


@glyph("g", "g", 610)
def _g(w):
    # drawn as a mirrored p-shape whose descender hook curves right
    V = w.V
    x = 75
    cy = -30
    box = (x, 520, DESC - OV, 2 * cy - DESC + OV)
    cx = box_c(*box)[0]
    hook = D(I(ring(*box, V, w.H), below(cy)), wedge(cx, cy, -28, 0))
    p = U(rect(x, cy - 1, x + V, XH), hook, bowl_r(w, x, 565))
    return mirror(p, 610)


@glyph("h", "h", 590)
def _h(w):
    return U(rect(75, 0, 75 + w.V, ASC), arch(w, 75, 515))


@glyph("i", "i", 240)
def _i(w):
    return U(rect(120 - w.V / 2, 0, 120 + w.V / 2, XH), dot(120, XH + 150, w.R))


@glyph("dotlessi", "ı", 240)
def _dotlessi(w):
    return rect(120 - w.V / 2, 0, 120 + w.V / 2, XH)


@glyph("j", "j", 250)
def _j(w):
    V = w.V
    xr = 120 + V / 2
    R = 95 + 0.7 * V
    top = -60
    return U(rect(xr - V, top - 1, xr, XH), hook_left(w, xr, R, top, DESC, 45), dot(120, XH + 150, w.R))


@glyph("k", "k", 545)
def _k(w):
    V = w.V
    x = 75
    arm, fa = diag((520, XH), (x + V / 2, 130), w.Dw, ("r", "c"))
    leg, _ = diag((fa(305), 305), (535, 0), w.Dw, ("c", "r"))
    return U(rect(x, 0, x + V, ASC), I(arm, right_of(x)), leg)


@glyph("l", "l", 270)
def _l(w):
    V = w.V
    return rect(75, 0, 75 + V, ASC)


@glyph("m", "m", 885)
def _m(w):
    V = w.V
    x1, xm, xr = 70, 470, 815
    a1 = arch(w, x1, xm, rise=190)
    a2 = arch(w, xm - V, xr, rise=190)
    return U(rect(x1, 0, x1 + V, XH), a1, a2)


@glyph("n", "n", 590)
def _n(w):
    return U(rect(75, 0, 75 + w.V, XH), arch(w, 75, 515))


@glyph("o", "o", 590)
def _o(w):
    return ring(45, 545, -OV, XH + OV, w.V, w.H)


@glyph("p", "p", 610)
def _p(w):
    return U(rect(75, DESC, 75 + w.V, XH), bowl_r(w, 75, 565))


@glyph("q", "q", 610)
def _q(w):
    return mirror(_p(w), 610)


@glyph("r", "r", 365)
def _r(w):
    V = w.V
    x = 75
    sh = I(arch(w, x, 470), left_of(345))
    sh = D(sh, rect(470 - V - 1, -1, 471, XH - 210 + 2))
    return U(rect(x, 0, x + V, XH), I(sh, above(XH - 215)))


@glyph("s", "s", 510)
def _s(w):
    return s_shape(w, 45, 465, XH, XH / 2)


@glyph("t", "t", 365)
def _t(w):
    V, H = w.V, w.H
    x, R = 100, 100 + 0.7 * V
    ry = 150
    return U(rect(x, ry - 1, x + V, 655), tail_right(w, x, R, ry, 45), rect(25, XH - H, 335, XH))


@glyph("u", "u", 590)
def _u(w):
    return rotate180(_n(w), 590, XH)


@glyph("v", "v", 540)
def _v(w):
    a, _ = diag((20, XH), (270, 0), w.Dw, ("l", "c"))
    b, _ = diag((520, XH), (270, 0), w.Dw, ("r", "c"))
    return U(a, b)


@glyph("w", "w", 805)
def _w(w):
    d = w.V * 0.9
    p1, _ = diag((18, XH), (215, 0), d, ("l", "c"))
    p2, _ = diag((402, XH), (215, 0), d)
    p3, _ = diag((402, XH), (590, 0), d)
    p4, _ = diag((787, XH), (590, 0), d, ("r", "c"))
    return U(p1, p2, p3, p4)


@glyph("x", "x", 540)
def _x(w):
    a, _ = diag((30, XH), (510, 0), w.Dw, ("l", "r"))
    b, _ = diag((510, XH), (30, 0), w.Dw, ("r", "l"))
    return U(a, b)


@glyph("y", "y", 545)
def _y(w):
    a, _ = diag((20, XH), (272, 0), w.Dw, ("l", "c"))
    b, f = diag((525, XH), (272, 0), w.Dw, ("r", "c"))
    tail, _ = diag((f(0), 0), (f(DESC), DESC), w.Dw)
    return U(a, b, tail)


@glyph("z", "z", 515)
def _z(w):
    H = w.H
    d, _ = diag((460, XH - H), (50, H), w.V, ("r", "l"))
    return U(rect(55, XH - H, 460, XH), rect(50, 0, 470, H), d)


@glyph("germandbls", "ß", 610)
def _ss(w):
    V, H = w.V, w.H
    x = 75
    ym = 405
    up = (x, 465, ym, ASC + OV)
    cxu, cyu = box_c(*up)
    lo = (2 * cxu - 545, 545, -OV, ym + H)
    cxl, cyl = box_c(*lo)
    upper = I(ring(*up, V, H), U(above(cyu), right_of(cxu)))
    lower = I(ring(*lo, V, H), U(right_of(cxl), I(below(cyl), right_of(235))))
    return U(rect(x, 0, x + V, cyu + 1), upper, lower)


# ---------- punctuation & symbols
@glyph("space", " ", 245)
def _space(w):
    return P()


@glyph("period", ".", 250)
def _period(w):
    return dot(125, w.R, w.R)


def comma_at(w, x, y):
    r = w.R
    tail, _ = diag((x + r, y), (x - 25, y - 165), w.V * 0.72, ("r", "c"))
    return U(dot(x, y, r), I(tail, below(y + 1)))


@glyph("comma", ",", 250)
def _comma(w):
    return comma_at(w, 125, w.R)


@glyph("colon", ":", 250)
def _colon(w):
    return U(dot(125, w.R, w.R), dot(125, XH - w.R, w.R))


@glyph("semicolon", ";", 250)
def _semicolon(w):
    return U(comma_at(w, 125, w.R), dot(125, XH - w.R, w.R))


@glyph("exclam", "!", 260)
def _exclam(w):
    return U(dot(130, w.R, w.R), rect(130 - w.V / 2, 215, 130 + w.V / 2, CAP))


@glyph("question", "?", 495)
def _question(w):
    V, H = w.V, w.H
    ym = 300
    box = (55, 450, ym, CAP + OV)
    cx, cy = box_c(*box)
    hook = D(ring(*box, V, H), wedge(cx, cy, 152, 270))
    return U(hook, rect(cx - V / 2, 215, cx + V / 2, ym + H), dot(cx, w.R, w.R))


@glyph("hyphen", "-", 360)
def _hyphen(w):
    return rect(60, 270, 300, 270 + w.H * 1.05)


@glyph("endash", "–", 520)
def _endash(w):
    return rect(40, 270, 480, 270 + w.H)


@glyph("emdash", "—", 1000)
def _emdash(w):
    return rect(40, 270, 960, 270 + w.H)


@glyph("underscore", "_", 500)
def _us(w):
    return rect(20, -110, 480, -110 + w.H)


@glyph("slash", "/", 380)
def _slash(w):
    return diag((350, CAP + 40), (30, -120), w.V * 0.92)[0]


@glyph("bar", "|", 260)
def _bar(w):
    return rect(130 - w.V * 0.45, -170, 130 + w.V * 0.45, ASC + 40)


@glyph("parenleft", "(", 320)
def _pl(w):
    box = (95, 455, -360, 970)
    cx = box_c(*box)[0]
    rg = ring(*box, w.V * 0.95, w.H)
    return I(I(rg, left_of(cx)), rect(-BIG, -175, BIG, 785))


@glyph("parenright", ")", 320)
def _pr(w):
    return mirror(_pl(w), 320)


@glyph("bracketleft", "[", 320)
def _bl(w):
    V, H = w.V, w.H
    return U(rect(110, -175, 110 + V, 785), rect(110, 785 - H, 275, 785), rect(110, -175, 275, -175 + H))


@glyph("bracketright", "]", 320)
def _br(w):
    return mirror(_bl(w), 320)


@glyph("quoteright", "’", 240)
def _qr(w):
    return comma_at(w, 120, 650)


@glyph("quoteleft", "‘", 240)
def _ql(w):
    return rotate180(_qr(w), 240, 650 * 2 - 165)


@glyph("quotedblright", "”", 395)
def _qdr(w):
    return U(comma_at(w, 120, 650), comma_at(w, 275, 650))


@glyph("quotedblleft", "“", 395)
def _qdl(w):
    return rotate180(_qdr(w), 395, 650 * 2 - 165)


@glyph("quotedblbase", "„", 395)
def _qdb(w):
    return U(comma_at(w, 120, w.R), comma_at(w, 275, w.R))


@glyph("quotesingle", "'", 220)
def _qs(w):
    return rect(110 - w.V * 0.42, 470, 110 + w.V * 0.42, CAP + 20)


@glyph("quotedbl", '"', 360)
def _qd(w):
    return U(*[rect(x - w.V * 0.42, 470, x + w.V * 0.42, CAP + 20) for x in (110, 250)])


@glyph("ampersand", "&", 705)
def _amp(w):
    V, H = w.V, w.H
    up = (150, 450, 400, CAP + OV)
    lo = (50, 520, -OV, 445)
    cxu, cyu = box_c(*up)
    cxl, cyl = box_c(*lo)
    upper = ring(*up, V * 0.95, H)
    lower = D(ring(*lo, V, H), wedge(cxl, cyl, 22, 120))
    # the diagonal leaves the upper loop at its lower left and runs to the foot
    a = math.radians(222)
    rx, ry = (up[1] - up[0]) / 2 - V / 2, (up[3] - up[2]) / 2 - H / 2
    sx, sy = cxu + rx * math.cos(a), cyu + ry * math.sin(a)
    leg, _ = diag((sx, sy), (665, 0), w.Dw, ("c", "r"))
    return U(upper, lower, leg)


@glyph("plus", "+", 580)
def _plus(w):
    t = w.V * 0.9
    return U(rect(70, 330 - t / 2, 510, 330 + t / 2), rect(290 - t / 2, 110, 290 + t / 2, 550))


@glyph("equal", "=", 580)
def _eq(w):
    t = w.H
    return U(rect(70, 400, 510, 400 + t), rect(70, 240, 510, 240 + t))


@glyph("periodcentered", "·", 250)
def _mid(w):
    return dot(125, 320, w.R)


@glyph("asterisk", "*", 450)
def _ast(w):
    cx, cy, L, t = 225, 575, 125, w.V * 0.8
    out = P()
    for a in (90, 162, 234, 306, 18):
        r = math.radians(a)
        dx, dy = math.cos(r), math.sin(r)
        nx, ny = -dy * t / 2, dx * t / 2
        out = U(out, poly([(cx + nx, cy + ny), (cx + dx * L + nx, cy + dy * L + ny),
                           (cx + dx * L - nx, cy + dy * L - ny), (cx - nx, cy - ny)]))
    return out


@glyph("numbersign", "#", 640)
def _hash(w):
    d = w.V * 0.85
    a, _ = diag((300, CAP), (210, 0), d)
    b, _ = diag((515, CAP), (425, 0), d)
    return U(a, b, rect(65, 455, 595, 455 + w.H), rect(45, 245, 575, 245 + w.H))


@glyph("percent", "%", 820)
def _pct(w):
    V, H = w.V * 0.82, w.H * 0.85
    d, _ = diag((660, CAP), (160, 0), w.V * 0.9)
    return U(ring(40, 330, 330, CAP + OV, V, H), ring(490, 780, -OV, 380, V, H), d)


@glyph("Euro", "€", FW)
def _euro(w):
    box = (85, 580, -OV, CAP + OV)
    cx, cy = box_c(*box)
    return U(D(ring(*box, w.V, w.H), wedge(cx, cy, -40, 40)),
             rect(20, 415, 390, 415 + w.H * 0.95), rect(20, 280, 370, 280 + w.H * 0.95))


# ---------- accented letters
def marks(w, cx, kind, base):
    """cx = optical centre of the base glyph's ink."""
    cx -= 10 if base == "a" else 0
    uc = kind.endswith("uc")
    if kind.startswith("dieresis"):
        y = CAP + 140 if uc else XH + 150
        dx = 120 if uc else 100
        return U(dot(cx - dx, y, w.R * 0.95), dot(cx + dx, y, w.R * 0.95))
    y0 = CAP + 80 if uc else XH + 90
    if kind.startswith("acute"):
        return diag((cx + 90, y0 + 150), (cx - 15, y0), w.V * 0.85)[0]
    return diag((cx - 90, y0 + 150), (cx + 15, y0), w.V * 0.85)[0]


COMPOSITES = {
    "Adieresis": ("Ä", "A", "dieresis_uc"), "Odieresis": ("Ö", "O", "dieresis_uc"),
    "Udieresis": ("Ü", "U", "dieresis_uc"), "adieresis": ("ä", "a", "dieresis"),
    "odieresis": ("ö", "o", "dieresis"), "udieresis": ("ü", "u", "dieresis"),
    "eacute": ("é", "e", "acute"), "egrave": ("è", "e", "grave"),
    "agrave": ("à", "a", "grave"), "aacute": ("á", "a", "acute"),
    "Eacute": ("É", "E", "acute_uc"),
}

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
  pos f quoteright 20;
} kern;
"""


# ------------------------------------------------------------------ spacing
# Side bearings are measured, not guessed: for every side the white space
# between the outline profile and the side bearing is averaged over the
# x-height (lowercase) or cap height (capitals, figures). Deep openings
# (c, r, T, L, v ...) are capped so they count as "open" space. Every side
# then gets  sb = target - reduction(mean_depth)  with a saturating curve, so
# round sides lose a little, diagonal and open sides lose most of the target.
LC = set("abcdefghijklmnopqrstuvwxyz") | {"germandbls", "dotlessi"}
UC = set("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
FIGS = {"zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine"}


class _Flatten:
    """Minimal pen flattening a path into polygons."""

    def __init__(self):
        self.polys, self.cur, self.last = [], [], None

    def moveTo(self, p):
        self.cur = [p]; self.last = p

    def lineTo(self, p):
        self.cur.append(p); self.last = p

    def curveTo(self, *pts):
        p0 = self.last
        c1, c2, p3 = pts[-3], pts[-2], pts[-1]
        for i in range(1, 17):
            t = i / 16
            a, b, c, d = (1 - t) ** 3, 3 * t * (1 - t) ** 2, 3 * t * t * (1 - t), t ** 3
            self.cur.append((a * p0[0] + b * c1[0] + c * c2[0] + d * p3[0], a * p0[1] + b * c1[1] + c * c2[1] + d * p3[1]))
        self.last = p3

    def qCurveTo(self, *pts):
        for p in pts:
            self.lineTo(p)

    def closePath(self):
        if self.cur:
            self.polys.append(self.cur)
        self.cur = []

    endPath = closePath


def profile(path, y0, y1, step=4):
    fp = _Flatten()
    path.draw(fp)
    rows = []
    y = y0 + step / 2
    while y < y1:
        xs = []
        for poly_ in fp.polys:
            n = len(poly_)
            for i in range(n):
                (xa, ya), (xb, yb) = poly_[i - 1], poly_[i]
                if (ya <= y < yb) or (yb <= y < ya):
                    xs.append(xa + (y - ya) * (xb - xa) / (yb - ya))
        rows.append((min(xs), max(xs)) if xs else None)
        y += step
    return rows


def measure_sides(path, zone_h):
    xmin, _, xmax, _ = path.bounds
    rows = profile(path, 0, zone_h)
    cap = zone_h * 0.5
    dl = [min(cap, r[0] - xmin) if r else cap for r in rows]
    dr = [min(cap, xmax - r[1]) if r else cap for r in rows]
    return xmin, xmax, sum(dl) / len(dl), sum(dr) / len(dr)


def spacing(name, path, V):
    """Return (xshift, advance) for a glyph."""
    if name in LC:
        zone, target = XH, 63 + (V - 84) * 0.25
    elif name in UC:
        zone, target = CAP, 78 + (V - 84) * 0.3
    else:
        zone, target = CAP, 70
    xmin, xmax, ml, mr = measure_sides(path, zone)
    scale, most = zone * 0.21, target * 0.82

    def red(d):
        return most * (1 - math.exp(-(d / scale) ** 2))

    lsb = target - red(ml)
    rsb = target - red(mr)
    return lsb - xmin, (xmax - xmin) + lsb + rsb


# ------------------------------------------------------------------ build
def path_to_glyph(path, dx):
    path = pathops.simplify(path, fix_winding=True)
    ap = AreaPen()
    path.draw(ap)
    pen = TTGlyphPen(None)
    # PostScript-style ccw outers (positive area) must be reversed for TrueType
    cp = Cu2QuPen(pen, max_err=0.6, reverse_direction=ap.value > 0)
    path.draw(TransformPen(cp, (1, 0, 0, 1, dx, 0)))
    return pen.glyph()


def build(weight, outdir, hint=True):
    V, H, wc = WEIGHTS[weight]
    w = W(V, H)
    pad = round((V - 84) * 0.3)
    paths, advs, shift, cmap = {}, {}, {}, {}
    for name, (uni, adv, fn) in G.items():
        p = fn(w)
        paths[name] = p
        cmap[ord(uni)] = name
        if name in LC or name in UC:
            shift[name], a = spacing(name, p, V)
            advs[name] = round(a)
            shift[name] = round(shift[name])
        elif name in FIGS:  # tabular figures: centre the ink in a fixed width
            x0, _, x1, _ = p.bounds
            advs[name] = FW + 2 * pad
            shift[name] = round((advs[name] - (x1 - x0)) / 2 - x0)
        else:
            advs[name] = adv + 2 * pad
            shift[name] = pad
    for name, (uni, base, kind) in COMPOSITES.items():
        x0, _, x1, _ = paths[base].bounds
        paths[name] = U(paths[base], marks(w, (x0 + x1) / 2, kind, base))
        advs[name] = advs[base]
        shift[name] = shift[base]
        cmap[ord(uni)] = name
    order = [".notdef"] + list(paths)

    fb = FontBuilder(UPM, isTTF=True)
    fb.setupGlyphOrder(order)
    fb.setupCharacterMap(cmap)
    nd = D(rect(60, 0, 460, CAP), rect(60 + V, H, 460 - V, CAP - H))
    glyphs = {".notdef": path_to_glyph(nd, 0)}
    for name, p in paths.items():
        glyphs[name] = path_to_glyph(p, shift[name])
    fb.setupGlyf(glyphs)
    glyf = fb.font["glyf"]
    metrics = {}
    for name in order:
        gl = glyf[name]
        gl.recalcBounds(glyf)
        adv = 520 if name == ".notdef" else advs[name]
        metrics[name] = (adv, gl.xMin if gl.numberOfContours else 0)
    fb.setupHorizontalMetrics(metrics)
    fb.setupHorizontalHeader(ascent=950, descent=-250)
    ps = f"FranzSans-{weight}"
    ribbi = weight in ("Regular", "Bold")
    fb.setupNameTable({
        "familyName": FAMILY if ribbi else f"{FAMILY} {weight}",
        "styleName": weight if ribbi else "Regular",
        "typographicFamily": FAMILY,
        "typographicSubfamily": weight,
        "uniqueFontIdentifier": f"{ps};2.000",
        "fullName": f"{FAMILY} {weight}",
        "psName": ps,
        "version": "Version 2.000",
        "copyright": "Copyright 2026 Franzwerk",
        "licenseDescription": "This Font Software is licensed under the SIL Open Font License, Version 1.1.",
        "licenseInfoURL": "https://openfontlicense.org",
    })
    fs = 0x20 if weight == "Bold" else 0x40
    fb.setupOS2(version=4, sTypoAscender=950, sTypoDescender=-250, sTypoLineGap=0, usWinAscent=1000,
                usWinDescent=300, sxHeight=XH, sCapHeight=CAP, usWeightClass=wc, fsSelection=fs | 0x80,
                achVendID="FRZW", fsType=0)
    fb.setupPost()
    fb.setupHead(unitsPerEm=UPM, fontRevision=2.0, created=timestampNow(), modified=timestampNow(),
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
    for wt in WEIGHTS:
        build(wt, out)
