# Interactions on slides

Polls, quizzes, forms, word clouds and web content added to slides on the
manage screen. Intro-page interactions are in [INTRO.md](INTRO.md), breakout
pieces in [BREAKOUT.md](BREAKOUT.md).

## Results on the big screen (2026-11-14, Jose)

1. **Chosen when building.** Polls, quizzes, word clouds and forms each have
   a box in their editor: "Show the results on the big screen" ("Show the
   answers on the big screen" for a form). Unticked by default, and for every
   interaction that existed before this.
2. **Turning an interaction on starts the big screen from that box.**
   Ticked, its live results appear at once; unticked, the slide stays. Nothing
   carries over from the interaction before it.
3. **The manage screen's switch is for this run only.** In Current Interaction
   Settings (shortcut Z, shown while an interaction is on), "Show results on
   big screen" ("Show answers on big screen" for a form) hides or shows the
   results now without changing the box. The next time the interaction is
   turned on, or in a copy of the event, it follows the box again.
4. **Forms on the big screen** show what people wrote, newest first, without
   names, and how many answered. Before this, slide forms never showed there.
5. **Phones are a separate choice**: "Show the results on phones" (poll) and
   "Show the word cloud on phones" (word cloud). A quiz has one reveal for
   both: phones see their score and the right answers when the big screen
   shows the results.

Web content has no results; a breakout reports back with its own "Show on big
screen".

### How it is built

- `results_on_screen` on `polls`, `quizzes`, `word_clouds` and `forms`
  (slides only: breakout and intro copies never use it). Copied when an event
  is duplicated or its interactions imported.
- `Claper.Interactions.show_planned_results/2`, called by the manage screen
  right after turning an interaction on (`EventLive.Manage` `activate/2`):
  poll, word cloud and form set the presentation's `poll_visible` (the
  switch); a quiz sets its own `show_results` (its reveal).
- The big screen (`EventLive.Presenter`) draws form answers with
  `BreakoutLive.Components.results/1` from `Claper.Forms.summarize_answers/1`,
  refreshed on every new, changed or deleted answer.
