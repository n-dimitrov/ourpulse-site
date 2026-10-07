# OurPulse

Tiny pulses for teams and agents. This repo holds everything public about [OurPulse](https://ourpulse.click):

- `docs/`: the landing page and the plugin catalog, served by GitHub Pages at https://ourpulse.click
- `skills/ourpulse/`: the Claude Code skill
- `.claude-plugin/`: the plugin manifest and the marketplace for installs by repo name

## The skill

Ask a group of humans a question from Claude Code, hand them a link and a QR code, and continue with their answers as data. Runs against https://ourpulse.click.

### Install

One line. It asks which agent you use and copies the skill into that agent's skills folder; re-run it to upgrade.

```
curl -LsSf https://ourpulse.click/install.sh | sh          # Mac, Linux
irm https://ourpulse.click/install.ps1 | iex               # Windows (PowerShell)
```

| agent | global | in a project |
|---|---|---|
| `claude` (default) | `~/.claude/skills` | `.claude/skills` |
| `agents` — shared by Codex, Gemini CLI, Copilot, Cursor, OpenCode | `~/.agents/skills` | `.agents/skills` |
| `codex` | `~/.agents/skills` | `.agents/skills` |
| `gemini` | `~/.gemini/skills` | `.gemini/skills` |
| `copilot` (GitHub Copilot, VS Code) | `~/.copilot/skills` | `.github/skills` |
| `cursor` | `~/.cursor/skills` | `.cursor/skills` |
| `opencode` | `~/.config/opencode/skills` | `.opencode/skills` |

Skip the question with `--agent codex`, install into the current project with `--local` (commit it and the team has it),
or name any folder with `--dir`: `curl -LsSf https://ourpulse.click/install.sh | sh -s -- --agent codex --local`.
On Windows: `& ([scriptblock]::Create((irm https://ourpulse.click/install.ps1))) -Agent codex -Local`.
Without a terminal (CI, piped input) it installs for Claude Code.

Or as a plugin, inside Claude Code, once:

```
/plugin marketplace add https://ourpulse.click/marketplace.json
/plugin install ourpulse@ourpulse
```

`/plugin marketplace add n-dimitrov/ourpulse-site` works too. Or with the community skills CLI, globally:

```
npx skills add n-dimitrov/ourpulse-site -g
```

### Sign in

Nothing to configure. The first time you say "ask the team …" the skill runs `ourpulse.sh login`, which opens
the browser on an approval page. Sign in with Google, press Approve, and the key is saved to
`~/.config/ourpulse/`. Revoke it any time at https://ourpulse.click/me/keys.
`ourpulse.sh logout` forgets the local copy. Setting `OURPULSE_API_KEY` overrides the saved key, for CI.

To use a different account in one project, say "use another account in this folder" (or run
`ourpulse.sh login --local` there). That login applies to that folder only and wins over the global one.
The draft of every pulse shows which account will create it. All keys stay under `~/.config/ourpulse/`;
nothing is written into the project folder.

### Use

Say "ask the team which day works for the demo, close in 2 hours", or `/ourpulse`. The skill drafts the questions, creates the pulse, gives you the link, QR, and a live results page, waits for the close, and summarises the numbers.

Question types: single, multi, agree, scale, text, with optional sections.

Afterwards, say "write the report and push it". The skill writes an HTML report from the results (key numbers, a chart per question, comment themes, proposed actions), asks whether to include quotes, opens a preview, and pushes it to the pulse once you approve. You get a link to share; nobody else does.

## Maintaining

- The skill and the manifests are edited here. Bump `version` in `.claude-plugin/plugin.json` on every change, or installed copies do not update.
- There are two catalogs with the same content: `.claude-plugin/marketplace.json` (relative source, for installs by repo name) and `docs/marketplace.json` (HTTPS git URL, for installs by URL; an explicit `https://` source clones without a GitHub SSH key). Change both together.
- `skills/ourpulse/report-preview.html` copies the report styles from the app (`src/lib/reports.ts`), so the local preview matches the served page. Change both together.
- `docs/index.html` copies its colours and base styles from the app. The app itself is a Cloudflare Worker in a private repo; on `ourpulse.click` it answers `/s`, `/r`, `/me`, `/auth`, `/api` and `/cli`, and every other path is served from `docs/`.

Open issues here.
