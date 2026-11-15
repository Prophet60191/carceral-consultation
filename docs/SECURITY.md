# Security

How this app protects a copy that is reachable from the internet, and what
each setting does. Settings go in the environment (`.env`, see `.env.sample`).
This guide grows as the work in the security plan is done; what isn't here
yet isn't built yet.

## Passwords

Following NIST SP 800-63B-4 (section 3.1.1.2), in
`Claper.Accounts.PasswordPolicy`:

- **At least 15 characters**, NIST's minimum for a password that may be an
  account's only protection. A short sentence works well. There are no rules
  about mixing letters, digits and symbols, which NIST forbids because they
  make passwords harder to remember, not harder to guess.
- **At most 72 bytes**, the most bcrypt uses (at least 64 characters of
  ordinary text, as NIST asks).
- **Not a known breached password.** Checked with Have I Been Pwned's
  Pwned Passwords (`Claper.Accounts.PwnedPasswords`). Only the first 5
  characters of the password's SHA-1 hash leave the server, and the answer
  is padded with decoys. If the service can't be reached, the password is
  allowed and a warning is logged. Turn the check off with
  `PASSWORD_BREACH_CHECK=false` (for example, a copy with no internet).
- **Not the person's name or email address, or the app's name**, even with
  numbers or symbols added.
- **Every refusal says why.**
- Checked when a password is set or changed: sign-up, My account, reset,
  and an administrator setting one. Existing passwords keep working, since
  NIST rules out forcing changes on a schedule.
- Passwords the server makes for accounts that sign in elsewhere (OIDC, an
  LMS) are random and never typed, so these checks skip them.

## Sign-in attempts

Counted in a **sliding window** (`Claper.AuthRateLimit`): "10 in 15
minutes" means no more than 10 in *any* 15 minutes, with no reset point to
time against. Each try is its own record, so tries at the same instant all
count.

- **Per address:** 10 requests a minute to the sign-in pages
  (`ClaperWeb.Plugs.RateLimitPlug`). Blocked requests keep counting, so an
  address that keeps hammering stays blocked.
- **Per account:** 10 *failed* tries in any 15 minutes, wherever they come
  from, counting wrong passwords and wrong codes alike
  (`ClaperWeb.UserAuth.check_account_attempts/1`). This stops guessing
  spread over many addresses. The message is the same whether or not the
  account exists.
  - A successful sign-in clears the count (NIST SP 800-63B-4: earlier
    failures are disregarded after a success).
  - A password reset clears it too, so "reset your password" really gets
    someone back in.
  - Someone who keeps failing at one account can keep it paused. That's the
    trade-off of any per-account limit (OWASP). Two-step sign-in is the real
    protection against guessing, and a reset always works.
- **LMS approval:** 5 tries a minute per account.
- Chat, reactions and the audit's own budgets use `Claper.RateLimit` (fixed
  windows). They are abuse brakes, not guessing defenses.

## Password reset links

A reset link is checked when the form opens **and again when the new
password is saved**. The account always comes from the link, never from the
browser session, so a browser that once opened a link can't set a password
later with a made-up one. Saving spends the link, ends every session of the
account, and lifts its sign-in limit.

## Two-step sign-in

After the password, a 6-digit code from an authenticator app (TOTP), or one
of ten single-use backup codes (`Claper.Accounts.TwoFactor`).

- **Each person chooses** with the switch on My account (Jose, 2026-11-15):
  turning it on goes to the setup page, turning it off asks for a recent
  sign-in and a confirmation, and emails the owner.
- **Unless the administrators require it:** Admin › Settings › "Require
  two-step sign-in for everyone" overrides every switch. When it's on,
  everyone must use it, administrators included, and nobody can turn it
  off. Someone who hasn't set it up is sent to the setup page from any page
  (`ClaperWeb.UserAuth.require_authenticated_user/2` for page loads,
  `ClaperWeb.TwoFactorHook` for live pages).
- **Set up in My account › Two-step sign-in:** scan a QR code (or type the
  key), confirm with a code, then save the backup codes, which are shown once.
- **Stored safely.** The secret is encrypted with the app's secret key, and
  backup codes are kept only as hashes. A code can't be used twice. The
  code from the previous 30 seconds is still accepted, for clocks that drift.
- **Signing in:** a correct password alone grants nothing. The code step
  closes after 5 minutes or 5 wrong codes.
- **Not asked for sign-in through an outside provider** (OIDC, an LMS),
  which runs its own checks.
