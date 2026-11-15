#!/usr/bin/env python3
"""One-time conversion of Claper's fixed colors to Carceral Consultation theme tokens (2026-11-13).

Every color class in templates, Elixir and JS is rewritten to a theme role
(see docs/THEME.md). The rulebook lives in RULES below so every page is
converted the same way. Text that sits on a filled color (text-white on a
primary button, say) becomes that fill's "-content" color, decided per class
string and per variant prefix (hover:, md:, ...).

Usage: convert_colors.py [--write] FILE...   (dry run prints a report)
"""
import re, sys, collections

# family -> shade -> role.  "*" = any shade.  Roles are theme tokens.
BG = {
    "white": "base-200", "black": "stage",
    "gray": {"50": "base-100", "100": "base-300", "200": "base-400", "300": "base-400",
             "400": "faint", "500": "faint", "600": "base-400", "700": "base-300",
             "800": "base-200", "900": "base-100", "950": "stage"},
    "neutral": {"500": "faint", "700": "base-400", "800": "base-300", "900": "base-200"},
    "primary": {"50": "selected", "100": "selected", "200": "selected", "300": "primary",
                "400": "primary", "500": "primary", "600": "primary", "700": "primary",
                "800": "primary", "900": "selected", "": "primary"},
    "secondary": {"*": "base-300", "": "secondary"},
    "indigo": {"50": "selected", "*": "primary"},
    "blue": {"100": "info/15", "*": "info"},
    "red": {"50": "error/15", "100": "error/15", "*": "error"},
    "supporting-red": {"900": "error/15", "*": "error"},
    "green": {"*": "success"}, "supporting-green": {"900": "success/15", "*": "success"},
    "amber": {"50": "warning/15", "*": "warning"}, "orange": {"50": "warning/15", "*": "warning"},
    "yellow": {"100": "warning/15", "*": "warning"},
    "supporting-yellow": {"50": "warning/15", "100": "warning/15", "200": "warning/15", "*": "warning"},
}
TEXT = {
    "gray": {"900": "base-content", "800": "base-content", "700": "base-content", "600": "muted",
             "500": "muted", "400": "faint", "300": "muted", "200": "base-content", "100": "base-content"},
    "neutral": {"": "muted", "800": "base-content", "50": "base-content"},
    "primary": {"*": "primary", "": "primary", "content": "primary-content"},
    "secondary": {"*": "base-content", "": "base-content", "content": "secondary-content"},
    "indigo": {"*": "primary"}, "blue": {"*": "info"}, "cyan": {"*": "info"},
    "red": {"*": "error"}, "supporting-red": {"*": "error"},
    "green": {"*": "success"}, "supporting-green": {"*": "success"},
    "amber": {"*": "warning"}, "orange": {"*": "warning"}, "yellow": {"*": "warning"},
    "supporting-yellow": {"*": "warning"},
}
LINE = {  # border, divide, ring, outline, decoration
    "white": "base-content",
    "gray": {"100": "line", "200": "line", "300": "line-strong", "400": "line-strong",
             "500": "line-strong", "600": "line-strong", "700": "line", "800": "line", "900": "line"},
    "neutral": {"500": "line-strong", "800": "line"},
    "primary": {"*": "primary", "": "primary"}, "secondary": {"*": "line-strong"},
    "indigo": {"*": "primary"}, "red": {"*": "error"}, "supporting-red": {"*": "error"},
    "green": {"*": "success"}, "supporting-green": {"*": "success"},
    "amber": {"*": "warning"}, "supporting-yellow": {"*": "warning"},
}
GRAD = {"black": "scrim", "white": "base-200", "primary": {"*": "base-100"},
        "secondary": {"*": "base-200"}}
FILLED = {  # bg role -> text color that sits on it
    "primary": "primary-content", "secondary": "secondary-content", "info": "info-content",
    "success": "success-content", "warning": "warning-content", "error": "error-content",
}
FAMILIES = ("supporting-red|supporting-green|supporting-yellow|slate|gray|zinc|neutral|stone|red|"
            "orange|amber|yellow|lime|green|emerald|teal|cyan|sky|blue|indigo|violet|purple|"
            "fuchsia|pink|rose|white|black|primary|secondary")
UTIL = "bg|text|border(?:-[trblxy])?|divide|ring|outline|decoration|placeholder|from|via|to|shadow|fill|stroke|caret|accent"
TOK = re.compile(rf"(?<![\w\-/\[])((?:[a-z0-9\-\[\]&>*:]+:)*)({UTIL})-({FAMILIES})(?:-(\d+|content))?(?:/(\d+))?(?![\w\-])")
ARB = {"#140553": ("text", "base-content"), "#f3defa": ("bg", "selected")}
ARB_RE = re.compile(r"(?<![\w\-])((?:[a-z0-9\-:]+:)*)(bg|text|border)-\[(#[0-9a-fA-F]{6})\]")

