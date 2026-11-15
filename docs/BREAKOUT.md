# Breakout — design record

A new interaction type for Carceral Consultation: the app splits the room
into small groups, gives each group material to read and tasks to answer,
and shows Jose each group's work. Proposed by Jose on 2026-11-13. This file
records the decisions as they are agreed, and the build plan. Nothing is
built yet.

## How the app tells people apart

Each phone's browser gets a random, signed "ticket" in a cookie the first
time it opens the app (`ClaperWeb.EventController.attendee_identifier/2`),
valid 30 days. Same browser = same person across refreshes; a second
browser or a private tab counts as another person. Phones that have the
event open check in under their ticket (Phoenix Presence on
`event:<uuid>`), which is the live list Breakout sorts into groups.

Each open phone has its own LiveView process on the server. Messages are
broadcast to those processes and filtered there, so a phone only ever
receives what is meant for it. Breakout adds a channel per group and a
private channel per ticket.

## Decisions (2026-11-13, Jose)

1. **Groups work together in the room.** They talk face to face; the phone
   carries the material and the answers.
2. **Answers per task.** Each task is either one answer per person or one
   answer per group; Jose chooses per task.
3. **Material per breakout.** Either every group gets the same material or
   each group gets its own; Jose chooses per breakout.
4. **Who sees answers, per exercise.** Group-mates may or may not see each
   other's individual answers; Jose chooses per exercise.
5. **No names.** Reporting back uses group numbers; people identify
   themselves out loud when they speak.
6. **Smart sorter.** Jose sets the largest group size (default 5). The app
   makes the fewest groups that respect it, sizes within one of each other
   (23 → 5,5,5,4,4; 12 → 4,4,4; 7 → 4,3). An exact number of groups can be
   set instead for a breakout.
7. ~~**Late arrivals** join the smallest group~~ (replaced 2026-11-14 by
   decision 24: groups are locked when the breakout starts).
8. **Different material per group cycles across groups** (6 groups, 3 cases
   → groups 1 and 4 get A, 2 and 5 get B, 3 and 6 get C), so each case is
   discussed by more than one group.
9. **Group answers are written by a note-taker** the app picks in each
   group; the rest of the group sees the answer as it is written.
10. **Note-takers volunteer** (revised 2026-11-13; first version had the app
    pick at random). When the breakout starts, every phone in a group offers
    "I'll take notes"; the first to tap it becomes the note-taker, and the
    others' phones then say "Group N's note-taker is writing". A "Hand off"
    button reopens the offer to the group; it also reopens if the
    note-taker's phone is gone for about a minute. Nothing written is lost.
    Jose's screen flags groups without a note-taker.
11. **Material is built from pieces:** typed text plus any of the app's
    interactions (poll, quiz, form, word cloud, web content) and any
    interaction added later. Each group gets a *packet*, an ordered stack of
    pieces; one packet for all groups, or one per case shared out in turn.
12. **Each group's material has its own tasks.** With different material per
    group, each case carries its own tasks and questions.
13. **Choice tasks vary per task:** one answer or several, with or without
    a marked right answer, as Jose sets each task.
14. **Reuse through a Breakout library.** Build once, save to the library,
    pull into any event. The copy in an event and the library copy are
    independent: editing one never changes the other or past workshops.
15. **A dedicated builder page**, not a pop-up form, for building a
    breakout and its packets.

16. **Whole packet at once.** Groups get the entire packet when the breakout
    starts and work through it at their own pace; unfinished work at the
    end is fine and is kept as it is. (Refined 2026-11-14 by decision 23:
    the tasks are shown one at a time; each group still keeps its own pace.)
17. **Reporting back follows each task's setting:** a task with individual
    answers shows the individual answers; a task with a group answer shows
    the group answer.

18. **Timer on the phones, signal only.** A breakout can have a countdown on
    the phones and Jose's screen. At zero it shows "Time's up" and nothing
    locks; Jose stops the breakout when he chooses, and can add time.
19. **Phone flow agreed:** follow the slides → big "Group N" with its color
    → the whole packet in order, pieces marked done → individual or
    note-taker answering as each task says → Jose's messages at the top
    without losing your place → back to the slides at the end.
20. **Answers can be changed until the breakout stops**, then they are final.
21. **Reporting back shows on the phones too**, the way slides do: when a
    group's work is on the big screen, every phone shows it.
