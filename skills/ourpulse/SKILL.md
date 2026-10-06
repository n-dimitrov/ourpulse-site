---
name: ourpulse
description: Ask a group of humans a question with an OurPulse survey (a "pulse") and continue with their answers. Use when the user says "ask the team", "run a quick poll/survey/retro/check-in", "get votes on", or wants a decision from several people. Shows the draft (questions, open and close times) for approval, creates the pulse, hands back the link and offers the full-screen invite screen, waits for it to close, and returns the results as data. Also use for follow-ups on an existing pulse: "what did the team say", "show the results", "analyze the retro", "write the report", "push the report to the pulse".
---

# OurPulse: tiny surveys ("pulses") for teams and agents

OurPulse is a REST API. The helper `ourpulse.sh` next to this file wraps the calls and handles the key.
Run it as `bash <this skill dir>/ourpulse.sh …`.

Base URL: `$OURPULSE_URL`, default `https://ourpulse.click`.
Full API reference: `docs/agents.md` in the OurPulse repo, or `GET $OURPULSE_URL/api/surveys/:id` for the live shape.

## Setup check

Before anything else run `ourpulse.sh check`. Exit 0 means go on, and the line it prints names the account
and the key in use, e.g. `ok: logged in to … as niki@example.com (global)`. Keep that for the draft.
Otherwise run `ourpulse.sh login`: it opens
the browser on an approval page (and prints the link in case the browser did not open), waits up to ten
minutes for the user to sign in with Google and press Approve, then saves the key under `~/.config/ourpulse/`.
While it runs, tell the user in one line to approve in the browser. When it exits 0, continue with the task in
the same turn; nothing needs restarting. The key never appears in the terminal output, and you never need to
see it: do not ask the user to paste a key into chat.

### One account everywhere, or a different one in this folder

A login is either **global** (every folder on this machine) or for **this folder only** (the git root, or
the current directory outside a repository). A folder login wins over the global one inside that folder.
Both are stored under `~/.config/ourpulse/`; nothing is written into the project.

- Nobody is logged in (check exits 3): run plain `ourpulse.sh login`. It saves globally. Do not ask about scope.
- The key was rejected (check exits 4): run plain `ourpulse.sh login`. It renews the key that was rejected.
- Already logged in and the user wants another account ("use my work account", "switch account", "log in
  again"): ask once, "Use it in this folder only, or everywhere on this machine?", then run
  `ourpulse.sh login --local` or `ourpulse.sh login --global`. Skip the question when they already said which.
- `ourpulse.sh logout` forgets the folder login when this folder has one, otherwise the global one;
  `--local` / `--global` pick explicitly.

## The loop

1. **Draft the pulse from the user's ask.** Keep it to 1–5 questions. Prefer `single` for decisions,
   `multi` with `max_picks` for priorities, `agree` for statements people rate (put several in a row: they
   share one screen), `scale` for a numeric 1–N rating, `text` only when free-form matters.

2. **Show the draft and get approval. Always, before creating anything.** Even when the user gave exact
   questions: creating a pulse is visible to other people, so the user confirms the final shape once.
   Present it in this form, then stop and wait for a yes:

   ```
   Pulse: <title>
   Account: <email> (this folder only | global)   (exactly as `check` printed it)
   Opens:  <local date and time, with zone, or "now">
   Closes: <local date and time, with zone>  (<duration>, e.g. "2 hours")
   Access: anyone with the link · pseudonyms · one answer per browser
           (or: Google sign-in · one answer per person [· real names])
   Expected: <n people>  (omit when unknown)

   1. [single]  Which option should we ship?  — A / B / C
   2. [scale 1–5]  How confident are you?  — Not at all … Very
   3. [text]  Anything else?

   Create it?
   ```

   Show times in the **user's** timezone (ask once if you don't know it; never assume UTC). If they change
   anything, show the updated draft again. Do not run `create` until they approve. A reply like "yes",
   "go", "create it" or "ok" is approval; a question or a change is not.

