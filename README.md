# Carceral Consultation

**A self-hosted app for interactive workshops and presentations.** The audience joins from their phones with a code, follows the slides, and takes part: messages, polls, quizzes, forms, word clouds, reactions and small-group work. The facilitator runs it all from a laptop. No app to install, and no account needed to join.

It was built for workshops on incarceration, parole and clemency led by formerly incarcerated people, and it works for any workshop or training. It is a fork of [Claper](https://github.com/ClaperCo/Claper) (AGPL-3.0), reworked in November 2026. Every copy sets its own name, logo, photo and colors on the Brand page, without code.

## What it does

**For the people in the room**
- Join with a short code or a QR code, on any phone.
- Follow the slides, send messages and replies, react, and answer polls, quizzes, forms and word clouds.
- Work in breakout groups: tasks one at a time, a shared group answer, a timer.
- See an intro page before the event starts, with its own questions.

**For facilitators**
- Upload slides (PDF or PowerPoint) or show videos, Google Slides, Canva or any website.
- A manager view with the slides, the interactions on each slide, and live results. A presenter view for the big screen.
- **Breakout groups:** a builder and a library for breakout material, a control room while groups work, and results with a CSV export.
- **Intro page:** a page builder for before the start, with Start Event when you're ready.
- Statistics and exports after the event.

**For administrators**
- **Brand page:** name, short mark, description, logo, mark, browser icon, landing photo, home-screen name, privacy contact and source code link.
- Users invited by email (no admin-set passwords), with roles, sign-out-everywhere and two-step reset.
- An Audit Log of sign-ins, account changes and admin actions.

**Security and privacy**
- Passwords of 15+ characters with breached-password checks, and optional two-step sign-in (authenticator app and backup codes; administrators can require it for everyone).
- Sign-in limits, new-device emails, a sessions-and-activity page and security notices.
- Strict security headers, real visitor addresses behind a trusted proxy, and HTTPS settings.
- A privacy page that describes what the copy keeps. Sign-in records are deleted automatically after a year (adjustable).
- Saving to a phone's home screen gives a proper icon and name.

The design and the reasons behind it are in [`docs/`](docs/):
- [THEME.md](docs/THEME.md): colors and controls
- [BRAND.md](docs/BRAND.md): branding, the landing page, the home screen
- [SECURITY.md](docs/SECURITY.md): sign-in, the Audit Log, privacy and retention
- [BREAKOUT.md](docs/BREAKOUT.md): breakout groups
- [INTRO.md](docs/INTRO.md): the intro page
- [INTERACTIONS.md](docs/INTERACTIONS.md): interactions

## Run your own copy

You need Docker with Compose.

```sh
git clone https://github.com/Prophet60191/carceral-consultation.git
cd carceral-consultation
cp .env.sample .env
```

Edit `.env`. At least:

- `SECRET_KEY_BASE`: a new random value, for example from `openssl rand -base64 48`. **Keep it.** Two-step sign-in secrets and stored settings are locked with it, and changing it later breaks them.
- `BASE_URL`: the address people will use, e.g. `https://workshops.example.org`. With `https`, the app turns on secure cookies and HSTS.
- `MAIL_TRANSPORT` and its settings (`resend`, `smtp` or `postmark`), so invitations and password emails can be sent.

Then:

```sh
docker compose up -d --build
```

The app listens on port **4100** (set in `docker-compose.override.yml`; `APP_BIND=127.0.0.1` keeps it to the machine itself). Database migrations run on start. There is no default account. Invite the first administrator from the command line:

```sh
docker compose exec app bin/claper rpc 'Claper.Release.create_admin("you@example.org")'
```

It prints a one-time link (also emailed, if email is set up). Open it to choose your password, then invite everyone else from Admin › Users.

**Behind Cloudflare Tunnel or another proxy:**
- Set `REMOTE_IP_HEADERS` (e.g. `cf-connecting-ip`) and `REMOTE_IP_PROXIES` (the address the proxy connects from), so sign-in limits and the Audit Log see real visitors.
- The other settings, all commented, are in [`.env.sample`](.env.sample).

## Develop

The test suite runs in throwaway Docker containers, so you need no Elixir on your machine:

```sh
scripts/test/run_tests.sh              # all tests
scripts/test/run_tests.sh test/claper  # some
scripts/theme/check_theme.sh           # color and controls checks, before any UI change
```

Built with Elixir, Phoenix LiveView, PostgreSQL, Oban, Tailwind CSS and daisyUI.

## License and credit

Copyright © 2022–2026 Alexandre Lion and the Claper contributors; changes © 2026 the Carceral Consultation contributors.

This program is free software: you can redistribute it and/or modify it under the terms of the **GNU Affero General Public License**, version 3 or (at your option) any later version. See [LICENSE.txt](LICENSE.txt). It comes with no warranty.

If you run a changed copy for others, the license asks you to offer them its source code. The app's About page links to it; set your own address on the Brand page.
