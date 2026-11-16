# Live room (what participants see after the start)

`ClaperWeb.EventLive.Show` (`show.html.heex`), once the event has started; before the start participants see the intro page ([INTRO.md](INTRO.md)). One page, one set of parts (the menu, the attendee count, the slide, the interaction, captions, messages, reactions), laid out per device. Devices are told apart by how they point, not by width (see "Device rules" below).

## Computers (2026-11-15, Jose)

The slide fills the window, and everything else floats over it:

- **Top left:** the menu (the event code button opening the side menu).
- **Top right:** the attendee count, as a pill readable over any slide.
- **Bottom left:** the light/dark button, with the message bubble above it. The bubble opens the same frosted-glass messenger as the intro page, in the same place, with the same behavior. A click outside it or Escape closes it. A red dot on the bubble means someone else posted while it was closed. On opening it shows the newest messages and puts the cursor in the message box.
- **Bottom right:** the live reactions button (next to the full-screen button when there is one).
- **Interactions** (polls, quizzes, forms, word clouds, web content shown to participants) appear as a solid card in the middle of the slide. The slide stays visible behind it. Jose: the card is **not** frosted glass. The interaction's own panel is the card (a border and shadow are added on computers, with no second frame around it).
- **Captions** run as a strip across the bottom of the slide, clear of the corner buttons on both sides.
- There is no "hide the slide" on computers; the slide always fills the window.

## Phones and tablets

Phones and tablets share one layout: the slide on top (expand to full screen or hide it), then captions, then the message feed with the message box at the bottom. The messenger's wrapper and panel are `display: contents` here, so the feed and the message box are the room's own rows; the bubble, the panel header and the theme button are hidden.

## How it is built

- **One messenger component** (Jose, 2026-11-15: "they should be the same and reusable"): `ClaperWeb.EventLive.Messenger` draws the bubble, the red dot, the glass panel with its header, and the light/dark button (`theme_button/1`), for the intro page (`place={:intro}`) and the live room (`place={:room}`, `inline_on_touch`). Its look and placement, both pages, all devices, are in `assets/css/messenger.css`. `assets/css/room_desktop.css` holds only the room's own layout: the slide, the top corners, the interaction card, captions and reactions.
- **One message system:** `ClaperWeb.EventLive.MessagesComponents` (`feed/1`, `composer/1`, `identity_menu/1`) draws the messages, the message box and the "post as" menu, on the intro page and in the room, on every device.
- **Open/closed is the server's:** `messenger_open` and `messenger_unread` assigns; events `toggle-messenger` and `close-messenger`. The red dot is set for any message that isn't your own while the messenger is closed.
- **The hook:** `Messenger` (`assets/js/messenger.js`) serves both pages. It finds the panel and bubble by `[data-messenger-panel]` and `[data-messenger-toggle]`.
- **The slide behind an interaction:** in interaction mode the slide image is drawn as `.room-slide-backdrop` (hidden on phones and tablets) so the card has something to sit on.

## Device rules

- Computers: `(hover: hover) and (pointer: fine)`, at any width.
- Phones and tablets: `(pointer: coarse)`.
- **LiveView redraws the room on every message, reaction and attendee change.** Any class or style a script puts on a redrawn element is undone. State that must survive (slide expanded or hidden, captions hidden, messenger open on a phone) lives on `<html>` as a class (`cc-slide-fullscreen`, `cc-slide-collapsed`, `cc-captions-collapsed`, `cc-sheet-open`), or on the server. The theme button sits in a `phx-update="ignore"` block.
