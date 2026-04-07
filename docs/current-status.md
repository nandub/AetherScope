# Current Status

## Summary
AetherScope has a documented intended architecture, but the current Codex-visible workspace snapshot did **not** include the expected source files under `Source/` or the expected tests under `Tests/`.

## What is known
- The project is intended to target **Windows PowerShell 5.1**.
- Historical feature scope included celestial positions, visibility windows, ISS radio tracking, fixed-star support, GPS/NMEA ingestion, rotator control, and dashboards.
- The build entry point is assumed to be `scripts/Build-AetherScope.ps1`.
- Historical work uncovered issues that only appeared during actual host execution.

## What is not yet confirmed in this workspace
- The current canonical `Source/AetherScope.ps1`
- The current canonical `Source/README.md`
- The current canonical `Source/EXAMPLES.md`
- The current smoke tests under `Tests/`
- The current packaging logic in the build script

## Confidence level
Documentation confidence is moderate.
Runtime confidence is low until the real source is restored and executed in Windows PowerShell 5.1.

## Immediate recommendation
Before any functional refactor, verify the actual source tree and run it in a real Windows PowerShell 5.1 host.
