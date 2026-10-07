#!/bin/sh
set -eu
#
# Install or upgrade the OurPulse skill for your coding agent. Copies the
# skill folder into the agent's skills directory, where it is found on the
# next session. No plugin, no marketplace, no Node.
#
# One-liner (asks which agent when run in a terminal; Claude Code otherwise):
#   curl -LsSf https://ourpulse.click/install.sh | sh
#
# Pick the agent up front:
#   curl -LsSf https://ourpulse.click/install.sh | sh -s -- --agent codex
#
#   agent      global                       in a project (--local)
#   claude     ~/.claude/skills             .claude/skills          Claude Code (default)
#   agents     ~/.agents/skills             .agents/skills          shared: Codex, Gemini, Copilot, Cursor, OpenCode
#   codex      ~/.agents/skills             .agents/skills          ChatGPT & Codex
#   gemini     ~/.gemini/skills             .gemini/skills          Gemini CLI
#   copilot    ~/.copilot/skills            .github/skills          GitHub Copilot, VS Code
#   cursor     ~/.cursor/skills             .cursor/skills          Cursor
#   opencode   ~/.config/opencode/skills    .opencode/skills        OpenCode
#
# For one project only (commit it and the team has it):
#   curl -LsSf https://ourpulse.click/install.sh | sh -s -- --local
#
# Any folder:
#   curl -LsSf https://ourpulse.click/install.sh | sh -s -- --dir ~/somewhere/skills
#
# Environment: OURPULSE_SKILL_DIR (same as --dir), OURPULSE_REF (branch or tag).
# Re-running it upgrades. Plain POSIX sh on purpose: `curl | sh` runs
# under dash on Debian/Ubuntu.

REPO="n-dimitrov/ourpulse-site"
REF="${OURPULSE_REF:-main}"

fail() {
  echo "$*" >&2
  exit 1
}

# --- options ---------------------------------------------------------
AGENT=""; LOCAL=0; DIR="${OURPULSE_SKILL_DIR:-}"
while [ $# -gt 0 ]; do
  case "$1" in
    --agent) [ $# -ge 2 ] || fail "--agent needs a name (claude, agents, codex, gemini, copilot, cursor, opencode)"; AGENT="$2"; shift ;;
    --agent=*) AGENT="${1#--agent=}" ;;
    --local) LOCAL=1 ;;
    --dir) [ $# -ge 2 ] || fail "--dir needs a path"; DIR="$2"; shift ;;
    --dir=*) DIR="${1#--dir=}" ;;
    -h|--help) sed -n '3,30p' "$0" 2>/dev/null | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) fail "Unknown option: $1 (try --agent, --local, --dir)" ;;
  esac
  shift
done

# The skills folder for an agent: global, or inside the current project.
skills_dir() {
  case "$1" in
    claude)   [ "$LOCAL" = 1 ] && echo "$PWD/.claude/skills"   || echo "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/skills" ;;
    agents|codex) [ "$LOCAL" = 1 ] && echo "$PWD/.agents/skills" || echo "$HOME/.agents/skills" ;;
    gemini)   [ "$LOCAL" = 1 ] && echo "$PWD/.gemini/skills"   || echo "$HOME/.gemini/skills" ;;
    copilot)  [ "$LOCAL" = 1 ] && echo "$PWD/.github/skills"   || echo "$HOME/.copilot/skills" ;;
    cursor)   [ "$LOCAL" = 1 ] && echo "$PWD/.cursor/skills"   || echo "$HOME/.cursor/skills" ;;
    opencode) [ "$LOCAL" = 1 ] && echo "$PWD/.opencode/skills" || echo "${XDG_CONFIG_HOME:-$HOME/.config}/opencode/skills" ;;
    *) return 1 ;;
  esac
}

