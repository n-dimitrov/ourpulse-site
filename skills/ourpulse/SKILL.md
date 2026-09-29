---
name: ourpulse
description: Ask a group of humans a question with an OurPulse survey (a "pulse") and continue with their answers. Use when the user says "ask the team", "run a quick poll/survey/retro/check-in", "get votes on", or wants a decision from several people. Creates the pulse, hands back a link and QR, waits for it to close, and returns the results as data.
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
   Confirm the draft with the user in one message unless they already gave exact questions.

2. **Create it.** Write the JSON to a temp file and run `ourpulse.sh create <file>`.
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
   per browser only). Set `"access": "google"` when one answer per person matters (votes, decisions with
   stakes); add `"named": true` on top only when the user wants real names (sign-ups, accountability). Group questions with `"section": "Name"` when the pulse has more than one topic (all questions or none). Reuse one option list across two questions with
   `"option_sets": {"axes": [...]}` and `"option_set": "axes"` to get a map view.

3. **Hand back the links.** Give the user `url` and `qr_svg_url` from the response, plus the close time, and
   `results_url` for a full-screen live results page they can put on a projector or share (no sign-in, no names).
   Tell them respondents sign in with Google and can answer once.

4. **Wait for close.** Either:
   - `ourpulse.sh wait <id> [seconds]` blocks and prints the results when closed, or
   - if the session can't block that long, tell the user the id and how to resume: `ourpulse.sh results <id>`.
   Don't poll faster than every 60 s.

5. **Use the results.** `results` JSON has `response_count`, `expected`, `response_rate`, and
   `per_question` with `counts` (choices), `mean` + `distribution` (scale), or `texts` (text). Each entry
   carries `section` (null when the pulse has none); summarise by section when it is set.
   Summarise in two or three lines, then continue the user's original task with the numbers.
   `raw` rows exist for per-response analysis; `name` is a pseudonym on open pulses, a real name on named
   pulses, `null` otherwise.

6. **Control it when asked.** `ourpulse.sh pause|resume|close|reset <id>`, `ourpulse.sh reopen <id> [days]`.
   "Close it now" means `close`; "let's run it again" means `reset` (wipes answers) or `reopen` (extends).

7. **Clean up when asked.** `ourpulse.sh delete <id>` removes everything, including raw answers.

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
- Never fabricate results. If the pulse is still open, say so and report the count so far.
- Results pages are for the owner. Share the pulse `url`, not the results URL, with respondents.
