# Intro page

The page participants see on their phones from the moment they join until
the presenter starts the event (Jose, 2026-11-14). It replaces the old
"ticket" waiting screen, which only showed before an event's scheduled start
time and could not be changed.

## Decisions (2026-11-14, Jose)

1. **Every event has an intro page.** It is required: a new event gets a
   starter page automatically, existing events got one when this was built,
   and a page can be changed but not removed.
2. **Built from blocks, without code.** Blocks are added like interactions,
   each with its own simple form, and stacked in order. First set: Heading,
   Text, Image, Stat (a big number and a label), Agenda (time + item rows),
   Link (a button that opens a web page), Divider. Adjusted after use.
3. **The app draws every block** with the design system, so a page always
   looks right on any phone, dark or light. No free-form layout, fonts or
   colors.
4. **Reusable.** Pages can be saved to a library and copied into events, like
   breakouts.
5. **The presenter starts the event.** A **Start Event** button (manage
   screen top bar) moves every phone from the intro page to the first slide.
   The scheduled start date and time no longer starts anything; it is shown
   on the intro page with the countdown, which stays as it is.
6. **Starting can be undone**: "Back to intro" sends everyone back.
7. **Latecomers** after the start go straight to the slides; an "About this
   event" link keeps the intro page within reach.
8. **The intro page has no QR code**: anyone seeing it is already in.
9. **The big screen before the start** shows the join screen (brand, QR
   code, address, code) with the start time / countdown added, for people not
   looking at their phones.
10. **Edit intro** and **Start event / Back to intro** sit in the manage
    screen's top bar, nowhere else.

### Interactions on the intro page (2026-11-14, Jose)

11. **Interactions are blocks too**: Poll, Quiz, Form, Word cloud and Web
    content (not Breakout) are added from the same Add buttons, edited with
    the editors used on slides (without the slide-only options), and sit in
    the section cards in order. They save and copy with the page (library,
    duplicates) like any block.
12. **Answers are individual and anonymous** (the phone's ticket), and can be
    given and changed while phones show the intro page: until **Start
    event**, then they freeze (Back to intro opens them again).
13. **Phones don't show results; the big screen does.**
14. **The big screen before the start is side by side, in even halves**: the
    join column on the left (brand, the QR at nearly full size, address, code,
    start time) and the live results on the right, scaled up to fill their
    half, one interaction at a time, moving on about every 12
    seconds with dots showing where it is; one interaction just stays; with
    none, the join screen stays as it is. Web content has no results and is
    skipped.
15. **Form answers on the big screen are a per-form choice**: a switch in
    the form's editor shows the written answers (anonymously); off (the
    default), only how many people answered.
16. **No separate results view** for the presenter: the big screen is it.

## Build plan

1. Design (this record).
2. **Page builder** (done 2026-11-14): the data (required page per event, blocks), the
   builder page at `/e/<code>/intro` with a live phone preview, image
   upload, and the Edit intro button.
3. **Start Event** (done 2026-11-14): the started / not started state, Start Event and Back
   to intro, phones showing the intro page (with the countdown, without the
   QR code) until the start, "About this event" afterwards.
4. **Big screen before the start** (done 2026-11-14): join screen with the start time.
5. **Library** (done 2026-11-14): save a page to the library, start an event's page from one.
6. **Interaction foundations** (done 2026-11-14): interaction blocks backed by the
   interactions' own tables (as breakout pieces are), an `intro_answers`
   table, the answering rules (open until Start event).
7. **Builder** (done 2026-11-14): Poll, Quiz, Form, Word cloud and Web content in the Add
   buttons, their editors in intro mode, the per-form big-screen switch; the
   phone preview shows them.
8. **Phones** (done 2026-11-14): answering on the intro page.
9. **Big screen** (done 2026-11-14): the side-by-side join screen with the cycling live results.

## How the page builder is built (step 2)

- **Data**: `intro_pages` (one per event, unique `event_id`; `event_id`
  null for library pages, owned by `user_id`) and `intro_blocks` (`kind`,
  `position`, `data` as JSON). The `Claper.Intro` context creates the
  starter page with every new event (`Events.create_event/1`), copies it when
  an event is duplicated, and validates each block kind
  (`Claper.Intro.Block`).
