# Decisions

## 1. PowerShell target
**Decision:** Windows PowerShell 5.1 only.

**Reason:** This is an explicit project requirement and affects syntax, cmdlet selection, packaging, and testing.

## 2. Public help standard
**Decision:** Public functions should use full comment-based help.

**Reason:** The project is intended to be durable and discoverable for future Codex and human maintenance.

## 3. ShouldProcess standard
**Decision:** State-changing functions should use `[CmdletBinding(SupportsShouldProcess = $true)]`.

**Reason:** Rotator control, packaging, and any file-modifying commands need `-WhatIf` / `-Confirm` semantics.

## 4. Runtime validation over packaging-only review
**Decision:** Treat real Windows PowerShell 5.1 execution as mandatory for confidence.

**Reason:** Historical defects were discovered only after runtime host validation.

## 5. Consolidation direction
**Decision:** Prefer a single clean consolidated script or module surface over layered patch files.

**Reason:** Historical patch accumulation increases risk of duplicate functions, parameter mismatches, and parse regressions.

## 6. Packaging direction
**Decision:** Keep `scripts/Build-AetherScope.ps1` as the main build entry point and emit release zips into `dist/`.

**Reason:** This matches the expected repo workflow and provides a stable handoff target for future work.
