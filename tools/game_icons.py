#!/usr/bin/env python3
"""The game look's icon set: one hand for every icon.

Rules (viewBox 48):
  - outline: INK #3b1a0c, 3.2 px, round joins (sub-parts 2.6)
  - fills: a vertical gradient, light top -> rich bottom, from the game palette
  - a white gloss stroke on the upper-left of the main shape (opacity .65)
  - a soft dark ground shadow under standing things (opacity .25)
Writes <out>/<relative asset path>.svg
"""
import math, os, sys

OUT = sys.argv[1]
INK = "#3b1a0c"
SW = 3.2
SW2 = 2.6

G = {  # name: (top, mid, bottom)
    "gold": ("#fff0a0", "#ffd04a", "#f29a0c"),
    "orange": ("#ffb86a", "#ff8a3d", "#e2581e"),
    "red": ("#ff9a8a", "#f25a55", "#c8323a"),
    "teal": ("#8ff5e0", "#3cc9ae", "#1f9a84"),
    "blue": ("#a8dcff", "#4aa3f0", "#2a6fd0"),
    "purple": ("#d6b8ff", "#9a6ae8", "#6a3fc0"),
    "green": ("#a8f0a0", "#4cc85a", "#2a9a3e"),
    "cream": ("#fffaf0", "#fff1dc", "#f2d2a6"),
    "wood": ("#e0995a", "#b8682e", "#7a3e18"),
    "lwood": ("#ffd9a0", "#eaa25a", "#b86a2a"),
    "silver": ("#f4f8fc", "#c9d6e6", "#8a9cb8"),
    "skin": ("#ffe2c4", "#ffcfa0", "#f0ac78"),
    "pink": ("#ffc0d8", "#ff8ab4", "#e2588e"),
    "dark": ("#6b3a20", "#4a2212", "#2b140a"),
}


