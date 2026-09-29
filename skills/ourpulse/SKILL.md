---
name: ourpulse
description: Ask a group of humans a question with an OurPulse survey (a "pulse") and continue with their answers. Use when the user says "ask the team", "run a quick poll/survey/retro/check-in", "get votes on", or wants a decision from several people. Shows the draft (questions, open and close times) for approval, creates the pulse, hands back the link and offers the full-screen invite screen, waits for it to close, and returns the results as data.
---

# OurPulse: tiny surveys ("pulses") for teams and agents

OurPulse is a REST API. The helper `ourpulse.sh` next to this file wraps the calls and handles the key.
Run it as `bash <this skill dir>/ourpulse.sh …`.

Base URL: `$OURPULSE_URL`, default `https://pulse.1153nikidimitrov.workers.dev`.
Full API reference: `docs/agents.md` in the OurPulse repo, or `GET $OURPULSE_URL/api/surveys/:id` for the live shape.

## Setup check

Before anything else run `ourpulse.sh check`. Exit 0 means go on. Otherwise run `ourpulse.sh login`: it opens
the browser on an approval page (and prints the link in case the browser did not open), waits up to ten
minutes for the user to sign in with Google and press Approve, then saves the key under `~/.config/ourpulse/`.
While it runs, tell the user in one line to approve in the browser. When it exits 0, continue with the task in
the same turn; nothing needs restarting. The key never appears in the terminal output, and you never need to
see it: do not ask the user to paste a key into chat.

## The loop

1. **Draft the pulse from the user's ask.** Keep it to 1–5 questions. Prefer `single` for decisions,
   `multi` with `max_picks` for priorities, `agree` for statements people rate (put several in a row: they
   share one screen), `scale` for a numeric 1–N rating, `text` only when free-form matters.

2. **Show the draft and get approval. Always, before creating anything.** Even when the user gave exact
   questions: creating a pulse is visible to other people, so the user confirms the final shape once.
   Present it in this form, then stop and wait for a yes:

   ```
   Pulse: <title>
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
   `per_question` with `counts` (choices), `mean` + `distribution` (scale), or `texts` (text). Each entry
   carries `section` (null when the pulse has none); summarise by section when it is set.
   Summarise in two or three lines, then continue the user's original task with the numbers.
   `raw` rows exist for per-response analysis; `name` is a pseudonym on open pulses, a real name on named
   pulses, `null` otherwise.

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

## Rules

- One pulse per question set. Don't create several pulses for one ask.
- Never create a pulse the user has not approved in the form above, and never create a second one for the
  same ask unless they say so.
- Never fabricate results. If the pulse is still open, say so and report the count so far.
- Results pages are for the owner. Share the pulse `url`, not the results URL, with respondents.
