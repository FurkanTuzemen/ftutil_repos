# CLAUDE.md

Guidance for working in this repo. See `README.md` for the full intent.

## What this repo is

Reproducible bootstrap/automation scripts to set up tools (OpenSSH, Docker, Git, …) **identically across many machines**: Windows/Linux PCs and a fleet of Raspberry Pis.

## Platform strategy (decisions)

- **Linux** — either **Docker** (for tools that can run containerized) **or** a host-level **`bootstrap.sh`** (for things Docker can't install into itself: the SSH daemon, the Docker engine, Git, system packages). Reproducibility on the Pi fleet comes from `git clone` + running the script identically on each device.
- **Windows** — native **PowerShell only, no Docker**. Prefer **winget** for installs.

## Conventions when adding or editing a project

- **Layout:** one folder per tool → `<project>/{linux,windows}/`. Shared helpers in `lib/`. Scaffold new projects from `_template/`.
- **Idempotent:** every script checks-before-acting and is safe to re-run.
- **Bash:** start with `set -euo pipefail`; source `lib/linux/common.sh` for `log` / `require_root` / `command_exists` / `detect_distro`. Keep the executable bit with `git update-index --chmod=+x <script>.sh` (the repo is authored on Windows, which doesn't track it).
- **PowerShell:** start with `#Requires -Version 5.1` + `#Requires -RunAsAdministrator`; set `$ErrorActionPreference = 'Stop'`; import `lib/windows/Common.psm1` for `Write-Log` / `Test-CommandExists` / `Assert-IsAdmin`. **Must run on both Windows PowerShell 5.1 and PowerShell 7+ (`pwsh`).**
- **Run manual:** every project ships a `RUNNING.md` **next to its scripts** (in `linux/` and `windows/`) with exact run steps — the Windows one includes PowerShell 7 instructions.
- **No secrets** committed; scripts must be safe to run unattended.
- `.gitattributes` forces **LF** on `*.sh` and **CRLF** on `*.ps1`.

## Verifying changes

- Bash syntax: `bash -n <script>.sh`.
- PowerShell syntax: parse-check with
  `[System.Management.Automation.Language.Parser]::ParseFile($path,[ref]$null,[ref]$errs)`.
  This machine has `pwsh` 7.x — prefer running checks under it to confirm PS7 compatibility.

## Commit / PR

- Clear, imperative commit subjects. End commit messages with the `Co-Authored-By` trailer.
- Commit and push only when the user asks.
