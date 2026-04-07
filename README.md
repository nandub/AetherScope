# AetherScope

AetherScope is a Windows PowerShell 5.1–first celestial tracking and antenna-pointing project.

## Goals
- Windows PowerShell 5.1 compatibility
- comment-based help on public functions
- `SupportsShouldProcess` where appropriate
- clean packaging
- runtime host validation, not packaging-only review

## Intended capabilities
AetherScope is intended to support or retain support for:
- Sun, Moon, and ISS position calculations
- visibility windows
- ISS radio visibility / planning
- fixed-star tracking
- staged precision star calculations
- GPS / NMEA coordinate ingestion
- rotator control for Hamlib / GS-232 style backends
- in-place console dashboard views

## Expected repository layout

```text
AetherScope/
|-- AGENTS.md
|-- CHANGELOG.md
|-- LICENSE
|-- README.md
|-- Source/
|   |-- AetherScope.ps1
|   |-- README.md
|   `-- EXAMPLES.md
|-- Tests/
|-- scripts/
|   `-- Build-AetherScope.ps1
|-- dist/
|-- docs/
|   |-- current-status.md
|   |-- decisions.md
|   `-- known-issues.md
`-- handoff/
    `-- latest-chat-handoff.md
```

## Current workspace caveat
When this handoff package was generated, the expected `Source/` and `Tests/` content was **not present in the workspace snapshot available to Codex CLI**. The documentation in this repository therefore records the intended shape and current assumptions, but future work should verify the actual source tree before making code changes.

## Build
Use the repository build script:

```powershell
.\scripts\Build-AetherScope.ps1 -Verbose
.\scripts\Build-AetherScope.ps1 -NewVersion '0.1.0' -WhatIf
```

The build script is expected to produce a clean zip in `dist/`.

## Coding requirements
- Target Windows PowerShell 5.1 only.
- Use approved `Verb-Noun` naming where practical.
- Use `[CmdletBinding(SupportsShouldProcess = $true)]` for state-changing functions.
- Include comment-based help on public functions.
- Favor `Write-Verbose` and `Write-Error`.
- Avoid `Invoke-Expression`.
- Do not override TLS validation.
- Do not store plaintext credentials.

## Next recommended actions
1. Restore or verify the actual `Source/AetherScope.ps1` and related source files.
2. Run the script under **Windows PowerShell 5.1** and capture parse/runtime issues.
3. Consolidate historical patch layers into a single clean codebase.
4. Add or restore smoke tests under `Tests/`.
5. Ensure the build script packages only production-ready artifacts.
