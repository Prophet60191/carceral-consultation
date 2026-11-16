# Live room (what participants see after the start)

`ClaperWeb.EventLive.Show` (`show.html.heex`), once the event has started; before the start participants see the intro page ([INTRO.md](INTRO.md)). One page, one set of parts (the menu, the attendee count, the slide, the interaction, captions, messages, reactions), laid out per device. Devices are told apart by how they point, not by width (see "Device rules" below).

## Layout (2026-11-15, Jose)

The slide fills the screen on every device, and everything else floats over it:

- **Top left:** the menu (the event code button opening the side menu).
- **Top right:** the attendee count, as a pill readable over any slide.
- **Interactions** (polls, quizzes, forms, word clouds, web content shown to participants) appear as a solid card in the middle of the slide. The slide stays visible behind it. Jose: the card is **not** frosted glass. The interaction's own panel is the card (with a border and shadow, and no second frame around it).
- **Captions** run as a strip across the bottom of the slide.
- **Messages** open from the chat bubble, the same messenger as the intro page's, with the same behavior. A click outside it or Escape closes it. A red dot on the bubble means someone else posted while it was closed.
- **The full-screen button** sits at the slide's bottom right. There is no "hide the slide" anymore: it existed to make room for the messages, which no longer share the screen.
- **No slide yet** (an event without a presentation): "The presentation will appear here."

### Computers

- **Bottom left:** the light/dark button, with the message bubble above it; the messenger opens as a glass panel above the bubble.
- **Bottom right:** the live reactions button, beside the full-screen button, and the handouts icon above the full-screen button (docs/MATERIALS.md).
- Captions are centred and kept clear of the corner buttons on both sides.

### Phones and tablets (Jose: "make the same change to phone and tablet")

- **The bottom bar**, the same as the intro page's: the message bubble and the light/dark button at its left, the live reactions button in its middle, the handouts icon at its right (when a handout is on; Jose 2026-11-15: left is you, right is the event's material). The slide fills the space above it.
- **Messages** slide up from the bar as a sheet (centred, at most 640 px wide, on tablets); swipe it down, tap outside it or tap the bubble to close it.

## How it is built

- **One messenger component** (Jose, 2026-11-15: "they should be the same and reusable"): `ClaperWeb.EventLive.Messenger` draws the bubble, the red dot, the glass panel with its header, the light/dark button (`theme_button/1`) and the phones' bottom bar (`phone_bar/1`). The intro page and the live room use them identically, on every device; their look and placement are in `assets/css/messenger.css`. `assets/css/room.css` holds only the room's own layout: the slide, the top corners, the interaction card, captions, reactions and the empty stage.
- **One message system:** `ClaperWeb.EventLive.MessagesComponents` (`feed/1`, `composer/1`, `identity_menu/1`) draws the messages, the message box and the "post as" menu, on the intro page and in the room, on every device.
- **Open/closed is the server's:** `messenger_open` and `messenger_unread` assigns; events `toggle-messenger` and `close-messenger`. The red dot is set for any message that isn't your own while the messenger is closed.
- **The hook:** `Messenger` (`assets/js/messenger.js`) serves both pages. It finds the panel and bubble by `[data-messenger-panel]` and `[data-messenger-toggle]`.
- **The slide behind an interaction:** in interaction mode the slide image is drawn as `.room-slide-backdrop`, so the card has something to sit on.

## Device rules

- Computers: `(hover: hover) and (pointer: fine)`, at any width.
- Phones and tablets: every other device (`not all and (hover: hover) and (pointer: fine)`), so each device gets one of the two layouts.
- **LiveView redraws the room on every message, reaction and attendee change.** Any class or style a script puts on a redrawn element is undone. State that must survive (slide full screen, captions hidden, messenger open on a phone) lives on `<html>` as a class (`cc-slide-fullscreen`, `cc-captions-collapsed`, `cc-sheet-open`), or on the server. The theme button sits in a `phx-update="ignore"` block.
