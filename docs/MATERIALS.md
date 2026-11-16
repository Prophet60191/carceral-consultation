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
- Storage: beside the slides on Dynames (in the nightly backup); files
  follow the event's 365-day retention.
- Served as downloads (`Content-Disposition: attachment`, `nosniff`); the
  in-room viewer shows the PDF in a sandboxed frame.
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
