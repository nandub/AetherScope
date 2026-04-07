# Source README

This folder contains the module source of truth for AetherScope.

## Files
- `AetherScope.ps1` - main PowerShell source script
- `AetherScope.psm1` - module entry point
- `AetherScope.psd1` - module manifest
- `AetherScopePrecisionHelper.cs` - C# precision helper source
- `EXAMPLES.md` - usage examples
- `en-US/AetherScope-help.xml` - external help scaffold

## Source of truth rule
When the user provides a newer attached `AetherScope.ps1` or helper file, update the corresponding file here and refresh the repo docs and release package.

## Validation expectation
After replacing source files here, validate in Windows PowerShell 5.1 rather than relying only on static packaging review.
