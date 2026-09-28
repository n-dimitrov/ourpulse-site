# OurPulse skill for Claude Code

Ask a group of humans a question from Claude Code, hand them a link and a QR code, and continue with their answers as data. Runs against https://pulse.1153nikidimitrov.workers.dev.

## Install

Inside Claude Code, once:

```
/plugin marketplace add n-dimitrov/ourpulse-skill
/plugin install ourpulse@ourpulse
```

Or with the community skills CLI, globally:

```
npx skills add n-dimitrov/ourpulse-skill -g
```

## Set up a key

1. Sign in at https://pulse.1153nikidimitrov.workers.dev/me/keys and create a key. The page has a "Copy export line" button.
2. Put `export OURPULSE_API_KEY=pk_...` in your shell profile, or add it to the `env` block of `~/.claude/settings.json`.
3. Restart Claude Code.

If the key is missing the skill tells you these steps itself.

## Use

Say "ask the team which day works for the demo, close in 2 hours", or `/ourpulse`. The skill drafts the questions, creates the pulse, gives you the link, QR, and a live results page, waits for the close, and summarises the numbers.

Question types: single, multi, agree, scale, text, with optional sections. Full API reference lives in the OurPulse repo's `docs/agents.md`.

This repo is generated from the private OurPulse repo. Open issues here.
