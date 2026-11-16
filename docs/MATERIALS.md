# Materials — design record

Handouts during a workshop and PDFs to take home after it. Proposed and
agreed with Jose on 2026-11-15. Nothing is built yet.

## The two kinds

- **Handouts:** PDFs for use during the event (a worksheet, a sample
  letter). Participants open them while the workshop runs.
- **Take-home:** PDFs people keep after the event (resource sheets, the
  slides). They are on a page every phone shows once the event ends.

The same file can be both: a handout can also be added to Take-home.

## Decisions (2026-11-15, Jose)

1. **Not an interaction.** Materials belong to the event, not to a slide
   or a moment in the presentation.
2. **A Materials card** in the manage screen's right sidebar, with the
   presentation and message settings. Two lists: Handouts and Take-home.
3. **Adding:** the card's **+** asks Handout or Take-home, then opens a
   window to upload a PDF and give it a title. For a handout, an "Also add
   to Take-home" checkbox; the two then have separate switches, so turning
   one off doesn't affect the other.
4. **Each item has an on/off switch**, like the settings. Off hides it
   from participants and keeps it in the card, so Jose can change his mind
   at any time, including mid-workshop.
5. **The slides** are a switch in the Take-home list: off by default, on per
   event. They are available **only after the workshop**, never during it.
6. **Take-home availability:** a date and time picker in the card sets when
   the take-home page closes. It is always set: it starts at 7 days after
   the event's end, and Jose can change it.
7. **The handouts icon:** a page icon at the bottom right of every screen.
   Messages and theme are on the left, the event's material on the right.
   - Computers: bottom-left stays theme + message bubble; bottom right holds
     the handouts icon above the full-screen button, beside the reactions
     button.
   - Phones and tablets: the bottom bar holds the message bubble and theme
     button on the left, reactions in the middle, handouts on the right.
   - Shown only while at least one handout is switched on, so it appears on
     every screen the moment one is.
8. **Opening a handout:** with one, the icon opens it straight in a viewer;
   with several, a short list to pick from. The viewer sits over the room,
   has a **download** button, and closing it returns to the slide.
9. **The take-home page:** when the event ends, phones show it in place of
   the room: the take-home PDFs that are switched on (and the slides, if
   on), each with a download button, with "Available until <date, time>"
   at the top. After that time the page says the materials are no longer
   available.

## Settled on the details (sensible defaults, Jose may revisit)

- Files: PDF only, up to 25 MB each, checked by content, not just name.
- Storage: on the same volume as the slides on Dynames (in the nightly
  backup), outside the public uploads folder. Files are kept until their
  item or the event is deleted (event content is kept until the event is
  deleted; the 365-day retention covers sign-in records only).
- Served as downloads (`Content-Disposition: attachment`, `nosniff`); the
  in-room viewer draws the PDF itself (phones can't show a PDF inside a
  page reliably: iPhones show only the first page).
- **Found while planning:** the slides' original PDF sat in the public
  uploads folder at an address every participant could work out from the
  slide images. It is now never served publicly
  (`ClaperWeb.Plugs.PrivateUploads`); the slides are handed out only
  through the take-home page.
- Download counts per file on the stats page (counts only, never who).
- The default "available until" follows the event's end while Jose hasn't
  changed it; once he picks a time, it stays as he set it.
- Duplicating an event copies its materials and switches; the
  availability time is reset to 7 days after the copy's end.

## Build plan

Each step ends complete: checks, tests, a real-browser test, a commit.

1. **Storage:** materials (event, kind, title, file, on/off, position), the
   take-home "available until", upload checks, safe serving, retention and
   copying with the event.
2. **The Materials card:** the + flow, the upload window, the switches, the
   slides switch, the date and time picker.
3. **Handouts in the room:** the icon (every device, per decision 7), the
   list, the viewer with download, live appearance when switched on.
4. **The take-home page:** shown when the event ends, until the set time;
   then the closed notice.
5. **Stats:** download counts.

## How storage is built (step 1)

- **Tables** (`priv/repo/migrations/20261115100000_create_materials.exs`):
  `materials` (event, kind `handout` / `take_home`, title, size, on/off,
  position, download count); on `events`, `take_home_until` (nil: 7 days
  after the end) and `take_home_slides`.
- **Logic:** `Claper.Materials`: adding (PDF checked by content, 25 MB,
  optional take-home copy), switching, renaming, ordering, removing (with
  the file), the take-home window (`take_home_until/1`, `take_home_open?/2`),
  who may have a file (`available?/3`, `slides_available?/2`), copying with
  the event, deleting with it, download counts, and live updates on
  `event:<uuid>:materials`.
- **Files:** `<storage>/materials/<event uuid>/<material uuid>.pdf`. Local
  storage only; with S3 storage, uploads are refused.
- **Serving:** `ClaperWeb.MaterialController`: `/materials/:id` and
  `/materials/slides/:event` (unique ids: event codes can repeat across
  ended events). People who run the event always get their files.
- Tests: `test/claper/materials_test.exs`,
  `test/claper_web/controllers/material_controller_test.exs`.


## How the Materials card is built (step 2)

- **The card** `ClaperWeb.EventLive.MaterialsComponent`, in the manage
  screen's settings (`ManagerSettingsComponent`, so it appears in the
  sidebar and in the settings window on smaller screens; ids are prefixed
  per copy). Handouts and Take-home lists: each item with its switch, move
  up / down, download, and remove (confirmed). Take-home also has the
  Slides switch (off and disabled when the slides have no PDF) and
  **Available until** (the shared date-time field: shown in local time,
  stored as UTC; must be after the event's start).
- **The add window** `ClaperWeb.EventLive.MaterialsAddComponent`, once per
  manage screen at its top level (opened by either card with
  `:open_materials_add`; a window inside the settings window would be cut
  off): Handout or Take-home, then the PDF (drag and drop or choose, up to
  25 MB), the title (filled from the file name) and, for a handout, "Also
  add to Take-home".
- **Live:** the manage screen listens on the materials channel and reloads
  both cards, so a change by another facilitator shows at once.
- Tests: `test/claper_web/live/materials_card_test.exs`.

## How handouts in the room are built (step 3)

- **The icon, list and viewer:** `ClaperWeb.EventLive.Handouts` (`button/1`,
  `viewer/1`) in the live room; open or closed is the room's
  (`handouts`, `handouts_menu`, `handout_open` in `EventLive.Show`), so
  redraws never undo it. The room listens on the materials channel: a
  handout switched on appears at once, and an open one switched off closes.
- **Placement** (`assets/css/room.css`): phones and tablets, the right end of
  the bottom bar (44 px), with the theme button now next to the message
  bubble on the left (`assets/css/messenger.css`, both pages); computers,
  bottom right above the full-screen button. With several handouts, a
  count on the icon and a list above it.
- **The viewer** draws the PDF itself with PDF.js 4.10.38
  (`assets/js/pdf_viewer.js`): phones can't show a PDF inside a page
  reliably. PDF.js is served as is from `/assets/pdfjs/` (copied at build
  by `assets/scripts/copy-pdfjs.mjs`, loaded by `assets/js/pdfjs_loader.mjs`
  the first time a handout opens), since `app.js` is built for older
  browsers. Pages fit the screen's width and sharpness; the loading and
  error notes live inside the part the page never redraws. Escape or ×
  closes it; Download saves the file.
- Tests: `test/claper_web/live/handouts_room_test.exs`.
