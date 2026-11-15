# Carceral Consultation theme

Set up 2026-11-13. Every color in the app comes from one file:
`assets/css/theme-config.css`. Pages, components, scripts and stylesheets name
a **role** (what the color is for) and never a color. To change a color,
change it in that file and rebuild; the whole app follows.

The look: near-black charcoal surfaces, off-white text, **white buttons**.
Red, amber, green and blue are kept for error, warning, success and info.

## The roles

**Surfaces** go from darkest to lightest. Something that sits "above" another
thing is one step lighter, the way dark themes show depth (Material Design,
Apple's dark mode).

| Role | Class | Value | Used for |
|---|---|---|---|
| stage | `bg-stage` | #0b0b0c | behind slides, full-screen views |
| base-100 | `bg-base-100` | #121214 | the page |
| base-200 | `bg-base-200` | #1b1b1e | cards, panels |
| base-300 | `bg-base-300` | #252528 | raised: menus, inputs, chat bubbles, result boxes |
| base-400 | `bg-base-400` | #303034 | strongest surface: hover on raised, icon tiles |
| selected | `bg-selected` | #38383d | the chosen tab, row or option |
| scrim | `bg-scrim/60` | #000000 | dimming behind dialogs (always with opacity) |
| sheen | `color-mix(... var(--color-sheen) N%, ...)` | #ffffff | light caught by a raised surface (a top highlight, a soft top-lit gradient); always with opacity, the same in both themes |

**Text**

| Role | Class | Value | Used for |
|---|---|---|---|
| base-content | `text-base-content` | #ededef | main text |
| muted | `text-muted` | #a1a1aa | secondary text: dates, hints, labels |
| faint | `text-faint` | #7c7c85 | disabled and decorative only, never text people must read |

**Lines**

| Role | Class | Value | Used for |
|---|---|---|---|
| line | `border-line` | #2e2e33 | dividers, card edges |
| line-strong | `border-line-strong` | #7c7c85 | input borders, outline buttons |

**Buttons and anything you can press**

| Role | Class | Value | Text on it |
|---|---|---|---|
| primary | `bg-primary` | #f2f2f3 (white) | `text-primary-content` #121214 |
| primary-hover | `hover:bg-primary-hover` | #d4d4d8 | |
| secondary | `bg-secondary` | #303034 | `text-secondary-content` |
| accent | `bg-accent` | #d4d4d8 | `text-accent-content` |

**Status** (softened for dark backgrounds; dark text sits on a filled status color)

| Role | Value | Text on it | Hover |
|---|---|---|---|
| info | #8ab4f8 | `text-info-content` | `info-hover` |
| success | #6ccb8f | `text-success-content` | `success-hover` |
| warning | #ebc15a | `text-warning-content` | `warning-hover` |
| error | #f28b82 | `text-error-content` | `error-hover` |

For a soft status background use the color with opacity, for example
`bg-error/15 text-error`.

**Charts:** `chart-1` (#ededef) and `chart-2` (#8ab4f8) for data series.

**Breakout groups:** `group-1` … `group-6` with `group-content` for text on them
(2026-11-13). Six colors kept clear of the four status colors: violet, pink,
teal, orange, lime, indigo (dark: #a78bfa #f472b6 #2dd4bf #fb923c #a3e635
#818cf8 with #121214 text; light: #6d28d9 #be185d #0f766e #c2410c #4d7c0f
#4338ca with white text). Group 7 starts again at violet; the group number is
always shown, so color is never the only cue. Contrast: text on each color is
at least 5:1, and each color stands at least 5:1 off its panel. Use them only
through `ClaperWeb.BreakoutLive.Components` (`group_chip/1`, `group_class/1`,
`group_bar/1`), which writes the class names out in full for Tailwind.

## Standard patterns

- **Buttons:** see "Buttons" below.
- **Text on a filled color always uses that color's `-content` role**
  (`bg-primary text-primary-content`, `bg-success text-success-content`).
  Never put a status color's own text on its own fill.
- **Poll and quiz result bars:** box `bg-base-300`, percentage fill
  `bg-base-content/20` (your own vote `bg-base-content/25` with a
  `border-primary` edge), correct quiz answer `bg-success text-success-content`.
- **Chat bubbles:** `bg-base-300`; pinned adds a soft warning tint, questions
  a soft info tint.
- **Avatars:** `ClaperWeb.Theme.avatar_class/1` picks one of three charcoal
  surfaces. The emoji tells attendees apart.
- **Icons** use `currentColor` so they take the surrounding text color. The
  app's own icons are function components in `lib/claper_web/components/icons.ex`.
- **The brand** (name, logo, mark, browser icon, sign-in photo) is not part of
  the theme: it is set on the Brand page in Admin ([BRAND.md](BRAND.md)). Logo
  and mark images are drawn in the current text color, so they follow the
  theme on their own.

## Buttons

Every button's look is defined once, in `assets/css/buttons.css`, modeled on
the shadcn/ui Button ("base-nova" style): slightly rounded corners, compact
heights, small medium-weight text, a 1px nudge when pressed, a soft focus
glow. daisyUI's own button styles are switched off (`exclude: button`), and
the class names stay daisyUI's, so markup reads `btn btn-primary btn-sm`.

| Class | Look | Use for |
|---|---|---|
| `btn btn-primary` | white, dark text | the main action on a screen |
| `btn btn-outline` | thin border, faint fill | second actions |
| `btn btn-secondary` (or plain `btn`) | quiet gray | everyday actions |
| `btn btn-ghost` | no fill until hovered | icon buttons, toolbars, close (X) |
| `btn btn-error` | soft red tint, red text | delete, end, remove |
| `btn btn-success` / `btn-warning` / `btn-info` | soft tint | status actions |
| `btn btn-link` | looks like a link | inline actions in text |

Sizes: `btn-xs` 24px, `btn-sm` 28px, default 32px, `btn-lg` 36px. `btn-stacked` puts an icon above a short label (toolbar tiles).

**No restyling.** A standard button never adds its own corners, fill, border,
height, padding, text size or weight, capitals or shadow; those come only
from `buttons.css`. Layout classes (position, width, margins) and text color
are fine. The controls check enforces this. Icon-only
buttons add `btn-square` (or `btn-circle` for round). Disabled buttons are
half-transparent.

**Touch screens.** On phones and tablets (any screen used with a finger),
every button, choice and menu row is at least 44px tall on every page, the
recommended size for thumbs. With a mouse, the compact sizes apply.

`btn btn-overlay` is the translucent button for controls floating over
slides and video.

## Panels

Cards that group content (the manage screen's Preview, Interactions,
Audience Responses and settings panels) all use one style, defined in
`assets/css/panels.css`, so they sit at the same height above the page:

| Class | What it is |
|---|---|
| `panel` | the card: one step lighter than the page (`base-200`), thin border, rounded corners, soft shadow |
| `panel-header` | the title row, with a divider line under it |
| `panel-inset` | a recessed area inside a panel (the slide in Preview, the word list): darker, with an inner shadow |
| `card` | the same as `panel` (daisyUI's card is switched off), with `card-body`, `card-title`, `card-actions`; used across Admin and My account |
| `app-bar` | the top bar of every signed-in screen (My events, event stats, My account, Manage): 60px tall, every control in it 36px (`btn-lg`, segmented groups, search); on touch screens controls are 44px, so the bar is 68px |
| `app-bar-title` | the bar's title: 16px on phones, 20px from 1024px wide |
| `modal-box` | every dialog (daisyUI modal): a 1px `line-strong` edge, the same as a switch row, so it stands out from the page behind; the event editor's side drawer has the same edge on its open side | Settings, Reorder, interaction editors, breakout piece editor, admin dialogs, create/edit event drawer |
| `alert-dialog` | every confirmation (shadcn base-nova Alert Dialog, `ClaperWeb.AlertDialog`, placed once per page by the layouts). **Never the browser's `confirm()`**: write `data-confirm` (the description) plus `data-confirm-title` (a question), `data-confirm-action` (a verb: "Delete", "Block", not "OK") and, for anything that can't be undone, `data-confirm-variant="destructive"` (red button, trash can; `data-confirm-icon="warning"` for red actions that delete nothing). Cancel is focused first; Esc cancels; buttons stack full width on phones | every delete, block, end, stop, revoke and the other confirmations |
| `toaster` / `toast-card` | short messages that come and go (shadcn base-nova Toast, `ClaperWeb.Toast`, in the layouts): a raised card (`base-200`, `line-strong` edge) with a colored status icon (success, info, warning, error, loading), title, optional description and ×; bottom right, full width on phones; closes after 5 s (errors 8 s), paused while hovered. Flash messages show here (`:info` as success); from a LiveView without a page change use `Toast.push/4`. Not for errors that belong beside a form: those stay inline (`ClaperWeb.Component.Alert`) | every saved / deleted / could-not message |

Admin pages start with `ClaperWeb.AdminBar.bar` (its `tools` slot puts search and filters on the breadcrumb line, right-aligned) (title, the page's buttons, the account button, the phone menu toggle, then the breadcrumb trail) instead of their own heading.

A panel always sits on the page color (`bg-base-100`); on `base-200` it has
nothing to stand out against.

## Form fields

Every text box, drop-down, text area, checkbox and radio uses one style,
defined in `assets/css/fields.css` and modeled on shadcn/ui (base-nova input,
textarea, native-select, checkbox, radio-group): slightly rounded corners,
32px tall, a `line-strong` border (passes 3:1) over a faint fill, the same
focus glow as buttons. daisyUI's field styles are switched off; class names
stay daisyUI's (`input`, `select`, `textarea`, `checkbox`, `radio`, with
`-sm` / `-lg` and `-error`).

- An icon inside a field: `<label class="input"><svg/><input/></label>`.
- Drop-down arrows and checkbox ticks are drawn from theme colors.
- Touch screens: fields are 44px tall with 16px text (smaller text makes
  iPhones zoom in on focus).
- Field components (`ClaperWeb.Component.Input`, `TextInput`, `Select`,
  `Checkbox`, `CoreComponents.input`) emit these classes; `fieldClass` must
  not carry look classes.
- Deliberate exceptions: the join page's big code box (`join-code-input`)
  and the audience message composer (`composer-input`).

## Badges

Small labels (status, counts, an event's code) use one style, defined in
`assets/css/badges.css` and modeled on shadcn/ui's Badge: a 20px pill with
12px medium text. daisyUI's badge styles are switched off (`exclude: badge`);
class names stay daisyUI's.

| Class | Look | Use for |
|---|---|---|
| `badge` / `badge-primary` | white | strong emphasis |
| `badge-secondary` | gray | neutral states (Upcoming, LTI) |
| `badge-outline` | thin border | event codes, Finished |
| `badge-ghost` | no fill | quiet labels |
| `badge-error` / `-success` / `-warning` / `-info` | soft tint, colored text | status (Live is `badge-error` with a pulsing dot) |

Sizes: `badge-sm` 16px, default 20px, `badge-lg` 24px. An event's code is
always `ClaperWeb.Component.Badge.event_code/1`: outline, "#CODE" in capitals.
Soft and outline badges are see-through, so never place them over a photo or
slide; put them in a text row.

## Pagination

Every table has the same footer (`ClaperWeb.Pagination.footer/1`, shadcn
"data table" style): "Showing 1–20 of 54" (or "No results") on the left,
"Page 1 of 3" with Previous / page numbers / Next as a segmented group on the
right. It always shows, even on one page. Flop-backed tables use
`ClaperWeb.CoreComponents.pagination/1`; tables that load a whole list cut it
with `ClaperWeb.Pagination.paginate/3` (20 rows a page). A short "recent"
preview links to the full, paginated list instead of paging.

## Breadcrumbs

Admin pages and My account show a trail that starts where you came from
(`ClaperWeb.Breadcrumbs`): the event's name and code when you opened them
from an event's account menu (back to its Manage screen), otherwise My
events. The event is remembered for your session
(`ClaperWeb.Plugs.ReturnContext`, set by `?from=<event uuid>` on the menu
links; cleared by opening My events) and shown only if you may manage it or
are an admin (`Claper.Events.get_return_event/2`). The Admin sidebar's
button reads "Back to event" in that case.

## Other controls

Every clickable thing in the app is a button or one of these patterns, all
defined in `assets/css/buttons.css`. There are no one-off controls.

| Class | What it is | Where |
|---|---|---|
| `switch` | on/off switch, shadcn base-nova: 32×18px track, 16px knob (`switch-sm` 24×14px); green (`success`) when on; write it with `ClaperWeb.Component.Switch.switch`, or `class="switch"` on a form checkbox. **Its label never changes:** it names what *on* means ("Allow messages", not "Enable"/"Disable messages") | everywhere a setting turns on or off |
| `switch-card` | a whole row that flips a switch: icon, title, optional description, shortcut key, switch (shadcn "choice card"); faint green when on; use `ClaperWeb.Component.Switch.switch_row` | presentation, attendee and interaction settings; admin settings |
| `choice` | an answer or option you pick; chosen = `aria-pressed="true"`, `aria-checked="true"` or `choice-selected` | poll and quiz answers, slide thumbnails |
| `menu-item` | a row in a drop-down or side menu (`menu-item-error` / `menu-item-warning` for risky rows); daisyUI `.menu` rows look the same. A drop-down inside a scrolling panel floats above the page with the `FloatingMenu` hook (`position: fixed`, opened with the `cc:place-menu` event) so the panel can't cut it off | event card menu, audience side menu, admin row menu, "add interaction" list |
| `pressable` | a click target with no look of its own | tap a collapsed card to open it, accordion headers, dialog backdrops |
| tabs | the shared tabs component, `style={:segmented}` | event tabs, message tabs, stats tabs |

Also allowed as click targets: dialog backdrops (`modal-backdrop`), full-screen
dimming layers, and clickable table rows.

In Elixir, `ClaperWeb.Component.Button` (`<.button style={:outline} size={:sm}>`)
produces the same classes.

## Light theme

A second theme, `carceral-light`, uses the same roles with light values. Since
2026-11-15 it is **warm** (Jose's choice, from a reference he liked):
- cream cards (`base-200` #f7f3ee) on a warm stone page (`base-100` #e9e2da)
- espresso text (#2a211d) and espresso buttons (#3a2e29) with cream text. The
  espresso ties the light theme to the dark one.
- warm-grey secondary text (muted #62554c), deliberately darker than the
  reference, so it stays readable on projectors and phones
- status colors deepened for stone (error #c02626, success #126b33, warning
  #854b05, info #1d4ed8)
- shadows tinted espresso (`scrim` #1e1714). Page and cards are close in tone,
  so the shadows carry the depth.

The previous neutral light theme (white on #f4f4f5, near-black #18181b) is in
git history. Both themes live in `theme-config.css`.

- **Switching:** Dark | Light | System in the account menu, above Logout
  (`ClaperWeb.ThemeScript.switcher`). The choice is saved in this browser and
  applied in each page's `<head>` before it draws (`ClaperWeb.ThemeScript.script`),
  so there is no flash. System follows the device, live. Default: Dark.
- **Stay-dark regions:** anything over a photo (the sign-in panel) carries
  `data-theme="carceral"` so its text stays light.
- **Wordmarks** use `ClaperWeb.Wordmark.mark`, which fills the brand's logo
  or mark with the current text color (or sets the name in type); over the
  sign-in photo the panel is dark, so it shows light. Emails stay dark and
  show the name in type.
- Charts read their colors when they draw, so they follow a theme change on
  the next page load.

Light contrast (warm, checked 2026-11-15):
- main text 12.3–14.3 : 1
- muted 5.2–6.5, including on selected rows
- faint 4.0 (decorative only)
- status colors 5.2–6.3 on both stone and cream, and white on each 5.4–6.3
- cream text on espresso buttons 11.9 (9.1 on hover)
- input borders 3.2–3.5
- breakout group colors with white text 4.5–7.2
- chart series 4.9 and 11.9 on cards

## Readability

The theme meets the WCAG AA contrast minimums: 4.5:1 for normal text, 3:1 for
large text and for interface edges like input borders and focus rings.

| Pair | Contrast |
|---|---|
| main text on page / card / raised | 16.0 / 14.7 / 13.1 |
| muted text on page / card / raised | 7.3 / 6.7 / 6.0 |
| button text on a white button | 16.7 |
| status colors on a card | 7.2 to 10.1 |
| dark text on a status fill | 7.8 to 11.0 |
| input border (line-strong) on card / raised | 4.2 / 3.7 |

`faint` is below 4.5:1 on purpose; it is only for disabled and decorative
things, which WCAG exempts.

## Where colors may be written

Only three files hold color values:

1. `assets/css/theme-config.css`: the theme, the source of truth.
2. `lib/claper_web/theme.ex`: a copy of a few theme colors for **email**,
   because mail programs cannot read the app's stylesheet. The check script
   fails if these drift from the theme.
3. `assets/js/theme.js`: reads theme colors at runtime for scripts that must
   hand a color to a library (charts, QR codes, the page-load bar).

The theme also switches off Tailwind's built-in palette (`--color-*: initial`),
so `bg-gray-500`, `text-white`, `ring-indigo-600` and the rest don't exist in
this app. A stray one produces no style at all, or breaks the build if it is
used in `@apply`.

**Exceptions (on purpose):** the emoji reaction pictures (clap, heart, 100,
laugh, raised hand, thumbs up) keep their own colors because they are emoji
artwork. The Moodle and OpenID pictures are other organizations' logos.
Photos (the sign-in background) are content.

## Checking

```
scripts/theme/check_theme.sh
```

It runs two checks. The controls check (`check_controls.py`) fails if a
button, a button-looking link or a clickable element is not one of the
standard patterns above, or if daisyUI's `toggle` appears. It also fails on a
hand-made label (use a badge), text smaller than 12px, and text faded by
opacity (`text-base-content/60`; use `text-muted` or `text-faint`). The color check
fails if it finds any of the following: a Tailwind palette class, a color
value or color name outside the three files above, a color class naming a role
the theme doesn't define (which Tailwind would silently drop), email colors
that drift from the theme, or a new icon with colors baked in. Run it before
every commit that touches the interface.

`scripts/theme/convert_colors.py` is the one-time converter that moved
Claper's colors onto these roles (its rulebook is kept for the record).