# No agent and no folder given: ask, when there is a terminal to ask on.
# Piped from curl, stdin is the script itself, so the answer comes from /dev/tty.
if [ -z "$DIR" ] && [ -z "$AGENT" ]; then
  if [ -t 1 ] && { : < /dev/tty; } 2>/dev/null; then
    echo "Where should the OurPulse skill go?"
    echo "  1) Claude Code                 $(LOCAL=$LOCAL skills_dir claude)"
    echo "  2) Shared .agents folder       $(LOCAL=$LOCAL skills_dir agents)   (Codex, Gemini CLI, Copilot, Cursor, OpenCode)"
    echo "  3) Gemini CLI                  $(LOCAL=$LOCAL skills_dir gemini)"
    echo "  4) GitHub Copilot / VS Code    $(LOCAL=$LOCAL skills_dir copilot)"
    echo "  5) Cursor                      $(LOCAL=$LOCAL skills_dir cursor)"
    echo "  6) OpenCode                    $(LOCAL=$LOCAL skills_dir opencode)"
    echo "  7) Another folder"
    printf "Choice [1]: "
    read -r choice < /dev/tty || choice=""
    case "${choice:-1}" in
      1) AGENT=claude ;; 2) AGENT=agents ;; 3) AGENT=gemini ;; 4) AGENT=copilot ;; 5) AGENT=cursor ;; 6) AGENT=opencode ;;
      7) printf "Skills folder: "; read -r DIR < /dev/tty; [ -n "$DIR" ] || fail "No folder given." ;;
      *) fail "Not an option: $choice" ;;
    esac
  else
    AGENT=claude
  fi
fi
if [ -z "$DIR" ]; then
  DIR="$(skills_dir "$AGENT")" || fail "Unknown agent: $AGENT (claude, agents, codex, gemini, copilot, cursor, opencode)"
fi
case "$DIR" in "~"*) DIR="$HOME${DIR#\~}" ;; esac
DEST="$DIR/ourpulse"

command -v curl >/dev/null 2>&1 || fail "curl is required to download the skill."
command -v tar >/dev/null 2>&1 || fail "tar is required to unpack the skill."

# --- download --------------------------------------------------------
TMP="$(mktemp -d 2>/dev/null || mktemp -d -t ourpulse)"
trap 'rm -rf "$TMP"' EXIT INT TERM

echo "Downloading the OurPulse skill ($REF)..."
curl -fsSL "https://github.com/$REPO/archive/refs/heads/$REF.tar.gz" -o "$TMP/src.tgz" ||
  curl -fsSL "https://github.com/$REPO/archive/refs/tags/$REF.tar.gz" -o "$TMP/src.tgz" ||
  fail "Couldn't download https://github.com/$REPO ($REF)."
tar -xzf "$TMP/src.tgz" -C "$TMP"

SRC="$(ls -d "$TMP"/*/skills/ourpulse 2>/dev/null | head -n1 || true)"
[ -n "$SRC" ] && [ -f "$SRC/SKILL.md" ] || fail "The download has no skills/ourpulse/SKILL.md; is $REF right?"
VERSION="$(sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' "$TMP"/*/.claude-plugin/plugin.json 2>/dev/null | head -n1 || true)"

# --- install ---------------------------------------------------------
# Replace the folder wholesale, but only one that is ours, so a typo in
# --dir cannot wipe something else.
if [ -d "$DEST" ]; then
  [ -f "$DEST/SKILL.md" ] || fail "$DEST exists and is not an OurPulse skill folder. Remove it or pick another --dir."
  rm -rf "$DEST"
fi
mkdir -p "$DEST"
cp -R "$SRC"/. "$DEST"/
chmod +x "$DEST/ourpulse.sh"

echo "Installed OurPulse skill${VERSION:+ $VERSION} to $DEST"

# Both the Claude Code plugin and the copied skill would answer to "ask the team"; say so once.
if [ "${AGENT:-}" = claude ] && grep -rqs '"ourpulse@ourpulse"' "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins" 2>/dev/null; then
  echo "Note: the ourpulse plugin is installed too. Remove one of them: /plugin uninstall ourpulse@ourpulse, or rm -r $DEST"
fi

cat <<EOF

Next: open a new session of your agent and say "ask the team ...".
The first time, your browser opens: sign in with Google and press Approve.
EOF
