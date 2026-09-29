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

## Sign in

Nothing to configure. The first time you say "ask the team …" the skill runs `ourpulse.sh login`, which opens
the browser on an approval page. Sign in with Google, press Approve, and the key is saved to
`~/.config/ourpulse/`. Revoke it any time at https://pulse.1153nikidimitrov.workers.dev/me/keys.
`ourpulse.sh logout` forgets the local copy. Setting `OURPULSE_API_KEY` overrides the saved key, for CI.

## Use

Say "ask the team which day works for the demo, close in 2 hours", or `/ourpulse`. The skill drafts the questions, creates the pulse, gives you the link, QR, and a live results page, waits for the close, and summarises the numbers.

Question types: single, multi, agree, scale, text, with optional sections. Full API reference lives in the OurPulse repo's `docs/agents.md`.

This repo is generated from the private OurPulse repo. Open issues here.
