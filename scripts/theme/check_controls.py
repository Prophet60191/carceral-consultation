#!/usr/bin/env python3
"""Carceral Consultation clickable-controls check (2026-11-13).

Every clickable thing in the app must be one of the standard patterns defined
in assets/css/buttons.css (see docs/THEME.md, "Buttons" and "Other controls"):

  btn          buttons (with btn-primary, btn-outline, btn-ghost, ... and sizes)
  switch       on/off switches
  choice       answers / options you pick
  menu-item    rows in drop-down and side menus
  pressable    click targets with no look of their own
  tabs         the shared tabs component (tabs_component.ex)

This fails (exit 1) if it finds:
  - a <button> whose class uses none of those patterns
  - a link (<a>, <.link>, link(...)) styled to look like a button (fill,
    rounded corners, border, padding) without one of those patterns
  - daisyUI's "toggle" class (switches use .switch)
  - a non-button element (div, span, ...) with a click handler that is not a
    known pattern (dialog backdrop, full-screen scrim, clickable table row)
  - an element with role="button" that is not a standard control
  - a submit(...) helper without a standard button class
  - a standard button whose own classes change its look (corners, fill,
    border, height/size, padding on the block axis, text size or weight,
    capitals, shadow): the look comes from buttons.css only. Layout classes
    (position, width, margins, gaps) and text color are fine.
  - a hand-made label (rounded, padded, small text, filled or bordered)
    instead of a badge (badges.css)
  - text smaller than 12px (text-[10px], text-[11px]) or text faded by
    opacity (text-base-content/60) instead of the muted / faint roles
  - a form field (input / select / textarea) that is not a standard field
    (fields.css: input, select, textarea, checkbox, radio; or switch) or
    restyles itself. Exceptions by name: join-code-input (the join page's
    big code box) and composer-input (the audience message composer).
"""
import pathlib, re, sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
LIB = ROOT / "lib"

APPROVED = re.compile(r"(?<![\w-])(btn|switch|choice|menu-item|pressable)(?![\w-])")
# Files that build button / tab classes in code; their output is the standard.
GENERATORS = {
    "lib/claper_web/views/components/button_component.ex",
    "lib/claper_web/views/components/tabs_component.ex",
    "lib/claper_web/components/core_components.ex",  # <.button>: ["btn", variant]
}
# Helper functions that return standard classes (checked where defined).
HELPERS = re.compile(r"segmented_item_class|picker_reaction_classes|reaction_chip_classes")
# Looks like a button: a fill, rounded corners with padding, or a border with padding.
BUTTONISH = re.compile(r"(?<![\w-])(rounded-full\b[^\"]*\bborder\b|(?:hover:)?bg-(?!transparent)[a-z]|rounded-(?:md|lg|xl|full)[^\"]*\bp[xy]?-\d|border(?:-[\w/-]+)?[^\"]*\bp[xy]-\d)")
# Non-button click targets that are allowed by name.
ALLOWED_CLICK_TARGETS = re.compile(r"modal-backdrop|fixed inset-0|pressable|choice|menu-item|btn\b")

def tags(text, name_re):
    """Yield (match_start, name, attrs) for each opening tag, reading to the
    real end of the tag: '>' inside {...} code or quotes (like |>) is skipped."""
    for m in re.finditer(r"<(" + name_re + r")\b", text):
        i, depth, quote = m.end(), 0, None
        while i < len(text):
            ch = text[i]
            if quote:
                if ch == quote:
                    quote = None
            elif ch in "\"'" and depth == 0:
                quote = ch
            elif ch == "{":
                depth += 1
            elif ch == "}":
                depth -= 1
            elif ch == ">" and depth == 0:
                break
            i += 1
        yield m.start(), m.group(1), text[m.end():i]
LINK_HELPER = re.compile(r"\blink\((.*?)\)\s*(?:%>|\}|do)", re.S)
CLICKABLE_OTHER = re.compile(r"<(div|span|li|img|p|svg|section|article|label)\b([^>]*?\bphx-click=[^>]*?)>", re.S)
CLASS = re.compile(r'(?<![\w-])class[=:]\s*(\{.*?\}(?=\s+[:a-z@-]+=|\s*/?$)|"[^"]*"|\[.*?\](?=\s*[,)]))', re.S)


