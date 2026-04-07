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
    [string]$SourcePath,

    [Parameter()]
    [string]$OutputPath
)

try {
    $scriptRoot = $PSScriptRoot
    if ([string]::IsNullOrWhiteSpace($scriptRoot)) {
        $scriptRoot = Split-Path -Path $MyInvocation.MyCommand.Path -Parent
    }

    if ([string]::IsNullOrWhiteSpace($SourcePath)) {
        $SourcePath = '..\Source\AetherScopePrecisionHelper.cs'
    }

    if ([string]::IsNullOrWhiteSpace($OutputPath)) {
        $OutputPath = '..\Source\AetherScopePrecisionHelper.dll'
    }

    function Resolve-AetherScopeBuildPath {
        param(
            [Parameter(Mandatory = $true)]
            [string]$Path,

            [Parameter(Mandatory = $true)]
            [string]$BasePath
        )

        if ([System.IO.Path]::IsPathRooted($Path)) {
            return [System.IO.Path]::GetFullPath($Path)
        }

        return [System.IO.Path]::GetFullPath((Join-Path -Path $BasePath -ChildPath $Path))
    }

    $resolvedSourcePath = Resolve-AetherScopeBuildPath -Path $SourcePath -BasePath $scriptRoot
    $resolvedOutputPath = Resolve-AetherScopeBuildPath -Path $OutputPath -BasePath $scriptRoot

    if (-not (Test-Path -LiteralPath $resolvedSourcePath)) {
        Write-Error ('Source file not found: {0}' -f $resolvedSourcePath)
        return
    }

    if ($PSCmdlet.ShouldProcess($resolvedOutputPath, 'Compile AetherScope precision helper DLL')) {
        $typeDefinition = Get-Content -LiteralPath $resolvedSourcePath -Raw -ErrorAction Stop
        $temporaryOutputPath = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ('AetherScopePrecisionHelper-{0}.dll' -f ([guid]::NewGuid().ToString()))

        try {
            Add-Type -TypeDefinition $typeDefinition -Language CSharp -OutputAssembly $temporaryOutputPath -ErrorAction Stop | Out-Null

            if (Test-Path -LiteralPath $resolvedOutputPath) {
                Remove-Item -LiteralPath $resolvedOutputPath -Force -ErrorAction Stop
            }

            Move-Item -LiteralPath $temporaryOutputPath -Destination $resolvedOutputPath -Force -ErrorAction Stop
            Get-Item -LiteralPath $resolvedOutputPath
        }
        catch [System.UnauthorizedAccessException] {
            Write-Error ('Failed to replace precision helper DLL at {0}. The file is likely in use by another PowerShell session or process. Close sessions that imported AetherScope and try again. Original error: {1}' -f $resolvedOutputPath, $_.Exception.Message)
        }
        finally {
            if (Test-Path -LiteralPath $temporaryOutputPath) {
                Remove-Item -LiteralPath $temporaryOutputPath -Force -ErrorAction SilentlyContinue
            }
        }
    }
}
catch {
    Write-Error ('Failed to build AetherScope precision helper DLL: {0}' -f $_.Exception.Message)
}
