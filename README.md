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

## Current state
The expected `Source/`, `scripts/`, and `Tests/` content is present in this workspace.

Recent validation in Windows PowerShell 5.1 confirmed:
- `.\scripts\Build-AetherScope.ps1` produces `dist\AetherScope-1.0.3.zip`
- `.\scripts\Build-AetherScopePrecisionHelper.ps1` rebuilds the precision helper DLL
- `Tests\AetherScope.Smoke.Tests.ps1` passes when `Pester 3.4.0` is loaded from non-cloud module paths

The main remaining gap is broader interactive runtime validation of the public command surface.

## Build
Use the repository build script:

```powershell
.\scripts\Build-AetherScope.ps1 -Verbose
.\scripts\Build-AetherScope.ps1 -NewVersion '0.1.0' -WhatIf
```

The build script is expected to produce a clean zip in `dist/`.

To rebuild the precision helper:

```powershell
.\scripts\Build-AetherScopePrecisionHelper.ps1 -Verbose
```

For new rotator parking automation, prefer the approved-verb command:

```powershell
Set-AetherScopeRotatorPark -Backend HamlibTcp -HostName 127.0.0.1 -Port 4533
```

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
1. Perform focused runtime validation of the public tracking, visibility, GPS/NMEA, and rotator commands.
2. Decide whether to fix the local `PSModulePath` / OneDrive-backed module-loading issue so `Pester` imports cleanly without overrides.
3. Keep `Set-AetherScopeRotatorPark` as the public parking command and maintain approved-verb naming across new additions.
4. Consolidate historical patch layers into a single clean codebase.
5. Ensure the build script packages only production-ready artifacts.
