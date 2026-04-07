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
The expected source files are now present in this workspace, including `Source/AetherScope.ps1`, `Source/AetherScope.psm1`, `Source/AetherScope.psd1`, `Source/AetherScopePrecisionHelper.cs`, `scripts/Build-AetherScope.ps1`, `scripts/Build-AetherScopePrecisionHelper.ps1`, and `Tests/AetherScope.Smoke.Tests.ps1`.

## Recommended next steps
1. Perform focused runtime validation of the public tracking, visibility, GPS/NMEA, and rotator commands.
2. Decide whether to fix the local `PSModulePath` / OneDrive-backed module-loading issue so `Pester` imports cleanly without environment overrides.
3. Keep `Set-AetherScopeRotatorPark` as the public parking command and maintain approved-verb naming across new additions.
4. Keep the build and packaging path deterministic.
5. Close sessions that imported AetherScope before rebuilding `Source/AetherScopePrecisionHelper.dll`.
