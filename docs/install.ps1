#Requires -Version 5.1
<#
.SYNOPSIS
  Install or upgrade the OurPulse skill for your coding agent on Windows.

.DESCRIPTION
  Copies the skill folder into the agent's skills directory, where it is
  found on the next session. No plugin, no marketplace, no Node.

  One-liner (asks which agent; Claude Code when it cannot ask):
    irm https://ourpulse.click/install.ps1 | iex

  Pick the agent up front, or a project-local install, or any folder:
    & ([scriptblock]::Create((irm https://ourpulse.click/install.ps1))) -Agent codex
    & ([scriptblock]::Create((irm https://ourpulse.click/install.ps1))) -Local
    & ([scriptblock]::Create((irm https://ourpulse.click/install.ps1))) -Dir D:\skills

    agent      global                        in a project (-Local)
    claude     ~\.claude\skills              .claude\skills          Claude Code (default)
    agents     ~\.agents\skills              .agents\skills          shared: Codex, Gemini, Copilot, Cursor, OpenCode
    codex      ~\.agents\skills              .agents\skills          ChatGPT & Codex
    gemini     ~\.gemini\skills              .gemini\skills          Gemini CLI
    copilot    ~\.copilot\skills             .github\skills          GitHub Copilot, VS Code
    cursor     ~\.cursor\skills              .cursor\skills          Cursor
    opencode   ~\.config\opencode\skills     .opencode\skills        OpenCode

  Environment: OURPULSE_SKILL_DIR (same as -Dir), OURPULSE_REF (branch or tag).
  Re-running the installer upgrades.

.PARAMETER Agent
  claude, agents, codex, gemini, copilot, cursor or opencode.
.PARAMETER Local
  Install into the agent's skills folder inside the current directory.
.PARAMETER Dir
  A skills folder of your own; the skill goes into <Dir>\ourpulse.
#>
param(
    [string]$Agent,
    [switch]$Local,
    [string]$Dir
)

# Everything runs in a child scope and fails by throwing: under
# `irm | iex` this code executes in the user's own session, where a stray
# `exit` would close their window and a leaked $ErrorActionPreference
# would outlive the install.
& {
    param([string]$Agent, [bool]$Local, [string]$Dir)

    $ErrorActionPreference = 'Stop'
    $repo = 'n-dimitrov/ourpulse-site'
    $ref = if ($env:OURPULSE_REF) { $env:OURPULSE_REF } else { 'main' }
    if (-not $Dir -and $env:OURPULSE_SKILL_DIR) { $Dir = $env:OURPULSE_SKILL_DIR }

    # Windows PowerShell 5.1 can still default to TLS 1.0, which GitHub refuses.
    [Net.ServicePointManager]::SecurityProtocol =
        [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

    $claudeDir = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $HOME '.claude' }
    $here = (Get-Location).Path
    function SkillsDir([string]$a) {
        switch ($a) {
            'claude'   { if ($Local) { Join-Path $here '.claude\skills' }   else { Join-Path $claudeDir 'skills' } }
            'agents'   { if ($Local) { Join-Path $here '.agents\skills' }   else { Join-Path $HOME '.agents\skills' } }
            'codex'    { if ($Local) { Join-Path $here '.agents\skills' }   else { Join-Path $HOME '.agents\skills' } }
            'gemini'   { if ($Local) { Join-Path $here '.gemini\skills' }   else { Join-Path $HOME '.gemini\skills' } }
            'copilot'  { if ($Local) { Join-Path $here '.github\skills' }   else { Join-Path $HOME '.copilot\skills' } }
            'cursor'   { if ($Local) { Join-Path $here '.cursor\skills' }   else { Join-Path $HOME '.cursor\skills' } }
            'opencode' { if ($Local) { Join-Path $here '.opencode\skills' } else { Join-Path $HOME '.config\opencode\skills' } }
            default    { throw "Unknown agent: $a (claude, agents, codex, gemini, copilot, cursor, opencode)" }
        }
    }

    # --- where to put it ---------------------------------------------
    # No agent and no folder given: ask, when there is a console to ask on.
    if (-not $Dir -and -not $Agent) {
        $canAsk = $Host.Name -ne 'ServerRemoteHost' -and -not [Console]::IsInputRedirected
        if ($canAsk) {
            Write-Host 'Where should the OurPulse skill go?'
            Write-Host ("  1) Claude Code                 {0}" -f (SkillsDir claude))
            Write-Host ("  2) Shared .agents folder       {0}   (Codex, Gemini CLI, Copilot, Cursor, OpenCode)" -f (SkillsDir agents))
            Write-Host ("  3) Gemini CLI                  {0}" -f (SkillsDir gemini))
            Write-Host ("  4) GitHub Copilot / VS Code    {0}" -f (SkillsDir copilot))
            Write-Host ("  5) Cursor                      {0}" -f (SkillsDir cursor))
            Write-Host ("  6) OpenCode                    {0}" -f (SkillsDir opencode))
            Write-Host '  7) Another folder'
            $choice = Read-Host 'Choice [1]'
            switch ($choice.Trim()) {
                ''  { $Agent = 'claude' }
                '1' { $Agent = 'claude' }
                '2' { $Agent = 'agents' }
                '3' { $Agent = 'gemini' }
                '4' { $Agent = 'copilot' }
                '5' { $Agent = 'cursor' }
                '6' { $Agent = 'opencode' }
                '7' { $Dir = (Read-Host 'Skills folder').Trim(); if (-not $Dir) { throw 'No folder given.' } }
                default { throw "Not an option: $choice" }
            }
        } else {
            $Agent = 'claude'
        }
    }
    if (-not $Dir) { $Dir = SkillsDir $Agent }
    if ($Dir.StartsWith('~')) { $Dir = $HOME + $Dir.Substring(1) }
    $dest = Join-Path $Dir 'ourpulse'

    # --- download ----------------------------------------------------
    $tmp = Join-Path ([IO.Path]::GetTempPath()) ("ourpulse-" + [IO.Path]::GetRandomFileName())
    New-Item -ItemType Directory -Path $tmp | Out-Null
    try {
        Write-Host "Downloading the OurPulse skill ($ref)..."
        $zip = Join-Path $tmp 'src.zip'
        try {
            Invoke-WebRequest -UseBasicParsing "https://github.com/$repo/archive/refs/heads/$ref.zip" -OutFile $zip
        } catch {
            try { Invoke-WebRequest -UseBasicParsing "https://github.com/$repo/archive/refs/tags/$ref.zip" -OutFile $zip }
            catch { throw "Couldn't download https://github.com/$repo ($ref)." }
        }
        Expand-Archive -Path $zip -DestinationPath $tmp -Force

        $src = Get-ChildItem -Path $tmp -Directory | ForEach-Object { Join-Path $_.FullName 'skills\ourpulse' } |
               Where-Object { Test-Path (Join-Path $_ 'SKILL.md') } | Select-Object -First 1
        if (-not $src) { throw "The download has no skills\ourpulse\SKILL.md; is $ref right?" }
        $version = $null
        $manifest = Get-ChildItem -Path $tmp -Directory | ForEach-Object { Join-Path $_.FullName '.claude-plugin\plugin.json' } |
                    Where-Object { Test-Path $_ } | Select-Object -First 1
        if ($manifest) { try { $version = (Get-Content $manifest -Raw | ConvertFrom-Json).version } catch {} }

        # --- install -------------------------------------------------
        # Replace the folder wholesale, but only one that is ours, so a typo
        # in -Dir cannot wipe something else.
        if (Test-Path $dest) {
            if (-not (Test-Path (Join-Path $dest 'SKILL.md'))) {
                throw "$dest exists and is not an OurPulse skill folder. Remove it or pick another -Dir."
            }
            Remove-Item -Recurse -Force $dest
        }
        New-Item -ItemType Directory -Path $dest -Force | Out-Null
        Copy-Item -Path (Join-Path $src '*') -Destination $dest -Recurse -Force

        $v = if ($version) { " $version" } else { '' }
        Write-Host "Installed OurPulse skill$v to $dest"
    } finally {
        Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
    }

    # Both the Claude Code plugin and the copied skill would answer to "ask the team"; say so once.
    $plugins = Join-Path $claudeDir 'plugins'
    if ($Agent -eq 'claude' -and (Test-Path $plugins) -and
        (Get-ChildItem -Path $plugins -Recurse -Filter '*.json' -ErrorAction SilentlyContinue |
            Select-String -SimpleMatch '"ourpulse@ourpulse"' -Quiet)) {
        Write-Host "Note: the ourpulse plugin is installed too. Remove one of them: /plugin uninstall ourpulse@ourpulse, or delete $dest"
    }

    Write-Host ''
    Write-Host 'Next: open a new session of your agent and say "ask the team ...".'
    Write-Host 'The first time, your browser opens: sign in with Google and press Approve.'
} -Agent $Agent -Local:$Local.IsPresent -Dir $Dir
