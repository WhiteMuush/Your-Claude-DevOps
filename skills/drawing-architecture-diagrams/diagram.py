"""Draws a draw.io style architecture diagram as one self-contained SVG.

Usage from a spec file:

    import os, sys; sys.path.insert(0, os.path.expanduser("~/.claude/skills/drawing-architecture-diagrams"))
    from diagram import Diagram
    d = Diagram(1280, 720)
    d.frame(190, 20, 935, 685, "Microsoft Azure", style="cloud")
    d.node(95, 360, "simple:gitlab", "GitLab.com", "code and CI jobs")
    d.arrow([(127, 360), (286, 360)], "CI jobs")
    d.save("docs/architecture.svg")   # also writes architecture.png for review

Logo sources:
    simple:<slug>           Simple Icons in brand color (https://simpleicons.org)
    azure:<name>            official Azure architecture icon, e.g. azure:Kubernetes-Services
    url:<https://...svg>    any SVG on the web
    file:<path.svg>         a local SVG
"""

import base64
import glob
import hashlib
import os
import re
import urllib.request
import zipfile

CACHE = os.path.expanduser("~/.cache/drawing-architecture-diagrams")
AZURE_ZIP = "https://arch-center.azureedge.net/icons/Azure_Public_Service_Icons_V21.zip"

STYLE = """
.t{font-size:13px;fill:#222;text-anchor:middle}
.s{font-size:11px;fill:#777;text-anchor:middle}
.l{font-size:12px;font-weight:bold;fill:#222}
.b{font-size:15px;font-weight:bold;fill:#222}
.a{fill:none;stroke:#222;stroke-width:1.4}
.d{fill:none;stroke:#222;stroke-width:1.4;stroke-dasharray:5 4}
.cloud{fill:#f3f8fd;stroke:#0078d4;stroke-width:1.5;stroke-dasharray:6 4}
.cluster{fill:#ffffff;stroke:#326ce5;stroke-width:1.5}
.zone{fill:#fafafa;stroke:#bbbbbb;stroke-width:1.2;stroke-dasharray:4 4}
"""


def _fetch(url):
    os.makedirs(CACHE, exist_ok=True)
    path = os.path.join(CACHE, hashlib.sha1(url.encode()).hexdigest() + ".svg")
    if not os.path.exists(path):
        req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
        with urllib.request.urlopen(req, timeout=30) as r, open(path, "wb") as f:
            f.write(r.read())
    return open(path, encoding="utf-8").read()


def _azure(name):
    root = os.path.join(CACHE, "azure")
    if not os.path.isdir(root):
        os.makedirs(CACHE, exist_ok=True)
        zpath = os.path.join(CACHE, "azure.zip")
        urllib.request.urlretrieve(AZURE_ZIP, zpath)
        zipfile.ZipFile(zpath).extractall(root)
    hits = sorted(glob.glob(os.path.join(root, "**", f"*-icon-service-{name}.svg"), recursive=True))
    if not hits:
        raise SystemExit(f"no Azure icon named {name}, try: ls {root}/**/Icons/*/ | grep -i {name}")
    return open(hits[0], encoding="utf-8").read()


def load_logo(source, crop=None):
    """Returns the logo as a data URI, with a viewBox so it scales."""
    kind, _, ref = source.partition(":")
    if kind == "simple":
        svg = _fetch(f"https://cdn.simpleicons.org/{ref}")
    elif kind == "azure":
        svg = _azure(ref)
    elif kind == "url":
        svg = _fetch(ref)
    elif kind == "file":
        svg = open(ref, encoding="utf-8").read()
    else:
        raise SystemExit(f"unknown logo source: {source}")
    head = svg[: svg.index(">", svg.index("<svg")) + 1]
    if "viewBox" not in head:
        w = re.search(r'\swidth="([0-9.]+)', head).group(1)
        h = re.search(r'\sheight="([0-9.]+)', head).group(1)
        svg = svg.replace("<svg", f'<svg viewBox="0 0 {w} {h}"', 1)
    if crop:
        svg = re.sub(r'viewBox="[^"]+"', f'viewBox="{crop}"', svg, count=1)
    svg = re.sub(r'(<svg[^>]*?)\swidth="[^"]*"', r"\1", svg, count=1)
    svg = re.sub(r'(<svg[^>]*?)\sheight="[^"]*"', r"\1", svg, count=1)
    return "data:image/svg+xml;base64," + base64.b64encode(svg.encode()).decode()


