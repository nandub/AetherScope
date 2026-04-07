<#
.SYNOPSIS
AetherScope module entry point.
.DESCRIPTION
Imports the AetherScope public command surface from the consolidated script file
and exports only the AetherScope-prefixed public functions.
#>

$script:ModuleRoot = Split-Path -Path $MyInvocation.MyCommand.Path -Parent
$script:MainScriptPath = Join-Path -Path $script:ModuleRoot -ChildPath 'AetherScope.ps1'

if (-not (Test-Path -LiteralPath $script:MainScriptPath)) {
    Write-Error ('AetherScope source script was not found: {0}' -f $script:MainScriptPath)
    return
}

. $script:MainScriptPath

Export-ModuleMember -Function @(
    'Get-AetherScopeGpsCoordinate',
    'Get-AetherScopeIssCurrentPosition',
    'Get-AetherScopeIssObserverPosition',
    'Get-AetherScopeIssPassPrediction',
    'Get-AetherScopeIssPositionSeries',
    'Get-AetherScopeIssRadioVisibility',
    'Get-AetherScopeIssRadioWindow',
    'Get-AetherScopeMoonPosition',
    'Get-AetherScopeMoonVisibilityWindow',
    'Get-AetherScopePosition',
    'Get-AetherScopePrecisionStarPosition',
    'Get-AetherScopeRotatorPosition',
    'Get-AetherScopeStarCatalog',
    'Get-AetherScopeStarPosition',
    'Get-AetherScopeStarReferenceSet',
    'Get-AetherScopeSunPosition',
    'Get-AetherScopeSunVisibilityWindow',
    'Get-AetherScopeVisibilityWindow',
    'Park-AetherScopeRotator',
    'Set-AetherScopeRotatorPosition',
    'Start-AetherScopeDashboard',
    'Start-AetherScopeIssTrack',
    'Start-AetherScopeTrack',
    'Start-AetherScopeTracker',
    'Stop-AetherScopeRotator'
)