- **Images** are uploaded in the builder (drag and drop or Choose image,
  PNG/JPG/WebP/GIF up to 8 MB) and stored with the app's other uploads on the
  uploads volume (`<storage>/uploads/intro/<uuid>.<ext>`, served at
  `/uploads/intro/...`). An image block only accepts files from there.
  Removing a block leaves its file (a duplicated event's copy may share it).
- **Builder**: `ClaperWeb.IntroLive.Builder` at `/e/<code>/intro` (event
  leaders only). Add buttons at the top, the blocks in order with move
  up/down, edit and remove; the block form opens in a dialog driven by the
  URL (`?add=<kind>`, `?edit=<id>`). Beside it, a phone-sized preview drawn
  by `ClaperWeb.IntroLive.Components.page/1`, the same component the phones
  use from step 3.

## How Start Event and the phones are built (step 3)

- **State**: `presentation_states.started` (false for new events and copies;
  the migration marked events whose scheduled start had passed as started).
  Changing it goes out like every other presentation setting
  (`:state_updated`), so all phones switch at once.
- **Manage screen**: one button in the top bar, next to Edit intro:
  **Start event** (highlighted) before the start, **Back to intro** after it,
  so the bar itself shows where phones are (2026-11-14, Jose: the strip under
  the bar and the second Edit intro were removed). Words from 1024px, the icon
  narrower; on phones it sits in the row under the bar. Both confirm with the
  alert dialog and end with a toast.
- **Phones** (`EventLive.Show`): `ClaperWeb.IntroLive.Components.intro_screen/1`
  until the start: the ticket (event name, date, the countdown to the
  scheduled start, "Starting soon" once it has passed; the clock starts
  nothing) and the blocks below, no QR code. After the start, the side menu's
  **About this event** opens the same page over the slides. Builder changes
  reach open phones live (`:intro_updated` on the event channel). Event
  leaders signed in on a phone see the slides view, as before.

## How the big screen works before the start (step 4)

The presenter page shows the join screen while `state.started` is false (as
well as whenever "Show join instructions" is on), with the scheduled start in
local time and a live "Starts in …" countdown (`StartCountdown` hook) that
reads "Starting soon" at zero. While the time shows, the QR code is a little
smaller (38vmin) so everything fits; the QR redraws whenever its box changes
size (ResizeObserver in the `QRCode` hook). Start event hides it on every
screen at once.

## How the library works (step 5)

- **Intro library** (account menu, `/intros`, `ClaperWeb.IntroLive.Library`):
  the user's saved pages with Edit and Delete, and "New intro page" (a name,
  then the builder with the starter blocks).
- **Library pages** open in the same builder (`/intros/<id>`), with a Name
  field; editing one never changes events that already used it (they hold a
  copy).
- **In an event's builder**, an Intro library panel: "Save a copy" (named, the
  event's name by default) and "Use this page" (replaces the event's blocks
  with a copy of a library page, after a confirmation; phones showing it
  update right away).
- `Claper.Intro`: `list_library/1`, `get_library_page/2` (owner only, never
  an event's page), `create_library_page/2`, `save_to_library/3`,
  `rename_library_page/2`, `delete_library_page/1`, and
  `copy_page_to_event/2` for using one in an event.

## Banner (added 2026-11-14, Jose)

An optional cover image across the top of the ticket card, above the title
and countdown, tilting with the card on desktop (`intro_pages.banner_src`,
`banner_alt`; an uploaded image under /uploads/intro/ only). Set, replaced or
removed in the builder's Banner section (drop zone, description for screen
readers, Save banner); copied with the page into the library, from it, and
when an event is duplicated.

## Messages before the start (2026-11-15, Jose)

On computers (any device with a mouse or trackpad, at any window width; a narrowed browser window still gets it, Jose 2026-11-15), when **Allow messages** is on, a chat bubble sits in the bottom-left corner of the intro page.
- **The messenger:** clicking the bubble opens a frosted-glass messenger above it. It holds the event's messages as chat bubbles, with replies and reactions, and the message box with the name or anonymous choice. It is the live room's message system: `ClaperWeb.EventLive.MessagesComponents` draws the feed, the message box and the "post as" menu for both. Messages sent here are the event's messages and carry into the live feed at Start Event.
- **Closing:** clicking the bubble again, anywhere outside the messenger, its close button or Escape closes it. Clicking a confirmation dialog or tooltip doesn't count as outside.
- **The red dot:** a red dot on the bubble means someone else's message arrived while the messenger was closed; opening it clears the dot. Your own messages never light it.
- **"Allow messages"** now applies from the moment people join, not only after the start (the server always accepted it; only the page was missing). It's on by default, so existing events show the bubble unless messages are turned off.
- **Unchanged:** the big screen before the start (the join page and QR code), phones and tablets (to be discussed), and the "About this event" view over the slides.
- **Files:** server state (open, red dot) in `EventLive.Show`, closing behavior in `assets/js/intro_messenger.js`, the look in `assets/css/intro_messenger.css`.

