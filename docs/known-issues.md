# Known Issues

## 1. Pester import is sensitive to the local module search path
`Pester 3.4.0` is installed and the smoke tests now pass, but `Import-Module Pester` failed in the default host with `The cloud file provider is not running.` until `PSModulePath` was constrained to non-cloud module folders.

**Impact:** The repository test file is valid for Windows PowerShell 5.1, but the local environment may still fail to load `Pester` without a host-level workaround.

**Recommended action:** Decide whether to normalize the host `PSModulePath` / OneDrive-backed documents configuration or keep using a constrained `PSModulePath` for smoke validation.

## 2. Historical runtime-only defects
Prior iterations reportedly experienced runtime defects that packaging-only review missed.

**Examples of defect classes:**
- parse errors under Windows PowerShell 5.1
- helper/parameter mismatches
- layered patch drift
- naming inconsistency between public and internal surfaces

**Recommended action:** Always run smoke validation in Windows PowerShell 5.1 after structural cleanup.

## 3. Helper DLL replacement can fail when the output file is in use
`scripts/Build-AetherScopePrecisionHelper.ps1` now handles path resolution correctly, but rebuilding `Source/AetherScopePrecisionHelper.dll` will still fail if another PowerShell session or process has the DLL open.

**Impact:** Precision helper rebuilds can appear broken when the actual problem is an external file lock.

**Recommended action:** Close sessions that imported AetherScope before rebuilding the helper DLL.

## 4. Risk of layered patch accumulation
Historical development through many patch versions implies a risk of duplicate definitions or partially updated call paths.

**Recommended action:** Keep a single clean canonical source and avoid shipping stacked patch scripts.