- **Locked out** (no phone, no backup codes): an administrator can turn it
  off for someone (Admin › Users › the person › "Turn off two-step
  sign-in"). For the last administrator, the server can:

  ```
  docker compose exec app /app/bin/claper eval 'Claper.Release.reset_two_factor("person@example.org")'
  ```

## Confirming it's you ("sudo mode")

Some actions need a sign-in from the last 15 minutes. Otherwise the person is
asked for their password again (and a code, with two-step sign-in on) at
`/users/confirm_password`, then brought back. Confirming starts a fresh
session and ends the old one. Those actions are:

- changing the email address, and deleting the account
- turning two-step sign-in on or off, and making new backup codes (so
  someone at a computer left signed in can't attach their own phone)
- administrators creating, editing, disabling, enabling or deleting
  accounts, and changing the two-step requirement

The check is `ClaperWeb.UserAuth.recently_signed_in?/1`, based on when the
session's token was made.

## Running behind a proxy (Cloudflare Tunnel, nginx, ...)

The app needs each visitor's real address: the sign-in limit (10 tries a
minute per address) and the Audit Log both depend on it. Behind a proxy,
every request arrives from the proxy, and the visitor's address comes in a
header the proxy adds.

**A header is only believed from a trusted proxy** (`ClaperWeb.ClientIp`).
Anyone can write any address into a header. If the app believed headers from
everyone, a person guessing passwords could claim a new address with every
guess and never hit the limit. So:

- `REMOTE_IP_PROXIES`: the addresses (or CIDR ranges) of the proxies that
  connect straight to the app. Requests from anywhere else are judged by
  their own connection address. Empty (the default): no header is believed.
  Keep the list as narrow as the proxy, since anything inside a listed range
  can claim any address.
- `REMOTE_IP_HEADERS`: the header holding the visitor's address. The default
  is `x-forwarded-for`, using the address the proxy added (the last one), not
  ones the visitor wrote before it. **Behind Cloudflare, use
  `cf-connecting-ip`**, which Cloudflare sets to exactly one address.

Live pages (the attendee and presenter screens) are told the address worked
out for the page request; their own connection would only show the proxy.

**A Cloudflare Tunnel example:** run `cloudflared` as a container in the
app's Docker Compose project, on a network with a fixed range, and trust
only that range:

```
REMOTE_IP_PROXIES=172.30.0.0/24      # the tunnel network's range
REMOTE_IP_HEADERS=cf-connecting-ip
```

## HTTPS

When `BASE_URL` starts with `https://`:

- **Cookies are HTTPS-only** (the session and "remember me"), so they are
  never sent over plain http. `SECURE_COOKIE` overrides this for the cookies.
- **HSTS** (`Strict-Transport-Security: max-age=31536000; includeSubDomains`)
  tells browsers to use https for this address from then on, for a year.
- **Plain-http links inside pages are upgraded** (`upgrade-insecure-requests`).

The proxy handles the encryption itself (Cloudflare does). A copy on a home
network over plain http (`BASE_URL=http://...`) keeps working, without these.

## Headers on every response

Set by `ClaperWeb.Plugs.SecurityHeaders`:

- **Content-Security-Policy.** Scripts run only from the app's own files,
  plus the one inline theme script, allowed by its SHA-256 hash
  (`ClaperWeb.ThemeScript.csp_hash/0`). An attacker who slips a `<script>`
  into a page gets nothing. For that to hold, **pages must not contain inline
  scripts or `on...=""` handlers**: put the code in `assets/js` and hook it to
  a `data-` attribute (the LTI buttons are an example). A test checks this.
  - Styles may be inline (the app uses `style=` attributes).
  - Images, media and frames may come from any https address, because
    presentations embed websites, videos and pictures by design.
  - Plugins (`object-src`), changing the page's base address, and forms
    posting to other sites are refused.
- **frame-ancestors** follows each page's `X-Frame-Options`. The attendee
  page can be embedded (learning platforms embed it); the rest only inside
  the app itself.
- **Permissions-Policy**: no camera, location, payment or USB; the
  microphone only for the app itself (live transcription).
- **From Phoenix**: `X-Content-Type-Options: nosniff`,
  `Referrer-Policy: strict-origin-when-cross-origin`, `X-Frame-Options`.

## Email

Password resets and other account email need a real mail service:

- `MAIL_TRANSPORT=resend`, with `RESEND_API_KEY`. Resend sends from a domain
  you verify in its dashboard (it gives DNS records: SPF, DKIM, and a DMARC
  record is recommended).
- `MAIL_TRANSPORT=smtp` or `postmark` also work (see `.env.sample`).
- `MAIL_FROM` must be on the verified domain. Without it, mail comes from
  `noreply@` plus `BASE_URL`'s host.
- With `MAIL_TRANSPORT=local` (the default), mail stays inside the app and
  nothing is sent. That's fine on a private network, but on the internet it
  means nobody can reset a forgotten password.

Starting with `MAIL_TRANSPORT=resend` and no `RESEND_API_KEY` stops the app
with an error, so a missing key is caught at start, not when someone needs a
reset.

**Links with a secret stay sealed until sent.** Reset, confirmation,
change-of-email, magic and OIDC links let whoever holds them act on an
account. Emails go out through a job queue that retries if the mail service
is down; job arguments are kept in the database for a week and written to
the log. So these links are stored encrypted with the app's secret key
(`Claper.Workers.Mailers`), opened only when the email is built. A job whose
link can't be opened is cancelled, not retried.

## Managing accounts

Admin › Users (`Claper.Accounts.Administration`):

- **Two roles:** Administrator (stored as `admin`) and Facilitator
  (stored as `user`). Facilitators run their own events and the ones
  they're added to. Administrators also manage the app, and **see and run
  every event** (Jose, 2026-11-15).
- **Who may do what with an event:**
  - `Claper.Events.can_manage?/2` (owner, facilitator or administrator) is the one rule for every event screen: manage, presenter, the attendee view's host controls, the intro and breakout builders, the breakout control room, statistics and exports, and host replies.
  - `Events.get_owned_event!/3` (owner or administrator) guards editing, ending and deleting.
  - Duplicating and importing stay owner-only, since they copy into your own account.
  - An administrator's edit never changes the owner, and a replaced slide deck's progress shows on the owner's My events.
  - Admin › Events has an **Open** button for each event, and Open event on its details page.
- **Invitations, not passwords.** "Invite someone" takes a name, an email
  and a role. The person gets an email link (7 days, sealed in the mail
  queue) and chooses their own password, under the usual rules. Until then
  the account has a random password nobody knows, and shows as "Invited",
  with "Send the invitation again" (which replaces the old link).
  Administrators never set or see passwords. "Send a password reset link"
  is the way to help someone who forgot theirs.
- **Guards, on the server:** nobody changes their own role or disables or
  deletes themselves, and the last active administrator can't be demoted,
  disabled or deleted.
- **Changes take effect at once:**
  - A new role, disabling, "Sign out everywhere" and turning off someone's
    two-step sign-in end all their sessions. Their tokens are deleted (so
    "remember me" stops too) and open pages disconnect.
  - A new email address gets a confirmation link and changes when its owner
    opens it. For an invitation nobody has accepted yet, the address is
    simply corrected and the invitation re-sent.
- **Each user's page shows** role, status (Invited, Active, Disabled),
  two-step sign-in (On, Off, or Needed), last sign-in and open sessions.
- All of these need a recent sign-in and are written to the Audit Log.

## Audit Log

Admin › Audit Logs keeps a record of sign-ins and of changes to accounts
and settings (`Claper.Audit.record/3`). Each entry says who acted, on what,
and from which address (and, for page requests, which browser).
**Passwords, codes and keys are never recorded**, only that they changed.

- **Sign-in:**
  - `user.login`, with `method`: password, password+code,
    password+backup_code, confirm_password, oidc, lms, sign_up or email_link
  - `user.logout`
  - `user.login_failed`, with `reason`: wrong_password, wrong_code or
    confirm_password_failed. Logged on the account that was tried. Tries at
    addresses with no account aren't logged: what people type there is
    sometimes a password typed in the wrong box.
  - `user.login_paused`: the account reached its limit of failed tries
  - `user.new_device`
  - `security.rate_limit_exceeded`: an address hit the per-address limit
- **People's own changes:**
  - `user.password_changed`, `user.password_set`, `user.password_reset`
  - `user.email_change_requested`, `user.email_changed`
  - `user.profile_updated`, `user.identity_unlinked`
  - `user.two_factor_enabled`, `user.two_factor_disabled`,
    `user.backup_codes_regenerated`
  - `user.account_deleted`
- **Administrators' actions**, logged as the administrator acting on a user
  or other resource, with the target's email kept so entries still read
  after a deletion:
  - `admin.user_invited`, `admin.invitation_resent`,
    `admin.invitation_email_corrected`, `admin.email_change_sent`,
    `admin.password_reset_sent`, `admin.user_signed_out_everywhere`,
    `admin.two_factor_reset`; and on the person's side,
    `user.invitation_accepted`
  - `admin.user_created`, `admin.user_updated` (which fields),
    `admin.user_role_changed` (from, to), `admin.user_disabled`,
    `admin.user_enabled`, `admin.user_deleted`
  - `admin.settings_changed`
  - `admin.brand_updated`, `admin.brand_image_updated`,
    `admin.brand_image_removed`
  - `admin.oidc_provider_created`, `admin.oidc_provider_updated`,
    `admin.oidc_provider_deleted` (never the client secret)
  - `admin.lti_platform_approved`, `admin.lti_platform_revoked`
  - `admin.event_created`, `admin.event_updated`, `admin.event_deleted`,
    `admin.transcription_deleted`

Live pages get the visitor's address from the page request
(`ClaperWeb.AuditContext`), since their own connection only shows the proxy.

## New-device email

When an account signs in from a browser it hasn't used before, its owner
gets an email: when, which browser ("Safari on iPhone",
`ClaperWeb.UserAgent`), from which address, and what to do if it wasn't
them (reset the password, turn on two-step sign-in).

- Each browser keeps a random ID in a signed, HTTPS-only (when served over
  https), HttpOnly cookie, `_cc_device`, for 400 days. Each account keeps
  only the hashes of the IDs it has used (`user_devices`,
  `Claper.Accounts.KnownDevices`).
- Quiet the first time: an account's first browser on record (a new account,
  or one from before this existed) doesn't trigger an email, and neither
  does signing up.