class Icon:
    def __init__(self):
        self.defs = {}
        self.body = []

    def g(self, name):
        gid = "g_" + name
        if gid not in self.defs:
            a, b, c = G[name]
            self.defs[gid] = (f'<linearGradient id="{gid}" x1="0" y1="0" x2="0" y2="1">'
                              f'<stop offset="0" stop-color="{a}"/><stop offset="0.5" stop-color="{b}"/>'
                              f'<stop offset="1" stop-color="{c}"/></linearGradient>')
        return f"url(#{gid})"

    def add(self, s):
        self.body.append(s)

    def shape(self, tag, fill, sw=SW, **kw):
        attrs = " ".join(f'{k.replace("_", "-")}="{v}"' for k, v in kw.items())
        f = self.g(fill) if fill in G else fill
        self.add(f'<{tag} {attrs} fill="{f}" stroke="{INK}" stroke-width="{sw}" stroke-linejoin="round" stroke-linecap="round"/>')

    def path(self, d, fill, sw=SW):
        self.shape("path", fill, sw, d=d)

    def circle(self, cx, cy, r, fill, sw=SW):
        self.shape("circle", fill, sw, cx=cx, cy=cy, r=r)

    def rect(self, x, y, w, h, rx, fill, sw=SW):
        self.shape("rect", fill, sw, x=x, y=y, width=w, height=h, rx=rx)

    def ellipse(self, cx, cy, rx, ry, fill, sw=SW):
        self.shape("ellipse", fill, sw, cx=cx, cy=cy, rx=rx, ry=ry)

    def gloss(self, d, w=2.4, op=0.7):
        self.add(f'<path d="{d}" fill="none" stroke="#fff" stroke-opacity="{op}" stroke-width="{w}" stroke-linecap="round"/>')

    def dot(self, cx, cy, r, col="#fff", op=0.85):
        self.add(f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="{col}" fill-opacity="{op}"/>')

    def shadow(self, cx=24, cy=44.5, rx=15, ry=2.6):
        self.add(f'<ellipse cx="{cx}" cy="{cy}" rx="{rx}" ry="{ry}" fill="#000" fill-opacity="0.22"/>')

    def stroke2(self, d, col, w):
        """An outlined stroke: ink under, colour over (handles, rails, snake bodies)."""
        self.add(f'<path d="{d}" fill="none" stroke="{INK}" stroke-width="{w + 2 * SW2 * 0.95}" stroke-linecap="round" stroke-linejoin="round"/>')
        c = self.g(col) if col in G else col
        self.add(f'<path d="{d}" fill="none" stroke="{c}" stroke-width="{w}" stroke-linecap="round" stroke-linejoin="round"/>')

    def svg(self):
        return ('<svg xmlns="http://www.w3.org/2000/svg" width="192" height="192" viewBox="0 0 48 48">'
                + "<defs>" + "".join(self.defs.values()) + "</defs>" + "".join(self.body) + "</svg>")


def star_path(cx, cy, r1, r2, n=5, rot=-90):
    pts = []
    for i in range(n * 2):
        r = r1 if i % 2 == 0 else r2
        a = math.radians(rot + i * 180 / n)
        pts.append(f"{cx + r * math.cos(a):.2f} {cy + r * math.sin(a):.2f}")
    return "M" + " L".join(pts) + "Z"


def gear_path(cx, cy, r_out, r_in, teeth=8, tooth=0.42):
    d = []
    step = 2 * math.pi / teeth
    for i in range(teeth):
        a0 = i * step
        for (a, r) in [(a0 - step * tooth / 2 - 0.08, r_in), (a0 - step * tooth / 2 + 0.06, r_out),
                       (a0 + step * tooth / 2 - 0.06, r_out), (a0 + step * tooth / 2 + 0.08, r_in)]:
            d.append(f"{cx + r * math.cos(a):.2f} {cy + r * math.sin(a):.2f}")
    return "M" + " L".join(d) + "Z"


def pawn(ic, x, y, s, col):
    """A ludo pawn standing on (x, y) (its foot), height ~ 34 * s."""
    t = lambda px, py: f"{x + px * s:.2f} {y + py * s:.2f}"
    ic.path(f"M{t(-5.2, -15)} C{t(-5, -9)} {t(-9.5, -6)} {t(-10.5, -3.6)} Q{t(-11.5, 0)} {t(-7.5, 0)} H{x + 7.5 * s:.2f} "
            f"Q{t(11.5, 0)} {t(10.5, -3.6)} C{t(9.5, -6)} {t(5, -9)} {t(5.2, -15)} Z", col)
    ic.ellipse(x, y - 16 * s, 7.6 * s, 2.6 * s, col, SW2)
    ic.circle(x, y - 24.5 * s, 7 * s, col)
    ic.gloss(f"M{t(-3.6, -27.5)} Q{t(-2.6, -29.8)} {t(-0.4, -30.2)}", 2.0 * s)
    ic.gloss(f"M{t(-4.2, -10.5)} L{t(-6.4, -5)}", 1.8 * s, 0.5)


def person(ic, x, y, s, shirt, hair="#3b1a0c"):
    """Head and shoulders, the shoulders' bottom on y."""
    t = lambda px, py: f"{x + px * s:.2f} {y + py * s:.2f}"
    ic.path(f"M{t(-12, 0)} Q{t(-12, -11)} {t(0, -11)} Q{t(12, -11)} {t(12, 0)} Z", shirt)
    ic.circle(x, y - 17.5 * s, 7.2 * s, "skin")
    ic.add(f'<path d="M{t(-7.2, -17.5)} Q{t(-7.6, -25.8)} {t(0, -25.6)} Q{t(7.6, -25.8)} {t(7.2, -17.5)} '
           f'Q{t(3, -22.5)} {t(-7.2, -17.5)} Z" fill="{hair}"/>')
    ic.gloss(f"M{t(-6.5, -6)} Q{t(-3, -8.6)} {t(1, -8.8)}", 1.8 * s, 0.55)


ICONS = {}


def icon(path):
    def deco(f):
        ICONS[path] = f
        return f
    return deco


# --- the bottom bar -------------------------------------------------------------------------------------------------

@icon("home/hi_home.svg")
def _home(ic):
    ic.shadow(24, 44.6, 15)
    ic.path("M10.5 24.5 L24 13 L37.5 24.5 V40 a3 3 0 0 1 -3 3 H13.5 a3 3 0 0 1 -3 -3 Z", "cream")
    ic.path("M19.5 43 V34 a4.5 4.5 0 0 1 9 0 V43 Z", "teal", SW2)
    ic.circle(24, 24.5, 3.6, "blue", SW2)
    ic.path("M4.2 22.6 L24 5.2 L43.8 22.6 Q45.6 26.4 41.6 27.4 L24 12.6 L6.4 27.4 Q2.4 26.4 4.2 22.6 Z", "red")
    ic.gloss("M7.6 22.2 L22.4 9.4", 2.2)
    ic.dot(32, 37.5, 1.4, INK, 0.0)


@icon("home/hi_shop.svg")
def _shop(ic):
    ic.shadow(24, 44.6, 15)
    ic.stroke2("M16.5 20 V14.5 a7.5 7.5 0 0 1 15 0 V20", "gold", 3.4)
    ic.path("M10.2 17 H37.8 a2.2 2.2 0 0 1 2.2 2 L41.4 40.4 a2.4 2.4 0 0 1 -2.4 2.6 H9 a2.4 2.4 0 0 1 -2.4 -2.6 L8 19 a2.2 2.2 0 0 1 2.2 -2 Z", "teal")
    ic.path(star_path(24, 30.5, 7.6, 3.4), "gold", SW2)
    ic.circle(16.5, 21.6, 1.9, INK, 0)
    ic.circle(31.5, 21.6, 1.9, INK, 0)
    ic.gloss("M11.6 21 L10.8 33", 2.2)


@icon("ic_trophy.svg")
def _trophy(ic):
    ic.shadow(24, 44.6, 13)
    ic.stroke2("M13.5 12.5 H8.6 V15.6 A6.8 6.8 0 0 0 14.8 22.6 M34.5 12.5 H39.4 V15.6 A6.8 6.8 0 0 1 33.2 22.6", "gold", 2.6)
    ic.path("M21.2 29 h5.6 l1.4 7 h-8.4 z", "gold", SW2)
    ic.rect(12.5, 35.2, 23, 7.6, 2.8, "wood")
    ic.rect(19, 37.4, 10, 3.2, 1.2, "gold", 1.6)
    ic.path("M12.8 6.5 H35.2 V18.5 a11.2 11.2 0 0 1 -22.4 0 Z", "gold")
    ic.path(star_path(24, 18.2, 5.6, 2.5), "#fff6d8", 2.0)
    ic.gloss("M16.8 10.5 V18", 2.4)


@icon("home/hi_inventory.svg")
def _chest(ic):
    ic.shadow(24, 44.6, 17)
    ic.path("M6.5 22 H41.5 V39.5 a3 3 0 0 1 -3 3 H9.5 a3 3 0 0 1 -3 -3 Z", "orange")
    ic.path("M6.5 22 V17 C6.5 11 11 7 17 7 H31 C37 7 41.5 11 41.5 17 V22 Z", "red")
    for x in (12.5, 35.5):
        ic.rect(x - 2.6, 7.6, 5.2, 34.6, 1.2, "gold", 2.0)
    ic.rect(18.5, 16.5, 11, 12, 2.6, "gold", SW2)
    ic.circle(24, 21.2, 1.8, INK, 0)
    ic.add(f'<path d="M24 22 V25.4" stroke="{INK}" stroke-width="2" stroke-linecap="round"/>')
    ic.gloss("M17.5 10.5 H29", 2.2)


# --- the Shop / Inventory tabs ----------------------------------------------------------------------------------------

@icon("cat_rooms.svg")
def _rooms(ic):
    # a round café table, a ludo board on it (the rooms are cafés around a board)
    ic.shadow(24, 45, 12, 2.0)
    ic.path("M20.6 33 h6.8 l1.8 9.6 h-10.4 z", "wood", SW2)
    ic.ellipse(24, 30.2, 21, 10.6, "#7a3e18")
    ic.ellipse(24, 27.2, 21, 10.6, "lwood")
    c, top, rgt, bot, lft = (24, 25.4), (24, 12.6), (40.5, 25.4), (24, 38.2), (7.5, 25.4)
    pt = lambda p: f"{p[0]} {p[1]}"
    for a, b, col in [(lft, top, "#f25a55"), (top, rgt, "#4cc85a"), (rgt, bot, "#ffd04a"), (bot, lft, "#4aa3f0")]:
        ic.add(f'<path d="M{pt(c)} L{pt(a)} L{pt(b)} Z" fill="{col}"/>')
    # the cream cross of paths, and the centre
    ic.add(f'<path d="M{pt(top)} L{pt(bot)} M{pt(lft)} L{pt(rgt)}" stroke="#fff6e6" stroke-width="3.4"/>')
    ic.add(f'<path d="M{pt(top)} L{pt(rgt)} L{pt(bot)} L{pt(lft)} Z" fill="none" stroke="{INK}" stroke-width="{SW2}" stroke-linejoin="round"/>')
    ic.add(f'<path d="M24 22 L28.4 25.4 L24 28.8 L19.6 25.4 Z" fill="#fff6e6" stroke="{INK}" stroke-width="1.6" stroke-linejoin="round"/>')
    for (x, y) in [(15.8, 21.6), (32.2, 21.6), (15.8, 29.2), (32.2, 29.2)]:
        ic.add(f'<ellipse cx="{x}" cy="{y}" rx="2.4" ry="1.4" fill="#fff" stroke="{INK}" stroke-width="1.2"/>')


@icon("cat_pawns.svg")
def _pieces(ic):
    ic.shadow(24, 44.6, 17)
    pawn(ic, 17, 41.5, 0.92, "red")
    pawn(ic, 31, 43.4, 0.98, "blue")


@icon("cat_emotes.svg")
def _emotes(ic):
    ic.shadow(24, 45, 13, 2.2)
    ic.circle(24, 23.5, 18.5, "gold")
    ic.add(f'<ellipse cx="17.6" cy="20" rx="2.6" ry="3.6" fill="{INK}"/><ellipse cx="30.4" cy="20" rx="2.6" ry="3.6" fill="{INK}"/>')
    ic.dot(18.4, 18.7, 1.0)
    ic.dot(31.2, 18.7, 1.0)
    ic.add('<circle cx="12.6" cy="27.2" r="3" fill="#ff7a8a" fill-opacity=".55"/><circle cx="35.4" cy="27.2" r="3" fill="#ff7a8a" fill-opacity=".55"/>')
    ic.path("M15 26.4 Q24 28.4 33 26.4 Q32 36.6 24 36.6 Q16 36.6 15 26.4 Z", "#9a2a2a", SW2)
    ic.add('<path d="M19 33.6 Q24 30.8 29 33.6 Q27.4 35.4 24 35.4 Q20.6 35.4 19 33.6 Z" fill="#ff7a7a"/>')
    ic.gloss("M10.5 17 Q12.4 10.6 18.4 8.2", 2.6)


@icon("cat_avatars.svg")
def _look(ic):
    ic.shadow(24, 45.2, 13, 2.2)
    ic.rect(5.5, 5.5, 37, 37, 11, "gold")
    ic.rect(11, 11, 26, 26, 6.5, "blue", SW2)
    ic.add('<clipPath id="cl"><rect x="12.2" y="12.2" width="23.6" height="23.6" rx="5.4"/></clipPath><g clip-path="url(#cl)">')
    person(ic, 24, 38, 0.92, "red")
    ic.add("</g>")
    ic.add(f'<rect x="11" y="11" width="26" height="26" rx="6.5" fill="none" stroke="{INK}" stroke-width="{SW2}"/>')
    for x, y in [(8.6, 8.6), (39.4, 8.6), (8.6, 39.4), (39.4, 39.4)]:
        ic.circle(x, y, 2.6, "red", 1.8)
    ic.gloss("M9.5 15 Q10 10.4 14.6 9.4", 2.0, 0.75)


# --- Home ---------------------------------------------------------------------------------------------------------

@icon("home/hi_gift.svg")
def _gift(ic):
    ic.shadow(24, 44.6, 15)
    ic.rect(9, 21, 30, 21.5, 3, "red")
    ic.rect(6.5, 14.5, 35, 9, 3, "red")
    ic.rect(20.6, 14.5, 6.8, 28, 1, "gold", SW2)
    ic.path("M24 14.5 C17 4 8.5 8.6 12 13 C13.6 15 19 14.8 24 14.5 Z", "gold", SW2)
    ic.path("M24 14.5 C31 4 39.5 8.6 36 13 C34.4 15 29 14.8 24 14.5 Z", "gold", SW2)
    ic.gloss("M10.5 17.4 H17", 2.0)
    ic.gloss("M12.6 25 V34", 2.0, 0.5)


@icon("home/hi_spin.svg")
def _spin(ic):
    ic.shadow(24, 45, 13, 2.2)
    cols = ["#f25a55", "#ffd04a", "#3cc9ae", "#4aa3f0", "#9a6ae8", "#ff8a3d"]
    cx, cy, r = 24, 25.5, 17
    for i, col in enumerate(cols):
        a0 = math.radians(-90 + i * 60)
        a1 = math.radians(-90 + (i + 1) * 60)
        ic.add(f'<path d="M{cx} {cy} L{cx + r * math.cos(a0):.2f} {cy + r * math.sin(a0):.2f} '
               f'A{r} {r} 0 0 1 {cx + r * math.cos(a1):.2f} {cy + r * math.sin(a1):.2f} Z" fill="{col}" '
               f'stroke="{INK}" stroke-width="1.4" stroke-linejoin="round"/>')
    ic.add(f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="none" stroke="{INK}" stroke-width="{SW + 3.4}"/>')
    ic.add(f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="none" stroke="{ic.g("gold")}" stroke-width="3.2"/>')
    for i in range(6):
        a = math.radians(-60 + i * 60)
        ic.dot(cx + r * math.cos(a), cy + r * math.sin(a), 0.95, "#fff", 0.95)
    ic.circle(cx, cy, 4, "cream", SW2)
    ic.path("M18.6 3.6 H29.4 L24 12.6 Z", "red", SW2)


@icon("home/hi_gear.svg")
def _gear(ic):
    ic.path(gear_path(24, 24, 20, 15.2, 8, 0.46), "silver")
    ic.circle(24, 24, 6.6, "dark", SW2)
    ic.gloss("M11.6 17 Q14 12.4 18.6 10.6", 2.2)


@icon("home/hi_ludo.svg")
def _ludo(ic):
    ic.rect(5.5, 5.5, 37, 37, 7, "cream")
    for (x, y, col) in [(9, 9, "red"), (27, 9, "green"), (9, 27, "blue"), (27, 27, "gold")]:
        ic.rect(x, y, 12, 12, 3, col, SW2)
        ic.add(f'<circle cx="{x + 6}" cy="{y + 6}" r="2.6" fill="#fff" stroke="{INK}" stroke-width="1.4"/>')
    ic.add(f'<path d="M21 21 L27 21 L24 24 Z" fill="#4cc85a"/><path d="M27 21 L27 27 L24 24 Z" fill="#ffd04a"/>'
           f'<path d="M27 27 L21 27 L24 24 Z" fill="#4aa3f0"/><path d="M21 27 L21 21 L24 24 Z" fill="#f25a55"/>'
           f'<rect x="21" y="21" width="6" height="6" fill="none" stroke="{INK}" stroke-width="1.4"/>')
    ic.gloss("M9.6 6.8 H16", 1.8, 0.0)


@icon("home/hi_snakes.svg")
def _snakes(ic):
    ic.stroke2("M10 43 L19 5 M20 44.5 L29 6.5", "lwood", 3.2)
    for i in range(5):
        t = 0.14 + i * 0.18
        x0, y0 = 10 + 9 * t, 43 - 38 * t
        ic.stroke2(f"M{x0:.2f} {y0:.2f} L{x0 + 10:.2f} {y0 + 1.5:.2f}", "lwood", 2.4)
    ic.stroke2("M28 42 C42 40 40 30 32 28 C24 26 26 16 36 13", "green", 5.6)
    ic.add(f'<path d="M30 41.5 C38 40 37 32 32 30" fill="none" stroke="#c8f5a0" stroke-width="1.6" stroke-linecap="round" stroke-dasharray="1.6 2.4"/>')
    ic.circle(38.2, 11.6, 5, "green", SW2)
    ic.dot(39.4, 10.4, 1.5, "#fff", 1)
    ic.dot(39.7, 10.6, 0.8, INK, 1)
    ic.add(f'<path d="M42.8 12.6 L45.6 13.6 M45.6 13.6 L46.6 12.2 M45.6 13.6 L46.4 15.2" stroke="#e5484d" stroke-width="1.2" stroke-linecap="round"/>')


@icon("home/hi_resume.svg")
def _resume(ic):
    ic.circle(24, 24, 19, "teal")
    ic.path("M19.5 14.5 Q19.5 12.3 21.5 13.3 L33.5 21.8 Q35.3 24 33.5 26.2 L21.5 34.7 Q19.5 35.7 19.5 33.5 Z", "cream")
    ic.gloss("M10.5 17.5 Q12.6 11.8 18 9.6", 2.4)


@icon("home/hi_cpu.svg")
def _cpu(ic):
    ic.shadow(24, 45, 14, 2.2)
    ic.stroke2("M24 13 V7", "silver", 2.2)
    ic.circle(24, 5.6, 3.2, "red", SW2)
    ic.rect(4.5, 22, 5, 11, 2, "blue", SW2)
    ic.rect(38.5, 22, 5, 11, 2, "blue", SW2)
    ic.rect(8.5, 12.5, 31, 29, 9, "silver")
    ic.rect(13, 18, 22, 13.5, 5, "dark", SW2)
    ic.add('<circle cx="19" cy="24.6" r="3.2" fill="#6ff0d6"/><circle cx="29" cy="24.6" r="3.2" fill="#6ff0d6"/>')
    ic.dot(20, 23.6, 1.1)
    ic.dot(30, 23.6, 1.1)
    ic.add(f'<path d="M19 36 H29" stroke="{INK}" stroke-width="2.4" stroke-linecap="round"/>')
    ic.gloss("M12.4 20 Q13 15.6 17.6 15.2", 2.2)


@icon("home/hi_pass_play.svg")
def _pass(ic):
    ic.shadow(24, 45, 17)
    pawn(ic, 17, 43, 0.95, "red")
    pawn(ic, 32.5, 39, 0.82, "blue")
    ic.stroke2("M21.5 6.5 Q27.5 2.8 33.5 6.2", "gold", 2.4)
    ic.path("M33.8 2.6 L37.6 7.4 L31.6 8.6 Z", "gold", 1.8)


@icon("perk_friends.svg")
def _friends(ic):
    ic.shadow(24, 45, 18)
    person(ic, 31.5, 39.5, 0.86, "purple", "#6b3a20")
    person(ic, 18, 43, 1.0, "teal")


@icon("home/hi_coins.svg")
def _coins(ic):
    ic.shadow(24, 45, 16)
    for i, y in enumerate((38.5, 33, 27.5)):
        ic.ellipse(17, y + 2.6, 12, 4.6, "#c26a0a", SW2)
        ic.ellipse(17, y, 12, 4.6, "gold", SW2)
    ic.circle(32, 21, 12.5, "gold")
    ic.circle(32, 21, 8.2, "#f7b528", 2.0)
    ic.path(star_path(32, 21.4, 5.2, 2.3), "#fff2b0", 1.6)
    ic.gloss("M22.6 16.5 Q24.2 11.6 29 10.2", 2.2)


@icon("home/hi_coin.svg")
def _coin(ic):
    ic.circle(24, 24, 19, "gold")
    ic.circle(24, 24, 12.6, "#f7b528", SW2)
    ic.path(star_path(24, 24.6, 8, 3.6), "#fff2b0", 2.0)
    ic.gloss("M9.6 18.5 Q11.6 11.4 18 8.8", 2.6)


@icon("home/hi_again.svg")
def _again(ic):
    # a bold round arrow (Daily missions, reroll)
    ic.stroke2("M36.5 16.5 A14 14 0 1 0 38 27.5", "gold", 5.6)
    ic.path("M30.2 6.4 L42.6 9.2 L38.2 21.2 Z", "gold", SW2)
    ic.add('<path d="M12.6 20.5 Q14 14.4 19.6 11.6" fill="none" stroke="#fff" stroke-opacity=".75" stroke-width="2" stroke-linecap="round"/>')


# --- small ones -------------------------------------------------------------------------------------------------------

@icon("ic_eye.svg")
def _eye(ic):
    ic.path("M3.5 24 C8.6 14.6 15.6 10 24 10 S39.4 14.6 44.5 24 C39.4 33.4 32.4 38 24 38 S8.6 33.4 3.5 24 Z", "cream")
    ic.circle(24, 24, 9, "blue", SW2)
    ic.circle(24, 24, 4, INK, 0)
    ic.dot(21, 21, 2.0, "#fff", 1)


@icon("ic_lock_gold.svg")
def _lock(ic):
    ic.stroke2("M15.5 22 V16 a8.5 8.5 0 0 1 17 0 V22", "silver", 3.6)
    ic.rect(9.5, 20.5, 29, 22, 6, "gold")
    ic.circle(24, 29.4, 3, INK, 0)
    ic.add(f'<path d="M24 30.5 V35.5" stroke="{INK}" stroke-width="3" stroke-linecap="round"/>')
    ic.gloss("M13.6 25 V33", 2.2)


@icon("ic_crown.svg")
def _crown(ic):
    ic.path("M7 37 L4.6 15.5 L15.5 23.5 L24 9.5 L32.5 23.5 L43.4 15.5 L41 37 Z", "gold")
    ic.rect(6.5, 35, 35, 7, 2.6, "orange", SW2)
    for x, y in [(4.6, 15.5), (24, 9.5), (43.4, 15.5)]:
        ic.circle(x, y, 3, "gold", 2.0)
    ic.circle(24, 27.5, 3.6, "red", 2.0)
    ic.circle(14.5, 30, 2.4, "teal", 1.8)
    ic.circle(33.5, 30, 2.4, "blue", 1.8)
    ic.gloss("M9 20.5 L10.5 31", 2.0)


@icon("ic_star.svg")
def _star(ic):
    ic.path(star_path(24, 25, 20, 9.2), "gold")
    ic.gloss("M15.4 20.5 L19.6 20", 2.2)


def main():
    for rel, f in ICONS.items():
        ic = Icon()
        f(ic)
        dst = os.path.join(OUT, rel)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        with open(dst, "w") as fh:
            fh.write(ic.svg())
    print(len(ICONS), "icons")


main()
