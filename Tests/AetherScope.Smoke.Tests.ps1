# Requires -Version 5.1
Describe 'AetherScope smoke tests' {
    It 'imports the module manifest' {
        $modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\Source\AetherScope.psd1'
        $module = Import-Module -Name $modulePath -Force -PassThru
        $module.Name | Should -Be 'AetherScope'
    }

    It 'exports expected public functions' {
        $modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\Source\AetherScope.psd1'
        $module = Import-Module -Name $modulePath -Force -PassThru
        $module.ExportedFunctions.Keys | Should -Contain 'Get-AetherScopePosition'
        $module.ExportedFunctions.Keys | Should -Contain 'Start-AetherScopeDashboard'
    }

    It 'returns a fixed star reference set' {
        $modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\Source\AetherScope.psd1'
        Import-Module -Name $modulePath -Force | Out-Null
        $stars = Get-AetherScopeStarReferenceSet
        $stars | Should -Contain 'Polaris'
    }
}
