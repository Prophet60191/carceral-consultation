# Brand

Anyone who runs a copy of this app sets their organization's brand on the
**Brand page** (Admin › Brand, `/admin/brand`), without changing code
(2026-11-14). A fresh copy shows plain, neutral defaults until its owner does.

## What the Brand page sets

| Setting | Where it shows | Without it |
|---|---|---|
| Organization name | page titles, emails (sender and subjects), sign-in panel, About page, and in type wherever there is no logo | "Your organization" |
| Short mark (up to 3 letters) | the round tile in the brand lockup, event cards without slides, when there is no mark image | the name's initials |
| Description | the landing page and the sign-in pages, over the photo | a neutral sentence |
| Logo (PNG/WebP, transparent) | join page, phones, sign-in panel, LMS pages, About page | the name in type |
| Mark (PNG/WebP, transparent) | the lockup tile (phone intro page, big-screen join page), event cards | the short mark's letters |
| Browser icon (square PNG) | browser tabs and bookmarks; the LMS registration; the home-screen icon when it is at least 180 × 180 | `/images/default-icon.png` (a plain chat bubble) |
| Home-screen name (up to 12 characters) | under the app's icon on a phone's home screen, and the manifest's `short_name` | the organization name if it fits, otherwise the short mark |
| Photo (JPG/PNG/WebP) and which side to keep in view | the landing page (full screen; `ClaperWeb.Landing`) and the sign-in, sign-up and password pages | a plain panel in the current theme |
| Source code address | the About page's "Get the source code" | the upstream project (see below) |
| Privacy contact email | the privacy page (`/privacy`), for questions and deletion requests | the contact line is left out |

## Decisions

1. **Settings, not code.** Everything that names or shows the organization
   comes from `Claper.Branding`; nothing brand-specific is in the
   repository. (Jose's own brand lives in his copy's database and uploads;
   the original files are kept outside git.)
2. **Colors are not part of the brand.** The app's palette is a neutral grey
   design system (docs/THEME.md) tuned to stay readable in dark and light;
   letting each copy change it would risk unreadable text. Logo and mark
   images are drawn in the theme's text color (their shape, used as a mask),
   so one file works in both themes. A full-color logo shows as one color.
3. **Images are checked.** Each image accepts only its own file types, up to
   a size limit, and its first bytes must match the type, so a renamed file
   is refused. SVG is never accepted: a script inside one could run on the
   app's own address. Replacing or removing an image deletes the old file.
4. **Administrators only**, checked again on every change.
5. **Emails** show the name in type (email clients can't recolor a logo);
   the sender name is the server's `MAIL_FROM_NAME` when set, otherwise the
   brand's name.
6. **Error pages** (404, 500) don't read the brand: they may be shown because
   the database is unreachable.

## License obligations (AGPL-3.0)

This program is a modified version of Claper, under the GNU Affero General
Public License v3 (see [../NOTICE.md](../NOTICE.md) and `LICENSE.txt`). For
everyone who uses a running copy over the network:

- **The About page** (`/about`, public) says the app is free software based
  on Claper, credits Claper's authors, says it has been changed, names the
  license with a link to it, states that there is no warranty, and links to
  the source code (section 13, and the "Appropriate Legal Notices" of
  section 5d).
- **It is linked** from the join page, the sign-in pages, the phone's side
  menu and intro page, and the account menu.
- **The source code address** defaults to the upstream Claper repository
  (`Claper.Branding.default_source_url/0`). Whoever runs a changed copy must
  point it at their own published source on the Brand page; when this fork
  is published, the default changes to its repository.
- The license text (`LICENSE.txt`) and `NOTICE.md` (what this program is
  based on, the starting point, that it has been changed and when) stay in
  the repository.

## How it is built

- **Data**: one row in `brand_settings` (`Claper.Branding.Brand`); every
  field may be empty. Image fields are only set by the server.
- **`Claper.Branding`**: `get/0` (cached in `:persistent_term`, replaced on
  every save), `update/1`, `put_image/3`, `remove_image/1`, and the readers
  with defaults (`name/1`, `monogram/1`, `description/1`, `icon_src/1`,
  `source_url/1`, `mail_from/0`). Images are stored under
  `<storage>/uploads/brand/` and served at `/uploads/brand/…`.
- **Display**: `ClaperWeb.Wordmark.mark/1` and `lockup/1` (pass `brand=` where
  it can change on the page, so LiveView redraws it), `ClaperWeb.BrandPanel`
  (sign-in panel), `ClaperWeb.LayoutView.brand_name/0` and `brand_icon/0`
  (titles and icon), the email layout and notifiers, the LMS registration.
- **Page**: `ClaperWeb.AdminLive.BrandLive`; uploads save as soon as they
  finish (`auto_upload` with a progress callback).
- **Tests**: `test/claper/branding_test.exs`,
  `test/claper_web/live/admin_live/brand_live_test.exs`.

## The home screen

Added 2026-11-15, after Jose's phone test showed iPhones asking for `/apple-touch-icon.png` and getting nothing. Every page layout (root, user, admin) includes `ClaperWeb.HomeScreen.tags/1`:
- `<link rel="apple-touch-icon">` (180 px), which iPhones use when the page is added to the home screen
- `<meta name="apple-mobile-web-app-title">` for the home-screen name
- `<link rel="manifest" crossorigin="use-credentials">`, for Android's "Add to Home screen"; the credentials let it load behind a sign-in such as Cloudflare Access

`ClaperWeb.HomeScreenController` serves `/home-icon/{180,192,512}.png`, `/apple-touch-icon.png`, `/apple-touch-icon-precomposed.png` and `/manifest.webmanifest`. The manifest uses `display: browser`, so a saved icon opens the app in the phone's browser, where sign-in and cookies behave as usual.

`Claper.Branding.HomeIcon` draws each size with ImageMagick: square and solid (iPhones fill transparency with black), on the theme's page color. It uses the uploaded browser icon when that is at least 180 px on its short side; otherwise it uses the short mark, drawn sharp in Roboto Medium in the theme's text color. Files are cached in `uploads/brand/home-icons/`, named after a version of everything that shapes them, and the old ones are removed. Links carry `?v=<version>`, so phones fetch the new icon after a brand change. Without ImageMagick, the addresses redirect to the browser icon as it is. The Brand page previews the home-screen icon and its name on the icon card.

## The landing page

`/` is the front door for everyone (`ClaperWeb.Landing`, 2026-11-15): the
photo fills the screen with the name, description and "About this app";
"Join event" and "Log in" (top right; "My events" when signed in) open a
panel on the right and the photo narrows to make room. On phones the photo
shrinks to a banner with just the name. `/join` and `/users/log_in` open
with their panel; opening one on the page adds `#join` / `#log-in` so the
browser's Back button (and Escape) closes it. Less motion on the device:
no animation. Search engines are asked not to index the app
(`ALLOW_SEARCH_INDEXING`).

