# AetherScope Examples

## Import the module

```powershell
Import-Module .\Source\AetherScope.psd1 -Force
```

## Get Sun position

```powershell
Get-AetherScopeSunPosition -Coordinate '30.2752,-89.7812'
```

## Get Moon visibility window

```powershell
Get-AetherScopeVisibilityWindow -Body Moon -Coordinate '30.2752,-89.7812' -MinAltitudeDegrees 10
```

## Start the dashboard

```powershell
Start-AetherScopeDashboard -Coordinate '30.2752,-89.7812' -IntervalSeconds 2
```

## Build the precision helper DLL

```powershell
.\scripts\Build-AetherScopePrecisionHelper.ps1 -Verbose
.\scripts\Build-AetherScopePrecisionHelper.ps1 -WhatIf
```

## Build the release zip

```powershell
.\scripts\Build-AetherScope.ps1 -Verbose
.\scripts\Build-AetherScope.ps1 -NewVersion '1.0.3' -WhatIf
```