class Diagram:
    def __init__(self, width, height):
        self.w, self.h = width, height
        self.items = []
        self.logos = {}

    def _logo(self, source, crop):
        key = (source, crop)
        if key not in self.logos:
            self.logos[key] = load_logo(source, crop)
        return self.logos[key]

    def frame(self, x, y, w, h, title, style="cluster", icon=None):
        """A rounded box around a group: cloud (dashed blue), cluster (solid blue) or zone (dashed grey)."""
        self.items.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="14" class="{style}"/>')
        tx = x + 16
        if icon:
            uri = self._logo(icon, None)
            self.items.append(f'<image x="{x+12}" y="{y+9}" width="24" height="24" href="{uri}" xlink:href="{uri}"/>')
            tx = x + 44
        self.items.append(f'<text x="{tx}" y="{y+27}" class="b">{title}</text>')

    def node(self, cx, cy, source, title, sub=None, size=56, crop=None):
        """A logo centered on (cx, cy), with a caption and an optional grey sub caption below."""
        uri = self._logo(source, crop)
        self.items.append(f'<image x="{cx-size/2}" y="{cy-size/2}" width="{size}" height="{size}" href="{uri}" xlink:href="{uri}"/>')
        y = cy + size / 2 + 16
        self.items.append(f'<text x="{cx}" y="{y}" class="t">{title}</text>')
        if sub:
            self.items.append(f'<text x="{cx}" y="{y+15}" class="s">{sub}</text>')

    def person(self, cx, cy, title, sub=None):
        """A grey user silhouette, for people outside the system."""
        self.items.append(f'<circle cx="{cx}" cy="{cy-14}" r="11" fill="#555"/>')
        self.items.append(f'<path d="M{cx-22},{cy+26} q0,-28 22,-28 q22,0 22,28 z" fill="#555"/>')
        self.items.append(f'<text x="{cx}" y="{cy+44}" class="t">{title}</text>')
        if sub:
            self.items.append(f'<text x="{cx}" y="{cy+59}" class="s">{sub}</text>')

    def arrow(self, points, label=None, at=None, anchor="middle", dashed=False):
        """An orthogonal arrow through the points, label in bold at (x, y) or above the first segment."""
        d = "M" + " L".join(f"{x},{y}" for x, y in points)
        self.items.append(f'<path d="{d}" class="{"d" if dashed else "a"}" marker-end="url(#h)"/>')
        if label:
            if at is None:
                (x1, y1), (x2, y2) = points[0], points[1]
                at = ((x1 + x2) / 2, min(y1, y2) - 10)
            self.items.append(f'<text x="{at[0]}" y="{at[1]}" class="l" text-anchor="{anchor}">{label}</text>')

    def text(self, x, y, value, cls="s", anchor="middle"):
        self.items.append(f'<text x="{x}" y="{y}" class="{cls}" text-anchor="{anchor}">{value}</text>')

    def svg(self):
        body = "\n".join(self.items)
        return f'''<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="{self.w}" height="{self.h}" viewBox="0 0 {self.w} {self.h}" font-family="Helvetica, Arial, sans-serif">
<defs><marker id="h" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto"><path d="M0,0 L10,5 L0,10 z" fill="#222"/></marker>
<style>{STYLE}</style></defs>
<rect width="{self.w}" height="{self.h}" fill="#ffffff"/>
{body}
</svg>
'''

    def save(self, path, png=True):
        """Writes the SVG, and a PNG next to it in the cache so the result can be looked at."""
        with open(path, "w", encoding="utf-8") as f:
            f.write(self.svg())
        if png:
            import cairosvg
            out = os.path.join(CACHE, os.path.basename(path).rsplit(".", 1)[0] + ".png")
            cairosvg.svg2png(url=path, write_to=out)
            print("review:", out)


def zoom(png, box, scale=2):
    """Saves a zoomed crop (x1, y1, x2, y2) of a rendered PNG, to check one area closely."""
    from PIL import Image
    im = Image.open(png).crop(box)
    im = im.resize((im.width * scale, im.height * scale))
    out = png.rsplit(".", 1)[0] + "-zoom.png"
    im.save(out)
    print("zoom:", out)
