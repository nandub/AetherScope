# Requires -Version 5.1
Describe 'AetherScope smoke tests' {
    It 'imports the module manifest' {
        $modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\Source\AetherScope.psd1'
        $module = Import-Module -Name $modulePath -Force -PassThru
        $module.Name | Should Be 'AetherScope'
    }

    It 'exports expected public functions' {
        $modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\Source\AetherScope.psd1'
        $module = Import-Module -Name $modulePath -Force -PassThru
        ($module.ExportedFunctions.Keys -contains 'Get-AetherScopePosition') | Should Be $true
        ($module.ExportedFunctions.Keys -contains 'Set-AetherScopeRotatorPark') | Should Be $true
        ($module.ExportedFunctions.Keys -contains 'Start-AetherScopeDashboard') | Should Be $true
    }

    It 'returns a fixed star reference set' {
        $modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\Source\AetherScope.psd1'
        Import-Module -Name $modulePath -Force | Out-Null
        $stars = Get-AetherScopeStarReferenceSet
        ($stars -contains 'Polaris') | Should Be $true
    }
}