- Clearing cookies or using a private window looks like a new browser, so
  it sends the email again. That errs on the side of telling the owner.

## My account: sessions and activity

My account › Sessions and activity (`ClaperWeb.UserSettingsLive.Security`):

- **Where you're signed in:** every open session, with its browser and
  address (recorded when it signed in, on `users_tokens`) and when, with
  "This browser" marked. Sign any other one out, or "Sign out everywhere
  else". Ending a session deletes its token and disconnects its open
  pages (`Claper.Accounts.Sessions`). Each lookup is scoped to the person,
  so nobody can end someone else's session by guessing its number.
- **Recent activity:** the last 30 entries of the person's own Audit Log in
  plain sentences (`ClaperWeb.ActivityText`), including what administrators
  did to their account (role, sign-outs, two-step turned off). Other
  people's actions and event activity aren't shown.
- Changing the email address or deleting the account needs a recent
  sign-in (see "Confirming it's you").

## Security notices

Emails that make a takeover hard to miss (`Claper.Accounts.SecurityNotices`):

- **Email address changed:** sent to the **old** address. If it wasn't
  them, the new address is the attacker's, so the old one is the one that
  needs to know.
- **Password changed:** changed in My account, reset by link, or set.
- **Two-step sign-in turned off:** by them, or by an administrator.

