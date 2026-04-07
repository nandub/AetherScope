# Known Issues

## 1. Workspace incompleteness during this handoff
The expected project source files were not present in the Codex-visible workspace snapshot when this handoff package was created.

**Impact:** Current documentation reflects intended structure and lessons learned, but not verified current source content.

**Recommended action:** Restore or verify `Source/AetherScope.ps1`, `Source/README.md`, `Source/EXAMPLES.md`, and `Tests/`.

## 2. Historical runtime-only defects
Prior iterations reportedly experienced runtime defects that packaging-only review missed.

**Examples of defect classes:**
- parse errors under Windows PowerShell 5.1
- helper/parameter mismatches
- layered patch drift
- naming inconsistency between public and internal surfaces

**Recommended action:** Always run smoke validation in Windows PowerShell 5.1 after structural cleanup.

## 3. Risk of layered patch accumulation
Historical development through many patch versions implies a risk of duplicate definitions or partially updated call paths.

**Recommended action:** Keep a single clean canonical source and avoid shipping stacked patch scripts.