## Cards (2026-11-15, Jose)

Below the ticket, every block is its own card, shaped for its kind (`IntroLive.Components.page/1`; styles in `assets/css/ticket.css`, "Intro cards"). Before this, all the blocks between two headings shared one card.

- **Heading:** a section title above its cards, not a card.
- **Text:** a card.
- **Image:** edge to edge across the top of its card, with the caption under it.
- **Stats:** stats next to each other share a row, three across (two on a phone, where a leftover one takes the full row).
- **Agenda:** an "Agenda" label, with times in their own column.
- **Link:** the whole card opens it, showing the site's name and an arrow, and it lifts under the mouse.
- **Divider:** a quiet line between cards.
- **Interactions** (poll, quiz, form, word cloud, web content): a label saying which kind, then the question.

Groups fade up one after another when the page opens, with no motion when the device asks for less. The builder's preview uses the same component. All text on the ticket and intro page is at least 12 px; the countdown labels, ticket details, code label and footer were raised from 10–11 px.

## Hiding the brand (2026-11-15, Jose)

The builder's first setting, **Show the brand at the top**, is a switch row that is on by default (`intro_pages.show_brand`). Off removes the brand pill (the mark and name from Admin › Brand) above the ticket card, on participants' phones and in the preview at once. It is copied with the page into and out of the library, and when an event is duplicated. The footer's "Powered by Claper" and "About this app" stay: they are the license notices (AGPL-3.0), not branding. The big screen's join page before the start keeps its own brand.

## The phone preview (2026-11-14, Jose)

The builder's preview is the real phone page, not a sketch of it:
`ClaperWeb.IntroLive.Preview` (`/e/<code>/intro/preview`, `/intros/<id>/preview`)
draws the same `intro_screen/1` participants get (brand, ticket with banner
and live countdown, section cards), shown in a 390px-wide frame so it uses the
phone layout. The builder announces every change on `"intro_page:<id>"`, and
the preview reloads (and follows the event's new page after "Use this page").
A library page has no event, so its name stands in for the title and the
countdown runs to a sample start an hour away.

## How interactions on the intro page are built (steps 6-9)

- **Content**: an interaction block's content is a row in the interaction's
  own table with `intro_block_id` (as breakout pieces use
  `breakout_piece_id`); `Claper.Breakouts.Pieces.Content` takes either owner,
  so the breakout piece types (create, load, copy, validate an answer,
  summarize) serve both. Deleting a block deletes its content and answers.
- **Answers**: `intro_answers`, one per phone per block. `Claper.Intro.put_answer/4`
  and `withdraw_answer/3` refuse once `state.started` is true;
  `Intro.results/1` sums each answerable block for the big screen.
- **Builder**: the Add buttons include the interactions; each opens its slide
  editor with an intro target (`ClaperWeb.BreakoutLive.PieceEditor`:
  `{:intro_new, page}` / `{:intro_edit, block}`): no "Group answer" box; a
  form gets "Show answers on the big screen" (`block.data["show_answers"]`).
  Saving announces the change (`Intro.broadcast_changed/2`) to the preview and
  phones.
- **Phones**: the blocks are drawn by `BreakoutLive.Components.piece_input/1`
  with `events="intro"`; `ClaperWeb.IntroLive.Answering` handles the
  `intro_*` events, building the answer with `BreakoutLive.Responses` (shared
  with breakout phones), and tells the big screen (`:intro_answered`).
- **Big screen**: before the start, with answerable interactions, the join
  screen splits into even halves: the join column (QR at 38vmin) and a results card cycling one
  interaction every 12 seconds (`IntroCarousel` hook) with dots; results
  drawn by `BreakoutLive.Components.results/1`, scaled up with the screen
  height; a form shows only its count unless its switch is on.