# Classes that would change a standard button's look (layout is fine).
LOOK_OVERRIDE = re.compile(
    r"(?<![\w:/\[-])!?(?:[a-z-]+:)*!?("
    r"rounded(?:-[a-z0-9]+)?|bg-[a-z][\w/-]*|border(?:-(?:\d|[a-z][\w/-]*))?|"
    r"h-\d[\w.]*|min-h-[\w.]+|size-\d+|py-[\d.]+|p-[\d.]+|"
    r"text-(?:xs|sm|base|lg|xl|\d?xl|\[[^\]]+\])|font-(?:thin|light|normal|medium|semibold|bold|black|display)|"
    r"shadow(?:-[\w/-]+)?|uppercase|normal-case|tracking-[\w.\[\]-]+"
    r")(?![\w-])")
BTN = re.compile(r"(?<![\w-])btn(?![\w-])")


def line_of(text, pos):
    return text[:pos].count("\n") + 1


def main():
    problems = []
    for path in sorted(LIB.rglob("*")):
        if path.suffix not in {".ex", ".heex", ".eex"}:
            continue
        rel = str(path.relative_to(ROOT))
        text = path.read_text(errors="replace")
        # ignore HEEx/HTML comments
        text = re.sub(r"<!--.*?-->|<%!--.*?--%>", lambda m: "\n" * m.group(0).count("\n"), text, flags=re.S)
        # ignore documentation text
        text = re.sub(r'@(?:module)?doc\s+(?:~S)?"""(.*?)"""', lambda m: "\n" * m.group(0).count("\n"), text, flags=re.S)

        for start, _name, attrs in tags(text, "button"):
            if rel in GENERATORS:
                continue
            c = CLASS.search(attrs)
            cls = c.group(1) if c else ""
            if re.search(r"(?<![\w-])switch(?![\w-])", cls) and rel != "lib/claper_web/views/components/switch_component.ex":
                problems.append(f"{rel}:{line_of(text, start)}: hand-written switch button; use ClaperWeb.Component.Switch")
                continue
            if APPROVED.search(cls) or HELPERS.search(cls):
                continue
            problems.append(f"{rel}:{line_of(text, start)}: <button> is not a standard control: class={cls[:90] or '(none)'}")

        for start, _name, attrs in tags(text, r"a|\.link"):
            c = CLASS.search(attrs)
            cls = c.group(1) if c else ""
            if cls and BUTTONISH.search(cls) and not APPROVED.search(cls):
                problems.append(f"{rel}:{line_of(text, start)}: link styled as a button without a standard class: {cls[:90]}")

        for m in LINK_HELPER.finditer(text):
            c = CLASS.search(m.group(1))
            cls = c.group(1) if c else ""
            if cls and BUTTONISH.search(cls) and not APPROVED.search(cls):
                problems.append(f"{rel}:{line_of(text, m.start())}: link(...) styled as a button without a standard class: {cls[:90]}")

        for m in re.finditer(r"(?<![\w-])toggle(?:-(?:sm|xs|md|lg|primary|secondary|accent|success|warning|error|info))?(?=[\s\"])", text):
            before = text[max(0, m.start() - 200):m.start()]
            if re.search(r'class[=:]\s*["{][^"}]*$', before):
                problems.append(f"{rel}:{line_of(text, m.start())}: daisyUI toggle; use class=\"switch\"")

        # role="button" elements
        for m in re.finditer(r"<(\w+)\b([^>]*?role=\"button\"[^>]*?)>", text, re.S):
            c = CLASS.search(m.group(2))
            cls = c.group(1) if c else ""
            if not APPROVED.search(cls):
                problems.append(f"{rel}:{line_of(text, m.start())}: role=\"button\" element is not a standard control")

        # submit(...) helpers
        for m in re.finditer(r"\bsubmit\((.*?)\)\}", text, re.S):
            if not BTN.search(m.group(1)):
                problems.append(f"{rel}:{line_of(text, m.start())}: submit(...) without a standard button class")

        # standard buttons must not restyle themselves: look at each whole
        # class value (a quoted string, or every string in a class={[...]} list)
        if rel not in GENERATORS:
            seen = set()
            values = [(m.start(), " ".join(re.findall(r'"([^"]*)"', m.group(1))))
                      for m in re.finditer(r"class=\{\[(.*?)\]\}", text, re.S)]
            for start, _v in values:
                seen.add(start)
            values += [(m.start(), m.group(1)) for m in re.finditer(r'"([^"\n]*)"', text)
                       if not any(a <= m.start() <= a + 2000 for a in seen)]
            for start, cls in values:
                if not BTN.search(cls) or "segmented" in cls:
                    continue
                for o in sorted(set(LOOK_OVERRIDE.findall(cls))):
                    problems.append(f"{rel}:{line_of(text, start)}: standard button restyled with '{o}': {cls[:90]}")

        # hand-made labels, tiny text, faded text
        for m in re.finditer(r'class=\{?\[?"([^"\n]*)"', text):
            cls = m.group(1)
            if re.search(r"(?<![\w-])(badge|btn|menu-item|choice|switch|panel|card)(?![\w-])", cls):
                pass
            elif (re.search(r"(?<![\w-])rounded(-full|-md|-lg)?(?![\w-])", cls)
                  and re.search(r"(?<![\w-])px-[0-9.]+", cls) and re.search(r"(?<![\w-])py-[0-9.]+", cls)
                  and re.search(r"(?<![\w-])text-(xs|\[1[01]px\])", cls)
                  and re.search(r"(?<![\w-])(bg-(?!transparent)[a-z]|border(?![\w-]))", cls)):
                problems.append(f"{rel}:{line_of(text, m.start())}: hand-made label; use a badge: {cls[:90]}")
            for t in re.findall(r"(?<![\w-])text-\[(?:[0-9]|1[01])px\]", cls):
                problems.append(f"{rel}:{line_of(text, m.start())}: text smaller than 12px ({t}); use text-xs")
            for t in re.findall(r"(?<![\w-])text-base-content/[0-9]+", cls):
                problems.append(f"{rel}:{line_of(text, m.start())}: faded text ({t}); use text-muted or text-faint")

        # form fields
        FIELD_OK = re.compile(r"(?<![\w-])(input|select|textarea|checkbox|radio|switch|hidden|drawer-toggle|join-code-input|composer-input)(?![\w-])")
        FIELD_LOOK = re.compile(r"(?<![\w:/\[-])!?(?:[a-z-]+:)*!?(bg-(?!transparent)[a-z][\w/-]*|rounded(?:-[a-z]+)?|h-\d[\w.]*|min-h-[\w.]+|border(?:-[\w/-]+)?|shadow(?:-[\w/-]+)?|text-(?:xs|sm|base|lg|xl|\d?xl)|ring(?:-[\w/-]+)?|outline-hidden)(?![\w-])")
        for start, name, attrs in tags(text, r"input|select|textarea"):
            if re.search(r'type="(hidden|checkbox)"', attrs) and not re.search(r'class=', attrs):
                continue
            c = CLASS.search(attrs)
            cls = c.group(1) if c else ""
            if not cls:
                # allowed only inside a standard container: <label class="input">
                if re.search(r'<label class="input[^"]*">(?:(?!</label>).)*$', text[:start], re.S):
                    continue
                problems.append(f"{rel}:{line_of(text, start)}: <{name}> without a standard field class")
                continue
            if rel in GENERATORS or re.search(r"\{@class|@class \|\||\{\[\s*@class", cls):
                continue
            if not FIELD_OK.search(cls):
                problems.append(f"{rel}:{line_of(text, start)}: <{name}> is not a standard field: {cls[:90]}")
            elif not re.search(r"join-code-input|composer-input", cls):
                for o in sorted(set(FIELD_LOOK.findall(cls))):
                    problems.append(f"{rel}:{line_of(text, start)}: standard field restyled with '{o}': {cls[:90]}")
        for m in re.finditer(r'(?<!def )(?<![\w.])(?:text_input|textarea|select|email_input|password_input|number_input|datetime_local_input|date_input)\((?:(?!\)\s*\}).)*?class:\s*"([^"]*)"', text, re.S):
            cls = m.group(1)
            if re.search(r"join-code-input|composer-input|hidden|switch|btn", cls):
                continue
            if not FIELD_OK.search(cls):
                problems.append(f"{rel}:{line_of(text, m.start())}: helper field is not a standard field: {cls[:90]}")
            else:
                for o in sorted(set(FIELD_LOOK.findall(cls))):
                    problems.append(f"{rel}:{line_of(text, m.start())}: standard field restyled with '{o}': {cls[:90]}")

        for m in re.finditer(r'fieldClass=\{?"([^"]*)"', text):
            for o in sorted(set(FIELD_LOOK.findall(m.group(1)))):
                problems.append(f"{rel}:{line_of(text, m.start())}: field restyled through fieldClass with '{o}'")

        for m in CLICKABLE_OTHER.finditer(text):
            attrs = m.group(2)
            if ALLOWED_CLICK_TARGETS.search(attrs) or "flash" in attrs:
                continue
            problems.append(f"{rel}:{line_of(text, m.start())}: <{m.group(1)}> with a click handler is not a standard control")

    # table rows and cells are allowed click targets (handled by regex scope above)
    if problems:
        print(f"Controls check FAILED: {len(problems)} problem(s)\n")
        print("\n".join(problems))
        return 1
    print("Controls check passed: every clickable element is a standard control.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
