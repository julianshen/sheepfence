#!/usr/bin/env python3
"""Render the developer guides and validate local links without fetching URLs."""
from html import escape
from html.parser import HTMLParser
from pathlib import Path
import shutil
from string import Template
from urllib.parse import unquote, urlsplit

import markdown

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "docs/developer"
OUTPUT = ROOT / ".build/site"
PAGES = [
    ("index", "Overview", "A foreground polygon geofencing SDK for Swift."),
    ("quick-start", "Quick start", "Install SheepFence and evaluate your first location."),
    ("queries", "Queries & distance", "Find matching regions and measure boundary distance."),
    ("monitoring", "Monitoring & GPS", "Manage location sources, events and GPS availability."),
    ("datasets", "Datasets", "Author and update transactional GeoJSON snapshots."),
    ("api", "API guide", "Choose the right SheepFence API and configuration."),
    ("troubleshooting", "Troubleshooting", "Diagnose location, import and subscription failures."),
    ("contributing", "Contributing", "Build, test and maintain SheepFence documentation."),
]


class GuideRenderer(markdown.treeprocessors.Treeprocessor):
    def run(self, root):
        # Rewrite links only, never code samples or prose containing '.md'.
        for link in root.iter("a"):
            href = link.get("href", "")
            parts = urlsplit(href)
            if not parts.scheme and not parts.netloc and parts.path.endswith(".md"):
                link.set("href", href.replace(parts.path, parts.path[:-3] + ".html", 1))
        for table in list(root.iter("table")):
            for parent in root.iter():
                if table in list(parent):
                    import xml.etree.ElementTree as ET
                    wrapper = ET.Element("div", {"class": "table-scroll", "tabindex": "0", "role": "region", "aria-label": "Scrollable reference table"})
                    index = list(parent).index(table)
                    parent.remove(table)
                    wrapper.append(table)
                    parent.insert(index, wrapper)
                    break


class GuideExtension(markdown.extensions.Extension):
    def extendMarkdown(self, md):
        md.treeprocessors.register(GuideRenderer(md), "guide-links", 5)


class LinkInventory(HTMLParser):
    def __init__(self):
        super().__init__()
        self.links = []
        self.ids = set()

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if "id" in attrs:
            self.ids.add(attrs["id"])
        for key in ("href", "src"):
            if key in attrs:
                self.links.append(attrs[key])


def main():
    if OUTPUT.exists():
        shutil.rmtree(OUTPUT)
    OUTPUT.mkdir(parents=True)
    shutil.copytree(ROOT / "docs/site/assets", OUTPUT / "assets")
    template = Template((ROOT / "docs/site/template.html").read_text())
    for i, (slug, label, description) in enumerate(PAGES):
        text = (SOURCE / f"{slug}.md").read_text()
        if not text.startswith("# "):
            raise ValueError(f"Missing page title: {slug}")
        renderer = markdown.Markdown(extensions=["fenced_code", "tables", "toc", GuideExtension()])
        content = renderer.convert(text)
        nav = "\n".join(
            f'<a href="{key}.html"' + (' aria-current="page"' if key == slug else '') + f'>{escape(name)}</a>'
            for key, name, _ in PAGES
        )
        previous = "" if i == 0 else f'<a href="{PAGES[i-1][0]}.html">← {escape(PAGES[i-1][1])}</a>'
        following = "" if i == len(PAGES)-1 else f'<a href="{PAGES[i+1][0]}.html">{escape(PAGES[i+1][1])} →</a>'
        html = template.substitute(
            title=escape(label), description=escape(description), nav=nav,
            content=content, toc=renderer.toc, slug=slug,
            previous=previous, following=following,
            page_class="overview" if slug == "index" else "guide",
        )
        (OUTPUT / f"{slug}.html").write_text(html)
    (OUTPUT / ".nojekyll").touch()
    inventories = {}
    for path in OUTPUT.glob("*.html"):
        parser = LinkInventory()
        parser.feed(path.read_text())
        inventories[path.resolve()] = parser
    errors = []
    for page, inventory in inventories.items():
        for href in inventory.links:
            parts = urlsplit(href)
            if parts.scheme or parts.netloc:
                continue
            target = (page.parent / unquote(parts.path)).resolve() if parts.path else page
            if not target.is_relative_to(OUTPUT.resolve()) or not target.exists():
                errors.append(f"{page.name}: missing local link {href}")
            elif parts.fragment and target in inventories and unquote(parts.fragment) not in inventories[target].ids:
                errors.append(f"{page.name}: missing anchor {href}")
    if errors:
        raise SystemExit("\n".join(errors))
    print(f"Built {len(PAGES)} pages; all local links and anchors valid: {OUTPUT}")


if __name__ == "__main__":
    main()
