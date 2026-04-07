# Latest Chat Handoff

## Context
This handoff package was created to provide durable repository context for future Codex CLI work on AetherScope.

## What was requested
Create or refresh the following repository-level durable context files:
- `AGENTS.md`
- `CHANGELOG.md`
- `LICENSE`
- `README.md`
- `docs/current-status.md`
- `docs/decisions.md`
- `docs/known-issues.md`
- `handoff/latest-chat-handoff.md`

Also create a zip containing these files.

## Important project constraints
- Windows PowerShell 5.1 only
- comment-based help on public functions
- `SupportsShouldProcess` where appropriate
- clean packaging
- avoid PowerShell 6/7-only syntax
- avoid insecure practices such as `Invoke-Expression`, TLS override, or embedded plaintext credentials

## Workflow assumptions recorded
- `scripts/Build-AetherScope.ps1` is the build script
- `Source/` is intended to contain:
  - `AetherScope.ps1`
  - `README.md`
  - `EXAMPLES.md`
- `Tests/` contains smoke tests
- `dist/` is the release output folder

## What was actually present in this workspace
The expected source files were not visible in the Codex workspace snapshot during this task. Because of that, this package is a **documentation and handoff baseline**, not a verification of the current functional code.

## Recommended next steps
1. Verify the actual repository content.
2. Restore or locate `Source/AetherScope.ps1` and related files if missing.
3. Run the script under Windows PowerShell 5.1.
4. Repair parse/runtime defects before attempting deeper refactors.
5. Keep the build and packaging path deterministic.
