#!/usr/bin/env python3
"""Carceral Consultation theme check (2026-11-13). Run: scripts/theme/check_theme.sh

Fails (exit 1) if any color is written anywhere except the theme:
  1. a Tailwind palette class (bg-gray-500, text-white, ring-indigo-600, ...)
  2. a color value (#hex, rgb(), hsl(), or a color name like "white") in
     templates, Elixir, scripts or stylesheets
  3. a color class that names a role the theme does not define (Tailwind
     would silently drop it)
  4. an email color in lib/claper_web/theme.ex that differs from the theme
  5. an image icon with colors baked in that is not on the allowed list

The theme itself (assets/css/theme-config.css) and its two mirrors
(lib/claper_web/theme.ex for email, assets/js/theme.js for scripts) are the
only places colors may be written. See docs/THEME.md.
"""
import pathlib, re, sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
THEME_CSS = ROOT / "assets/css/theme-config.css"
THEME_EX = ROOT / "lib/claper_web/theme.ex"
THEME_JS = ROOT / "assets/js/theme.js"
ALLOWED_FILES = {THEME_CSS, THEME_EX, THEME_JS}

# Images whose colors are content, not interface: emoji reaction artwork,
# the wordmarks (generated from the theme colors by scripts/brand/make_wordmarks.py),
# and other organizations' logos.
ALLOWED_IMAGES = {
    "icons/clap.svg", "icons/heart.svg", "icons/hundred.svg", "icons/laugh.svg",
    "icons/raisehand.svg", "icons/thumb.svg",
    "logo.svg", "logo-large.svg", "logo-large-black.svg", "logo-white.svg",
}

PALETTE = ("slate|gray|grey|zinc|neutral|stone|red|orange|amber|yellow|lime|green|emerald|teal|cyan|"
           "sky|blue|indigo|violet|purple|fuchsia|pink|rose|white|black|supporting-[a-z]+")
UTIL = ("bg|text|border(?:-[trblxy])?|divide|ring(?:-offset)?|outline|decoration|placeholder|"
        "from|via|to|shadow|fill|stroke|caret|accent")
PALETTE_CLASS = re.compile(rf"(?<![\w\-/#])(?:[\w\-\[\]&>*:]+:)*(?:{UTIL})-(?:{PALETTE})(?:-\d+)?(?:/\d+)?(?![\w\-])")
SHADE_CLASS = re.compile(rf"(?<![\w\-/#])(?:[\w\-\[\]&>*:]+:)*(?:{UTIL})-(?:primary|secondary|accent)-\d+(?![\w\-])")
ARBITRARY = re.compile(rf"(?<![\w\-])(?:{UTIL})-\[(?:#|rgb|hsl|color)")
LITERAL = re.compile(r"(?<![\w&])#(?:[0-9a-fA-F]{8}|[0-9a-fA-F]{6}|[0-9a-fA-F]{3})(?![\w-])|\b(?:rgba?|hsla?|oklch|oklab)\(")
NAMES = "white|black|red|green|blue|gray|grey|purple|pink|orange|yellow|cyan|magenta|navy|silver|maroon"
NAMED = re.compile(rf"(?:(?:color|background(?:-color)?|border(?:-[a-z]+)?-color|border|fill|stroke|outline(?:-color)?)\s*:\s*[^;\"'}}]*\b(?:{NAMES})\b"
                   rf"|\b(?:fill|stroke|color|bgcolor|stop-color)=[\"'](?:{NAMES})[\"']"
                   rf"|\[--[\w-]+:(?:{NAMES})\])")
# Things that look like colors but are not.
NOT_COLOR = re.compile(r"#\{|&#|href=\"#|url\(#|#[0-9a-fA-F]{3,8}\b(?=[^\n]*(?:id=|phx-|\.svg#))")

SOURCES = [p for d in ("lib", "assets/js", "assets/css") for p in (ROOT / d).rglob("*")
           if p.is_file() and p.suffix in {".ex", ".exs", ".heex", ".eex", ".js", ".mjs", ".css", ".scss"}]

def roles_from_theme():
    css = THEME_CSS.read_text()
    roles = set(re.findall(r"--color-([a-z0-9-]+)\s*:", css)) - {"*"}
    return roles

def strip_comments(text, suffix):
    if suffix in {".css", ".scss", ".js", ".mjs"}:
        text = re.sub(r"/\*.*?\*/", lambda m: "\n" * m.group(0).count("\n"), text, flags=re.S)
    if suffix in {".js", ".mjs", ".scss"}:
        text = re.sub(r"(?m)(^|[^:])//.*$", r"\1", text)
    if suffix in {".ex", ".exs", ".heex", ".eex"}:
        text = re.sub(r"<!--.*?-->", lambda m: "\n" * m.group(0).count("\n"), text, flags=re.S)
        text = re.sub(r"(?m)^\s*#(?!\{).*$", "", text)
        # @moduledoc / @doc text is prose, not code
        text = re.sub(r'@(?:module)?doc\s+"""(.*?)"""', lambda m: "\n" * m.group(0).count("\n"), text, flags=re.S)
    return text

