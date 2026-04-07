# AGENTS.md

## Purpose
AetherScope is a Windows PowerShell 5.1–targeted celestial tracking and antenna-pointing project. Future Codex CLI work should treat this repository as a **PowerShell 5.1 compatibility-first** codebase.

## Non-negotiable standards
- Target **Windows PowerShell 5.1 only**.
- Do not use PowerShell 6/7 syntax or operators.
- Prefer approved `Verb-Noun` naming for public functions.
- Public functions should include comment-based help with:
  - `.SYNOPSIS`
  - `.DESCRIPTION`
  - `.PARAMETER`
  - `.EXAMPLE`
  - `.INPUTS`
  - `.OUTPUTS`
  - `.NOTES`
- Use `[CmdletBinding(SupportsShouldProcess = $true)]` for state-changing functions.
- Use `begin {}`, `process {}`, and `end {}` for pipeline-oriented functions.
- Prefer `Write-Verbose` and `Write-Error` over abrupt termination.
- Avoid `Invoke-Expression`.
- Do not bypass certificate/TLS validation.
- Do not embed plaintext secrets or credentials.

## Packaging expectations
- Expected working layout:
  - `Source/`
    - `AetherScope.ps1`
    - `README.md`
    - `EXAMPLES.md`
  - `scripts/`
    - `Build-AetherScope.ps1`
  - `Tests/`
  - `dist/`
  - `docs/`
  - `handoff/`
- The build script should remain PowerShell 5.1 compatible and produce a clean release zip in `dist/`.
- If the project becomes a module, package it in a drop-in installable layout and keep the build script deterministic.

## Testing expectations
- Packaging-only review has been insufficient in the past.
- Always prefer **runtime host validation** in Windows PowerShell 5.1 in addition to static review.
- When fixing parse issues, helper mismatches, or parameter binding issues, capture the exact error and document it in `docs/known-issues.md` or `CHANGELOG.md` as appropriate.

## Known design direction
- AetherScope has grown through multiple patch iterations.
- Historical functionality includes:
  - Sun/Moon/ISS position calculation
  - visibility windows
  - ISS radio visibility windows
  - fixed-star support
  - staged precision star handling
  - GPS/NMEA coordinate ingestion
  - rotator control (Hamlib / GS-232 family)
  - in-place console dashboards
- Public surface should be branded consistently with `AetherScope`.
- Internal helpers may remain technical, but public commands should be easy to discover and document.

## If the repo is incomplete
If a future Codex run opens this repository and expected source files are missing, do **not** guess silently. Update the status docs and handoff notes with:
- what was present
- what was missing
- what assumptions were made
- what still requires runtime validation
