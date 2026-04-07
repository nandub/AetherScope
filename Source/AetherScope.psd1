@{
    RootModule = 'AetherScope.psm1'
    ModuleVersion = '1.0.3'
    GUID = 'ddf3c46f-ff5b-49f3-b2b2-9afdec2d8a78'
    Author = 'OpenAI'
    CompanyName = 'OpenAI'
    Copyright = '(c) 2026'
    Description = 'AetherScope provides celestial tracking, visibility planning, dashboarding, GPS/NMEA ingestion, precision star support, and rotator control for Windows PowerShell 5.1.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @(
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
        'Set-AetherScopeRotatorPark',
        'Set-AetherScopeRotatorPosition',
        'Start-AetherScopeDashboard',
        'Start-AetherScopeIssTrack',
        'Start-AetherScopeTrack',
        'Start-AetherScopeTracker',
        'Stop-AetherScopeRotator'
    )
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()
    FileList = @(
        'AetherScope.ps1',
        'AetherScope.psm1',
        'AetherScope.psd1',
        'AetherScopePrecisionHelper.cs',
        'en-US\AetherScope-help.xml'
    )
    PrivateData = @{
        PSData = @{
            Tags = @('Astronomy','Tracking','Rotator','ISS','WindowsPowerShell51')
            ProjectUri = 'https://example.invalid/AetherScope'
            LicenseUri = 'https://opensource.org/licenses/MIT'
            ReleaseNotes = 'Module conversion scaffolded around the attached AetherScope.ps1 and helper source. Latest version is 1.0.3.'
        }
    }
}