3. **Create it.** Write the JSON to a temp file and run `ourpulse.sh create <file>`.
   ```json
   {
     "title": "Which option should we ship?",
     "closes_at": <unix ms, e.g. now + 2h>,
     "expected": <number of people, if known>,
     "questions": [
       { "type": "single", "prompt": "Pick one", "options": ["A", "B", "C"] },
       { "type": "scale",  "prompt": "How confident are you?", "max": 5, "labels": ["Not at all", "Very"] },
       { "type": "text",   "prompt": "Anything else?" }
     ]
   }
   ```
   Defaults: opens now, closes in 7 days, `"access": "anyone"` (no sign-in, pseudonyms, duplicates blocked
   per browser only). `opens_at` and `closes_at` are exact instants in unix ms. When the user names a
   time ("until Friday 5pm", "open Monday 9 to 10"), convert it in **their** timezone (ask once if you
   don't know it; never assume UTC), e.g. `date -j -f '%Y-%m-%d %H:%M' '2026-10-03 17:00' +%s000` on
   macOS or `date -d '2026-10-03 17:00' +%s000` on Linux. Answers are refused after `closes_at`, and the
   link shows "not open yet" before `opens_at`. Set `"access": "google"` when one answer per person matters (votes, decisions with
   stakes); add `"named": true` on top only when the user wants real names (sign-ups, accountability). Group questions with `"section": "Name"` when the pulse has more than one topic (all questions or none). Reuse one option list across two questions with
   `"option_sets": {"axes": [...]}` and `"option_set": "axes"` to get a map view.

4. **Hand back the links, then offer the invite screen.** In one short message give the user `url` and
   the open/close times (their zone). For a chat post (Teams, Slack, mail) the `url` alone unfurls with
   title, times and QR; attach `qr_png_url` when they want the image itself (`?size=` px, default 512).
   `qr_svg_url` is the vector QR for slides and print. `results_url` is the live results page for a
   projector (no names). On `"access": "google"` mention that respondents sign in with Google and answer once.

   End that same message with: **"Open the invite screen on this machine?"** The invite screen
   (`invite_url`) is a public full-screen page with a big QR, the link and a countdown, made for a TV or
   projector. If they say yes, run `ourpulse.sh invite <id>`: it opens `invite_url` in the default browser
   (`open` on macOS, `xdg-open` on Linux) and prints the URL. If they say no, or the session has no
   browser, just leave the URL with them. Ask once; do not repeat the offer later.

5. **Wait for close.** Either:
   - `ourpulse.sh wait <id> [seconds]` blocks and prints the results when closed, or
   - if the session can't block that long, tell the user the id and how to resume: `ourpulse.sh results <id>`.
   Don't poll faster than every 60 s.

6. **Use the results.** `results` JSON has `response_count`, `expected`, `response_rate`, and
   `per_question` with `counts` (choices), `mean` + `distribution` (scale, agree), or `texts` (text).
   Each entry carries `section` (null when the pulse has none). `raw` rows exist for per-response
   analysis; `name` is a pseudonym on open pulses, a real name on named pulses, `null` otherwise.
   Give the chat summary from "Reports" below, then continue the user's original task with the numbers.
   In a later session, find the pulse with `ourpulse.sh list` (match on title, newest first; ask when
   two fit) before running `results`.

7. **Control it when asked.** `ourpulse.sh pause|resume|close|reset <id>`, `ourpulse.sh reopen <id> [days]`,
   `ourpulse.sh schedule <id> <closes-ms|-> [opens-ms]` to move the window to exact instants.
   "Close it now" means `close`; "extend to Friday 5pm" means `schedule` with the converted close time;
   "let's run it again" means `reset` (wipes answers) or `reopen` (extends by days from now).

8. **Clean up when asked.** `ourpulse.sh delete <id>` removes everything, including raw answers.

## Question types

| type | fields | result |
|---|---|---|
| `single` | `options` or `option_set` | count per option |
| `multi` | `options` or `option_set`, optional `max_picks` | count per option |
| `agree` | optional `max` 2–10 (default 5), optional `labels` (default Fully disagree / Fully agree) | mean + distribution |
| `scale` | optional `max` 2–10 (default 5), optional `labels: [low, high]` | mean + distribution |
| `text` | none | list of strings |

Any type also takes optional `section` (a group heading; all questions or none).

## Reports

Three forms. Pick by what the user asked for; default to the chat summary.

### Chat summary

After `wait`, or for "what did the team say". At most six lines:

```
Sprint 41 retro · closed today 17:30 · 8 of 8 answered
We shipped what we planned       3.9 / 5
I knew what to work on each day  2.6 / 5
Slowed us down most: Unclear specs 4 · Flaky tests 2 · Reviews 1 · On-call 1
Comments (6): most ask for acceptance criteria before sprint start.
Lowest score: "I knew what to work on each day".
```

First line: title, state with the close time in the user's zone, `n of expected answered` (just
`n answered` when `expected` is unset). Then one line per question in pulse order: choices as
`option count`, highest first, zero counts left out; scale and agree as `mean / max` to one decimal;
text as the count and one sentence on what most say. Last line: the one finding that matters for
the user's task. With sections, put the section name on its own line above its questions.

