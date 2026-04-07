<#
.SYNOPSIS
Builds the AetherScope precision helper DLL.
.DESCRIPTION
Compiles Source\AetherScopePrecisionHelper.cs into Source\AetherScopePrecisionHelper.dll using Add-Type
so Windows PowerShell 5.1 can load the helper as a stage-3 precision engine.
.PARAMETER SourcePath
Path to AetherScopePrecisionHelper.cs.
.PARAMETER OutputPath
Path to the compiled DLL.
.EXAMPLE
.\Build-AetherScopePrecisionHelper.ps1 -WhatIf
.EXAMPLE
.\Build-AetherScopePrecisionHelper.ps1 -Verbose
.INPUTS
None
.OUTPUTS
System.IO.FileInfo
.NOTES
This build script targets the practical helper DLL included with the staged
fixed-star precision pipeline. The resulting DLL can later be replaced by a
SOFA/ERFA or NOVAS-backed implementation without changing the PowerShell API.
Add-Type in Windows PowerShell 5.1 does not support combining -Path with
-OutputAssembly, so this script reads the source file content and compiles it
through the -TypeDefinition parameter set.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter()]
    [string]$SourcePath = (Join-Path -Path $PSScriptRoot -ChildPath '..\Source\AetherScopePrecisionHelper.cs'),

    [Parameter()]
    [string]$OutputPath = (Join-Path -Path $PSScriptRoot -ChildPath '..\Source\AetherScopePrecisionHelper.dll')
)

try {
    $resolvedSourcePath = [System.IO.Path]::GetFullPath((Join-Path -Path $PSScriptRoot -ChildPath $SourcePath))
    $resolvedOutputPath = [System.IO.Path]::GetFullPath((Join-Path -Path $PSScriptRoot -ChildPath $OutputPath))

    if (-not (Test-Path -LiteralPath $resolvedSourcePath)) {
        Write-Error ('Source file not found: {0}' -f $resolvedSourcePath)
        return
    }

    if ($PSCmdlet.ShouldProcess($resolvedOutputPath, 'Compile AetherScope precision helper DLL')) {
        if (Test-Path -LiteralPath $resolvedOutputPath) {
            Remove-Item -LiteralPath $resolvedOutputPath -Force -ErrorAction Stop
        }

        $typeDefinition = Get-Content -LiteralPath $resolvedSourcePath -Raw -ErrorAction Stop
        Add-Type -TypeDefinition $typeDefinition -Language CSharp -OutputAssembly $resolvedOutputPath -ErrorAction Stop | Out-Null
        Get-Item -LiteralPath $resolvedOutputPath
    }
}
catch {
    Write-Error ('Failed to build AetherScope precision helper DLL: {0}' -f $_.Exception.Message)
}