These emails carry no links with secrets, only where to go next.


## Privacy page and record retention

Added 2026-11-15, before the app went public.

- **`/privacy`** (`PageController.privacy`, `templates/page/privacy.html.heex`) says what the app keeps, who sees it, how long it is kept, the cookies it uses, and who to ask. It is linked from the landing page (desktop and phone) and the About page.
- **Setup-dependent facts come from `ClaperWeb.Privacy`,** so the page never names a service a copy doesn't use: Cloudflare when `REMOTE_IP_HEADERS` includes `cf-connecting-ip`, Resend or an email server from the mail transport, Amazon S3 when presentations are stored there, and the sign-in provider when single sign-on is on.
- **The contact address** is the Brand page's "Privacy contact email" (`brand_settings.privacy_email`). Without one, the contact line is left out.
- **`PRIVACY_URL`:** when a copy sets it for its own policy, every privacy link goes there instead (`ClaperWeb.Privacy.url/0`).
- **Retention (`Claper.Retention`, daily `Claper.Workers.RecordRetention`):** after `RECORD_RETENTION_DAYS` (default 365; `0` keeps everything), the job deletes:
  - Audit Log entries
  - sign-in and account tokens, which hold each sign-in's address and device
  - remembered devices not seen in that time
  
  Event content is kept until the event is deleted, and accounts until they are deleted. The privacy page states the number of days in use.

## Password fields

Added 2026-11-15 (`ClaperWeb.Component.PasswordReveal`, `assets/js/password_reveal.js`).

- **Show/hide:** every password field has an eye button. It covers sign-in, the invitation, the password reset, sign-up, confirm-it's-you, My account (change and set password, the LMS local password) and the admin's secret fields.
  - On live pages it uses LiveView JS commands, so a shown password stays shown through the page's redraws while typing.
  - Sending a form hides its passwords again, so browsers still offer to save them.
- **Browser suggestions:** fields where someone chooses a password carry `autocomplete="new-password"`, `minlength="15"` and Safari's `passwordrules="minlength: 15;"`, matching the password rules. A hidden `autocomplete="username"` field with the account's email tells the browser which account the password belongs to. Together these let Safari, Chrome and password managers suggest a strong password and save it under the right account. Sign-in fields use `autocomplete="current-password"`.