22. **Who answers is decided when the task is made** (2026-11-14). Each
    answerable interaction's editor has a "Group answer" box: unticked, each
    person answers; ticked, the group answers once through a note-taker. A
    note-taker exists only because of that box: a group is asked for one
    (on its phones and in Jose's control room) only when its case has a
    group answer. How this plays out across groups with different cases is
    to be looked at next, as its own step.
23. **One task at a time** (2026-11-14), in every breakout. Each person sees
    one task and presses Next when done ("Done reading" for text and web
    content, "Finish" on the last); Back lets them review and change
    earlier answers until the breakout stops; nobody can answer ahead. Each
    person moves on alone, and nothing waits for anyone: a group answer
    opens for whoever reaches it. The phone says how many tasks there are
    at the start and shows a progress bar ("Task 2 of 4"). The note-taker
    request sits on the group-answer task itself ("This one is a group
    answer. Someone needs to take notes"), the only place it is asked. A
    breakout with a single task has no steps, bar or buttons.
24. **Groups are locked when the breakout starts** (2026-11-14). Only the
    people connected at Start get a group. Anyone who opens the app while
    it runs sees "See the presenter to be assigned to a group" until it
    stops; Jose places them in a group out loud and they follow along on a
    group-mate's phone. Jose's reasoning: handling late arrivals in the app
    is complexity it doesn't need. (Runs before this date recorded late
    arrivals in `breakout_members.late`; the column keeps that history.)
25. **Material has no name** (2026-11-14). With different material for each
    group, the sets were called "Case A, B…" (or a name typed in), shown on
    phones, the control room, reporting back, the stats page and the export.
    Jose: "case" is misleading since the material may not be a case, and no
    label is needed at all: the breakout's own text and instructions say
    what it is for. The builder shows each set as "Material and questions"
    with a "1 of 3" counter, "Add material for another group" and "Remove";
    nothing else names it. (Names typed before this stay in
    `breakout_packets.label`, unused.) Where this document says "case", read
    "set of material".

## Open questions (logged, nothing built)

- **A group that gets stuck** (2026-11-14). With one task at a time, a
  group could in theory stall on a task (someone leaves, nobody takes
  notes). Jose doesn't expect this to happen; logged so it is thought
  through before anyone builds a fix. No "move a group on" control for now.
- ~~**Late arrivals**~~ — settled the same day by decision 24.

## Shelved

- **Messages to one person** (2026-11-13, Jose): needs its own thinking and
  planning; return to it later. Messages to all groups and to one group
  stay in scope.

## Engineering consequence of decision 11

Because every interaction, present and future, can be a piece, Breakout
must not know about poll or quiz specifically. Each interaction type will
meet one shared "piece" contract: how it is built, how it shows on a phone,
how an answer is recorded (with its group, and per person or by the
note-taker), and how results are summarized. Breakout works only through
that contract, so a new interaction type becomes usable in breakouts by
meeting it. Typed text is a new piece type of its own.

## Build plan

Each step ends complete: checks, tests, a browser test, a commit.

1. **Agree on the experience** (no code): walk the setting-up, running and
   phone flows and settle each decision. *Done 2026-11-13.*
2. **Foundations** *(done 2026-11-13)*: storage for breakouts, packets,
   pieces, runs, groups, members and answers; the sorter; the piece
   contract with all six types; library and event copies; tests.
3. **Setting it up** *(done 2026-11-13)*: "Breakout" in the manage screen's add menu, built
   from the standard fields and buttons; listed with other interactions;
   copied with the event.
4. **Running it live** *(done 2026-11-13, built with step 5)*: start sorts the connected phones; group cards with
   live answers on Jose's screen; group and personal channels; show one
   group on the big screen; end keeps everything.
5. **The phone** *(done 2026-11-13)*: "You're in Group 3" with the group color; material;
   answering; dark and light; small phones; refresh-safe.
6. **Results** *(done 2026-11-13)*: answers by group on the stats page and in the export.
7. **Real test:** a dozen simulated phones on a test event, then a dry run
   with real phones on the home Wi-Fi.

Group colors become theme roles (distinct from each other, readable in dark
and light, not confusable with error red or success green).

## How the foundations are built (step 2)

- **Storage** (`priv/repo/migrations/20261113180000_create_breakouts.exs`):
  `breakouts` (in an event: slide + position; in the library: neither) →
  `breakout_packets` → `breakout_pieces`. A run (`breakout_runs`) has
  `breakout_groups` and `breakout_members`; answers are in
  `breakout_answers`. Only one run of a breakout can be open at a time.
- **Piece content** stays in each interaction's own table, linked by a
  `breakout_piece_id` column (one per table: polls, forms, quizzes,
  word_clouds, embeds). Piece content has no slide, so the slide screens and
  the audience's normal answer handlers can never reach it. Typed text lives
  on the piece.
- **Answers given in breakouts** are kept apart from the interactions' own
  answer tables, so breakouts cannot disturb slide interactions. One answer
  per person per piece (individual) or per group per piece (group), replaced
  on each change until the run stops.
- **The piece contract** is `Claper.Breakouts.PieceType`; the six types are
  in `lib/claper/breakouts/pieces/`. Each interaction schema has a
  `piece_changeset/2` (its content without a slide).
- **The logic** is `Claper.Breakouts` (building, library, copies, runs,
  each person's step, note-takers, timer, reporting back, answers, results)
  and `Claper.Breakouts.Sorter` (group sizes, dealing, packets in turn).
- **Duplicating an event** copies its breakouts; runs and answers stay
  behind, as with every interaction.
- Tests: `test/claper/breakouts_test.exs`. Run with
  `scripts/test/run_tests.sh`.

## How setting up is built (step 3)

- **Builder page** `ClaperWeb.BreakoutLive.Builder` at `/e/<code>/breakouts/<id>`
  (in an event) and `/breakouts/<id>` (library); `/…/new` names a new one,
  and in an event can start from the library. Settings save as they change.
  Each set of material is a panel ("1 of 3") listing its pieces in order; an answerable piece
  shows "Group answer · note-taker" or "Each person answers" (set in its
  editor, decision 22) and, for individual answers, the "Group sees
  answers" switch; move up/down, edit and remove.
- **Piece editors** reuse the slide editors in piece mode
  (`ClaperWeb.BreakoutLive.PieceEditor`, `piece_target`): delete and
  slide-only options are hidden; answerable editors add the "Group answer"
  box (`PieceEditor.answer_choice/1`), saved with the content in one
  transaction (`Breakouts.update_piece_and_content/3`); saving goes into
  the piece. Typed text has
  its own small editor on the builder. The pop-up is driven by the URL
  (`?add=<kind>&packet=<id>`, `?edit=<piece id>`).
- **Library page** `ClaperWeb.BreakoutLive.Library` at `/breakouts`, linked
  from the account menu ("Breakout library").
- **Manage screen**: "Breakout" is in all three add menus; breakouts are
  listed with the slide's interactions (their own icon; edit opens the
  builder; no on/off switch until starting exists in step 4) and can be
  dragged to another slide like any interaction.
- Tests: `test/claper_web/live/breakout_live_test.exs`.

## How running live is built (steps 4–5)

- **Live updates** (`Claper.Breakouts.Live`): every action (start, stop, add
  time, show a group, note-taker changes, answers, messages)
  goes out on the event's channel `event:<uuid>` with only what changed and
  which run and group. Each LiveView reloads its own viewer's slice from the
  database (`ClaperWeb.BreakoutLive.ViewData`), so a phone never receives
  another group's material. This replaces the per-group channels sketched
  earlier: same privacy, one channel, filtering on the server.
- **Control room** `ClaperWeb.BreakoutLive.Control` at
  `/e/<code>/breakouts/<id>/live`: before starting, "N people connected →
  groups: sizes" and Start; while running, the timer with +1/+5 min, a
  message to all groups or one, a card per group (people, note-taker
  when its tasks need one, progress per piece, answers, "Show on big
  screen"),
  Stop; after stopping, the last run's results and "Start again". Reached
  from the Start / Live button on the breakout's row in the manage screen,
  or "Run live" on the builder.
- **Phones** (`ClaperWeb.BreakoutLive.Phone`, inside the event page): while a
  breakout runs, a full-screen group view covers the slides: group banner
  and color, timer, messages, the tasks one at a time (progress bar, Back /
  Next; each person's place is `breakout_members.step`, and answers are
  accepted only for tasks they have reached), the note-taker request /
  hand-off on group-answer tasks, answering (`Components.piece_input/1`),
  group answers read-only for everyone but the note-taker, group-mates'
  answers where shared, and the reporting-back view. People not in a group
  see `Components.outside_screen/1` (decision 24). A
  note-taker absent for 60 s is freed by the group's other phones (only if
  they still hold the role). Clearing an answer takes it back
  (`Breakouts.withdraw_answer/3`).
- **Big screen** (presenter page): title, groups and people, a large timer;
  during reporting back, that group's results.
- **Timer**: the `BreakoutCountdown` browser hook counts down to the run's
  `ends_at`; at zero it shows "Time's up" (warning color) and nothing locks.
- **Group colors**: theme roles `group-1`…`group-6`, see docs/THEME.md.
- Tests: `test/claper_web/live/breakout_run_test.exs` (a full run with
  phones, the big screen and the control room), plus unit tests in
  `test/claper/breakouts_test.exs`.

## How results are built (step 6)

- **Stats page** (`ClaperWeb.StatLive.Index`): a "Breakouts" tab lists each
  breakout and every run of it, newest first: when it started (viewer's
  local time), groups, people, stopped or running, and each group's
  answers (the same `group_report` as reporting back).
- **Export** `POST /export/breakouts/runs/<run id>`
  (`ClaperWeb.StatController.export_breakout_run/2`, rows from
  `Claper.Breakouts.Export`): one CSV row per answer part, by group, piece
  and person, with the piece, its type and title, who answered (the same
  encoded attendee code as the other exports, or "Group (note-taker)"), the
  question or field, the answer, and when it was saved. Leaders and the
  owner only.
- **Piece contract**: `describe_response/2` turns a stored answer into plain
  text for exports; every piece type implements it.
- Tests: `test/claper_web/controllers/breakout_export_test.exs`.
