# The overflow audit

Finds anything that doesn't fit, page by page and device by device (Jose,
2026-11-16): an element that reaches past the box it sits in, is cut off by
it, or makes the whole page wider than the screen. On a phone, that last one
lets the page slide sideways under your thumb.

It visits every page in `pages.json` (participants' and staff's, signed in
where needed, including the manage screen's cards, its settings window, the
Add menus and the messenger) on an iPhone SE, an iPhone, an iPad upright and
sideways (WebKit, Safari's engine) and a laptop (Chrome), and reports:

- `wider-page`: the page is wider than the screen, and what causes it
- `sticks-out`: an element reaches past the edge of its box
- `cut-off`: an element is chopped off by a box that hides overflow (text
  shortened with "…" on purpose isn't reported)
- `text-spills`: text, such as a long word or link, runs past its own box

Things meant to scroll sideways (the manage screen's card row, tab strips)
and pop-ups placed on the screen are left alone. A deliberate nudge is
marked on the element with `data-overflow-ok="why"`.

It runs against a running copy of the app with sample data: an event
running (`code`), one before its start (`introCode`), one ended with
take-home material (`endedCode`), a breakout (`breakoutId`), and an admin
account.

```
cd scripts/audit && npm install
AUDIT_BASE=http://localhost:4100 \
AUDIT_EMAIL=admin@example.com AUDIT_PASSWORD_FILE=/path/to/password-file \
AUDIT_VARS='{"code":"…","uuid":"…","eventId":1,"introCode":"…","endedCode":"…","breakoutId":1}' \
node overflow_audit.mjs
```

`AUDIT_ONLY="iPhone SE,iPhone"` limits the devices; `AUDIT_OUT` names the
JSON report (default `overflow_report.json`). Add a page to `pages.json`
when a page is added to the app.

Its limit: WebKit here is Safari's engine, not an iPhone, so a few
iPhone-only quirks (Safari's own date control, for one) don't show; a real
phone stays the last check.
