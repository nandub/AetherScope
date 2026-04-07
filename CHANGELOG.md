# CHANGELOG

All notable changes to AetherScope should be documented in this file.

## [Unreleased]
### Added
- Durable repository handoff package:
  - `AGENTS.md`
  - `CHANGELOG.md`
  - `LICENSE`
  - `README.md`
  - `docs/current-status.md`
  - `docs/decisions.md`
  - `docs/known-issues.md`
  - `handoff/latest-chat-handoff.md`
- Repository-oriented build script placeholder at `scripts/Build-AetherScope.ps1`.

### Changed
- Standardized project documentation around Windows PowerShell 5.1 compatibility, packaging expectations, and runtime validation requirements.
- Captured current workspace uncertainty: expected source layout was not present in this workspace snapshot when the handoff package was generated.

### Fixed
- `scripts/Build-AetherScopePrecisionHelper.ps1` no longer resolves default paths inside the `param()` block, which failed in Windows PowerShell with: `Join-Path : Cannot bind argument to parameter 'Path' because it is an empty string.`
- `scripts/Build-AetherScopePrecisionHelper.ps1` now resolves absolute and relative source/output paths correctly and emits a targeted error when the destination DLL is locked by another process.
- `scripts/Build-AetherScope.ps1` and `Source/AetherScope.psd1` were revalidated in Windows PowerShell 5.1 via successful package creation and module import.
- `Tests/AetherScope.Smoke.Tests.ps1` now uses Pester 3-compatible assertion syntax so the smoke suite can run under the Windows PowerShell 5.1 environment available on this host.
- `Set-AetherScopeRotatorPark` is now the exported public parking command, and the legacy `Park-AetherScopeRotator` export was removed before release.

### Notes
- Historical development included many patch-style revisions and runtime defect fixes.
- Future changes should prefer a clean consolidated codebase over stacked patch files.