def look(table, fam, shade):
    v = table.get(fam)
    if v is None: return None
    if isinstance(v, str): return v
    return v.get(shade or "", v.get("*"))

def role_for(util, fam, shade, alpha):
    if util == "bg":
        r = look(BG, fam, shade)
        if fam == "white" and alpha and int(alpha) < 50:
            return "base-content", alpha   # a light tint over a dark surface
    elif util in ("text", "placeholder", "fill", "stroke", "caret", "accent"):
        r = look(TEXT, fam, shade)
        if fam == "white" and alpha:
            a = int(alpha); return ("base-content" if a >= 80 else "muted" if a >= 60 else "faint"), None
    elif util in ("from", "via", "to", "shadow"): r = look(GRAD, fam, shade) or look(BG, fam, shade)
    else:
        r = look(LINE, fam, shade)
        if fam == "white" and alpha:
            return ("line" if int(alpha) <= 20 else "line-strong"), None
    if r is None: return None, None
    if "/" in r: r, a = r.split("/"); return r, a
    return r, alpha

def convert_string(s, stats, unmapped):
    toks = list(TOK.finditer(s))
    # first pass: background role per variant prefix (after conversion)
    bgs = {}
    for m in toks:
        pre, util, fam, shade, alpha = m.groups()
        if util == "bg":
            r, _ = role_for("bg", fam, shade, alpha)
            if r: bgs.setdefault(pre, r)
    bgs.update({m.group(1): m.group(2) for m in re.finditer(
        r"(?<![\w\-])((?:[a-z0-9\-:]+:)*)bg-(primary|secondary|info|success|warning|error)(?![\w\-])", s)})
    if re.search(r"(?<![\w-])btn-(primary|secondary|info|success|warning|error)\b", s):
        bgs.setdefault("", re.search(r"btn-(primary|secondary|info|success|warning|error)\b", s).group(1))
    def rep(m):
        pre, util, fam, shade, alpha = m.groups()
        if util == "text" and fam in ("white", "black") and not alpha:
            on = bgs.get(pre) or bgs.get("")
            r = FILLED.get(on, "base-content")
            a = None
        else:
            r, a = role_for(util, fam, shade, alpha)
            # A hover/active fill that would equal the resting fill gets its hover token,
            # so filled buttons still respond to the pointer.
            if (util == "bg" and r in FILLED and re.search(r"(hover|active|focus)", pre or "")
                    and (bgs.get(re.sub(r"(group-)?(hover|active|focus(-visible)?):", "", pre)) == r)):
                r = f"{r}-hover"
        if r is None:
            unmapped[m.group(0)] += 1; return m.group(0)
        out = f"{pre}{util}-{r}" + (f"/{a}" if a else "")
        stats[(m.group(0), out)] += 1
        return out
    s = TOK.sub(rep, s)
    def arb(m):
        pre, util, hexv = m.groups()
        hit = ARB.get(hexv.lower()) or ARB.get(hexv)
        if not hit: unmapped[m.group(0)] += 1; return m.group(0)
        stats[(m.group(0), f"{pre}{util}-{hit[1]}")] += 1
        return f"{pre}{util}-{hit[1]}"
    return ARB_RE.sub(arb, s)

STR = re.compile(r'"(?:[^"\\]|\\.)*"|\'(?:[^\'\\\n]|\\.)*\'|`[^`]*`')

def convert_file(text, stats, unmapped):
    return STR.sub(lambda m: convert_string(m.group(0), stats, unmapped), text)

if __name__ == "__main__":
    write = "--write" in sys.argv
    files = [f for f in sys.argv[1:] if f != "--write"]
    stats, unmapped, changed = collections.Counter(), collections.Counter(), 0
    for f in files:
        src = open(f).read()
        out = convert_file(src, stats, unmapped)
        if out != src:
            changed += 1
            if write: open(f, "w").write(out)
    for (a, b), n in sorted(stats.items(), key=lambda x: -x[1]): print(f"{n:4} {a} -> {b}")
    print(f"\n{sum(stats.values())} replacements in {changed} files ({'written' if write else 'dry run'})")
    if unmapped:
        print("UNMAPPED:"); [print(f"{n:4} {k}") for k, n in unmapped.most_common()]