### HTML report, pushed to the pulse

For "write the report", "push a report", "make a report I can share". The report is stored with the
pulse and gets its own link, which only the owner receives.

1. Fetch `get <id>` and `results <id>`. If the pulse is still open, say so and ask whether to report
   on the answers so far.
2. If the pulse has text answers, ask once: **"Include quotes from the comments?"** Comments are
   anonymous, but a teammate may recognise an incident or a way of writing. On no, give themes and
   counts only.
3. Copy `report-template.html` (next to this file) to a temp file and fill it in. It holds the outline
   and every class to use: headline and facts, key numbers, one chart per question, comment themes,
   proposed actions. Write the body only. Scripts, forms and images from other sites do not work on
   the served page; charts are the template's HTML bars. Write dates and times as text in the user's
   timezone.
4. Run `ourpulse.sh report-preview <file>`. It opens the report in the browser as it will look and
   prints the preview path.
5. Show this and wait for a yes. Pushing is visible to whoever gets the link, so always ask:

   ```
   Report: <pulse title>
   Account: <email> (as `check` printed it)
   Contents: 3 key numbers · 4 charts · 5 comment themes, 7 quotes · 3 actions
   Preview: open in your browser (<preview path>)
   Sharing: only you get the link. Anyone you give it to can read the report without signing in.

   Push it?
   ```

   If they ask for changes, edit the file, preview again and show the block again.
6. Run `ourpulse.sh report <id> <file>` and hand back `report_url`. Pushing again later replaces the
   report and keeps the link. `ourpulse.sh report-delete <id>` removes it; the link stops working.

When the user wants a file in their project instead ("write it up in docs/retro.md"), write Markdown
with the same outline and do not push anything.

### Short post

For "three lines for Slack", "something for the channel". Plain text, no headings: response rate,
the top result, the next step. Add `report_url` when a report was pushed, otherwise `results_url`.

### Rules for every report

- Numbers come from `results` as returned. Never round a count, never fill in a missing answer.
- Quote comments exactly as written. Shorten a long one only by cutting, marked with "…".
- Never attach a pseudonym or name to an answer, unless the pulse is `named` and the user asks for it.
- Never say who has not answered. OurPulse does not know; report only how many.
- No subgroup smaller than three people ("the two who picked Reviews said …"). Fold it into the total.
- Every proposed action names the result it comes from. No action without one.
- If the pulse is still open, say so in the first line and call the numbers "so far".
- For a projector, give `results_url`. For a spreadsheet, `ourpulse.sh csv <id>`.

## Rules

- One pulse per question set. Don't create several pulses for one ask.
- Never create a pulse the user has not approved in the form above, and never create a second one for the
  same ask unless they say so.
- Never fabricate results. If the pulse is still open, say so and report the count so far.
- Never push a report the user has not approved in the form above.
- Results pages are for the owner. Share the pulse `url`, not the results URL, with respondents.
