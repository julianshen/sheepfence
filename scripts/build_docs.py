#!/usr/bin/env python3
"""Render the developer guides and validate local links without fetching URLs."""
from html import escape
from html.parser import HTMLParser
from pathlib import Path
import shutil
import json
import re
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
    ("fence-editor", "Fence Studio", "Draw and edit SDK-ready GeoJSON on OpenStreetMap."),
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


LOCALES = {"en": "English", "zh-Hant": "繁體中文", "ja": "日本語"}
CATALOG = json.loads((ROOT / "docs/site/assets/editor/messages.json").read_text())
LABELS = {
    "zh-Hant": ["總覽", "快速開始", "查詢與距離", "監控與 GPS", "Fence Studio", "資料集", "API 指南", "疑難排解", "參與開發"],
    "ja": ["概要", "クイックスタート", "検索と距離", "監視と GPS", "Fence Studio", "データセット", "API ガイド", "トラブルシューティング", "開発への参加"],
}


class Localizer(HTMLParser):
    """Translate exact text/accessible labels, never IDs, scripts or user data."""
    def __init__(self, locale):
        super().__init__(convert_charrefs=False)
        self.messages = CATALOG.get(locale, {})
        self.locale = locale
        self.out = []
        self.protected = 0

    def handle_starttag(self, tag, attrs):
        if tag in ("code", "pre", "script", "style"):
            self.protected += 1
        translated = []
        for key, value in attrs:
            if tag == "html" and key == "lang":
                value = self.locale
            elif key in ("aria-label", "placeholder", "title") or (tag == "meta" and key == "content"):
                value = self.messages.get(value, value)
            elif key in ("href", "src") and value and value.startswith("assets/") and self.locale != "en":
                value = "../" + value
            translated.append(key if value is None else f'{key}="{escape(value, quote=True)}"')
        self.out.append("<" + tag + (" " if translated else "") + " ".join(translated) + ">")

    def handle_startendtag(self, tag, attrs):
        self.handle_starttag(tag, attrs)

    def handle_endtag(self, tag):
        self.out.append(f"</{tag}>")
        if tag in ("code", "pre", "script", "style"):
            self.protected -= 1

    def handle_data(self, data):
        key = data.strip()
        if not self.protected and key in self.messages:
            data = data[:len(data)-len(data.lstrip())] + self.messages[key] + data[len(data.rstrip()):]
        self.out.append(data)

    def handle_entityref(self, name):
        self.out.append(f"&{name};")

    def handle_charref(self, name):
        self.out.append(f"&#{name};")

    def handle_decl(self, decl):
        self.out.append(f"<!{decl}>")

    def handle_comment(self, data):
        self.out.append(f"<!--{data}-->")


def localize(html, locale):
    parser = Localizer(locale)
    parser.feed(html)
    return "".join(parser.out)


def language_switcher(locale, slug):
    prefix = "" if locale == "en" else "../"
    links = []
    for code, label in LOCALES.items():
        href = prefix + ("" if code == "en" else code + "/") + slug + ".html"
        current = ' aria-current="page"' if code == locale else ''
        links.append(f'<a href="{href}" lang="{code}" hreflang="{code}"{current}>{label}</a>')
    label = {"en": "Language", "zh-Hant": "語言", "ja": "言語"}[locale]
    return f'<nav class="language-switch" aria-label="{label}"><span>{label}</span>' + " ".join(links) + "</nav>"


def main():
    if OUTPUT.exists():
        shutil.rmtree(OUTPUT)
    OUTPUT.mkdir(parents=True)
    shutil.copytree(ROOT / "docs/site/assets", OUTPUT / "assets")
    template = Template((ROOT / "docs/site/template.html").read_text())
    for locale in LOCALES:
        directory = OUTPUT if locale == "en" else OUTPUT / locale
        source = SOURCE if locale == "en" else SOURCE / locale
        directory.mkdir(exist_ok=True)
        pages = [(slug, LABELS[locale][i] if locale != "en" else label, description)
                 for i, (slug, label, description) in enumerate(PAGES)]
        for i, (slug, label, description) in enumerate(pages):
            text = (source / f"{slug}.md").read_text()
            if not text.startswith("# ") or "[[code:" in text:
                raise ValueError(f"Invalid page: {locale}/{slug}")
            renderer = markdown.Markdown(extensions=["fenced_code", "tables", "toc", "attr_list", GuideExtension()])
            content = renderer.convert(text)
            nav = "\n".join(
                f'<a href="{key}.html"' + (' aria-current="page"' if key == slug else '') + f'>{escape(name)}</a>'
                for key, name, _ in pages
            )
            previous = "" if i == 0 else f'<a href="{pages[i-1][0]}.html">← {escape(pages[i-1][1])}</a>'
            following = "" if i == len(pages)-1 else f'<a href="{pages[i+1][0]}.html">{escape(pages[i+1][1])} →</a>'
            if locale != "en":
                description = "SheepFence · " + label
            html = template.substitute(
                title=escape(label), description=escape(description), nav=nav,
                content=content, toc=renderer.toc,
                slug=slug if locale == "en" else locale + "/" + slug,
                previous=previous, following=following,
                page_class="overview" if slug == "index" else "guide",
            )
            html = localize(html, locale).replace('</header>', '</header>' + language_switcher(locale, slug), 1)
            (directory / f"{slug}.html").write_text(html)
        editor = localize((ROOT / "docs/site/editor.html").read_text(), locale)
        editor = editor.replace('</header>', '</header>' + language_switcher(locale, "editor"), 1)
        (directory / "editor.html").write_text(editor)
    (OUTPUT / ".nojekyll").touch()
    inventories = {}
    for path in OUTPUT.rglob("*.html"):
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
    print(f"Built {len(inventories)} pages across {len(LOCALES)} languages; all local links and anchors valid: {OUTPUT}")


if __name__ == "__main__":
    main()