def main():
    problems = []
    roles = roles_from_theme()
    color_class = re.compile(rf"(?<![\w\-/#])(?:[\w\-\[\]&>*:]+:)*(?:bg|text|border|divide|ring|outline|decoration|placeholder|from|via|to|fill|stroke)-([a-z][a-z0-9-]*?)(?:/\d+)?(?=[\s\"'`}}\]),]|$)(?!\s*:)")
    # Non-color utilities that share prefixes with color utilities.
    non_color = re.compile(r"^(?:\d|xs|sm|base$|lg|xl|\d?xl|left|right|center|justify|start|end|wrap|nowrap|balance|pretty|ellipsis|clip|"
                           r"x|y|t|r|b|l|s|e|solid|dashed|dotted|double|none|hidden|collapse|separate|spacing|offset|inset|"
                           r"opacity|cover|contain|auto|fixed|local|scroll|repeat|no-repeat|origin|clip|linear|radial|conic|"
                           r"gradient|blend|bottom|top|body|small-body|h\d|display|current|transparent|inherit|underline|"
                           r"color$|overline|line-through|from-font|wavy|transparent|tr|tl|br|bl|width|size|px|full|screen|min|max|"
                           r"fit|ellipsis|reverse|indent|shadow|wrap|stroke|fill|via|to|from)")
    for path in SOURCES:
        rel = path.relative_to(ROOT)
        if path in ALLOWED_FILES or "node_modules" in path.parts or "vendor" in path.parts:
            continue
        text = strip_comments(path.read_text(errors="replace"), path.suffix)
        for i, line in enumerate(text.split("\n"), 1):
            clean = NOT_COLOR.sub("", line)
            for rx, why in ((PALETTE_CLASS, "fixed palette class"), (SHADE_CLASS, "old color scale"),
                            (ARBITRARY, "arbitrary color class"), (LITERAL, "color value"), (NAMED, "color name")):
                for m in rx.finditer(clean):
                    problems.append(f"{rel}:{i}: {why}: {m.group(0).strip()}")
            if path.suffix in {".ex", ".heex", ".eex", ".js", ".mjs"}:
                for m in color_class.finditer(line):
                    name = m.group(1)
                    if non_color.match(name) or name in roles:
                        continue
                    problems.append(f"{rel}:{i}: unknown color role: {m.group(0).strip()}")

    # 4. email mirror matches the theme
    css = THEME_CSS.read_text()
    # Emails use the dark theme; the dark value of each role is its first
    # definition in the file (the light theme comes after).
    theme_vals = {}
    for k, v in re.findall(r"--color-([a-z0-9-]+)\s*:\s*(#[0-9a-fA-F]{6})", css):
        theme_vals.setdefault(k, v.lower())
    mirror = {"page": "base-100", "card": "base-200", "raised": "base-300", "text": "base-content",
              "muted": "muted", "line": "line", "button": "primary", "button_text": "primary-content"}
    ex = THEME_EX.read_text()
    for key, role in mirror.items():
        m = re.search(rf"\b{key}:\s*\"(#[0-9a-fA-F]{{6}})\"", ex)
        if not m:
            problems.append(f"lib/claper_web/theme.ex: email color :{key} missing")
        elif m.group(1).lower() != theme_vals.get(role):
            problems.append(f"lib/claper_web/theme.ex: email :{key} is {m.group(1)}, theme {role} is {theme_vals.get(role)}")

    # 5. images with baked-in colors
    images = ROOT / "priv/static/images"
    for svg in images.rglob("*.svg"):
        rel = str(svg.relative_to(images))
        if rel in ALLOWED_IMAGES:
            continue
        body = svg.read_text(errors="replace")
        if LITERAL.search(body) or re.search(rf"(?:fill|stroke)=\"(?:{NAMES})\"", body):
            problems.append(f"priv/static/images/{rel}: icon has colors baked in (use currentColor or ClaperWeb.Icons)")

    if problems:
        print(f"Theme check FAILED: {len(problems)} problem(s)\n")
        print("\n".join(sorted(set(problems))))
        return 1
    print(f"Theme check passed: {len(SOURCES)} files, {len(roles)} theme roles, no stray colors.")
    return 0

if __name__ == "__main__":
    sys.exit(main())
