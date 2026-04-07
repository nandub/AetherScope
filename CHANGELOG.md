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

### Notes
- Historical development included many patch-style revisions and runtime defect fixes.
- Future changes should prefer a clean consolidated codebase over stacked patch files.
