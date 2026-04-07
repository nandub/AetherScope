<#
.SYNOPSIS
Builds an installable release zip for the AetherScope module.
.DESCRIPTION
Packages the AetherScope module into an installable ZIP under `dist\`. The ZIP
contains the module layout `AetherScope\<Version>\...` and includes the module
files from `Source\`, plus scripts, tests, and core documentation.
.PARAMETER NewVersion
Optional module version. When specified, updates `ModuleVersion` and `GUID` in
`Source\AetherScope.psd1` before packaging.
.EXAMPLE
.\scripts\Build-AetherScope.ps1 -Verbose
.EXAMPLE
.\scripts\Build-AetherScope.ps1 -NewVersion '1.0.3' -WhatIf
.INPUTS
None
.OUTPUTS
System.IO.FileInfo
.NOTES
This script targets Windows PowerShell 5.1 and uses built-in .NET ZIP support.
The module files under `Source\` are copied to the module root inside the ZIP,
not into a nested `Source\` folder.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter()]
    [string]$NewVersion = '1.0.3'
)

begin {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    $sourceRoot = Join-Path -Path $repoRoot -ChildPath 'Source'
    $manifestPath = Join-Path -Path $sourceRoot -ChildPath 'AetherScope.psd1'
    $distPath = Join-Path -Path $repoRoot -ChildPath 'dist'
    $zipPath = Join-Path -Path $distPath -ChildPath ('AetherScope-{0}.zip' -f $NewVersion)
    $packageRoot = Join-Path -Path $env:TEMP -ChildPath ('AetherScope-Build-' + [guid]::NewGuid().ToString())
    $moduleRoot = Join-Path -Path $packageRoot -ChildPath (Join-Path -Path 'AetherScope' -ChildPath $NewVersion)
}

process {
    try {
        if (-not (Test-Path -LiteralPath $sourceRoot)) {
            Write-Error ('Source folder not found: {0}' -f $sourceRoot)
            return
        }

        if (-not (Test-Path -LiteralPath $manifestPath)) {
            Write-Error ('Module manifest not found: {0}' -f $manifestPath)
            return
        }

        if (-not (Test-Path -LiteralPath $distPath)) {
            if ($PSCmdlet.ShouldProcess($distPath, 'Create dist folder')) {
                New-Item -Path $distPath -ItemType Directory -Force | Out-Null
            }
        }

        if ($PSCmdlet.ShouldProcess($manifestPath, ('Update module version to {0} and refresh GUID' -f $NewVersion))) {
            $content = Get-Content -LiteralPath $manifestPath -Raw -ErrorAction Stop
            $content = [regex]::Replace($content, "ModuleVersion\s*=\s*'[^']+'", "ModuleVersion = '$NewVersion'")
            $content = [regex]::Replace($content, "GUID\s*=\s*'[^']+'", ("GUID = '{0}'" -f ([guid]::NewGuid().ToString())))
            Set-Content -LiteralPath $manifestPath -Value $content -Encoding UTF8
        }

        if ($PSCmdlet.ShouldProcess($zipPath, 'Create installable module zip')) {
            if (Test-Path -LiteralPath $zipPath) {
                Remove-Item -LiteralPath $zipPath -Force -ErrorAction Stop
            }

            if (Test-Path -LiteralPath $packageRoot) {
                Remove-Item -LiteralPath $packageRoot -Recurse -Force -ErrorAction Stop
            }

            New-Item -Path $moduleRoot -ItemType Directory -Force | Out-Null

            $sourceItems = Get-ChildItem -LiteralPath $sourceRoot -Force
            foreach ($item in $sourceItems) {
                $destination = Join-Path -Path $moduleRoot -ChildPath $item.Name
                if ($item.PSIsContainer) {
                    Copy-Item -LiteralPath $item.FullName -Destination $destination -Recurse -Force
                }
                else {
                    Copy-Item -LiteralPath $item.FullName -Destination $destination -Force
                }
            }

            $includeItems = @('scripts','Tests','README.md','CHANGELOG.md','LICENSE','docs','handoff')
            foreach ($item in $includeItems) {
                $path = Join-Path -Path $repoRoot -ChildPath $item
                if (-not (Test-Path -LiteralPath $path)) {
                    continue
                }

                $destination = Join-Path -Path $moduleRoot -ChildPath $item
                if ((Get-Item -LiteralPath $path).PSIsContainer) {
                    Copy-Item -LiteralPath $path -Destination $destination -Recurse -Force
                }
                else {
                    Copy-Item -LiteralPath $path -Destination $destination -Force
                }
            }

            Add-Type -AssemblyName System.IO.Compression.FileSystem
            [System.IO.Compression.ZipFile]::CreateFromDirectory($packageRoot, $zipPath)
            Get-Item -LiteralPath $zipPath
        }
    }
    catch {
        Write-Error ('Failed to build AetherScope package: {0}' -f $_.Exception.Message)
    }
    finally {
        if (Test-Path -LiteralPath $packageRoot) {
            Remove-Item -LiteralPath $packageRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

end {
}
