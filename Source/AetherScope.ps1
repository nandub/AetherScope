<#
.SYNOPSIS
AetherScope - celestial tracking, visibility planning, dashboarding, GPS ingestion, fixed-star pointing, and rotator control for Windows PowerShell 5.1.
.DESCRIPTION
AetherScope provides a consolidated public command surface for Sun, Moon, ISS, and fixed-star tracking. It supports in-place console dashboards, visibility windows, GPS/NMEA coordinate input, simplified and staged precision star calculations, and rotator control through Hamlib/rotctld and GS-232 style backends.
.NOTES
This cleaned revision removes the layered vNext concatenation artifacts and keeps a single public command surface using AetherScope-prefixed function names.
#>

Set-StrictMode -Version 2.0


function Resolve-AetherScopeCoordinate {
<#
.SYNOPSIS
Resolves latitude and longitude input into a standard coordinate object.
.DESCRIPTION
Accepts latitude/longitude as separate parameters or through a coordinate object.
The Coordinate parameter is intentionally flexible so it can be extended later to
support GPS devices or serialized coordinate payloads. Supported inputs include:
- A string in the form 'latitude,longitude'
- A hashtable or dictionary with Latitude/Longitude or Lat/Lon keys
- An object with Latitude/Longitude or Lat/Lon properties
.PARAMETER Latitude
Latitude in decimal degrees. North is positive and south is negative.
.PARAMETER Longitude
Longitude in decimal degrees. East is positive and west is negative.
.PARAMETER Coordinate
Flexible coordinate input.
.EXAMPLE
Resolve-AetherScopeCoordinate -Latitude 30.2752 -Longitude -89.7812
.EXAMPLE
Resolve-AetherScopeCoordinate -Coordinate '30.2752,-89.7812'
.INPUTS
System.Object
.OUTPUTS
System.Management.Automation.PSCustomObject
.NOTES
This helper is designed to make future GPS integrations easier by centralizing
coordinate normalization in one place.

.LINK
https://gpsd.gitlab.io/gpsd/NMEA.html
.LINK
https://www.serialmon.com/protocols/nmea0183.shtml
#>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([pscustomobject])]
    param(
        [Parameter()]
        [Nullable[Double]]$Latitude,

        [Parameter()]
        [Nullable[Double]]$Longitude,

        [Parameter(ValueFromPipeline = $true)]
        [AllowNull()]
        [Object]$Coordinate
    )

    begin {
    }

    process {
        $resolvedLatitude = $null
        $resolvedLongitude = $null
        $source = 'Unknown'

        if (($Latitude -ne $null) -and ($Longitude -ne $null)) {
            $resolvedLatitude = [double]$Latitude
            $resolvedLongitude = [double]$Longitude
            $source = 'Parameter'
        }
        elseif ($null -ne $Coordinate) {
            if ($Coordinate -is [string]) {
                $parts = $Coordinate -split ','
                if ($parts.Count -eq 2) {
                    try {
                        $resolvedLatitude = [double]($parts[0].Trim())
                        $resolvedLongitude = [double]($parts[1].Trim())
                        $source = 'String'
                    }
                    catch {
                        Write-Error "Unable to parse coordinate string '$Coordinate'. Use decimal degrees such as '30.2752,-89.7812'."
                        return
                    }
                }
                else {
                    Write-Error 'Coordinate string must be in the form "latitude,longitude".'
                    return
                }
            }
            elseif ($Coordinate -is [System.Collections.IDictionary]) {
                if ($Coordinate.Contains('NmeaSentence')) {
                    $nmeaParsed = ConvertFrom-NmeaSentence -Sentence ([string]$Coordinate['NmeaSentence'])
                    if ($null -ne $nmeaParsed) {
                        $resolvedLatitude = [double]$nmeaParsed.Latitude
                        $resolvedLongitude = [double]$nmeaParsed.Longitude
                        $source = 'NmeaSentence'
                    }
                }
                if (($null -eq $resolvedLatitude) -and $Coordinate.Contains('Latitude')) {
                    $resolvedLatitude = [double]$Coordinate['Latitude']
                }
                elseif ($Coordinate.Contains('Lat')) {
                    $resolvedLatitude = [double]$Coordinate['Lat']
                }

                if (($null -eq $resolvedLongitude) -and $Coordinate.Contains('Longitude')) {
                    $resolvedLongitude = [double]$Coordinate['Longitude']
                }
                elseif ($Coordinate.Contains('Lon')) {
                    $resolvedLongitude = [double]$Coordinate['Lon']
                }

                $source = 'Dictionary'
            }
            else {
                $nmeaSentenceProperty = $Coordinate.PSObject.Properties['NmeaSentence']
                if ($null -ne $nmeaSentenceProperty) {
                    $nmeaParsed = ConvertFrom-NmeaSentence -Sentence ([string]$nmeaSentenceProperty.Value)
                    if ($null -ne $nmeaParsed) {
                        $resolvedLatitude = [double]$nmeaParsed.Latitude
                        $resolvedLongitude = [double]$nmeaParsed.Longitude
                        $source = 'NmeaSentence'
                    }
                }

                $latitudeProperty = $Coordinate.PSObject.Properties['Latitude']
                if ($null -eq $latitudeProperty) {
                    $latitudeProperty = $Coordinate.PSObject.Properties['Lat']
                }

                $longitudeProperty = $Coordinate.PSObject.Properties['Longitude']
                if ($null -eq $longitudeProperty) {
                    $longitudeProperty = $Coordinate.PSObject.Properties['Lon']
                }

                if (($null -eq $resolvedLatitude) -and ($null -ne $latitudeProperty) -and ($null -ne $longitudeProperty)) {
                    $resolvedLatitude = [double]$latitudeProperty.Value
                    $resolvedLongitude = [double]$longitudeProperty.Value
                    $source = 'Object'
                }
            }
        }

        if (($resolvedLatitude -eq $null) -or ($resolvedLongitude -eq $null)) {
            Write-Error 'Latitude and Longitude are required. Provide -Latitude and -Longitude, or use -Coordinate.'
            return
        }

        if (($resolvedLatitude -lt -90.0) -or ($resolvedLatitude -gt 90.0)) {
            Write-Error 'Latitude must be between -90 and 90 degrees.'
            return
        }

        if (($resolvedLongitude -lt -180.0) -or ($resolvedLongitude -gt 180.0)) {
            Write-Error 'Longitude must be between -180 and 180 degrees.'
            return
        }

        if ($PSCmdlet.ShouldProcess(("{0},{1}" -f $resolvedLatitude, $resolvedLongitude), 'Resolve coordinate')) {
            [pscustomobject]@{
                PSTypeName = 'AetherScope.GeoCoordinate'
                Latitude = $resolvedLatitude
                Longitude = $resolvedLongitude
                Source = $source
            }
        }
    }

    end {
    }
}



function ConvertTo-Radians {
    param([double]$Degrees)
    return $Degrees * ([Math]::PI / 180.0)
}



function ConvertTo-Degrees {
    param([double]$Radians)
    return $Radians * (180.0 / [Math]::PI)
}



function ConvertFrom-NmeaCoordinate {
<#
.SYNOPSIS
Converts an NMEA latitude or longitude field into decimal degrees.
.DESCRIPTION
Parses an NMEA coordinate value such as 3016.512 with its direction indicator
and converts it to signed decimal degrees.
.PARAMETER Value
NMEA coordinate value.
.PARAMETER Direction
Direction indicator such as N, S, E, or W.
.PARAMETER CoordinateType
Latitude or Longitude.
.EXAMPLE
ConvertFrom-NmeaCoordinate -Value '3016.512' -Direction N -CoordinateType Latitude
.EXAMPLE
ConvertFrom-NmeaCoordinate -Value '08946.866' -Direction W -CoordinateType Longitude -WhatIf
.INPUTS
System.String
.OUTPUTS
System.Double
.NOTES
Latitude uses ddmm.mmmm and longitude uses dddmm.mmmm.

.LINK
https://gpsd.gitlab.io/gpsd/NMEA.html
.LINK
https://www.serialmon.com/protocols/nmea0183.shtml
#>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([double])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Value,

        [Parameter(Mandatory = $true)]
        [ValidateSet('N', 'S', 'E', 'W')]
        [string]$Direction,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Latitude', 'Longitude')]
        [string]$CoordinateType
    )

    begin {
    }

    process {
        if (-not $PSCmdlet.ShouldProcess($Value, 'Convert NMEA coordinate to decimal degrees')) {
            return
        }

        try {
            $trimmed = $Value.Trim()
            if ([string]::IsNullOrWhiteSpace($trimmed)) {
                Write-Error 'NMEA coordinate value cannot be empty.'
                return
            }

            $degreeDigits = 2
            if ($CoordinateType -eq 'Longitude') {
                $degreeDigits = 3
            }

            if ($trimmed.Length -le $degreeDigits) {
                Write-Error ("NMEA coordinate value '{0}' is not long enough for {1}." -f $Value, $CoordinateType)
                return
            }

            $degrees = [double]$trimmed.Substring(0, $degreeDigits)
            $minutes = [double]$trimmed.Substring($degreeDigits)
            $decimal = $degrees + ($minutes / 60.0)

            if (($Direction -eq 'S') -or ($Direction -eq 'W')) {
                $decimal = -1.0 * $decimal
            }

            $decimal
        }
        catch {
            Write-Error ("Failed to convert NMEA coordinate '{0}': {1}" -f $Value, $_.Exception.Message)
        }
    }

    end {
    }
}



function ConvertFrom-NmeaSentence {
<#
.SYNOPSIS
Parses a supported NMEA sentence into a normalized GPS fix object.
.DESCRIPTION
Supports common GGA and RMC sentence formats and returns a coordinate object
that can be consumed by Resolve-AetherScopeCoordinate or Get-AetherScopeGpsCoordinate.
.PARAMETER Sentence
Raw NMEA sentence.
.EXAMPLE
ConvertFrom-NmeaSentence -Sentence '$GPGGA,123519,3016.512,N,08946.866,W,1,08,0.9,0.0,M,0.0,M,,*00'
.EXAMPLE
ConvertFrom-NmeaSentence -Sentence '$GPRMC,123519,A,3016.512,N,08946.866,W,000.5,054.7,290326,,,A*00' -WhatIf
.INPUTS
System.String
.OUTPUTS
System.Management.Automation.PSCustomObject
.NOTES
Checksum validation is not required in this first draft.

.LINK
https://gpsd.gitlab.io/gpsd/NMEA.html
.LINK
https://www.serialmon.com/protocols/nmea0183.shtml
#>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string]$Sentence
    )

    begin {
    }

    process {
        if (-not $PSCmdlet.ShouldProcess($Sentence, 'Parse NMEA sentence')) {
            return
        }

        try {
            $trimmed = $Sentence.Trim()
            if ([string]::IsNullOrWhiteSpace($trimmed) -or (-not $trimmed.StartsWith('$'))) {
                Write-Error 'NMEA sentence must start with $.'
                return
            }

            $noChecksum = $trimmed
            $checksumIndex = $trimmed.IndexOf('*')
            if ($checksumIndex -ge 0) {
                $noChecksum = $trimmed.Substring(0, $checksumIndex)
            }

            $parts = $noChecksum.Split(',')
            if ($parts.Length -lt 6) {
                Write-Verbose ("Skipping short NMEA sentence: {0}" -f $Sentence)
                return
            }

            $messageType = $parts[0].TrimStart('$')
            $sentenceType = ''
            if ($messageType.Length -ge 3) {
                $sentenceType = $messageType.Substring($messageType.Length - 3)
            }

            switch ($sentenceType) {
                'GGA' {
                    if ($parts.Length -lt 7) {
                        return
                    }

                    $latitude = ConvertFrom-NmeaCoordinate -Value $parts[2] -Direction $parts[3] -CoordinateType Latitude
                    $longitude = ConvertFrom-NmeaCoordinate -Value $parts[4] -Direction $parts[5] -CoordinateType Longitude
                    if (($null -eq $latitude) -or ($null -eq $longitude)) {
                        return
                    }

                    [pscustomobject]@{
                        PSTypeName = 'AetherScope.NmeaFix'
                        Latitude = [double]$latitude
                        Longitude = [double]$longitude
                        MessageType = $messageType
                        FixTimeRaw = $parts[1]
                        FixQuality = $parts[6]
                        SatelliteCount = if ($parts.Length -gt 7) { $parts[7] } else { $null }
                        Status = $null
                    }
                }

                'RMC' {
                    if ($parts.Length -lt 7) {
                        return
                    }

                    if (($parts[2] -ne 'A') -and ($parts[2] -ne 'V')) {
                        Write-Verbose ("Skipping unsupported RMC status in sentence: {0}" -f $Sentence)
                        return
                    }

                    $latitude = ConvertFrom-NmeaCoordinate -Value $parts[3] -Direction $parts[4] -CoordinateType Latitude
                    $longitude = ConvertFrom-NmeaCoordinate -Value $parts[5] -Direction $parts[6] -CoordinateType Longitude
                    if (($null -eq $latitude) -or ($null -eq $longitude)) {
                        return
                    }

                    [pscustomobject]@{
                        PSTypeName = 'AetherScope.NmeaFix'
                        Latitude = [double]$latitude
                        Longitude = [double]$longitude
                        MessageType = $messageType
                        FixTimeRaw = $parts[1]
                        FixQuality = $null
                        SatelliteCount = $null
                        Status = $parts[2]
                    }
                }

                default {
                    Write-Verbose ("Unsupported NMEA sentence type: {0}" -f $messageType)
                }
            }
        }
        catch {
            Write-Error ("Failed to parse NMEA sentence: {0}" -f $_.Exception.Message)
        }
    }

    end {
    }
}



function Get-IssLookAngleSample {
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$ResolvedCoordinate,

        [Parameter(Mandatory = $true)]
        [pscustomobject]$IssPosition,

        [Parameter()]
        [double]$ObserverAltitudeKm = 0.0
    )

    begin {
    }

    process {
        if (-not $PSCmdlet.ShouldProcess('ISS sample', 'Calculate look angles')) {
            return
        }

        $look = Get-LookAngles -ObserverLatitude $ResolvedCoordinate.Latitude -ObserverLongitude $ResolvedCoordinate.Longitude -ObserverAltitudeKm $ObserverAltitudeKm -TargetLatitude $IssPosition.Latitude -TargetLongitude $IssPosition.Longitude -TargetAltitudeKm $IssPosition.AltitudeKm
        [pscustomobject]@{
            TimeStamp = $IssPosition.TimeStamp
            IssLatitude = $IssPosition.Latitude
            IssLongitude = $IssPosition.Longitude
            IssAltitudeKm = $IssPosition.AltitudeKm
            Visibility = $IssPosition.Visibility
            Azimuth = [double]$look.Azimuth
            Altitude = [double]$look.Altitude
            RangeKm = [double]$look.RangeKm
            IsAboveHorizon = [bool]$look.IsAboveHorizon
        }
    }

    end {
    }
}



function Get-InterpolatedThresholdCrossing {
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(ParameterSetName = 'SampleObjects', Mandatory = $true)]
        [pscustomobject]$BeforeSample,

        [Parameter(ParameterSetName = 'SampleObjects', Mandatory = $true)]
        [pscustomobject]$AfterSample,

        [Parameter(ParameterSetName = 'ScalarValues', Mandatory = $true)]
        [datetime]$PreviousTime,

        [Parameter(ParameterSetName = 'ScalarValues', Mandatory = $true)]
        [double]$PreviousAltitude,

        [Parameter(ParameterSetName = 'ScalarValues', Mandatory = $true)]
        [double]$PreviousAzimuth,

        [Parameter(ParameterSetName = 'ScalarValues', Mandatory = $true)]
        [datetime]$CurrentTime,

        [Parameter(ParameterSetName = 'ScalarValues', Mandatory = $true)]
        [double]$CurrentAltitude,

        [Parameter(ParameterSetName = 'ScalarValues', Mandatory = $true)]
        [double]$CurrentAzimuth,

        [Parameter(ParameterSetName = 'SampleObjects')]
        [double]$Threshold = 0.0,

        [Parameter(ParameterSetName = 'ScalarValues')]
        [double]$ThresholdDegrees = 0.0
    )

    begin {
    }

    process {
        if (-not $PSCmdlet.ShouldProcess('Celestial threshold crossing', 'Interpolate crossing time')) {
            return
        }

        if ($PSCmdlet.ParameterSetName -eq 'ScalarValues') {
            $BeforeSample = [pscustomobject]@{
                TimeStamp = $PreviousTime
                Altitude = $PreviousAltitude
                Azimuth   = $PreviousAzimuth
            }
            $AfterSample = [pscustomobject]@{
                TimeStamp = $CurrentTime
                Altitude = $CurrentAltitude
                Azimuth   = $CurrentAzimuth
            }
            $Threshold = $ThresholdDegrees
        }

        $beforeAltitude = [double]$BeforeSample.Altitude
        $afterAltitude = [double]$AfterSample.Altitude
        $deltaAltitude = $afterAltitude - $beforeAltitude
        $fraction = 0.5

        if ([Math]::Abs($deltaAltitude) -gt 0.000001) {
            $fraction = ($Threshold - $beforeAltitude) / $deltaAltitude
        }

        if ($fraction -lt 0.0) {
            $fraction = 0.0
        }
        elseif ($fraction -gt 1.0) {
            $fraction = 1.0
        }

        $timeSpanSeconds = ($AfterSample.TimeStamp - $BeforeSample.TimeStamp).TotalSeconds
        $crossTime = $BeforeSample.TimeStamp.AddSeconds($timeSpanSeconds * $fraction)

        $beforeAzimuth = [double]$BeforeSample.Azimuth
        $afterAzimuth = [double]$AfterSample.Azimuth
        $deltaAzimuth = $afterAzimuth - $beforeAzimuth
        if ($deltaAzimuth -gt 180.0) {
            $deltaAzimuth -= 360.0
        }
        elseif ($deltaAzimuth -lt -180.0) {
            $deltaAzimuth += 360.0
        }
        $crossAzimuth = Normalize-Angle -Degrees ($beforeAzimuth + ($deltaAzimuth * $fraction))

        [pscustomobject]@{
            TimeStamp = $crossTime
            Azimuth = $crossAzimuth
            Fraction = $fraction
        }
    }

    end {
    }
}



function Normalize-Angle {
    param([double]$Degrees)
    $result = $Degrees % 360.0
    if ($result -lt 0.0) {
        $result += 360.0
    }
    return $result
}



function Get-JulianDate {
    param([datetime]$DateTime)
    $utc = $DateTime.ToUniversalTime()
    $year = $utc.Year
    $month = $utc.Month
    $day = $utc.Day
    $fractionalDay = ($utc.Hour + ($utc.Minute / 60.0) + ($utc.Second / 3600.0) + ($utc.Millisecond / 3600000.0)) / 24.0

    if ($month -le 2) {
        $year -= 1
        $month += 12
    }

    $a = [Math]::Floor($year / 100.0)
    $b = 2 - $a + [Math]::Floor($a / 4.0)

    return [Math]::Floor(365.25 * ($year + 4716)) + [Math]::Floor(30.6001 * ($month + 1)) + $day + $fractionalDay + $b - 1524.5
}



function Get-GreenwichMeanSiderealTime {
    param([datetime]$DateTime)
    $jd = Get-JulianDate -DateTime $DateTime
    $t = ($jd - 2451545.0) / 36525.0
    $gmst = 280.46061837 + (360.98564736629 * ($jd - 2451545.0)) + (0.000387933 * $t * $t) - (($t * $t * $t) / 38710000.0)
    return Normalize-Angle -Degrees $gmst
}



function Get-LocalSiderealTime {
    param(
        [datetime]$DateTime,
        [double]$Longitude
    )
    return Normalize-Angle -Degrees ((Get-GreenwichMeanSiderealTime -DateTime $DateTime) + $Longitude)
}



function ConvertTo-EcefCoordinate {
    param(
        [double]$Latitude,
        [double]$Longitude,
        [double]$AltitudeKm
    )

    $earthRadiusKm = 6371.0
    $latRad = ConvertTo-Radians -Degrees $Latitude
    $lonRad = ConvertTo-Radians -Degrees $Longitude
    $radius = $earthRadiusKm + $AltitudeKm

    [pscustomobject]@{
        X = $radius * [Math]::Cos($latRad) * [Math]::Cos($lonRad)
        Y = $radius * [Math]::Cos($latRad) * [Math]::Sin($lonRad)
        Z = $radius * [Math]::Sin($latRad)
    }
}



function Get-LookAngles {
    param(
        [double]$ObserverLatitude,
        [double]$ObserverLongitude,
        [double]$ObserverAltitudeKm,
        [double]$TargetLatitude,
        [double]$TargetLongitude,
        [double]$TargetAltitudeKm
    )

    $observer = ConvertTo-EcefCoordinate -Latitude $ObserverLatitude -Longitude $ObserverLongitude -AltitudeKm $ObserverAltitudeKm
    $target = ConvertTo-EcefCoordinate -Latitude $TargetLatitude -Longitude $TargetLongitude -AltitudeKm $TargetAltitudeKm

    $dx = $target.X - $observer.X
    $dy = $target.Y - $observer.Y
    $dz = $target.Z - $observer.Z

    $latRad = ConvertTo-Radians -Degrees $ObserverLatitude
    $lonRad = ConvertTo-Radians -Degrees $ObserverLongitude

    $east = (-[Math]::Sin($lonRad) * $dx) + ([Math]::Cos($lonRad) * $dy)
    $north = ((-[Math]::Sin($latRad) * [Math]::Cos($lonRad)) * $dx) + ((-[Math]::Sin($latRad) * [Math]::Sin($lonRad)) * $dy) + ([Math]::Cos($latRad) * $dz)
    $up = (([Math]::Cos($latRad) * [Math]::Cos($lonRad)) * $dx) + (([Math]::Cos($latRad) * [Math]::Sin($lonRad)) * $dy) + ([Math]::Sin($latRad) * $dz)

    $rangeKm = [Math]::Sqrt(($east * $east) + ($north * $north) + ($up * $up))
    $azimuth = Normalize-Angle -Degrees (ConvertTo-Degrees -Radians ([Math]::Atan2($east, $north)))
    $altitude = ConvertTo-Degrees -Radians ([Math]::Asin($up / $rangeKm))

    [pscustomobject]@{
        Azimuth = $azimuth
        Altitude = $altitude
        RangeKm = $rangeKm
        IsAboveHorizon = ($altitude -ge 0.0)
    }
}



function Get-AetherScopeSunPosition {
<#
.SYNOPSIS
Gets the Sun altitude and azimuth for an observer location.
.DESCRIPTION
Calculates the Sun horizontal coordinates using observer latitude, longitude,
and date/time. Latitude and longitude can be supplied directly or through the
Coordinate parameter for easier future GPS integration.
.PARAMETER Latitude
Latitude in decimal degrees.
.PARAMETER Longitude
Longitude in decimal degrees.
.PARAMETER Coordinate
Flexible coordinate input. Supports 'lat,lon', hashtables, and objects with
Latitude/Longitude or Lat/Lon properties.
.PARAMETER DateTime
Date and time for the observation. Defaults to the current date and time.
.EXAMPLE
Get-AetherScopeSunPosition -Latitude 30.2752 -Longitude -89.7812 -DateTime (Get-Date)
.EXAMPLE
Get-AetherScopeSunPosition -Coordinate '30.2752,-89.7812' -WhatIf
.INPUTS
System.Object
.OUTPUTS
System.Management.Automation.PSCustomObject
.NOTES
Uses a NOAA-style solar position approximation suitable for practical tracking.
Longitude is east-positive and west-negative.

.LINK
https://gml.noaa.gov/grad/solcalc/azel.html
.LINK
https://gml.noaa.gov/grad/solcalc/solareqns.PDF
#>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([pscustomobject])]
    param(
        [Parameter()]
        [Nullable[Double]]$Latitude,

        [Parameter()]
        [Nullable[Double]]$Longitude,

        [Parameter(ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [AllowNull()]
        [Object]$Coordinate,

        [Parameter()]
        [datetime]$DateTime = (Get-Date)
    )

    begin {
    }

    process {
        $resolved = Resolve-AetherScopeCoordinate -Latitude $Latitude -Longitude $Longitude -Coordinate $Coordinate
        if ($null -eq $resolved) {
            return
        }

        if ($PSCmdlet.ShouldProcess(("Sun position for {0},{1}" -f $resolved.Latitude, $resolved.Longitude), 'Calculate solar altitude and azimuth')) {
            try {
                $utc = $DateTime.ToUniversalTime()
                $julianDate = Get-JulianDate -DateTime $utc
                $julianCentury = ($julianDate - 2451545.0) / 36525.0

                $geomMeanLongSun = Normalize-Angle -Degrees (280.46646 + ($julianCentury * (36000.76983 + (0.0003032 * $julianCentury))))
                $geomMeanAnomSun = 357.52911 + ($julianCentury * (35999.05029 - (0.0001537 * $julianCentury)))
                $eccEarthOrbit = 0.016708634 - ($julianCentury * (0.000042037 + (0.0000001267 * $julianCentury)))
                $sunEqOfCtr = ([Math]::Sin((ConvertTo-Radians -Degrees $geomMeanAnomSun)) * (1.914602 - ($julianCentury * (0.004817 + (0.000014 * $julianCentury))))) + ([Math]::Sin((ConvertTo-Radians -Degrees (2.0 * $geomMeanAnomSun))) * (0.019993 - (0.000101 * $julianCentury))) + ([Math]::Sin((ConvertTo-Radians -Degrees (3.0 * $geomMeanAnomSun))) * 0.000289)
                $sunTrueLong = $geomMeanLongSun + $sunEqOfCtr
                $omega = 125.04 - (1934.136 * $julianCentury)
                $sunAppLong = $sunTrueLong - 0.00569 - (0.00478 * [Math]::Sin((ConvertTo-Radians -Degrees $omega)))
                $meanObliqEcliptic = 23.0 + ((26.0 + ((21.448 - ($julianCentury * (46.815 + ($julianCentury * (0.00059 - ($julianCentury * 0.001813))))) ) / 60.0)) / 60.0)
                $obliqCorr = $meanObliqEcliptic + (0.00256 * [Math]::Cos((ConvertTo-Radians -Degrees $omega)))
                $sunDeclination = ConvertTo-Degrees -Radians ([Math]::Asin([Math]::Sin((ConvertTo-Radians -Degrees $obliqCorr)) * [Math]::Sin((ConvertTo-Radians -Degrees $sunAppLong))))

                $vary = [Math]::Tan((ConvertTo-Radians -Degrees ($obliqCorr / 2.0)))
                $vary *= $vary
                $equationOfTime = 4.0 * (ConvertTo-Degrees -Radians (
                    ($vary * [Math]::Sin((2.0 * (ConvertTo-Radians -Degrees $geomMeanLongSun)))) -
                    (2.0 * $eccEarthOrbit * [Math]::Sin((ConvertTo-Radians -Degrees $geomMeanAnomSun))) +
                    (4.0 * $eccEarthOrbit * $vary * [Math]::Sin((ConvertTo-Radians -Degrees $geomMeanAnomSun)) * [Math]::Cos((2.0 * (ConvertTo-Radians -Degrees $geomMeanLongSun)))) -
                    (0.5 * $vary * $vary * [Math]::Sin((4.0 * (ConvertTo-Radians -Degrees $geomMeanLongSun)))) -
                    (1.25 * $eccEarthOrbit * $eccEarthOrbit * [Math]::Sin((2.0 * (ConvertTo-Radians -Degrees $geomMeanAnomSun))))
                ))

                $trueSolarTime = (($utc.Hour * 60.0) + $utc.Minute + ($utc.Second / 60.0) + $equationOfTime + (4.0 * $resolved.Longitude)) % 1440.0
                if ($trueSolarTime -lt 0.0) {
                    $trueSolarTime += 1440.0
                }

                if ($trueSolarTime / 4.0 -lt 0.0) {
                    $hourAngle = ($trueSolarTime / 4.0) + 180.0
                }
                else {
                    $hourAngle = ($trueSolarTime / 4.0) - 180.0
                }

                $latitudeRad = ConvertTo-Radians -Degrees $resolved.Latitude
                $declinationRad = ConvertTo-Radians -Degrees $sunDeclination
                $hourAngleRad = ConvertTo-Radians -Degrees $hourAngle

                $cosZenith = ([Math]::Sin($latitudeRad) * [Math]::Sin($declinationRad)) + ([Math]::Cos($latitudeRad) * [Math]::Cos($declinationRad) * [Math]::Cos($hourAngleRad))
                if ($cosZenith -gt 1.0) {
                    $cosZenith = 1.0
                }
                elseif ($cosZenith -lt -1.0) {
                    $cosZenith = -1.0
                }

                $zenith = ConvertTo-Degrees -Radians ([Math]::Acos($cosZenith))
                $altitude = 90.0 - $zenith

                $azimuthDenominator = [Math]::Cos($latitudeRad) * [Math]::Sin((ConvertTo-Radians -Degrees $zenith))
                if ([Math]::Abs($azimuthDenominator) -gt 0.001) {
                    $azimuthNumerator = (([Math]::Sin($latitudeRad) * [Math]::Cos((ConvertTo-Radians -Degrees $zenith))) - [Math]::Sin($declinationRad))
                    $azimuthArgument = $azimuthNumerator / $azimuthDenominator
                    if ($azimuthArgument -gt 1.0) {
                        $azimuthArgument = 1.0
                    }
                    elseif ($azimuthArgument -lt -1.0) {
                        $azimuthArgument = -1.0
                    }

                    $azimuth = 180.0 - (ConvertTo-Degrees -Radians ([Math]::Acos($azimuthArgument)))
                    if ($hourAngle -gt 0.0) {
                        $azimuth = 360.0 - $azimuth
                    }
                }
                else {
                    if ($resolved.Latitude -gt 0.0) {
                        $azimuth = 180.0
                    }
                    else {
                        $azimuth = 0.0
                    }
                }

                [pscustomobject]@{
                    PSTypeName = 'AetherScope.SunPosition'
                    Latitude = $resolved.Latitude
                    Longitude = $resolved.Longitude
                    DateTime = $DateTime
                    UtcDateTime = $utc
                    Azimuth = [Math]::Round((Normalize-Angle -Degrees $azimuth), 2)
                    Altitude = [Math]::Round($altitude, 2)
                    Zenith = [Math]::Round($zenith, 2)
                    Declination = [Math]::Round($sunDeclination, 4)
                    EquationOfTimeMinutes = [Math]::Round($equationOfTime, 4)
                    CoordinateSource = $resolved.Source
                }
            }
            catch {
                Write-Error ("Failed to calculate Sun position: {0}" -f $_.Exception.Message)
            }
        }
    }

    end {
    }
}



function Get-AetherScopeMoonPosition {
<#
.SYNOPSIS
Gets the approximate Moon altitude and azimuth for an observer location.
.DESCRIPTION
Calculates an approximate Moon position suitable for hobby tracking and general
observational use. Latitude and longitude can be supplied directly or through
Coordinate.
.PARAMETER Latitude
Latitude in decimal degrees.
.PARAMETER Longitude
Longitude in decimal degrees.
.PARAMETER Coordinate
Flexible coordinate input.
.PARAMETER DateTime
Date and time for the observation. Defaults to the current date and time.
.EXAMPLE
Get-AetherScopeMoonPosition -Latitude 30.2752 -Longitude -89.7812 -DateTime (Get-Date)
.EXAMPLE
Get-AetherScopeMoonPosition -Coordinate @{ Latitude = 30.2752; Longitude = -89.7812 } -WhatIf
.INPUTS
System.Object
.OUTPUTS
System.Management.Automation.PSCustomObject
.NOTES
This is an approximate implementation and is not a precision ephemeris.

.LINK
https://stjarnhimlen.se/comp/ppcomp.html
#>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([pscustomobject])]
    param(
        [Parameter()]
        [Nullable[Double]]$Latitude,

        [Parameter()]
        [Nullable[Double]]$Longitude,

        [Parameter(ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [AllowNull()]
        [Object]$Coordinate,

        [Parameter()]
        [datetime]$DateTime = (Get-Date)
    )

    begin {
    }

    process {
        $resolved = Resolve-AetherScopeCoordinate -Latitude $Latitude -Longitude $Longitude -Coordinate $Coordinate
        if ($null -eq $resolved) {
            return
        }

        if ($PSCmdlet.ShouldProcess(("Moon position for {0},{1}" -f $resolved.Latitude, $resolved.Longitude), 'Calculate lunar altitude and azimuth')) {
            try {
                $utc = $DateTime.ToUniversalTime()
                $jd = Get-JulianDate -DateTime $utc
                $d = $jd - 2451543.5

                $n = Normalize-Angle -Degrees (125.1228 - (0.0529538083 * $d))
                $i = 5.1454
                $w = Normalize-Angle -Degrees (318.0634 + (0.1643573223 * $d))
                $a = 60.2666
                $e = 0.0549
                $m = Normalize-Angle -Degrees (115.3654 + (13.0649929509 * $d))

                $mRad = ConvertTo-Radians -Degrees $m
                $eAnomaly = $m + (ConvertTo-Degrees -Radians ($e * [Math]::Sin($mRad) * (1.0 + ($e * [Math]::Cos($mRad)))))
                $eRad = ConvertTo-Radians -Degrees $eAnomaly

                $xv = $a * ([Math]::Cos($eRad) - $e)
                $yv = $a * ([Math]::Sqrt(1.0 - ($e * $e)) * [Math]::Sin($eRad))

                $v = ConvertTo-Degrees -Radians ([Math]::Atan2($yv, $xv))
                $r = [Math]::Sqrt(($xv * $xv) + ($yv * $yv))

                $nRad = ConvertTo-Radians -Degrees $n
                $iRad = ConvertTo-Radians -Degrees $i
                $vwRad = ConvertTo-Radians -Degrees ($v + $w)

                $xh = $r * (([Math]::Cos($nRad) * [Math]::Cos($vwRad)) - ([Math]::Sin($nRad) * [Math]::Sin($vwRad) * [Math]::Cos($iRad)))
                $yh = $r * (([Math]::Sin($nRad) * [Math]::Cos($vwRad)) + ([Math]::Cos($nRad) * [Math]::Sin($vwRad) * [Math]::Cos($iRad)))
                $zh = $r * ([Math]::Sin($vwRad) * [Math]::Sin($iRad))

                $ecl = 23.4393 - (3.563E-7 * $d)
                $eclRad = ConvertTo-Radians -Degrees $ecl

                $xe = $xh
                $ye = ($yh * [Math]::Cos($eclRad)) - ($zh * [Math]::Sin($eclRad))
                $ze = ($yh * [Math]::Sin($eclRad)) + ($zh * [Math]::Cos($eclRad))

                $rightAscension = Normalize-Angle -Degrees (ConvertTo-Degrees -Radians ([Math]::Atan2($ye, $xe)))
                $declination = ConvertTo-Degrees -Radians ([Math]::Atan2($ze, [Math]::Sqrt(($xe * $xe) + ($ye * $ye))))

                $lst = Get-LocalSiderealTime -DateTime $utc -Longitude $resolved.Longitude
                $hourAngle = Normalize-Angle -Degrees ($lst - $rightAscension)
                if ($hourAngle -gt 180.0) {
                    $hourAngle -= 360.0
                }

                $latitudeRad = ConvertTo-Radians -Degrees $resolved.Latitude
                $declinationRad = ConvertTo-Radians -Degrees $declination
                $hourAngleRad = ConvertTo-Radians -Degrees $hourAngle

                $altitude = ConvertTo-Degrees -Radians ([Math]::Asin(([Math]::Sin($declinationRad) * [Math]::Sin($latitudeRad)) + ([Math]::Cos($declinationRad) * [Math]::Cos($latitudeRad) * [Math]::Cos($hourAngleRad))))
                $azimuth = ConvertTo-Degrees -Radians ([Math]::Atan2([Math]::Sin($hourAngleRad), ([Math]::Cos($hourAngleRad) * [Math]::Sin($latitudeRad)) - ([Math]::Tan($declinationRad) * [Math]::Cos($latitudeRad))))
                $azimuth = Normalize-Angle -Degrees ($azimuth + 180.0)

                [pscustomobject]@{
                    PSTypeName = 'AetherScope.MoonPosition'
                    Latitude = $resolved.Latitude
                    Longitude = $resolved.Longitude
                    DateTime = $DateTime
                    UtcDateTime = $utc
                    Azimuth = [Math]::Round($azimuth, 2)
                    Altitude = [Math]::Round($altitude, 2)
                    RightAscension = [Math]::Round($rightAscension, 4)
                    Declination = [Math]::Round($declination, 4)
                    DistanceEarthRadii = [Math]::Round($r, 4)
                    CoordinateSource = $resolved.Source
                }
            }
            catch {
                Write-Error ("Failed to calculate Moon position: {0}" -f $_.Exception.Message)
            }
        }
    }

    end {
    }
}



function Invoke-WtiaRequest {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Uri
    )

    try {
        return Invoke-RestMethod -Uri $Uri -Method Get -ErrorAction Stop
    }
    catch {
        Write-Error ("Failed to call WTIA API: {0}" -f $_.Exception.Message)
        return $null
    }
}



function Get-AetherScopeIssCurrentPosition {
<#
.SYNOPSIS
Gets the current International Space Station location.
.DESCRIPTION
Queries the Where The ISS At API for the current ISS latitude, longitude,
altitude, velocity, and visibility. The result is normalized so it can be reused
by other functions.
.PARAMETER Raw
Returns the raw API response in addition to normalized output fields.
.EXAMPLE
Get-AetherScopeIssCurrentPosition
.EXAMPLE
Get-AetherScopeIssCurrentPosition -WhatIf
.INPUTS
None
.OUTPUTS
System.Management.Automation.PSCustomObject
.NOTES
Requires internet access.

.LINK
https://wheretheiss.at/w/developer
#>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([pscustomobject])]
    param(
        [Parameter()]
        [switch]$Raw
    )

    begin {
    }

    process {
        if ($PSCmdlet.ShouldProcess('ISS', 'Retrieve current position')) {
            $response = Invoke-WtiaRequest -Uri 'https://api.wheretheiss.at/v1/satellites/25544'
            if ($null -eq $response) {
                return
            }

            $output = [pscustomobject]@{
                PSTypeName = 'AetherScope.IssCurrentPosition'
                Name = $response.name
                Id = $response.id
                TimeStamp = [DateTimeOffset]::FromUnixTimeSeconds([Int64]$response.timestamp).UtcDateTime
                Latitude = [double]$response.latitude
                Longitude = [double]$response.longitude
                AltitudeKm = [double]$response.altitude
                VelocityKmH = [double]$response.velocity
                Visibility = $response.visibility
                FootprintKm = [double]$response.footprint
                SolarLatitude = [double]$response.solar_lat
                SolarLongitude = [double]$response.solar_lon
                Units = 'kilometers'
            }

            if ($Raw) {
                $output | Add-Member -MemberType NoteProperty -Name RawResponse -Value $response
            }

            $output
        }
    }

    end {
    }
}



function Get-AetherScopeIssPositionSeries {
<#
.SYNOPSIS
Gets ISS positions for one or more timestamps.
.DESCRIPTION
Queries the Where The ISS At API for multiple timestamps and returns normalized
ISS position objects. Requests are batched in groups of up to 10 timestamps.
.PARAMETER Timestamp
One or more timestamps to query.
.EXAMPLE
$times = @((Get-Date).ToUniversalTime(), (Get-Date).ToUniversalTime().AddMinutes(5))
Get-AetherScopeIssPositionSeries -Timestamp $times
.EXAMPLE
$times | Get-AetherScopeIssPositionSeries -WhatIf
.INPUTS
System.DateTime
.OUTPUTS
System.Management.Automation.PSCustomObject
.NOTES
Requires internet access.

.LINK
https://wheretheiss.at/w/developer
#>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [datetime[]]$Timestamp
    )

    begin {
        $allTimestamps = New-Object System.Collections.Generic.List[datetime]
    }

    process {
        foreach ($item in $Timestamp) {
            $allTimestamps.Add($item.ToUniversalTime())
        }
    }

    end {
        if ($allTimestamps.Count -eq 0) {
            return
        }

        if (-not $PSCmdlet.ShouldProcess('ISS', ("Retrieve position series for {0} timestamp(s)" -f $allTimestamps.Count))) {
            return
        }

        $index = 0
        while ($index -lt $allTimestamps.Count) {
            $batch = $allTimestamps[$index..([Math]::Min($index + 9, $allTimestamps.Count - 1))]
            $unixTimes = @()
            foreach ($ts in $batch) {
                $dto = New-Object System.DateTimeOffset($ts)
                $unixTimes += [string]$dto.ToUnixTimeSeconds()
            }

            $uri = 'https://api.wheretheiss.at/v1/satellites/25544/positions?timestamps={0}&units=kilometers' -f ($unixTimes -join ',')
            $response = Invoke-WtiaRequest -Uri $uri
            if ($null -eq $response) {
                $index += 10
                continue
            }

            foreach ($item in $response) {
                [pscustomobject]@{
                    PSTypeName = 'AetherScope.IssPosition'
                    Name = $item.name
                    Id = $item.id
                    TimeStamp = [DateTimeOffset]::FromUnixTimeSeconds([Int64]$item.timestamp).UtcDateTime
                    Latitude = [double]$item.latitude
                    Longitude = [double]$item.longitude
                    AltitudeKm = [double]$item.altitude
                    VelocityKmH = [double]$item.velocity
                    Visibility = $item.visibility
                    FootprintKm = [double]$item.footprint
                    Units = 'kilometers'
                }
            }

            $index += 10
        }
    }
}



function Get-AetherScopeIssObserverPosition {
<#
.SYNOPSIS
Gets the observer-relative ISS altitude and azimuth.
.DESCRIPTION
Uses the current ISS position and converts it into local look angles for an
observer at the supplied location.
.PARAMETER Latitude
Observer latitude in decimal degrees.
.PARAMETER Longitude
Observer longitude in decimal degrees.
.PARAMETER Coordinate
Flexible observer coordinate input.
.PARAMETER ObserverAltitudeKm
Observer altitude above mean Earth radius in kilometers. Defaults to zero.
.EXAMPLE
Get-AetherScopeIssObserverPosition -Latitude 30.2752 -Longitude -89.7812
.EXAMPLE
Get-AetherScopeIssObserverPosition -Coordinate '30.2752,-89.7812' -WhatIf
.INPUTS
System.Object
.OUTPUTS
System.Management.Automation.PSCustomObject
.NOTES
Uses a spherical Earth approximation.

.LINK
https://wheretheiss.at/w/developer
#>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([pscustomobject])]
    param(
        [Parameter()]
        [Nullable[Double]]$Latitude,

        [Parameter()]
        [Nullable[Double]]$Longitude,

        [Parameter(ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [AllowNull()]
        [Object]$Coordinate,

        [Parameter()]
        [double]$ObserverAltitudeKm = 0.0
    )

    begin {
    }

    process {
        $resolved = Resolve-AetherScopeCoordinate -Latitude $Latitude -Longitude $Longitude -Coordinate $Coordinate
        if ($null -eq $resolved) {
            return
        }

        if ($PSCmdlet.ShouldProcess(("ISS from {0},{1}" -f $resolved.Latitude, $resolved.Longitude), 'Calculate current ISS look angles')) {
            $iss = Get-AetherScopeIssCurrentPosition
            if ($null -eq $iss) {
                return
            }

            $look = Get-LookAngles -ObserverLatitude $resolved.Latitude -ObserverLongitude $resolved.Longitude -ObserverAltitudeKm $ObserverAltitudeKm -TargetLatitude $iss.Latitude -TargetLongitude $iss.Longitude -TargetAltitudeKm $iss.AltitudeKm

            [pscustomobject]@{
                PSTypeName = 'AetherScope.IssObserverPosition'
                ObserverLatitude = $resolved.Latitude
                ObserverLongitude = $resolved.Longitude
                ObserverAltitudeKm = $ObserverAltitudeKm
                TimeStamp = $iss.TimeStamp
                IssLatitude = $iss.Latitude
                IssLongitude = $iss.Longitude
                IssAltitudeKm = $iss.AltitudeKm
                IssVelocityKmH = $iss.VelocityKmH
                Visibility = $iss.Visibility
                Azimuth = [Math]::Round($look.Azimuth, 2)
                Altitude = [Math]::Round($look.Altitude, 2)
                RangeKm = [Math]::Round($look.RangeKm, 2)
                IsAboveHorizon = $look.IsAboveHorizon
                CoordinateSource = $resolved.Source
            }
        }
    }

    end {
    }
}



function Get-AetherScopeIssPassPrediction {
<#
.SYNOPSIS
Predicts upcoming ISS passes for an observer location.
.DESCRIPTION
Samples ISS positions across a future time window and estimates when the ISS
rises above the horizon, reaches maximum altitude, and sets below the horizon
for the observer. This is an approximation based on a configurable sampling
interval.
.PARAMETER Latitude
Observer latitude in decimal degrees.
.PARAMETER Longitude
Observer longitude in decimal degrees.
.PARAMETER Coordinate
Flexible observer coordinate input.
.PARAMETER StartTime
Start of the prediction window. Defaults to the current time.
.PARAMETER DurationHours
Length of the prediction window in hours.
.PARAMETER IntervalSeconds
Sampling interval in seconds. Smaller values improve accuracy but increase API
calls.
.PARAMETER ObserverAltitudeKm
Observer altitude above mean Earth radius in kilometers.
.PARAMETER MaxResults
Maximum number of passes to return.
.EXAMPLE
Get-AetherScopeIssPassPrediction -Latitude 30.2752 -Longitude -89.7812 -DurationHours 12
.EXAMPLE
Get-AetherScopeIssPassPrediction -Coordinate '30.2752,-89.7812' -IntervalSeconds 30 -WhatIf
.INPUTS
System.Object
.OUTPUTS
System.Management.Automation.PSCustomObject
.NOTES
Builds pass boundaries from sampled ISS positions returned by the WTIA API and
uses simple linear interpolation near threshold crossings to refine rise/set
timing. This is a planning-oriented estimator rather than a full orbital
propagator.

.LINK
https://wheretheiss.at/w/developer
#>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([pscustomobject])]
    param(
        [Parameter()]
        [Nullable[Double]]$Latitude,

        [Parameter()]
        [Nullable[Double]]$Longitude,

        [Parameter(ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [AllowNull()]
        [Object]$Coordinate,

        [Parameter()]
        [datetime]$StartTime = (Get-Date),

        [Parameter()]
        [ValidateRange(1, 48)]
        [int]$DurationHours = 12,

        [Parameter()]
        [ValidateRange(10, 600)]
        [int]$IntervalSeconds = 60,

        [Parameter()]
        [double]$ObserverAltitudeKm = 0.0,

        [Parameter()]
        [ValidateRange(1, 20)]
        [int]$MaxResults = 5
    )

    begin {
    }

    process {
        $resolved = Resolve-AetherScopeCoordinate -Latitude $Latitude -Longitude $Longitude -Coordinate $Coordinate
        if ($null -eq $resolved) {
            return
        }

        if (-not $PSCmdlet.ShouldProcess(("ISS pass prediction for {0},{1}" -f $resolved.Latitude, $resolved.Longitude), 'Estimate upcoming passes')) {
            return
        }

        try {
            $startUtc = $StartTime.ToUniversalTime()
            $endUtc = $startUtc.AddHours($DurationHours)
            $times = New-Object System.Collections.Generic.List[datetime]
            $cursor = $startUtc
            while ($cursor -le $endUtc) {
                $times.Add($cursor)
                $cursor = $cursor.AddSeconds($IntervalSeconds)
            }

            $samples = @()
            $positionSeries = Get-AetherScopeIssPositionSeries -Timestamp $times
            foreach ($position in $positionSeries) {
                $look = Get-LookAngles -ObserverLatitude $resolved.Latitude -ObserverLongitude $resolved.Longitude -ObserverAltitudeKm $ObserverAltitudeKm -TargetLatitude $position.Latitude -TargetLongitude $position.Longitude -TargetAltitudeKm $position.AltitudeKm
                $samples += [pscustomobject]@{
                    TimeStamp = $position.TimeStamp
                    IssLatitude = $position.Latitude
                    IssLongitude = $position.Longitude
                    IssAltitudeKm = $position.AltitudeKm
                    Visibility = $position.Visibility
                    Azimuth = $look.Azimuth
                    Altitude = $look.Altitude
                    RangeKm = $look.RangeKm
                    IsAboveHorizon = $look.IsAboveHorizon
                }
            }

            if ($samples.Count -eq 0) {
                return
            }

            $passes = New-Object System.Collections.Generic.List[object]
            $currentPass = $null
            $previousSample = $null
            foreach ($sample in $samples) {
                if ($sample.IsAboveHorizon) {
                    if ($null -eq $currentPass) {
                        $riseTime = $sample.TimeStamp
                        $riseAzimuth = $sample.Azimuth
                        if (($null -ne $previousSample) -and (-not $previousSample.IsAboveHorizon)) {
                            $riseCrossing = Get-InterpolatedThresholdCrossing -BeforeSample $previousSample -AfterSample $sample -Threshold 0.0
                            if ($null -ne $riseCrossing) {
                                $riseTime = $riseCrossing.TimeStamp
                                $riseAzimuth = $riseCrossing.Azimuth
                            }
                        }

                        $currentPass = [ordered]@{
                            RiseTime = $riseTime
                            RiseAzimuth = $riseAzimuth
                            MaxTime = $sample.TimeStamp
                            MaxAltitude = $sample.Altitude
                            MaxAzimuth = $sample.Azimuth
                            SetTime = $null
                            SetAzimuth = $null
                            VisibilityAtMax = $sample.Visibility
                        }
                    }

                    if ($sample.Altitude -gt $currentPass.MaxAltitude) {
                        $currentPass.MaxAltitude = $sample.Altitude
                        $currentPass.MaxTime = $sample.TimeStamp
                        $currentPass.MaxAzimuth = $sample.Azimuth
                        $currentPass.VisibilityAtMax = $sample.Visibility
                    }
                }
                else {
                    if ($null -ne $currentPass) {
                        $setTime = $sample.TimeStamp
                        $setAzimuth = $sample.Azimuth
                        if ($null -ne $previousSample) {
                            $setCrossing = Get-InterpolatedThresholdCrossing -BeforeSample $previousSample -AfterSample $sample -Threshold 0.0
                            if ($null -ne $setCrossing) {
                                $setTime = $setCrossing.TimeStamp
                                $setAzimuth = $setCrossing.Azimuth
                            }
                        }

                        $passes.Add([pscustomobject]@{
                            PSTypeName = 'AetherScope.IssPass'
                            ObserverLatitude = $resolved.Latitude
                            ObserverLongitude = $resolved.Longitude
                            ObserverAltitudeKm = $ObserverAltitudeKm
                            RiseTime = $currentPass.RiseTime
                            RiseAzimuth = [Math]::Round($currentPass.RiseAzimuth, 2)
                            MaxTime = $currentPass.MaxTime
                            MaxAltitude = [Math]::Round($currentPass.MaxAltitude, 2)
                            MaxAzimuth = [Math]::Round($currentPass.MaxAzimuth, 2)
                            SetTime = $setTime
                            SetAzimuth = [Math]::Round($setAzimuth, 2)
                            VisibilityAtMax = $currentPass.VisibilityAtMax
                            CoordinateSource = $resolved.Source
                            SampleIntervalSeconds = $IntervalSeconds
                        })

                        $currentPass = $null
                    }
                }

                $previousSample = $sample
            }

            if (($null -ne $currentPass) -and ($passes.Count -lt $MaxResults)) {
                $passes.Add([pscustomobject]@{
                    PSTypeName = 'AetherScope.IssPass'
                    ObserverLatitude = $resolved.Latitude
                    ObserverLongitude = $resolved.Longitude
                    ObserverAltitudeKm = $ObserverAltitudeKm
                    RiseTime = $currentPass.RiseTime
                    RiseAzimuth = [Math]::Round($currentPass.RiseAzimuth, 2)
                    MaxTime = $currentPass.MaxTime
                    MaxAltitude = [Math]::Round($currentPass.MaxAltitude, 2)
                    MaxAzimuth = [Math]::Round($currentPass.MaxAzimuth, 2)
                    SetTime = $null
                    SetAzimuth = $null
                    VisibilityAtMax = $currentPass.VisibilityAtMax
                    CoordinateSource = $resolved.Source
                    SampleIntervalSeconds = $IntervalSeconds
                })
            }

            $passes | Select-Object -First $MaxResults
        }
        catch {
            Write-Error ("Failed to predict ISS passes: {0}" -f $_.Exception.Message)
        }
    }

    end {
    }
}



function Get-AetherScopeGpsCoordinate {
<#
.SYNOPSIS
Reads GPS coordinates from NMEA input, a text file, or a serial port.
.DESCRIPTION
Provides a GPS-friendly ingestion layer that emits normalized coordinate objects
compatible with Resolve-AetherScopeCoordinate and the astronomy functions in this
script. This function is designed to make it easy to plug live GPS devices into
Sun, Moon, and ISS tracking workflows.
.PARAMETER NmeaSentence
One or more raw NMEA sentences to parse.
.PARAMETER Path
Path to a text file containing NMEA sentences. The function reads lines from the
file and returns the parsed coordinate fixes.
.PARAMETER PortName
Serial port name, such as COM3, used to read live NMEA data from a GPS receiver.
.PARAMETER BaudRate
Serial port baud rate. Defaults to 4800, which is common for NMEA devices.
.PARAMETER ReadCount
Maximum number of valid coordinate fixes to return from a file or serial port.
.PARAMETER TimeoutSeconds
Maximum number of seconds to wait for serial data before stopping.
.PARAMETER IncludeRaw
Includes the raw NMEA sentence in the output objects.
.EXAMPLE
Get-AetherScopeGpsCoordinate -NmeaSentence '$GPGGA,123519,3016.512,N,08946.866,W,1,08,0.9,0.0,M,0.0,M,,*00'
.EXAMPLE
Get-AetherScopeGpsCoordinate -Path .\gps.log -ReadCount 5 -WhatIf
.EXAMPLE
Get-AetherScopeGpsCoordinate -PortName COM3 -BaudRate 4800 -ReadCount 3 -TimeoutSeconds 30
.INPUTS
System.String
.OUTPUTS
System.Management.Automation.PSCustomObject
.NOTES
Normalizes GPS fixes from raw NMEA sentences, text sources, or serial devices
into a common coordinate object. The parser expects standard NMEA 0183 field
layouts such as GGA and RMC, as documented in the linked references. Serial
port access uses System.IO.Ports.SerialPort, which is available in Windows
PowerShell 5.1 on supported Windows systems.

.LINK
https://gpsd.gitlab.io/gpsd/NMEA.html
.LINK
https://www.serialmon.com/protocols/nmea0183.shtml
#>
    [CmdletBinding(SupportsShouldProcess = $true, DefaultParameterSetName = 'Sentence')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'Sentence', ValueFromPipeline = $true)]
        [string[]]$NmeaSentence,

        [Parameter(Mandatory = $true, ParameterSetName = 'File')]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter(Mandatory = $true, ParameterSetName = 'Serial')]
        [ValidateNotNullOrEmpty()]
        [string]$PortName,

        [Parameter(ParameterSetName = 'Serial')]
        [ValidateRange(110, 115200)]
        [int]$BaudRate = 4800,

        [Parameter(ParameterSetName = 'File')]
        [Parameter(ParameterSetName = 'Serial')]
        [ValidateRange(1, 100000)]
        [int]$ReadCount = 1,

        [Parameter(ParameterSetName = 'Serial')]
        [ValidateRange(1, 3600)]
        [int]$TimeoutSeconds = 30,

        [Parameter()]
        [switch]$IncludeRaw
    )

    begin {
        $resultsReturned = 0
    }

    process {
        switch ($PSCmdlet.ParameterSetName) {
            'Sentence' {
                foreach ($sentence in $NmeaSentence) {
                    if (-not $PSCmdlet.ShouldProcess($sentence, 'Parse GPS NMEA sentence')) {
                        continue
                    }

                    $parsed = ConvertFrom-NmeaSentence -Sentence $sentence
                    if ($null -eq $parsed) {
                        continue
                    }

                    $outputObject = [ordered]@{
                        PSTypeName = 'AetherScope.GpsCoordinate'
                        Latitude = [double]$parsed.Latitude
                        Longitude = [double]$parsed.Longitude
                        Source = 'NmeaSentence'
                        MessageType = $parsed.MessageType
                        FixTimeRaw = $parsed.FixTimeRaw
                        FixQuality = $parsed.FixQuality
                        SatelliteCount = $parsed.SatelliteCount
                    }

                    if ($IncludeRaw.IsPresent) {
                        $outputObject.RawSentence = $sentence
                    }

                    [pscustomobject]$outputObject
                }
            }

            'File' {
                try {
                    $resolvedPath = Resolve-Path -Path $Path -ErrorAction Stop
                    if (-not $PSCmdlet.ShouldProcess($resolvedPath.Path, 'Read GPS coordinates from file')) {
                        return
                    }

                    foreach ($line in [System.IO.File]::ReadLines($resolvedPath.Path)) {
                        if ([string]::IsNullOrWhiteSpace($line)) {
                            continue
                        }

                        $trimmedLine = $line.Trim()
                        if (-not $trimmedLine.StartsWith('$')) {
                            continue
                        }

                        $parsed = ConvertFrom-NmeaSentence -Sentence $trimmedLine
                        if ($null -eq $parsed) {
                            continue
                        }

                        $outputObject = [ordered]@{
                            PSTypeName = 'AetherScope.GpsCoordinate'
                            Latitude = [double]$parsed.Latitude
                            Longitude = [double]$parsed.Longitude
                            Source = 'File'
                            MessageType = $parsed.MessageType
                            FixTimeRaw = $parsed.FixTimeRaw
                            FixQuality = $parsed.FixQuality
                            SatelliteCount = $parsed.SatelliteCount
                            Path = $resolvedPath.Path
                        }

                        if ($IncludeRaw.IsPresent) {
                            $outputObject.RawSentence = $trimmedLine
                        }

                        [pscustomobject]$outputObject
                        $resultsReturned += 1
                        if ($resultsReturned -ge $ReadCount) {
                            break
                        }
                    }
                }
                catch {
                    Write-Error ("Failed to read GPS coordinates from file '{0}': {1}" -f $Path, $_.Exception.Message)
                }
            }

            'Serial' {
                $serialPort = $null
                try {
                    if (-not $PSCmdlet.ShouldProcess($PortName, 'Read GPS coordinates from serial port')) {
                        return
                    }

                    $serialPort = New-Object System.IO.Ports.SerialPort $PortName, $BaudRate, ([System.IO.Ports.Parity]::None), 8, ([System.IO.Ports.StopBits]::One)
                    $serialPort.NewLine = "`r`n"
                    $serialPort.ReadTimeout = 1000
                    $serialPort.Open()

                    $stopAt = (Get-Date).AddSeconds($TimeoutSeconds)
                    while (((Get-Date) -lt $stopAt) -and ($resultsReturned -lt $ReadCount)) {
                        try {
                            $line = $serialPort.ReadLine()
                        }
                        catch [System.TimeoutException] {
                            continue
                        }

                        if ([string]::IsNullOrWhiteSpace($line)) {
                            continue
                        }

                        $trimmedLine = $line.Trim()
                        if (-not $trimmedLine.StartsWith('$')) {
                            continue
                        }

                        $parsed = ConvertFrom-NmeaSentence -Sentence $trimmedLine
                        if ($null -eq $parsed) {
                            continue
                        }

                        $outputObject = [ordered]@{
                            PSTypeName = 'AetherScope.GpsCoordinate'
                            Latitude = [double]$parsed.Latitude
                            Longitude = [double]$parsed.Longitude
                            Source = 'SerialPort'
                            MessageType = $parsed.MessageType
                            FixTimeRaw = $parsed.FixTimeRaw
                            FixQuality = $parsed.FixQuality
                            SatelliteCount = $parsed.SatelliteCount
                            PortName = $PortName
                            BaudRate = $BaudRate
                        }

                        if ($IncludeRaw.IsPresent) {
                            $outputObject.RawSentence = $trimmedLine
                        }

                        [pscustomobject]$outputObject
                        $resultsReturned += 1
                    }
                }
                catch {
                    Write-Error ("Failed to read GPS coordinates from serial port '{0}': {1}" -f $PortName, $_.Exception.Message)
                }
                finally {
                    if (($null -ne $serialPort) -and $serialPort.IsOpen) {
                        $serialPort.Close()
                        $serialPort.Dispose()
                    }
                }
            }
        }
    }

    end {
    }
}



function Get-AetherScopeIssRadioVisibility {
<#
.SYNOPSIS
Tests whether the ISS should be receivable by radio from an observer location at a given date and time.
.DESCRIPTION
Calculates the ISS look angles for a specific observer and timestamp, then
returns a practical radio-visibility assessment. At minimum, the ISS must be
above the observer horizon for line-of-sight reception. A higher minimum
elevation threshold is often more realistic for usable reception, so this
function exposes both values.
.PARAMETER Latitude
Observer latitude in decimal degrees.
.PARAMETER Longitude
Observer longitude in decimal degrees.
.PARAMETER Coordinate
Flexible observer coordinate input.
.PARAMETER DateTime
Date and time to test. Defaults to the current date and time.
.PARAMETER ObserverAltitudeKm
Observer altitude in kilometers.
.PARAMETER MinAltitudeDegrees
Minimum elevation angle to consider the ISS practically receivable.
.PARAMETER DownlinkFrequencyMHz
Optional ISS downlink frequency in MHz used for approximate Doppler estimation.
.PARAMETER SampleOffsetSeconds
Number of seconds on either side of DateTime used to estimate radial motion for
Doppler shift calculations.
.EXAMPLE
Get-AetherScopeIssRadioVisibility -Coordinate '30.2752,-89.7812' -DateTime (Get-Date)
.EXAMPLE
Get-AetherScopeIssRadioVisibility -Coordinate '30.2752,-89.7812' -DateTime '2026-03-29T19:30:00' -MinAltitudeDegrees 10 -DownlinkFrequencyMHz 145.800 -WhatIf
.INPUTS
System.Object
.OUTPUTS
System.Management.Automation.PSCustomObject
.NOTES
This function answers the line-of-sight part of the radio question. Actual
reception still depends on ISS radio mode, antenna setup, polarization, local
interference, and Doppler correction.

.LINK
https://wheretheiss.at/w/developer
#>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([pscustomobject])]
    param(
        [Parameter()]
        [Nullable[Double]]$Latitude,

        [Parameter()]
        [Nullable[Double]]$Longitude,

        [Parameter(ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [AllowNull()]
        [Object]$Coordinate,

        [Parameter()]
        [datetime]$DateTime = (Get-Date),

        [Parameter()]
        [double]$ObserverAltitudeKm = 0.0,

        [Parameter()]
        [ValidateRange(0, 90)]
        [double]$MinAltitudeDegrees = 10.0,

        [Parameter()]
        [ValidateRange(0.0, 10000.0)]
        [double]$DownlinkFrequencyMHz = 0.0,

        [Parameter()]
        [ValidateRange(1, 300)]
        [int]$SampleOffsetSeconds = 5
    )

    begin {
    }

    process {
        try {
            $resolved = Resolve-AetherScopeCoordinate -Latitude $Latitude -Longitude $Longitude -Coordinate $Coordinate
            if ($null -eq $resolved) {
                return
            }

            if (-not $PSCmdlet.ShouldProcess(("ISS radio visibility for {0},{1} at {2}" -f $resolved.Latitude, $resolved.Longitude, $DateTime), 'Evaluate ISS radio line of sight')) {
                return
            }

            $timestamps = @(
                $DateTime.ToUniversalTime().AddSeconds(-1 * $SampleOffsetSeconds),
                $DateTime.ToUniversalTime(),
                $DateTime.ToUniversalTime().AddSeconds($SampleOffsetSeconds)
            )

            $positions = @(Get-AetherScopeIssPositionSeries -Timestamp $timestamps)
            if ($positions.Count -lt 1) {
                return
            }

            $currentPosition = $null
            foreach ($position in $positions) {
                if ($position.TimeStamp -eq $timestamps[1]) {
                    $currentPosition = $position
                    break
                }
            }
            if ($null -eq $currentPosition) {
                $currentPosition = $positions | Select-Object -First 1
            }

            $look = Get-LookAngles -ObserverLatitude $resolved.Latitude -ObserverLongitude $resolved.Longitude -ObserverAltitudeKm $ObserverAltitudeKm -TargetLatitude $currentPosition.Latitude -TargetLongitude $currentPosition.Longitude -TargetAltitudeKm $currentPosition.AltitudeKm

            $dopplerHz = $null
            $relativeVelocityKmPerSec = $null
            if (($DownlinkFrequencyMHz -gt 0.0) -and ($positions.Count -ge 3)) {
                $lookBefore = Get-LookAngles -ObserverLatitude $resolved.Latitude -ObserverLongitude $resolved.Longitude -ObserverAltitudeKm $ObserverAltitudeKm -TargetLatitude $positions[0].Latitude -TargetLongitude $positions[0].Longitude -TargetAltitudeKm $positions[0].AltitudeKm
                $lookAfter = Get-LookAngles -ObserverLatitude $resolved.Latitude -ObserverLongitude $resolved.Longitude -ObserverAltitudeKm $ObserverAltitudeKm -TargetLatitude $positions[2].Latitude -TargetLongitude $positions[2].Longitude -TargetAltitudeKm $positions[2].AltitudeKm
                $deltaRangeKm = $lookAfter.RangeKm - $lookBefore.RangeKm
                $deltaSeconds = ($timestamps[2] - $timestamps[0]).TotalSeconds
                if ($deltaSeconds -gt 0.0) {
                    $relativeVelocityKmPerSec = $deltaRangeKm / $deltaSeconds
                    $speedOfLightKmPerSec = 299792.458
                    $dopplerHz = -1.0 * (($relativeVelocityKmPerSec / $speedOfLightKmPerSec) * ($DownlinkFrequencyMHz * 1000000.0))
                }
            }

            $downlinkFrequencyValue = $null
            if ($DownlinkFrequencyMHz -gt 0.0) {
                $downlinkFrequencyValue = $DownlinkFrequencyMHz
            }

            $dopplerShiftRounded = $null
            if ($null -ne $dopplerHz) {
                $dopplerShiftRounded = [Math]::Round($dopplerHz, 0)
            }

            [pscustomobject]@{
                PSTypeName = 'AetherScope.IssRadioVisibility'
                ObserverLatitude = $resolved.Latitude
                ObserverLongitude = $resolved.Longitude
                ObserverAltitudeKm = $ObserverAltitudeKm
                DateTime = $DateTime
                UtcDateTime = $DateTime.ToUniversalTime()
                IssLatitude = $currentPosition.Latitude
                IssLongitude = $currentPosition.Longitude
                IssAltitudeKm = $currentPosition.AltitudeKm
                IssVisibility = $currentPosition.Visibility
                Azimuth = [Math]::Round($look.Azimuth, 2)
                Altitude = [Math]::Round($look.Altitude, 2)
                RangeKm = [Math]::Round($look.RangeKm, 2)
                IsLineOfSight = [bool]($look.Altitude -ge 0.0)
                MeetsMinAltitude = [bool]($look.Altitude -ge $MinAltitudeDegrees)
                MinAltitudeDegrees = $MinAltitudeDegrees
                ShouldBeReceivable = [bool]($look.Altitude -ge $MinAltitudeDegrees)
                RecommendedMinAltitudeDegrees = 10.0
                ApproximateRadialVelocityKmPerSec = $relativeVelocityKmPerSec
                DownlinkFrequencyMHz = $downlinkFrequencyValue
                ApproximateDopplerShiftHz = $dopplerShiftRounded
                CoordinateSource = $resolved.Source
            }
        }
        catch {
            Write-Error ("Failed to evaluate ISS radio visibility: {0}" -f $_.Exception.Message)
        }
    }

    end {
    }
}



function Get-AetherScopeIssRadioWindow {
<#
.SYNOPSIS
Finds windows when the ISS should be receivable from an observer location.
.DESCRIPTION
Scans a future or historical time window, evaluates ISS line-of-sight and
minimum elevation threshold, and returns radio windows with start, peak, and end
times. This is useful when planning receive sessions.
.PARAMETER Latitude
Observer latitude in decimal degrees.
.PARAMETER Longitude
Observer longitude in decimal degrees.
.PARAMETER Coordinate
Flexible observer coordinate input.
.PARAMETER StartTime
Beginning of the scan window.
.PARAMETER DurationHours
Length of the scan window in hours.
.PARAMETER IntervalSeconds
Sampling interval in seconds.
.PARAMETER ObserverAltitudeKm
Observer altitude in kilometers.
.PARAMETER MinAltitudeDegrees
Minimum altitude threshold for practical reception.
.PARAMETER MinWindowMinutes
Minimum window length in minutes to return.
.PARAMETER DownlinkFrequencyMHz
Optional downlink frequency for approximate Doppler estimates at peak.
.PARAMETER MaxResults
Maximum number of windows to return.
.EXAMPLE
Get-AetherScopeIssRadioWindow -Coordinate '30.2752,-89.7812' -StartTime (Get-Date) -DurationHours 12
.EXAMPLE
Get-AetherScopeIssRadioWindow -Coordinate '30.2752,-89.7812' -DurationHours 24 -MinAltitudeDegrees 10 -WhatIf
.INPUTS
System.Object
.OUTPUTS
System.Management.Automation.PSCustomObject
.NOTES
Uses sampled ISS look-angle data derived from WTIA positions and the shared
threshold-crossing logic to find radio-usable windows. Optional Doppler output
is an operational aid layered on top of the geometry scan.

.LINK
https://wheretheiss.at/w/developer
#>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([pscustomobject])]
    param(
        [Parameter()]
        [Nullable[Double]]$Latitude,

        [Parameter()]
        [Nullable[Double]]$Longitude,

        [Parameter(ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [AllowNull()]
        [Object]$Coordinate,

        [Parameter()]
        [datetime]$StartTime = (Get-Date),

        [Parameter()]
        [ValidateRange(1, 72)]
        [int]$DurationHours = 12,

        [Parameter()]
        [ValidateRange(5, 600)]
        [int]$IntervalSeconds = 30,

        [Parameter()]
        [double]$ObserverAltitudeKm = 0.0,

        [Parameter()]
        [ValidateRange(0, 90)]
        [double]$MinAltitudeDegrees = 10.0,

        [Parameter()]
        [ValidateRange(0, 180)]
        [double]$MinWindowMinutes = 0.0,

        [Parameter()]
        [ValidateRange(0.0, 10000.0)]
        [double]$DownlinkFrequencyMHz = 0.0,

        [Parameter()]
        [ValidateRange(1, 50)]
        [int]$MaxResults = 10
    )

    begin {
    }

    process {
        try {
            $resolved = Resolve-AetherScopeCoordinate -Latitude $Latitude -Longitude $Longitude -Coordinate $Coordinate
            if ($null -eq $resolved) {
                return
            }

            if (-not $PSCmdlet.ShouldProcess(("ISS radio window for {0},{1}" -f $resolved.Latitude, $resolved.Longitude), 'Scan receivable ISS windows')) {
                return
            }

            $startUtc = $StartTime.ToUniversalTime()
            $endUtc = $startUtc.AddHours($DurationHours)
            $times = New-Object System.Collections.Generic.List[datetime]
            $cursor = $startUtc
            while ($cursor -le $endUtc) {
                $times.Add($cursor)
                $cursor = $cursor.AddSeconds($IntervalSeconds)
            }

            $positions = @(Get-AetherScopeIssPositionSeries -Timestamp $times)
            if ($positions.Count -eq 0) {
                return
            }

            $samples = @()
            foreach ($position in $positions) {
                $sample = Get-IssLookAngleSample -ResolvedCoordinate $resolved -IssPosition $position -ObserverAltitudeKm $ObserverAltitudeKm
                if ($null -ne $sample) {
                    $sample | Add-Member -MemberType NoteProperty -Name MeetsThreshold -Value ([bool]($sample.Altitude -ge $MinAltitudeDegrees))
                    $samples += $sample
                }
            }

            if ($samples.Count -eq 0) {
                return
            }

            $windows = New-Object System.Collections.Generic.List[object]
            $currentWindow = $null
            for ($i = 0; $i -lt $samples.Count; $i++) {
                $sample = $samples[$i]
                $previous = $null
                if ($i -gt 0) {
                    $previous = $samples[$i - 1]
                }

                if ($sample.MeetsThreshold) {
                    if ($null -eq $currentWindow) {
                        $windowStart = $sample.TimeStamp
                        $windowAzimuth = $sample.Azimuth
                        if (($null -ne $previous) -and (-not $previous.MeetsThreshold)) {
                            $crossing = Get-InterpolatedThresholdCrossing -BeforeSample $previous -AfterSample $sample -Threshold $MinAltitudeDegrees
                            if ($null -ne $crossing) {
                                $windowStart = $crossing.TimeStamp
                                $windowAzimuth = $crossing.Azimuth
                            }
                        }

                        $currentWindow = [ordered]@{
                            StartTime = $windowStart
                            StartAzimuth = $windowAzimuth
                            PeakTime = $sample.TimeStamp
                            PeakAzimuth = $sample.Azimuth
                            PeakAltitude = $sample.Altitude
                            EndTime = $null
                            EndAzimuth = $null
                            PeakVisibility = $sample.Visibility
                            PeakRangeKm = $sample.RangeKm
                        }
                    }

                    if ($sample.Altitude -gt $currentWindow.PeakAltitude) {
                        $currentWindow.PeakTime = $sample.TimeStamp
                        $currentWindow.PeakAzimuth = $sample.Azimuth
                        $currentWindow.PeakAltitude = $sample.Altitude
                        $currentWindow.PeakVisibility = $sample.Visibility
                        $currentWindow.PeakRangeKm = $sample.RangeKm
                    }
                }
                else {
                    if ($null -ne $currentWindow) {
                        $windowEnd = $sample.TimeStamp
                        $windowAzimuth = $sample.Azimuth
                        if ($null -ne $previous) {
                            $crossing = Get-InterpolatedThresholdCrossing -BeforeSample $previous -AfterSample $sample -Threshold $MinAltitudeDegrees
                            if ($null -ne $crossing) {
                                $windowEnd = $crossing.TimeStamp
                                $windowAzimuth = $crossing.Azimuth
                            }
                        }

                        $durationMinutes = ($windowEnd - $currentWindow.StartTime).TotalMinutes
                        if ($durationMinutes -ge $MinWindowMinutes) {
                            $peakDoppler = $null
                            if ($DownlinkFrequencyMHz -gt 0.0) {
                                $peakVisibility = Get-AetherScopeIssRadioVisibility -Latitude $resolved.Latitude -Longitude $resolved.Longitude -DateTime $currentWindow.PeakTime -ObserverAltitudeKm $ObserverAltitudeKm -MinAltitudeDegrees $MinAltitudeDegrees -DownlinkFrequencyMHz $DownlinkFrequencyMHz
                                if ($null -ne $peakVisibility) {
                                    $peakDoppler = $peakVisibility.ApproximateDopplerShiftHz
                                }
                            }

                            $windows.Add([pscustomobject]@{
                                PSTypeName = 'AetherScope.IssRadioWindow'
                                ObserverLatitude = $resolved.Latitude
                                ObserverLongitude = $resolved.Longitude
                                ObserverAltitudeKm = $ObserverAltitudeKm
                                MinAltitudeDegrees = $MinAltitudeDegrees
                                StartTime = $currentWindow.StartTime
                                StartAzimuth = [Math]::Round($currentWindow.StartAzimuth, 2)
                                PeakTime = $currentWindow.PeakTime
                                PeakAzimuth = [Math]::Round($currentWindow.PeakAzimuth, 2)
                                PeakAltitude = [Math]::Round($currentWindow.PeakAltitude, 2)
                                PeakVisibility = $currentWindow.PeakVisibility
                                PeakRangeKm = [Math]::Round($currentWindow.PeakRangeKm, 2)
                                EndTime = $windowEnd
                                EndAzimuth = [Math]::Round($windowAzimuth, 2)
                                DurationMinutes = [Math]::Round($durationMinutes, 2)
                                DownlinkFrequencyMHz = $DownlinkFrequencyMHz
                                ApproximatePeakDopplerShiftHz = $peakDoppler
                                CoordinateSource = $resolved.Source
                                SampleIntervalSeconds = $IntervalSeconds
                            })
                        }

                        $currentWindow = $null
                    }
                }
            }

            if (($null -ne $currentWindow) -and ($windows.Count -lt $MaxResults)) {
                $windowEnd = $samples[$samples.Count - 1].TimeStamp
                $windowAzimuth = $samples[$samples.Count - 1].Azimuth
                $durationMinutes = ($windowEnd - $currentWindow.StartTime).TotalMinutes
                if ($durationMinutes -ge $MinWindowMinutes) {
                    $windows.Add([pscustomobject]@{
                        PSTypeName = 'AetherScope.IssRadioWindow'
                        ObserverLatitude = $resolved.Latitude
                        ObserverLongitude = $resolved.Longitude
                        ObserverAltitudeKm = $ObserverAltitudeKm
                        MinAltitudeDegrees = $MinAltitudeDegrees
                        StartTime = $currentWindow.StartTime
                        StartAzimuth = [Math]::Round($currentWindow.StartAzimuth, 2)
                        PeakTime = $currentWindow.PeakTime
                        PeakAzimuth = [Math]::Round($currentWindow.PeakAzimuth, 2)
                        PeakAltitude = [Math]::Round($currentWindow.PeakAltitude, 2)
                        PeakVisibility = $currentWindow.PeakVisibility
                        PeakRangeKm = [Math]::Round($currentWindow.PeakRangeKm, 2)
                        EndTime = $windowEnd
                        EndAzimuth = [Math]::Round($windowAzimuth, 2)
                        DurationMinutes = [Math]::Round($durationMinutes, 2)
                        DownlinkFrequencyMHz = $DownlinkFrequencyMHz
                        ApproximatePeakDopplerShiftHz = $null
                        CoordinateSource = $resolved.Source
                        SampleIntervalSeconds = $IntervalSeconds
                    })
                }
            }

            $windows | Select-Object -First $MaxResults
        }
        catch {
            Write-Error ("Failed to find ISS radio windows: {0}" -f $_.Exception.Message)
        }
    }

    end {
    }
}



function Start-AetherScopeTracker {
<#
.SYNOPSIS
Continuously samples a supported celestial body for an observer.
.DESCRIPTION
General tracker for Sun, Moon, or ISS that repeatedly calls Get-AetherScopePosition
and streams the results. This provides a consistent tracking surface regardless
of whether the observer coordinates come from manual entry or a GPS feed.
.PARAMETER Body
The body to track.
.PARAMETER Latitude
Observer latitude in decimal degrees.
.PARAMETER Longitude
Observer longitude in decimal degrees.
.PARAMETER Coordinate
Flexible observer coordinate input.
.PARAMETER ObserverAltitudeKm
Observer altitude in kilometers. Primarily relevant for ISS tracking.
.PARAMETER IntervalSeconds
Polling interval between samples.
.PARAMETER MaxSamples
Maximum number of samples to collect. Use 0 for continuous tracking.
.PARAMETER UseGpsSerial
Reads a fresh GPS fix from a serial port before each sample.
.PARAMETER GpsPortName
Serial port name used when -UseGpsSerial is specified.
.PARAMETER GpsBaudRate
GPS serial baud rate.
.EXAMPLE
Start-AetherScopeTracker -Body Sun -Coordinate '30.2752,-89.7812' -IntervalSeconds 30 -MaxSamples 4
.EXAMPLE
Start-AetherScopeTracker -Body ISS -UseGpsSerial -GpsPortName COM3 -GpsBaudRate 4800 -IntervalSeconds 5 -MaxSamples 10 -WhatIf
.INPUTS
System.Object
.OUTPUTS
System.Management.Automation.PSCustomObject
.NOTES
When -UseGpsSerial is used, the tracker asks the GPS for a fresh coordinate fix
on each iteration.
#>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Sun', 'Moon', 'ISS')]
        [string]$Body,

        [Parameter()]
        [Nullable[Double]]$Latitude,

        [Parameter()]
        [Nullable[Double]]$Longitude,

        [Parameter(ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [AllowNull()]
        [Object]$Coordinate,

        [Parameter()]
        [double]$ObserverAltitudeKm = 0.0,

        [Parameter()]
        [ValidateRange(1, 3600)]
        [int]$IntervalSeconds = 5,

        [Parameter()]
        [ValidateRange(0, 100000)]
        [int]$MaxSamples = 0,

        [Parameter()]
        [switch]$UseGpsSerial,

        [Parameter()]
        [string]$GpsPortName,

        [Parameter()]
        [ValidateRange(110, 115200)]
        [int]$GpsBaudRate = 4800
    )

    begin {
        $sampleCount = 0
    }

    process {
        if ($UseGpsSerial.IsPresent -and [string]::IsNullOrWhiteSpace($GpsPortName)) {
            Write-Error 'GpsPortName is required when -UseGpsSerial is specified.'
            return
        }

        if (-not $PSCmdlet.ShouldProcess($Body, 'Start celestial tracking loop')) {
            return
        }

        while (($MaxSamples -le 0) -or ($sampleCount -lt $MaxSamples)) {
            $activeCoordinate = $Coordinate
            $activeLatitude = $Latitude
            $activeLongitude = $Longitude

            if ($UseGpsSerial.IsPresent) {
                $gpsFix = Get-AetherScopeGpsCoordinate -PortName $GpsPortName -BaudRate $GpsBaudRate -ReadCount 1 | Select-Object -First 1
                if ($null -eq $gpsFix) {
                    Write-Verbose 'No GPS fix was returned for this sample.'
                    Start-Sleep -Seconds $IntervalSeconds
                    continue
                }

                $activeCoordinate = $gpsFix
                $activeLatitude = $null
                $activeLongitude = $null
            }

            $sample = Get-AetherScopePosition -Body $Body -Latitude $activeLatitude -Longitude $activeLongitude -Coordinate $activeCoordinate -DateTime (Get-Date) -ObserverAltitudeKm $ObserverAltitudeKm
            if ($null -ne $sample) {
                $sampleCount += 1
                $sample
            }

            if (($MaxSamples -gt 0) -and ($sampleCount -ge $MaxSamples)) {
                break
            }

            Start-Sleep -Seconds $IntervalSeconds
        }
    }

    end {
    }
}



function New-CelestialWindowFromSamples {
<#
.SYNOPSIS
Builds visibility windows from sampled altitude and azimuth observations.
.DESCRIPTION
Consumes time-ordered samples that contain TimeStamp, Altitude, and Azimuth and
creates windows using a minimum altitude threshold. Start and end times are
estimated using linear interpolation across the threshold boundary.
.PARAMETER Sample
Ordered sample collection containing TimeStamp, Altitude, and Azimuth.
.PARAMETER ThresholdDegrees
Minimum altitude threshold used to define the window.
.PARAMETER MinWindowMinutes
Minimum window duration in minutes required for output.
.PARAMETER Body
Body name associated with the samples.
.PARAMETER CoordinateSource
Coordinate source string from Resolve-AetherScopeCoordinate.
.PARAMETER Latitude
Observer latitude.
.PARAMETER Longitude
Observer longitude.
.PARAMETER MaxResults
Maximum number of windows to emit.
.PARAMETER AdditionalProperty
Optional hashtable of additional output properties to include in each object.
.EXAMPLE
New-CelestialWindowFromSamples -Sample $samples -ThresholdDegrees 0 -Body Sun -Latitude 30.2752 -Longitude -89.7812
.EXAMPLE
New-CelestialWindowFromSamples -Sample $samples -ThresholdDegrees 10 -Body Moon -Latitude 30.2752 -Longitude -89.7812 -WhatIf
.INPUTS
System.Object[]
.OUTPUTS
System.Management.Automation.PSCustomObject
.NOTES
Builds visibility windows from sampled altitude/azimuth series and uses simple
linear interpolation at threshold crossings so start/end times are smoother
than raw sample edges. This helper underpins the Sun, Moon, and ISS window
functions. Samples must already be ordered by TimeStamp.

.LINK
https://gml.noaa.gov/grad/solcalc/azel.html
.LINK
https://gml.noaa.gov/grad/solcalc/solareqns.PDF
#>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [Object[]]$Sample,

        [Parameter(Mandatory = $true)]
        [double]$ThresholdDegrees,

        [Parameter()]
        [ValidateRange(0, 1440)]
        [double]$MinWindowMinutes = 0.0,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Body,

        [Parameter()]
        [string]$CoordinateSource,

        [Parameter()]
        [Nullable[Double]]$Latitude,

        [Parameter()]
        [Nullable[Double]]$Longitude,

        [Parameter()]
        [ValidateRange(1, 100)]
        [int]$MaxResults = 10,

        [Parameter()]
        [hashtable]$AdditionalProperty
    )

    begin {
    }

    process {
        try {
            if (-not $PSCmdlet.ShouldProcess(($Body + ' sampled visibility series'), 'Build visibility windows')) {
                return
            }

            if (($null -eq $Sample) -or ($Sample.Count -eq 0)) {
                return
            }

            $ordered = $Sample | Sort-Object -Property TimeStamp
            $results = @()
            $windowStartTime = $null
            $windowStartAzimuth = $null
            $peakAltitude = [double]::NegativeInfinity
            $peakAzimuth = $null
            $peakTime = $null
            $previous = $null

            foreach ($current in $ordered) {
                if (($null -eq $current.TimeStamp) -or ($null -eq $current.Altitude) -or ($null -eq $current.Azimuth)) {
                    $previous = $current
                    continue
                }

                $currentAltitude = [double]$current.Altitude
                $currentAzimuth = [double]$current.Azimuth
                $currentTime = [datetime]$current.TimeStamp
                $isAbove = ($currentAltitude -ge $ThresholdDegrees)

                if ($null -eq $previous) {
                    if ($isAbove) {
                        $windowStartTime = $currentTime
                        $windowStartAzimuth = $currentAzimuth
                        $peakAltitude = $currentAltitude
                        $peakAzimuth = $currentAzimuth
                        $peakTime = $currentTime
                    }

                    $previous = $current
                    continue
                }

                $prevAltitude = [double]$previous.Altitude
                $prevAzimuth = [double]$previous.Azimuth
                $prevTime = [datetime]$previous.TimeStamp
                $wasAbove = ($prevAltitude -ge $ThresholdDegrees)

                if ((-not $wasAbove) -and $isAbove) {
                    $crossing = Get-InterpolatedThresholdCrossing -PreviousTime $prevTime -PreviousAltitude $prevAltitude -PreviousAzimuth $prevAzimuth -CurrentTime $currentTime -CurrentAltitude $currentAltitude -CurrentAzimuth $currentAzimuth -ThresholdDegrees $ThresholdDegrees
                    $windowStartTime = $crossing.TimeStamp
                    $windowStartAzimuth = $crossing.Azimuth
                    $peakAltitude = $currentAltitude
                    $peakAzimuth = $currentAzimuth
                    $peakTime = $currentTime
                }
                elseif ($wasAbove -and $isAbove) {
                    if ($currentAltitude -gt $peakAltitude) {
                        $peakAltitude = $currentAltitude
                        $peakAzimuth = $currentAzimuth
                        $peakTime = $currentTime
                    }
                }
                elseif ($wasAbove -and (-not $isAbove)) {
                    $crossing = Get-InterpolatedThresholdCrossing -PreviousTime $prevTime -PreviousAltitude $prevAltitude -PreviousAzimuth $prevAzimuth -CurrentTime $currentTime -CurrentAltitude $currentAltitude -CurrentAzimuth $currentAzimuth -ThresholdDegrees $ThresholdDegrees
                    if ($null -ne $windowStartTime) {
                        $durationMinutes = ($crossing.TimeStamp - $windowStartTime).TotalMinutes
                        if ($durationMinutes -ge $MinWindowMinutes) {
                            $obj = [ordered]@{
                                PSTypeName = 'AetherScope.VisibilityWindow'
                                Body = $Body
                                CoordinateSource = $CoordinateSource
                                Latitude = $Latitude
                                Longitude = $Longitude
                                ThresholdDegrees = [double]$ThresholdDegrees
                                StartTime = $windowStartTime
                                StartAzimuth = [double]$windowStartAzimuth
                                PeakTime = $peakTime
                                PeakAltitude = [double]$peakAltitude
                                PeakAzimuth = [double]$peakAzimuth
                                EndTime = $crossing.TimeStamp
                                EndAzimuth = [double]$crossing.Azimuth
                                DurationMinutes = [Math]::Round($durationMinutes, 2)
                            }

                            if ($null -ne $AdditionalProperty) {
                                foreach ($key in $AdditionalProperty.Keys) {
                                    $obj[$key] = $AdditionalProperty[$key]
                                }
                            }

                            $results += [pscustomobject]$obj
                            if ($results.Count -ge $MaxResults) {
                                break
                            }
                        }
                    }

                    $windowStartTime = $null
                    $windowStartAzimuth = $null
                    $peakAltitude = [double]::NegativeInfinity
                    $peakAzimuth = $null
                    $peakTime = $null
                }

                $previous = $current
            }

            if (($results.Count -lt $MaxResults) -and ($null -ne $windowStartTime) -and ($null -ne $previous) -and ([double]$previous.Altitude -ge $ThresholdDegrees)) {
                $durationMinutes = ([datetime]$previous.TimeStamp - $windowStartTime).TotalMinutes
                if ($durationMinutes -ge $MinWindowMinutes) {
                    $obj = [ordered]@{
                        PSTypeName = 'AetherScope.VisibilityWindow'
                        Body = $Body
                        CoordinateSource = $CoordinateSource
                        Latitude = $Latitude
                        Longitude = $Longitude
                        ThresholdDegrees = [double]$ThresholdDegrees
                        StartTime = $windowStartTime
                        StartAzimuth = [double]$windowStartAzimuth
                        PeakTime = $peakTime
                        PeakAltitude = [double]$peakAltitude
                        PeakAzimuth = [double]$peakAzimuth
                        EndTime = [datetime]$previous.TimeStamp
                        EndAzimuth = [double]$previous.Azimuth
                        DurationMinutes = [Math]::Round($durationMinutes, 2)
                    }

                    if ($null -ne $AdditionalProperty) {
                        foreach ($key in $AdditionalProperty.Keys) {
                            $obj[$key] = $AdditionalProperty[$key]
                        }
                    }

                    $results += [pscustomobject]$obj
                }
            }

            $results
        }
        catch {
            Write-Error ('Failed to build visibility windows from samples: {0}' -f $_.Exception.Message)
        }
    }

    end {
    }
}



function Get-AetherScopeSunVisibilityWindow {
<#
.SYNOPSIS
Finds Sun visibility or twilight windows for an observer location.
.DESCRIPTION
Scans a time range and returns windows where the Sun is at or above a chosen
altitude threshold. Use 0 degrees for sunrise-to-sunset style windows, -6 for
civil twilight, -12 for nautical twilight, or -18 for astronomical twilight.
.PARAMETER Latitude
Observer latitude in decimal degrees.
.PARAMETER Longitude
Observer longitude in decimal degrees.
.PARAMETER Coordinate
Flexible observer coordinate input.
.PARAMETER StartTime
Beginning of the scan window.
.PARAMETER DurationHours
Length of the scan window in hours.
.PARAMETER IntervalSeconds
Sampling interval in seconds.
.PARAMETER MinAltitudeDegrees
Minimum solar altitude threshold in degrees.
.PARAMETER MinWindowMinutes
Minimum window length in minutes to return.
.PARAMETER MaxResults
Maximum number of windows to return.
.EXAMPLE
Get-AetherScopeSunVisibilityWindow -Coordinate '30.2752,-89.7812' -DurationHours 24
.EXAMPLE
Get-AetherScopeSunVisibilityWindow -Coordinate '30.2752,-89.7812' -DurationHours 24 -MinAltitudeDegrees -6 -WhatIf
.INPUTS
System.Object
.OUTPUTS
System.Management.Automation.PSCustomObject
.NOTES
A threshold of 0 degrees approximates sunrise-to-sunset windows. Negative
thresholds can be used for twilight planning.

.LINK
https://gml.noaa.gov/grad/solcalc/azel.html
.LINK
https://gml.noaa.gov/grad/solcalc/solareqns.PDF
#>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([pscustomobject])]
    param(
        [Parameter()]
        [Nullable[Double]]$Latitude,

        [Parameter()]
        [Nullable[Double]]$Longitude,

        [Parameter(ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [AllowNull()]
        [Object]$Coordinate,

        [Parameter()]
        [datetime]$StartTime = (Get-Date),

        [Parameter()]
        [ValidateRange(1, 240)]
        [int]$DurationHours = 24,

        [Parameter()]
        [ValidateRange(30, 3600)]
        [int]$IntervalSeconds = 300,

        [Parameter()]
        [ValidateRange(-18.0, 90.0)]
        [double]$MinAltitudeDegrees = 0.0,

        [Parameter()]
        [ValidateRange(0, 1440)]
        [double]$MinWindowMinutes = 0.0,

        [Parameter()]
        [ValidateRange(1, 20)]
        [int]$MaxResults = 10
    )

    begin {
    }

    process {
        try {
            $resolved = Resolve-AetherScopeCoordinate -Latitude $Latitude -Longitude $Longitude -Coordinate $Coordinate
            if ($null -eq $resolved) {
                return
            }

            if (-not $PSCmdlet.ShouldProcess(("Sun window for {0},{1}" -f $resolved.Latitude, $resolved.Longitude), 'Scan solar visibility windows')) {
                return
            }

            $endTime = $StartTime.ToUniversalTime().AddHours($DurationHours)
            $cursor = $StartTime.ToUniversalTime()
            $samples = @()

            while ($cursor -le $endTime) {
                $position = Get-AetherScopeSunPosition -Latitude $resolved.Latitude -Longitude $resolved.Longitude -DateTime $cursor
                if ($null -ne $position) {
                    $samples += [pscustomobject]@{
                        TimeStamp = $position.UtcDateTime
                        Azimuth = [double]$position.Azimuth
                        Altitude = [double]$position.Altitude
                    }
                }

                $cursor = $cursor.AddSeconds($IntervalSeconds)
            }

            if ($samples.Count -eq 0) {
                return
            }

            $mode = 'Daylight'
            if ($MinAltitudeDegrees -eq -6.0) {
                $mode = 'CivilTwilight'
            }
            elseif ($MinAltitudeDegrees -eq -12.0) {
                $mode = 'NauticalTwilight'
            }
            elseif ($MinAltitudeDegrees -eq -18.0) {
                $mode = 'AstronomicalTwilight'
            }
            elseif ($MinAltitudeDegrees -gt 0.0) {
                $mode = 'HighSun'
            }

            New-CelestialWindowFromSamples -Sample $samples -ThresholdDegrees $MinAltitudeDegrees -MinWindowMinutes $MinWindowMinutes -Body 'Sun' -CoordinateSource $resolved.Source -Latitude $resolved.Latitude -Longitude $resolved.Longitude -MaxResults $MaxResults -AdditionalProperty ([ordered]@{
                Mode = $mode
                SampleIntervalSeconds = $IntervalSeconds
            })
        }
        catch {
            Write-Error ("Failed to scan Sun visibility windows: {0}" -f $_.Exception.Message)
        }
    }

    end {
    }
}



function Get-AetherScopeMoonVisibilityWindow {
<#
.SYNOPSIS
Finds Moon visibility windows for an observer location.
.DESCRIPTION
Scans a time range and returns windows where the Moon is at or above a chosen
altitude threshold. This is useful for general observing and planning when the
Moon is sufficiently high above the horizon.
.PARAMETER Latitude
Observer latitude in decimal degrees.
.PARAMETER Longitude
Observer longitude in decimal degrees.
.PARAMETER Coordinate
Flexible observer coordinate input.
.PARAMETER StartTime
Beginning of the scan window.
.PARAMETER DurationHours
Length of the scan window in hours.
.PARAMETER IntervalSeconds
Sampling interval in seconds.
.PARAMETER MinAltitudeDegrees
Minimum lunar altitude threshold in degrees.
.PARAMETER MinWindowMinutes
Minimum window length in minutes to return.
.PARAMETER MaxResults
Maximum number of windows to return.
.EXAMPLE
Get-AetherScopeMoonVisibilityWindow -Coordinate '30.2752,-89.7812' -DurationHours 48
.EXAMPLE
Get-AetherScopeMoonVisibilityWindow -Coordinate '30.2752,-89.7812' -DurationHours 24 -MinAltitudeDegrees 10 -WhatIf
.INPUTS
System.Object
.OUTPUTS
System.Management.Automation.PSCustomObject
.NOTES
Uses the shared sampled/interpolated window logic to find time ranges where
the Moon meets or exceeds a requested altitude threshold. The underlying Moon
position routine is intentionally approximate, so windows are suitable for
practical planning and pointing, not precision astronomical reduction.

.LINK
https://stjarnhimlen.se/comp/ppcomp.html
#>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([pscustomobject])]
    param(
        [Parameter()]
        [Nullable[Double]]$Latitude,

        [Parameter()]
        [Nullable[Double]]$Longitude,

        [Parameter(ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [AllowNull()]
        [Object]$Coordinate,

        [Parameter()]
        [datetime]$StartTime = (Get-Date),

        [Parameter()]
        [ValidateRange(1, 240)]
        [int]$DurationHours = 24,

        [Parameter()]
        [ValidateRange(30, 3600)]
        [int]$IntervalSeconds = 300,

        [Parameter()]
        [ValidateRange(0.0, 90.0)]
        [double]$MinAltitudeDegrees = 0.0,

        [Parameter()]
        [ValidateRange(0, 1440)]
        [double]$MinWindowMinutes = 0.0,

        [Parameter()]
        [ValidateRange(1, 20)]
        [int]$MaxResults = 10
    )

    begin {
    }

    process {
        try {
            $resolved = Resolve-AetherScopeCoordinate -Latitude $Latitude -Longitude $Longitude -Coordinate $Coordinate
            if ($null -eq $resolved) {
                return
            }

            if (-not $PSCmdlet.ShouldProcess(("Moon window for {0},{1}" -f $resolved.Latitude, $resolved.Longitude), 'Scan lunar visibility windows')) {
                return
            }

            $endTime = $StartTime.ToUniversalTime().AddHours($DurationHours)
            $cursor = $StartTime.ToUniversalTime()
            $samples = @()

            while ($cursor -le $endTime) {
                $position = Get-AetherScopeMoonPosition -Latitude $resolved.Latitude -Longitude $resolved.Longitude -DateTime $cursor
                if ($null -ne $position) {
                    $samples += [pscustomobject]@{
                        TimeStamp = $position.UtcDateTime
                        Azimuth = [double]$position.Azimuth
                        Altitude = [double]$position.Altitude
                    }
                }

                $cursor = $cursor.AddSeconds($IntervalSeconds)
            }

            if ($samples.Count -eq 0) {
                return
            }

            New-CelestialWindowFromSamples -Sample $samples -ThresholdDegrees $MinAltitudeDegrees -MinWindowMinutes $MinWindowMinutes -Body 'Moon' -CoordinateSource $resolved.Source -Latitude $resolved.Latitude -Longitude $resolved.Longitude -MaxResults $MaxResults -AdditionalProperty ([ordered]@{
                SampleIntervalSeconds = $IntervalSeconds
            })
        }
        catch {
            Write-Error ("Failed to scan Moon visibility windows: {0}" -f $_.Exception.Message)
        }
    }

    end {
    }
}



function Get-AetherScopeVisibilityWindow {
<#
.SYNOPSIS
Gets visibility windows for the Sun, Moon, or ISS.
.DESCRIPTION
Dispatches to Get-AetherScopeSunVisibilityWindow, Get-AetherScopeMoonVisibilityWindow, or
Get-AetherScopeIssRadioWindow using a common interface.
.PARAMETER Body
Target body name.
.PARAMETER Latitude
Observer latitude in decimal degrees.
.PARAMETER Longitude
Observer longitude in decimal degrees.
.PARAMETER Coordinate
Flexible observer coordinate input.
.PARAMETER StartTime
Beginning of the scan window.
.PARAMETER DurationHours
Length of the scan window in hours.
.PARAMETER IntervalSeconds
Sampling interval in seconds.
.PARAMETER MinAltitudeDegrees
Minimum altitude threshold in degrees.
.PARAMETER MinWindowMinutes
Minimum window length in minutes to return.
.PARAMETER ObserverAltitudeKm
Observer altitude in kilometers. Used for ISS windows.
.PARAMETER DownlinkFrequencyMHz
Optional ISS downlink frequency used for approximate Doppler estimates.
.PARAMETER MaxResults
Maximum number of windows to return.
.EXAMPLE
Get-AetherScopeVisibilityWindow -Body Sun -Coordinate '30.2752,-89.7812' -DurationHours 24
.EXAMPLE
Get-AetherScopeVisibilityWindow -Body Moon -Coordinate '30.2752,-89.7812' -MinAltitudeDegrees 10 -WhatIf
.INPUTS
System.Object
.OUTPUTS
System.Management.Automation.PSCustomObject
.NOTES
For Sun windows, negative thresholds support twilight-style planning.
#>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Sun', 'Moon', 'ISS')]
        [string]$Body,

        [Parameter()]
        [Nullable[Double]]$Latitude,

        [Parameter()]
        [Nullable[Double]]$Longitude,

        [Parameter(ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [AllowNull()]
        [Object]$Coordinate,

        [Parameter()]
        [datetime]$StartTime = (Get-Date),

        [Parameter()]
        [ValidateRange(1, 240)]
        [int]$DurationHours = 24,

        [Parameter()]
        [ValidateRange(5, 3600)]
        [int]$IntervalSeconds = 300,

        [Parameter()]
        [double]$MinAltitudeDegrees = 0.0,

        [Parameter()]
        [ValidateRange(0, 1440)]
        [double]$MinWindowMinutes = 0.0,

        [Parameter()]
        [double]$ObserverAltitudeKm = 0.0,

        [Parameter()]
        [double]$DownlinkFrequencyMHz = 0.0,

        [Parameter()]
        [ValidateRange(1, 50)]
        [int]$MaxResults = 10
    )

    begin {
    }

    process {
        switch ($Body) {
            'Sun' {
                Get-AetherScopeSunVisibilityWindow -Latitude $Latitude -Longitude $Longitude -Coordinate $Coordinate -StartTime $StartTime -DurationHours $DurationHours -IntervalSeconds $IntervalSeconds -MinAltitudeDegrees $MinAltitudeDegrees -MinWindowMinutes $MinWindowMinutes -MaxResults $MaxResults
            }
            'Moon' {
                Get-AetherScopeMoonVisibilityWindow -Latitude $Latitude -Longitude $Longitude -Coordinate $Coordinate -StartTime $StartTime -DurationHours $DurationHours -IntervalSeconds $IntervalSeconds -MinAltitudeDegrees $MinAltitudeDegrees -MinWindowMinutes $MinWindowMinutes -MaxResults $MaxResults
            }
            'ISS' {
                Get-AetherScopeIssRadioWindow -Latitude $Latitude -Longitude $Longitude -Coordinate $Coordinate -StartTime $StartTime -DurationHours $DurationHours -IntervalSeconds $IntervalSeconds -ObserverAltitudeKm $ObserverAltitudeKm -MinAltitudeDegrees $MinAltitudeDegrees -MinWindowMinutes $MinWindowMinutes -DownlinkFrequencyMHz $DownlinkFrequencyMHz -MaxResults $MaxResults
            }
        }
    }

    end {
    }
}



function Invoke-HamlibRotatorCommand {
<#
.SYNOPSIS
Sends a command to a Hamlib rotctld instance.
.DESCRIPTION
Opens a TCP connection to rotctld, sends a text command, and returns the raw
response lines. This helper is intended for Get/Set/Park/Stop rotator actions.
.PARAMETER HostName
DNS name or IP address of the rotctld host.
.PARAMETER Port
TCP port of the rotctld service.
.PARAMETER Command
Hamlib command string such as 'p', 'P 180 45', 'S', or 'K'.
.PARAMETER TimeoutMilliseconds
Network timeout in milliseconds.
.EXAMPLE
Invoke-HamlibRotatorCommand -HostName 127.0.0.1 -Port 4533 -Command 'p'
.EXAMPLE
Invoke-HamlibRotatorCommand -HostName 127.0.0.1 -Port 4533 -Command 'S' -WhatIf
.INPUTS
System.String
.OUTPUTS
System.String[]
.NOTES
Uses the simple line-oriented rotctld protocol.

.LINK
https://hamlib.sourceforge.net/html/rotctld.1.html
#>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([string[]])]
    param(
        [Parameter()]
        [string]$HostName = '127.0.0.1',

        [Parameter()]
        [ValidateRange(1, 65535)]
        [int]$Port = 4533,

        [Parameter(Mandatory = $true)]
        [string]$Command,

        [Parameter()]
        [ValidateRange(100, 60000)]
        [int]$TimeoutMilliseconds = 3000
    )

    begin {
    }

    process {
        if (-not $PSCmdlet.ShouldProcess(("{0}:{1}" -f $HostName, $Port), ("Send Hamlib rotator command '{0}'" -f $Command))) {
            return
        }

        $client = $null
        $stream = $null
        $reader = $null
        $writer = $null
        try {
            $client = New-Object System.Net.Sockets.TcpClient
            $async = $client.BeginConnect($HostName, $Port, $null, $null)
            if (-not $async.AsyncWaitHandle.WaitOne($TimeoutMilliseconds, $false)) {
                Write-Error ("Timed out connecting to rotctld at {0}:{1}." -f $HostName, $Port)
                return
            }

            $client.EndConnect($async)
            $stream = $client.GetStream()
            $stream.ReadTimeout = $TimeoutMilliseconds
            $stream.WriteTimeout = $TimeoutMilliseconds
            $reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::ASCII)
            $writer = New-Object System.IO.StreamWriter($stream, [System.Text.Encoding]::ASCII)
            $writer.NewLine = "`n"
            $writer.AutoFlush = $true
            $writer.WriteLine($Command)

            $lines = New-Object System.Collections.Generic.List[string]
            $deadline = [DateTime]::UtcNow.AddMilliseconds($TimeoutMilliseconds)
            do {
                try {
                    $line = $reader.ReadLine()
                }
                catch [System.IO.IOException] {
                    break
                }

                if ($null -eq $line) {
                    break
                }

                $lines.Add($line)

                if (($line -like 'RPRT *') -or (($Command -eq 'p') -and ($lines.Count -ge 2))) {
                    break
                }
            } while ([DateTime]::UtcNow -lt $deadline)

            ,$lines.ToArray()
        }
        catch {
            Write-Error ("Failed to communicate with rotctld at {0}:{1}: {2}" -f $HostName, $Port, $_.Exception.Message)
        }
        finally {
            if ($null -ne $writer) {
                $writer.Dispose()
            }
            if ($null -ne $reader) {
                $reader.Dispose()
            }
            if ($null -ne $stream) {
                $stream.Dispose()
            }
            if ($null -ne $client) {
                $client.Close()
            }
        }
    }

    end {
    }
}



function Invoke-Gs232RotatorCommand {
<#
.SYNOPSIS
Sends a command to a GS-232 style serial rotator controller.
.DESCRIPTION
Opens a serial port, sends a command, and optionally reads the controller reply.
This helper is intended for direct GS-232 compatible controllers.
.PARAMETER PortName
Serial port name such as COM3.
.PARAMETER BaudRate
Serial baud rate.
.PARAMETER Command
GS-232 command string.
.PARAMETER ReadResponse
Reads returned data when specified.
.PARAMETER TimeoutMilliseconds
Serial read/write timeout in milliseconds.
.EXAMPLE
Invoke-Gs232RotatorCommand -PortName COM3 -BaudRate 9600 -Command 'C2' -ReadResponse
.EXAMPLE
Invoke-Gs232RotatorCommand -PortName COM3 -BaudRate 9600 -Command 'S' -WhatIf
.INPUTS
System.String
.OUTPUTS
System.String
.NOTES
Implements the GS-232-style serial command family documented in the linked
manuals. The current draft uses the classic command pattern for get-position,
set-position, and stop control. Exact response formatting may vary slightly by
controller model and firmware. Commands are emitted as carriage-return
terminated lines.

.LINK
https://www.radiomanual.info/schemi/ACC_rotator/Yaesu_GS-232A_user.pdf
.LINK
https://www.yaesu.com/jp/manuals/yaesu_m/GS-232B_EAA14X002_1803E-AS-1.pdf
#>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PortName,

        [Parameter()]
        [ValidateRange(110, 115200)]
        [int]$BaudRate = 9600,

        [Parameter(Mandatory = $true)]
        [string]$Command,

        [Parameter()]
        [switch]$ReadResponse,

        [Parameter()]
        [ValidateRange(100, 60000)]
        [int]$TimeoutMilliseconds = 3000
    )

    begin {
    }

    process {
        if (-not $PSCmdlet.ShouldProcess($PortName, ("Send GS-232 rotator command '{0}'" -f $Command))) {
            return
        }

        $port = $null
        try {
            $port = New-Object System.IO.Ports.SerialPort $PortName, $BaudRate, ([System.IO.Ports.Parity]::None), 8, ([System.IO.Ports.StopBits]::One)
            $port.NewLine = "`r"
            $port.ReadTimeout = $TimeoutMilliseconds
            $port.WriteTimeout = $TimeoutMilliseconds
            $port.Open()
            $port.DiscardInBuffer()
            $port.DiscardOutBuffer()
            $port.Write($Command + "`r")

            if ($ReadResponse.IsPresent) {
                Start-Sleep -Milliseconds 100
                $response = $port.ReadExisting()
                if (-not [string]::IsNullOrWhiteSpace($response)) {
                    return $response.Trim()
                }
            }
        }
        catch {
            Write-Error ("Failed to communicate with GS-232 controller on {0}: {1}" -f $PortName, $_.Exception.Message)
        }
        finally {
            if (($null -ne $port) -and $port.IsOpen) {
                $port.Close()
            }
            if ($null -ne $port) {
                $port.Dispose()
            }
        }
    }

    end {
    }
}



function Test-RotatorTargetInRange {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [double]$Azimuth,

        [Parameter(Mandatory = $true)]
        [double]$Elevation,

        [Parameter()]
        [double]$MinAzimuth = 0.0,

        [Parameter()]
        [double]$MaxAzimuth = 450.0,

        [Parameter()]
        [double]$MinElevation = 0.0,

        [Parameter()]
        [double]$MaxElevation = 180.0
    )

    return (($Azimuth -ge $MinAzimuth) -and ($Azimuth -le $MaxAzimuth) -and ($Elevation -ge $MinElevation) -and ($Elevation -le $MaxElevation))
}



function Get-AetherScopeRotatorPosition {
<#
.SYNOPSIS
Gets the current rotator position from a supported backend.
.DESCRIPTION
Queries either Hamlib rotctld over TCP or a GS-232 compatible serial controller
and returns the reported azimuth and elevation.
.PARAMETER Backend
Rotator backend type.
.PARAMETER HostName
rotctld host name for HamlibTcp.
.PARAMETER Port
rotctld TCP port for HamlibTcp.
.PARAMETER PortName
Serial port for Gs232Serial.
.PARAMETER BaudRate
Serial baud rate for Gs232Serial.
.PARAMETER TimeoutMilliseconds
I/O timeout in milliseconds.
.EXAMPLE
Get-AetherScopeRotatorPosition -Backend HamlibTcp -HostName 127.0.0.1 -Port 4533
.EXAMPLE
Get-AetherScopeRotatorPosition -Backend Gs232Serial -PortName COM3 -BaudRate 9600 -WhatIf
.INPUTS
None
.OUTPUTS
System.Management.Automation.PSCustomObject
.NOTES
Abstracts position queries across the supported rotator backends. Hamlib
queries use the rotctld TCP command protocol, while GS-232 queries use the
controller's serial command family and parse returned azimuth/elevation
telemetry into PowerShell objects. GS-232 parsing accepts common +0aaa+0eee
and whitespace-delimited numeric forms.

.LINK
https://hamlib.sourceforge.net/html/rotctld.1.html
.LINK
https://www.radiomanual.info/schemi/ACC_rotator/Yaesu_GS-232A_user.pdf
#>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('HamlibTcp', 'Gs232Serial')]
        [string]$Backend,

        [Parameter()]
        [string]$HostName = '127.0.0.1',

        [Parameter()]
        [ValidateRange(1, 65535)]
        [int]$Port = 4533,

        [Parameter()]
        [string]$PortName,

        [Parameter()]
        [ValidateRange(110, 115200)]
        [int]$BaudRate = 9600,

        [Parameter()]
        [ValidateRange(100, 60000)]
        [int]$TimeoutMilliseconds = 3000
    )

    begin {
    }

    process {
        if (-not $PSCmdlet.ShouldProcess($Backend, 'Get rotator position')) {
            return
        }

        switch ($Backend) {
            'HamlibTcp' {
                $lines = @(Invoke-HamlibRotatorCommand -HostName $HostName -Port $Port -Command 'p' -TimeoutMilliseconds $TimeoutMilliseconds)
                if ($lines.Count -lt 2) {
                    Write-Error 'Hamlib get position returned fewer than two lines.'
                    return
                }

                $azimuth = $null
                $elevation = $null
                $successAz = [double]::TryParse(($lines[0] -as [string]), [ref]$azimuth)
                $successEl = [double]::TryParse(($lines[1] -as [string]), [ref]$elevation)
                if ((-not $successAz) -or (-not $successEl)) {
                    Write-Error ("Unable to parse Hamlib position response: {0}" -f (($lines -join ' | ')))
                    return
                }

                [pscustomobject]@{
                    PSTypeName = 'AetherScope.RotatorPosition'
                    Backend = $Backend
                    Azimuth = [Math]::Round($azimuth, 2)
                    Elevation = [Math]::Round($elevation, 2)
                    HostName = $HostName
                    Port = $Port
                    PortName = $null
                }
            }
            'Gs232Serial' {
                if ([string]::IsNullOrWhiteSpace($PortName)) {
                    Write-Error 'PortName is required for Gs232Serial.'
                    return
                }

                $response = Invoke-Gs232RotatorCommand -PortName $PortName -BaudRate $BaudRate -Command 'C2' -ReadResponse -TimeoutMilliseconds $TimeoutMilliseconds
                if ([string]::IsNullOrWhiteSpace($response)) {
                    Write-Error 'GS-232 controller returned no position response.'
                    return
                }

                $match = [regex]::Match($response, '([\+\-]?\d{3,4})\D*([\+\-]?\d{3,4})')
                if (-not $match.Success) {
                    Write-Error ("Unable to parse GS-232 position response: {0}" -f $response)
                    return
                }

                $azimuth = [double]$match.Groups[1].Value
                $elevation = [double]$match.Groups[2].Value
                [pscustomobject]@{
                    PSTypeName = 'AetherScope.RotatorPosition'
                    Backend = $Backend
                    Azimuth = [Math]::Round($azimuth, 2)
                    Elevation = [Math]::Round($elevation, 2)
                    HostName = $null
                    Port = $null
                    PortName = $PortName
                }
            }
        }
    }

    end {
    }
}



function Set-AetherScopeRotatorPosition {
<#
.SYNOPSIS
Sets a target azimuth and elevation on a supported rotator backend.
.DESCRIPTION
Sends a target position to either Hamlib rotctld or a GS-232 compatible serial
controller after applying optional safety limits.
.PARAMETER Backend
Rotator backend type.
.PARAMETER Azimuth
Desired azimuth in degrees.
.PARAMETER Elevation
Desired elevation in degrees.
.PARAMETER HostName
rotctld host name for HamlibTcp.
.PARAMETER Port
rotctld TCP port for HamlibTcp.
.PARAMETER PortName
Serial port for Gs232Serial.
.PARAMETER BaudRate
Serial baud rate for Gs232Serial.
.PARAMETER MinAzimuth
Minimum allowed azimuth.
.PARAMETER MaxAzimuth
Maximum allowed azimuth.
.PARAMETER MinElevation
Minimum allowed elevation.
.PARAMETER MaxElevation
Maximum allowed elevation.
.PARAMETER TimeoutMilliseconds
I/O timeout in milliseconds.
.EXAMPLE
Set-AetherScopeRotatorPosition -Backend HamlibTcp -Azimuth 150.2 -Elevation 28.4 -HostName 127.0.0.1 -Port 4533
.EXAMPLE
Set-AetherScopeRotatorPosition -Backend Gs232Serial -Azimuth 150 -Elevation 28 -PortName COM3 -BaudRate 9600 -WhatIf
.INPUTS
None
.OUTPUTS
System.Management.Automation.PSCustomObject
.NOTES
Abstracts position-setting across the supported rotator backends. Hamlib uses
rotctld TCP set-position commands, while GS-232 uses serial azimuth/elevation
commands formatted as integer-degree targets. Writes are guarded with
ShouldProcess.

.LINK
https://hamlib.sourceforge.net/html/rotctld.1.html
.LINK
https://www.radiomanual.info/schemi/ACC_rotator/Yaesu_GS-232A_user.pdf
#>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('HamlibTcp', 'Gs232Serial')]
        [string]$Backend,

        [Parameter(Mandatory = $true)]
        [double]$Azimuth,

        [Parameter(Mandatory = $true)]
        [double]$Elevation,

        [Parameter()]
        [string]$HostName = '127.0.0.1',

        [Parameter()]
        [ValidateRange(1, 65535)]
        [int]$Port = 4533,

        [Parameter()]
        [string]$PortName,

        [Parameter()]
        [ValidateRange(110, 115200)]
        [int]$BaudRate = 9600,

        [Parameter()]
        [double]$MinAzimuth = 0.0,

        [Parameter()]
        [double]$MaxAzimuth = 450.0,

        [Parameter()]
        [double]$MinElevation = 0.0,

        [Parameter()]
        [double]$MaxElevation = 180.0,

        [Parameter()]
        [ValidateRange(100, 60000)]
        [int]$TimeoutMilliseconds = 3000
    )

    begin {
    }

    process {
        $inRange = Test-RotatorTargetInRange -Azimuth $Azimuth -Elevation $Elevation -MinAzimuth $MinAzimuth -MaxAzimuth $MaxAzimuth -MinElevation $MinElevation -MaxElevation $MaxElevation
        if (-not $inRange) {
            Write-Error ("Target azimuth/elevation {0}/{1} is outside configured rotator limits." -f $Azimuth, $Elevation)
            return
        }

        if (-not $PSCmdlet.ShouldProcess($Backend, ("Set rotator position to azimuth {0:N2} elevation {1:N2}" -f $Azimuth, $Elevation))) {
            return
        }

        switch ($Backend) {
            'HamlibTcp' {
                $command = "P $Azimuth $Elevation"
                $lines = @(Invoke-HamlibRotatorCommand -HostName $HostName -Port $Port -Command $command -TimeoutMilliseconds $TimeoutMilliseconds)
                $responseText = $lines -join ' '
                if (($lines.Count -eq 0) -or ($responseText -notmatch 'RPRT\s+0')) {
                    Write-Error ("Hamlib set position did not report success: {0}" -f $responseText)
                    return
                }
            }
            'Gs232Serial' {
                if ([string]::IsNullOrWhiteSpace($PortName)) {
                    Write-Error 'PortName is required for Gs232Serial.'
                    return
                }

                $az = [int][Math]::Round($Azimuth, 0)
                $el = [int][Math]::Round($Elevation, 0)
                $command = ('W{0:D3} {1:D3}' -f $az, $el)
                Invoke-Gs232RotatorCommand -PortName $PortName -BaudRate $BaudRate -Command $command -TimeoutMilliseconds $TimeoutMilliseconds | Out-Null
            }
        }

        [pscustomobject]@{
            PSTypeName = 'AetherScope.RotatorCommandResult'
            Backend = $Backend
            Azimuth = [Math]::Round($Azimuth, 2)
            Elevation = [Math]::Round($Elevation, 2)
            Succeeded = $true
            TimeStamp = Get-Date
        }
    }

    end {
    }
}



function Stop-AetherScopeRotator {
<#
.SYNOPSIS
Stops a supported rotator backend.
.DESCRIPTION
Issues a stop command to Hamlib rotctld or to a GS-232 compatible controller.
.PARAMETER Backend
Rotator backend type.
.PARAMETER HostName
rotctld host name for HamlibTcp.
.PARAMETER Port
rotctld TCP port for HamlibTcp.
.PARAMETER PortName
Serial port for Gs232Serial.
.PARAMETER BaudRate
Serial baud rate for Gs232Serial.
.PARAMETER TimeoutMilliseconds
I/O timeout in milliseconds.
.EXAMPLE
Stop-AetherScopeRotator -Backend HamlibTcp -HostName 127.0.0.1 -Port 4533
.EXAMPLE
Stop-AetherScopeRotator -Backend Gs232Serial -PortName COM3 -BaudRate 9600 -WhatIf
.INPUTS
None
.OUTPUTS
System.Management.Automation.PSCustomObject
.NOTES
Stops motion using the selected rotator backend's native control path. Hamlib
uses the rotctld stop command; GS-232 uses the controller stop command.

.LINK
https://hamlib.sourceforge.net/html/rotctld.1.html
.LINK
https://www.radiomanual.info/schemi/ACC_rotator/Yaesu_GS-232A_user.pdf
#>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('HamlibTcp', 'Gs232Serial')]
        [string]$Backend,

        [Parameter()]
        [string]$HostName = '127.0.0.1',

        [Parameter()]
        [ValidateRange(1, 65535)]
        [int]$Port = 4533,

        [Parameter()]
        [string]$PortName,

        [Parameter()]
        [ValidateRange(110, 115200)]
        [int]$BaudRate = 9600,

        [Parameter()]
        [ValidateRange(100, 60000)]
        [int]$TimeoutMilliseconds = 3000
    )

    begin {
    }

    process {
        if (-not $PSCmdlet.ShouldProcess($Backend, 'Stop rotator motion')) {
            return
        }

        switch ($Backend) {
            'HamlibTcp' {
                $lines = @(Invoke-HamlibRotatorCommand -HostName $HostName -Port $Port -Command 'S' -TimeoutMilliseconds $TimeoutMilliseconds)
                if (($lines -join ' ') -notmatch 'RPRT\s+0') {
                    Write-Error ("Hamlib stop did not report success: {0}" -f ($lines -join ' '))
                    return
                }
            }
            'Gs232Serial' {
                if ([string]::IsNullOrWhiteSpace($PortName)) {
                    Write-Error 'PortName is required for Gs232Serial.'
                    return
                }
                Invoke-Gs232RotatorCommand -PortName $PortName -BaudRate $BaudRate -Command 'S' -TimeoutMilliseconds $TimeoutMilliseconds | Out-Null
            }
        }

        [pscustomobject]@{
            PSTypeName = 'AetherScope.RotatorCommandResult'
            Backend = $Backend
            Action = 'Stop'
            Succeeded = $true
            TimeStamp = Get-Date
        }
    }

    end {
    }
}



function Set-AetherScopeRotatorPark {
<#
.SYNOPSIS
Parks a supported rotator backend.
.DESCRIPTION
Issues a park command when supported. For GS-232 style controllers that do not
expose a common park command, this function parks by sending an explicit target
azimuth/elevation pair.
.PARAMETER Backend
Rotator backend type.
.PARAMETER ParkAzimuth
Parking azimuth in degrees.
.PARAMETER ParkElevation
Parking elevation in degrees.
.PARAMETER HostName
rotctld host name for HamlibTcp.
.PARAMETER Port
rotctld TCP port for HamlibTcp.
.PARAMETER PortName
Serial port for Gs232Serial.
.PARAMETER BaudRate
Serial baud rate for Gs232Serial.
.PARAMETER TimeoutMilliseconds
I/O timeout in milliseconds.
.EXAMPLE
Set-AetherScopeRotatorPark -Backend HamlibTcp -HostName 127.0.0.1 -Port 4533
.EXAMPLE
Set-AetherScopeRotatorPark -Backend Gs232Serial -ParkAzimuth 180 -ParkElevation 0 -PortName COM3 -WhatIf
.INPUTS
None
.OUTPUTS
System.Management.Automation.PSCustomObject
.NOTES
Moves the rotator to a parked azimuth/elevation using the selected backend.
For controllers that do not expose a distinct park primitive, this function
implements parking by issuing a normal set-position move to the requested park
coordinates.

.LINK
https://hamlib.sourceforge.net/html/rotctld.1.html
#>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('HamlibTcp', 'Gs232Serial')]
        [string]$Backend,

        [Parameter()]
        [double]$ParkAzimuth = 180.0,

        [Parameter()]
        [double]$ParkElevation = 0.0,

        [Parameter()]
        [string]$HostName = '127.0.0.1',

        [Parameter()]
        [ValidateRange(1, 65535)]
        [int]$Port = 4533,

        [Parameter()]
        [string]$PortName,

        [Parameter()]
        [ValidateRange(110, 115200)]
        [int]$BaudRate = 9600,

        [Parameter()]
        [ValidateRange(100, 60000)]
        [int]$TimeoutMilliseconds = 3000
    )

    begin {
    }

    process {
        if (-not $PSCmdlet.ShouldProcess($Backend, ("Park rotator at azimuth {0:N2} elevation {1:N2}" -f $ParkAzimuth, $ParkElevation))) {
            return
        }

        switch ($Backend) {
            'HamlibTcp' {
                $lines = @(Invoke-HamlibRotatorCommand -HostName $HostName -Port $Port -Command 'K' -TimeoutMilliseconds $TimeoutMilliseconds)
                if (($lines -join ' ') -notmatch 'RPRT\s+0') {
                    Write-Error ("Hamlib park did not report success: {0}" -f ($lines -join ' '))
                    return
                }
            }
            'Gs232Serial' {
                $parkResult = Set-AetherScopeRotatorPosition -Backend Gs232Serial -Azimuth $ParkAzimuth -Elevation $ParkElevation -PortName $PortName -BaudRate $BaudRate -TimeoutMilliseconds $TimeoutMilliseconds
                if ($null -eq $parkResult) {
                    return
                }
            }
        }

        [pscustomobject]@{
            PSTypeName = 'AetherScope.RotatorCommandResult'
            Backend = $Backend
            Action = 'Park'
            Azimuth = [Math]::Round($ParkAzimuth, 2)
            Elevation = [Math]::Round($ParkElevation, 2)
            Succeeded = $true
            TimeStamp = Get-Date
        }
    }

    end {
    }
}


function Start-AetherScopeTrack {
<#
.SYNOPSIS
Automatically points a supported rotator toward a celestial target.
.DESCRIPTION
Samples a celestial target at a fixed interval, computes the required azimuth
and elevation, applies threshold and deadband logic, and sends motion commands
only when the target is trackable and the requested move is materially different
from the prior commanded position.
.PARAMETER Body
Target body to track.
.PARAMETER Backend
Rotator backend type.
.PARAMETER Latitude
Observer latitude in decimal degrees.
.PARAMETER Longitude
Observer longitude in decimal degrees.
.PARAMETER Coordinate
Flexible observer coordinate input.
.PARAMETER ObserverAltitudeKm
Observer altitude in kilometers.
.PARAMETER IntervalSeconds
Tracking interval in seconds.
.PARAMETER MaxSamples
Maximum number of samples to collect. Use 0 for continuous tracking.
.PARAMETER MinTrackElevationDegrees
Minimum elevation required before commanding the rotator.
.PARAMETER PositionDeadbandDegrees
Minimum delta from the last commanded position before sending a new command.
.PARAMETER QueryRotatorPosition
Query the rotator before each decision.
.PARAMETER UseGpsSerial
Reads a fresh GPS fix before each sample.
.PARAMETER GpsPortName
GPS serial port name.
.PARAMETER GpsBaudRate
GPS serial baud rate.
.PARAMETER HostName
rotctld host name for HamlibTcp.
.PARAMETER Port
rotctld TCP port for HamlibTcp.
.PARAMETER PortName
Serial port for Gs232Serial.
.PARAMETER BaudRate
Serial baud rate for Gs232Serial.
.PARAMETER MinAzimuth
Minimum allowed azimuth for rotator motion.
.PARAMETER MaxAzimuth
Maximum allowed azimuth for rotator motion.
.PARAMETER MinElevation
Minimum allowed elevation for rotator motion.
.PARAMETER MaxElevation
Maximum allowed elevation for rotator motion.
.PARAMETER ParkOnExit
Parks the rotator when the loop exits.
.PARAMETER ParkAzimuth
Park azimuth.
.PARAMETER ParkElevation
Park elevation.
.PARAMETER TimeoutMilliseconds
I/O timeout in milliseconds.
.EXAMPLE
Start-AetherScopeTrack -Body ISS -Backend HamlibTcp -Coordinate '30.2752,-89.7812' -HostName 127.0.0.1 -Port 4533 -IntervalSeconds 2 -MinTrackElevationDegrees 10
.EXAMPLE
Start-AetherScopeTrack -Body Moon -Backend Gs232Serial -Coordinate '30.2752,-89.7812' -PortName COM3 -BaudRate 9600 -MaxSamples 20 -WhatIf
.INPUTS
System.Object
.OUTPUTS
System.Management.Automation.PSCustomObject
.NOTES
Implements a practical auto-tracking loop that combines computed celestial
look angles with a rotator-control backend. Safety limits, deadband, and
optional live rotator feedback are included so the loop is suitable for
station automation rather than just numerical tracking output.

.LINK
https://hamlib.sourceforge.net/html/rotctld.1.html
#>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Sun', 'Moon', 'ISS')]
        [string]$Body,

        [Parameter(Mandatory = $true)]
        [ValidateSet('HamlibTcp', 'Gs232Serial')]
        [string]$Backend,

        [Parameter()]
        [Nullable[Double]]$Latitude,

        [Parameter()]
        [Nullable[Double]]$Longitude,

        [Parameter(ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [AllowNull()]
        [Object]$Coordinate,

        [Parameter()]
        [double]$ObserverAltitudeKm = 0.0,

        [Parameter()]
        [ValidateRange(1, 3600)]
        [int]$IntervalSeconds = 2,

        [Parameter()]
        [ValidateRange(0, 1000000)]
        [int]$MaxSamples = 0,

        [Parameter()]
        [double]$MinTrackElevationDegrees = 0.0,

        [Parameter()]
        [ValidateRange(0.0, 45.0)]
        [double]$PositionDeadbandDegrees = 0.5,

        [Parameter()]
        [switch]$QueryRotatorPosition,

        [Parameter()]
        [switch]$UseGpsSerial,

        [Parameter()]
        [string]$GpsPortName,

        [Parameter()]
        [ValidateRange(110, 115200)]
        [int]$GpsBaudRate = 4800,

        [Parameter()]
        [string]$HostName = '127.0.0.1',

        [Parameter()]
        [ValidateRange(1, 65535)]
        [int]$Port = 4533,

        [Parameter()]
        [string]$PortName,

        [Parameter()]
        [ValidateRange(110, 115200)]
        [int]$BaudRate = 9600,

        [Parameter()]
        [double]$MinAzimuth = 0.0,

        [Parameter()]
        [double]$MaxAzimuth = 450.0,

        [Parameter()]
        [double]$MinElevation = 0.0,

        [Parameter()]
        [double]$MaxElevation = 180.0,

        [Parameter()]
        [switch]$ParkOnExit,

        [Parameter()]
        [double]$ParkAzimuth = 180.0,

        [Parameter()]
        [double]$ParkElevation = 0.0,

        [Parameter()]
        [ValidateRange(100, 60000)]
        [int]$TimeoutMilliseconds = 3000
    )

    begin {
        $sampleCount = 0
        $lastCommandedAzimuth = $null
        $lastCommandedElevation = $null
    }

    process {
        if ($UseGpsSerial.IsPresent -and [string]::IsNullOrWhiteSpace($GpsPortName)) {
            Write-Error 'GpsPortName is required when -UseGpsSerial is specified.'
            return
        }

        if (($Backend -eq 'Gs232Serial') -and [string]::IsNullOrWhiteSpace($PortName)) {
            Write-Error 'PortName is required when Backend is Gs232Serial.'
            return
        }

        if (-not $PSCmdlet.ShouldProcess($Body, ("Start automatic {0} tracking using backend {1}" -f $Body, $Backend))) {
            return
        }

        try {
            while (($MaxSamples -le 0) -or ($sampleCount -lt $MaxSamples)) {
                $activeCoordinate = $Coordinate
                $activeLatitude = $Latitude
                $activeLongitude = $Longitude

                if ($UseGpsSerial.IsPresent) {
                    $gpsFix = Get-AetherScopeGpsCoordinate -PortName $GpsPortName -BaudRate $GpsBaudRate -ReadCount 1 | Select-Object -First 1
                    if ($null -eq $gpsFix) {
                        Write-Verbose 'No GPS fix was returned for this tracking sample.'
                        Start-Sleep -Seconds $IntervalSeconds
                        continue
                    }

                    $activeCoordinate = $gpsFix
                    $activeLatitude = $null
                    $activeLongitude = $null
                }

                $sample = Get-AetherScopePosition -Body $Body -Latitude $activeLatitude -Longitude $activeLongitude -Coordinate $activeCoordinate -DateTime (Get-Date) -ObserverAltitudeKm $ObserverAltitudeKm
                if ($null -eq $sample) {
                    Start-Sleep -Seconds $IntervalSeconds
                    continue
                }

                $sampleCount += 1
                $targetAzimuth = [double]$sample.Azimuth
                $targetElevation = [double]$sample.Altitude
                $inRange = Test-RotatorTargetInRange -Azimuth $targetAzimuth -Elevation $targetElevation -MinAzimuth $MinAzimuth -MaxAzimuth $MaxAzimuth -MinElevation $MinElevation -MaxElevation $MaxElevation
                $shouldTrack = ($targetElevation -ge $MinTrackElevationDegrees) -and $inRange

                $rotatorAzimuth = $null
                $rotatorElevation = $null
                if ($QueryRotatorPosition.IsPresent) {
                    $rotatorPosition = Get-AetherScopeRotatorPosition -Backend $Backend -HostName $HostName -Port $Port -PortName $PortName -BaudRate $BaudRate -TimeoutMilliseconds $TimeoutMilliseconds
                    if ($null -ne $rotatorPosition) {
                        $rotatorAzimuth = [double]$rotatorPosition.Azimuth
                        $rotatorElevation = [double]$rotatorPosition.Elevation
                    }
                }

                $deltaAzimuth = $null
                $deltaElevation = $null
                $sendCommand = $false

                if ($shouldTrack) {
                    if (($null -eq $lastCommandedAzimuth) -or ($null -eq $lastCommandedElevation)) {
                        $sendCommand = $true
                    }
                    else {
                        $deltaAzimuth = [Math]::Abs($targetAzimuth - $lastCommandedAzimuth)
                        $deltaElevation = [Math]::Abs($targetElevation - $lastCommandedElevation)
                        $sendCommand = (($deltaAzimuth -ge $PositionDeadbandDegrees) -or ($deltaElevation -ge $PositionDeadbandDegrees))
                    }
                }

                $commandIssued = $false
                if ($sendCommand) {
                    $result = Set-AetherScopeRotatorPosition -Backend $Backend -Azimuth $targetAzimuth -Elevation $targetElevation -HostName $HostName -Port $Port -PortName $PortName -BaudRate $BaudRate -MinAzimuth $MinAzimuth -MaxAzimuth $MaxAzimuth -MinElevation $MinElevation -MaxElevation $MaxElevation -TimeoutMilliseconds $TimeoutMilliseconds
                    if ($null -ne $result) {
                        $lastCommandedAzimuth = $targetAzimuth
                        $lastCommandedElevation = $targetElevation
                        $commandIssued = $true
                    }
                }

                [pscustomobject]@{
                    PSTypeName = 'AetherScope.AutoTrackSample'
                    Body = $Body
                    TimeStamp = Get-Date
                    ObserverLatitude = $sample.ObserverLatitude
                    ObserverLongitude = $sample.ObserverLongitude
                    TargetAzimuth = [Math]::Round($targetAzimuth, 2)
                    TargetElevation = [Math]::Round($targetElevation, 2)
                    RotatorAzimuth = $rotatorAzimuth
                    RotatorElevation = $rotatorElevation
                    IsTrackable = [bool]$shouldTrack
                    CommandIssued = [bool]$commandIssued
                    LastCommandedAzimuth = $lastCommandedAzimuth
                    LastCommandedElevation = $lastCommandedElevation
                    PositionDeadbandDegrees = $PositionDeadbandDegrees
                    MinTrackElevationDegrees = $MinTrackElevationDegrees
                    Backend = $Backend
                    CoordinateSource = $sample.CoordinateSource
                    RangeKm = $(if ($null -ne $sample.PSObject.Properties['RangeKm']) { $sample.PSObject.Properties['RangeKm'].Value } else { $null })
                }

                if (($MaxSamples -gt 0) -and ($sampleCount -ge $MaxSamples)) {
                    break
                }

                Start-Sleep -Seconds $IntervalSeconds
            }
        }
        finally {
            if ($ParkOnExit.IsPresent) {
                Set-AetherScopeRotatorPark -Backend $Backend -ParkAzimuth $ParkAzimuth -ParkElevation $ParkElevation -HostName $HostName -Port $Port -PortName $PortName -BaudRate $BaudRate -TimeoutMilliseconds $TimeoutMilliseconds | Out-Null
            }
        }
    }

    end {
    }
}



function Start-AetherScopeIssTrack {
<#
.SYNOPSIS
Automatically points a supported rotator toward the ISS.
.DESCRIPTION
Convenience wrapper around Start-AetherScopeTrack for ISS-specific tracking.
It is intended for antenna systems that should follow the ISS across a pass.
.PARAMETER Latitude
Observer latitude in decimal degrees.
.PARAMETER Longitude
Observer longitude in decimal degrees.
.PARAMETER Coordinate
Flexible observer coordinate input.
.PARAMETER Backend
Rotator backend type.
.PARAMETER ObserverAltitudeKm
Observer altitude in kilometers.
.PARAMETER IntervalSeconds
Tracking interval in seconds.
.PARAMETER MaxSamples
Maximum number of samples to collect. Use 0 for continuous tracking.
.PARAMETER MinTrackElevationDegrees
Minimum elevation required before commanding the rotator.
.PARAMETER PositionDeadbandDegrees
Minimum delta from the last commanded position before sending a new command.
.PARAMETER QueryRotatorPosition
Query the rotator before each decision.
.PARAMETER UseGpsSerial
Reads a fresh GPS fix before each sample.
.PARAMETER GpsPortName
GPS serial port name.
.PARAMETER GpsBaudRate
GPS serial baud rate.
.PARAMETER HostName
rotctld host name for HamlibTcp.
.PARAMETER Port
rotctld TCP port for HamlibTcp.
.PARAMETER PortName
Serial port for Gs232Serial.
.PARAMETER BaudRate
Serial baud rate for Gs232Serial.
.PARAMETER MinAzimuth
Minimum allowed azimuth for rotator motion.
.PARAMETER MaxAzimuth
Maximum allowed azimuth for rotator motion.
.PARAMETER MinElevation
Minimum allowed elevation for rotator motion.
.PARAMETER MaxElevation
Maximum allowed elevation for rotator motion.
.PARAMETER ParkOnExit
Parks the rotator when the loop exits.
.PARAMETER ParkAzimuth
Park azimuth.
.PARAMETER ParkElevation
Park elevation.
.PARAMETER TimeoutMilliseconds
I/O timeout in milliseconds.
.EXAMPLE
Start-AetherScopeIssTrack -Coordinate '30.2752,-89.7812' -Backend HamlibTcp -HostName 127.0.0.1 -Port 4533 -IntervalSeconds 2 -MinTrackElevationDegrees 10
.EXAMPLE
Start-AetherScopeIssTrack -Coordinate '30.2752,-89.7812' -Backend Gs232Serial -PortName COM3 -BaudRate 9600 -MaxSamples 60 -WhatIf
.INPUTS
System.Object
.OUTPUTS
System.Management.Automation.PSCustomObject
.NOTES
Convenience wrapper around Start-AetherScopeTrack for the ISS. It combines
the WTIA-fed ISS pointing solution with the selected rotator backend so the
result can be used for practical antenna-pointing automation.

.LINK
https://hamlib.sourceforge.net/html/rotctld.1.html
.LINK
https://wheretheiss.at/w/developer
#>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([pscustomobject])]
    param(
        [Parameter()]
        [Nullable[Double]]$Latitude,

        [Parameter()]
        [Nullable[Double]]$Longitude,

        [Parameter(ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [AllowNull()]
        [Object]$Coordinate,

        [Parameter(Mandatory = $true)]
        [ValidateSet('HamlibTcp', 'Gs232Serial')]
        [string]$Backend,

        [Parameter()]
        [double]$ObserverAltitudeKm = 0.0,

        [Parameter()]
        [ValidateRange(1, 3600)]
        [int]$IntervalSeconds = 2,

        [Parameter()]
        [ValidateRange(0, 1000000)]
        [int]$MaxSamples = 0,

        [Parameter()]
        [double]$MinTrackElevationDegrees = 10.0,

        [Parameter()]
        [ValidateRange(0.0, 45.0)]
        [double]$PositionDeadbandDegrees = 0.5,

        [Parameter()]
        [switch]$QueryRotatorPosition,

        [Parameter()]
        [switch]$UseGpsSerial,

        [Parameter()]
        [string]$GpsPortName,

        [Parameter()]
        [ValidateRange(110, 115200)]
        [int]$GpsBaudRate = 4800,

        [Parameter()]
        [string]$HostName = '127.0.0.1',

        [Parameter()]
        [ValidateRange(1, 65535)]
        [int]$Port = 4533,

        [Parameter()]
        [string]$PortName,

        [Parameter()]
        [ValidateRange(110, 115200)]
        [int]$BaudRate = 9600,

        [Parameter()]
        [double]$MinAzimuth = 0.0,

        [Parameter()]
        [double]$MaxAzimuth = 450.0,

        [Parameter()]
        [double]$MinElevation = 0.0,

        [Parameter()]
        [double]$MaxElevation = 180.0,

        [Parameter()]
        [switch]$ParkOnExit,

        [Parameter()]
        [double]$ParkAzimuth = 180.0,

        [Parameter()]
        [double]$ParkElevation = 0.0,

        [Parameter()]
        [ValidateRange(100, 60000)]
        [int]$TimeoutMilliseconds = 3000
    )

    begin {
    }

    process {
        if (-not $PSCmdlet.ShouldProcess('ISS', 'Start ISS automatic tracking')) {
            return
        }

        Start-AetherScopeTrack -Body ISS -Backend $Backend -Latitude $Latitude -Longitude $Longitude -Coordinate $Coordinate -ObserverAltitudeKm $ObserverAltitudeKm -IntervalSeconds $IntervalSeconds -MaxSamples $MaxSamples -MinTrackElevationDegrees $MinTrackElevationDegrees -PositionDeadbandDegrees $PositionDeadbandDegrees -QueryRotatorPosition:$QueryRotatorPosition -UseGpsSerial:$UseGpsSerial -GpsPortName $GpsPortName -GpsBaudRate $GpsBaudRate -HostName $HostName -Port $Port -PortName $PortName -BaudRate $BaudRate -MinAzimuth $MinAzimuth -MaxAzimuth $MaxAzimuth -MinElevation $MinElevation -MaxElevation $MaxElevation -ParkOnExit:$ParkOnExit -ParkAzimuth $ParkAzimuth -ParkElevation $ParkElevation -TimeoutMilliseconds $TimeoutMilliseconds
    }

    end {
    }
}



function Write-ConsoleFrameInPlace {
<#
.SYNOPSIS
Writes a block of text to the console at a fixed location.
.DESCRIPTION
Rewrites the same console region so callers can present a live dashboard without
emitting a new line for each refresh cycle. Lines are truncated or padded to the
available console width to reduce visual artifacts from prior content.
.PARAMETER Line
Text lines to render.
.PARAMETER OriginLeft
Zero-based console column where rendering starts.
.PARAMETER OriginTop
Zero-based console row where rendering starts.
.PARAMETER Width
Target width used for truncation and padding. Defaults to the active console width.
.PARAMETER PreviousLineCount
The number of lines rendered by the previous frame so extra stale lines can be cleared.
.EXAMPLE
Write-ConsoleFrameInPlace -Line @('Header','Line 1') -OriginLeft 0 -OriginTop 0 -PreviousLineCount 0
.EXAMPLE
Write-ConsoleFrameInPlace -Line @('Updated Header','Updated Line 1') -OriginLeft 0 -OriginTop 0 -PreviousLineCount 2 -WhatIf
.INPUTS
System.String[]
.OUTPUTS
None
.NOTES
Uses the .NET Console cursor APIs so the same screen region is updated in place.
This helper is intended for interactive console hosts.
#>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Line,

        [Parameter()]
        [ValidateRange(0, 5000)]
        [int]$OriginLeft = 0,

        [Parameter()]
        [ValidateRange(0, 5000)]
        [int]$OriginTop = 0,

        [Parameter()]
        [ValidateRange(0, 5000)]
        [int]$Width = 0,

        [Parameter()]
        [ValidateRange(0, 5000)]
        [int]$PreviousLineCount = 0
    )

    begin {
    }

    process {
        if (-not $PSCmdlet.ShouldProcess('Console', 'Write frame in place')) {
            return
        }

        try {
            $bufferWidth = 120
            $bufferHeight = 300

            try {
                $bufferWidth = [Console]::BufferWidth
                $bufferHeight = [Console]::BufferHeight
            }
            catch {
                try {
                    $bufferWidth = $Host.UI.RawUI.BufferSize.Width
                    $bufferHeight = $Host.UI.RawUI.BufferSize.Height
                }
                catch {
                }
            }

            if ($Width -le 0) {
                try {
                    $Width = [Math]::Max(20, $Host.UI.RawUI.WindowSize.Width - $OriginLeft)
                }
                catch {
                    $Width = 120
                }
            }

            $Width = [Math]::Max(1, [Math]::Min($Width, [Math]::Max(1, $bufferWidth - $OriginLeft)))

            $totalLines = [Math]::Max($PreviousLineCount, $Line.Count)
            if ($totalLines -gt $bufferHeight) {
                $totalLines = $bufferHeight
            }

            $safeOriginLeft = [Math]::Max(0, [Math]::Min($OriginLeft, [Math]::Max(0, $bufferWidth - 1)))
            $safeOriginTop = [Math]::Max(0, [Math]::Min($OriginTop, [Math]::Max(0, $bufferHeight - $totalLines)))

            for ($index = 0; $index -lt $totalLines; $index++) {
                $text = ''
                if ($index -lt $Line.Count) {
                    $text = [string]$Line[$index]
                }

                if ($text.Length -gt $Width) {
                    $text = $text.Substring(0, $Width)
                }
                else {
                    $text = $text.PadRight($Width)
                }

                [Console]::SetCursorPosition($safeOriginLeft, $safeOriginTop + $index)
                [Console]::Write($text)
            }
        }
        catch {
            Write-Error ("Failed to write console frame: {0}" -f $_.Exception.Message)
        }
    }

    end {
    }
}



function Convert-RightAscensionHoursToDegrees {
    param(
        [double]$RightAscensionHours
    )

    return $RightAscensionHours * 15.0
}



function Resolve-FixedStarDefinition {
<#
.SYNOPSIS
Resolves a built-in fixed star name to a star definition object.
.DESCRIPTION
Looks up a star name in the built-in fixed star catalog and returns its right
ascension and declination values.
.PARAMETER Name
Name of the built-in star.
.EXAMPLE
Resolve-FixedStarDefinition -Name Polaris
.EXAMPLE
Resolve-FixedStarDefinition -Name Vega -WhatIf
.INPUTS
System.String
.OUTPUTS
System.Management.Automation.PSCustomObject
.NOTES
This helper resolves only the built-in star list supplied by Get-AetherScopeStarCatalog.
#>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    begin {
    }

    process {
        $catalog = Get-AetherScopeStarCatalog
        $match = $catalog | Where-Object { $_.Name -eq $Name } | Select-Object -First 1
        if ($null -eq $match) {
            Write-Error ("Unknown star '{0}'. Use Get-AetherScopeStarCatalog to see supported names." -f $Name)
            return
        }

        if ($PSCmdlet.ShouldProcess($Name, 'Resolve built-in fixed star')) {
            $match
        }
    }

    end {
    }
}



function Convert-RightAscensionDegreesToHours {
    param([double]$RightAscensionDegrees)
    return $RightAscensionDegrees / 15.0
}



function Get-JulianCenturiesJ2000 {
<#
.SYNOPSIS
Gets Julian centuries since J2000.0.
.DESCRIPTION
Converts a DateTime into Julian centuries relative to JD 2451545.0.
.PARAMETER DateTime
Date and time to convert.
.EXAMPLE
Get-JulianCenturiesJ2000 -DateTime (Get-Date)
.INPUTS
System.DateTime
.OUTPUTS
System.Double
.NOTES
Used by the stage-2 and stage-3 precision star pipeline.
#>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([double])]
    param(
        [Parameter(Mandatory = $true)]
        [datetime]$DateTime
    )

    process {
        $jd = Get-JulianDate -DateTime $DateTime
        if ($PSCmdlet.ShouldProcess($DateTime, 'Compute Julian centuries since J2000.0')) {
            return (($jd - 2451545.0) / 36525.0)
        }
    }
}



function Get-MeanObliquityDegrees {
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([double])]
    param(
        [Parameter(Mandatory = $true)]
        [datetime]$DateTime
    )

    process {
        $t = Get-JulianCenturiesJ2000 -DateTime $DateTime
        $seconds = 21.448 - (46.8150 * $t) - (0.00059 * $t * $t) + (0.001813 * $t * $t * $t)
        $value = 23.0 + (26.0 / 60.0) + ($seconds / 3600.0)
        if ($PSCmdlet.ShouldProcess($DateTime, 'Compute mean obliquity')) {
            return $value
        }
    }
}



function Get-SimplifiedNutation {
<#
.SYNOPSIS
Gets a simplified nutation model.
.DESCRIPTION
Computes a compact Meeus-style nutation approximation for longitude and
obliquity. This is a practical model, not a full IAU 2000A/2006 implementation.
.PARAMETER DateTime
Observation time.
.EXAMPLE
Get-SimplifiedNutation -DateTime (Get-Date)
.INPUTS
System.DateTime
.OUTPUTS
System.Management.Automation.PSCustomObject
.NOTES
This stage-2 helper is based on low-order nutation terms suitable for practical
tracking. For observatory-grade work, use the helper DLL boundary so the engine
can be replaced with SOFA or NOVAS later.
.LINK
https://www.iausofa.org/
.LINK
https://aa.usno.navy.mil/downloads/novas/NOVAS_C3.1_Guide.pdf
#>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [datetime]$DateTime
    )

    process {
        $t = Get-JulianCenturiesJ2000 -DateTime $DateTime
        $omega = Normalize-Angle -Degrees (125.04452 - (1934.136261 * $t) + (0.0020708 * $t * $t) + (($t * $t * $t) / 450000.0))
        $sunMeanLongitude = Normalize-Angle -Degrees (280.4665 + (36000.7698 * $t))
        $moonMeanLongitude = Normalize-Angle -Degrees (218.3165 + (481267.8813 * $t))

        $omegaRad = ConvertTo-Radians -Degrees $omega
        $sunMeanLongitudeRad = ConvertTo-Radians -Degrees $sunMeanLongitude
        $moonMeanLongitudeRad = ConvertTo-Radians -Degrees $moonMeanLongitude

        $deltaPsiArcSec = (-17.20 * [Math]::Sin($omegaRad)) - (1.32 * [Math]::Sin(2.0 * $sunMeanLongitudeRad)) - (0.23 * [Math]::Sin(2.0 * $moonMeanLongitudeRad)) + (0.21 * [Math]::Sin(2.0 * $omegaRad))
        $deltaEpsilonArcSec = (9.20 * [Math]::Cos($omegaRad)) + (0.57 * [Math]::Cos(2.0 * $sunMeanLongitudeRad)) + (0.10 * [Math]::Cos(2.0 * $moonMeanLongitudeRad)) - (0.09 * [Math]::Cos(2.0 * $omegaRad))

        if ($PSCmdlet.ShouldProcess($DateTime, 'Compute simplified nutation')) {
            [pscustomobject]@{
                PSTypeName = 'AetherScope.Nutation'
                DateTime = $DateTime
                DeltaPsiArcSeconds = $deltaPsiArcSec
                DeltaEpsilonArcSeconds = $deltaEpsilonArcSec
                DeltaPsiDegrees = ($deltaPsiArcSec / 3600.0)
                DeltaEpsilonDegrees = ($deltaEpsilonArcSec / 3600.0)
            }
        }
    }
}



function Get-SolarEclipticLongitude {
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [datetime]$DateTime
    )

    process {
        $t = Get-JulianCenturiesJ2000 -DateTime $DateTime
        $L0 = Normalize-Angle -Degrees (280.46646 + (36000.76983 * $t) + (0.0003032 * $t * $t))
        $M = Normalize-Angle -Degrees (357.52911 + (35999.05029 * $t) - (0.0001537 * $t * $t))
        $Mrad = ConvertTo-Radians -Degrees $M
        $C = ((1.914602 - (0.004817 * $t) - (0.000014 * $t * $t)) * [Math]::Sin($Mrad)) + ((0.019993 - (0.000101 * $t)) * [Math]::Sin(2.0 * $Mrad)) + (0.000289 * [Math]::Sin(3.0 * $Mrad))
        $trueLongitude = Normalize-Angle -Degrees ($L0 + $C)
        $e = 0.016708634 - (0.000042037 * $t) - (0.0000001267 * $t * $t)
        $pi = Normalize-Angle -Degrees (102.93735 + (1.71946 * $t) + (0.00046 * $t * $t))

        if ($PSCmdlet.ShouldProcess($DateTime, 'Compute solar ecliptic longitude')) {
            [pscustomobject]@{
                TrueLongitudeDegrees = $trueLongitude
                Eccentricity = $e
                PerihelionLongitudeDegrees = $pi
            }
        }
    }
}



function Convert-StarCatalogToApparentPlace {
<#
.SYNOPSIS
Converts catalog star coordinates to an apparent place.
.DESCRIPTION
Applies a staged precision pipeline for fixed stars:
Stage 1: catalog coordinates only.
Stage 2: proper motion, precession, compact nutation, and compact annual aberration.
Stage 3: helper DLL boundary when available, otherwise stage-2 fallback.
.PARAMETER RightAscensionHours
Catalog right ascension in decimal hours.
.PARAMETER Declination
Catalog declination in decimal degrees.
.PARAMETER DateTime
Observation time.
.PARAMETER PrecisionStage
Precision stage to apply.
.PARAMETER ProperMotionRaMasPerYear
Proper motion in right ascension as milli-arcseconds per Julian year. This stage-2
implementation treats the value as an angular RA motion rather than a pmRA*cos(dec)
term.
.PARAMETER ProperMotionDecMasPerYear
Proper motion in declination as milli-arcseconds per Julian year.
.PARAMETER ReferenceEpochJulianYear
Reference catalog epoch, usually 2000.0.
.EXAMPLE
Convert-StarCatalogToApparentPlace -RightAscensionHours 18.6156490 -Declination 38.7836889 -DateTime (Get-Date) -PrecisionStage 2
.INPUTS
None
.OUTPUTS
System.Management.Automation.PSCustomObject
.NOTES
Stage 2 deliberately uses compact, PowerShell-friendly approximations. Stage 3 is a
DLL boundary intended to be replaced with SOFA/ERFA or NOVAS-backed code without
changing the PowerShell calling pattern.
.LINK
https://www.iausofa.org/
.LINK
https://aa.usno.navy.mil/downloads/novas/NOVAS_C3.1_Guide.pdf
#>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [double]$RightAscensionHours,

        [Parameter(Mandatory = $true)]
        [double]$Declination,

        [Parameter(Mandatory = $true)]
        [datetime]$DateTime,

        [Parameter()]
        [ValidateSet(1, 2, 3)]
        [int]$PrecisionStage = 2,

        [Parameter()]
        [double]$ProperMotionRaMasPerYear = 0.0,

        [Parameter()]
        [double]$ProperMotionDecMasPerYear = 0.0,

        [Parameter()]
        [double]$ReferenceEpochJulianYear = 2000.0,

        [Parameter()]
        [string]$HelperAssemblyPath
    )

    process {
        if (-not $PSCmdlet.ShouldProcess('Catalog star coordinate', 'Convert to apparent place')) {
            return
        }

        if ($PrecisionStage -eq 1) {
            return [pscustomobject]@{
                RightAscensionHours = $RightAscensionHours
                Declination = $Declination
                Stage = 1
                AppliedCorrections = @('None')
                Engine = 'CatalogOnly'
            }
        }

        if (($PrecisionStage -eq 3) -and (Import-AetherScopePrecisionHelper -Path $HelperAssemblyPath -Quiet)) {
            $jd = Get-JulianDate -DateTime $DateTime
            $result = [AetherScopePrecision.PrecisionTransforms]::Transform(
                [double]$jd,
                [double]$RightAscensionHours,
                [double]$Declination,
                [double]$ProperMotionRaMasPerYear,
                [double]$ProperMotionDecMasPerYear,
                [double]$ReferenceEpochJulianYear
            )

            return [pscustomobject]@{
                RightAscensionHours = [double]$result.RightAscensionHours
                Declination = [double]$result.DeclinationDegrees
                Stage = 3
                AppliedCorrections = @('ProperMotion', 'Precession', 'Nutation', 'Aberration')
                Engine = 'AetherScopePrecisionHelper'
            }
        }

        $yearsSinceEpoch = (((Get-JulianDate -DateTime $DateTime) - 2451545.0) / 365.25) - ($ReferenceEpochJulianYear - 2000.0)
        $raDegrees = Convert-RightAscensionHoursToDegrees -RightAscensionHours $RightAscensionHours
        $decDegrees = $Declination

        # Proper motion.
        $raDegrees = $raDegrees + (($ProperMotionRaMasPerYear / 1000.0) / 3600.0 * $yearsSinceEpoch)
        $decDegrees = $decDegrees + (($ProperMotionDecMasPerYear / 1000.0) / 3600.0 * $yearsSinceEpoch)

        # Precession (compact Meeus/J2000-to-date form).
        $t = ((Get-JulianDate -DateTime $DateTime) - 2451545.0) / 36525.0
        $zeta = ConvertTo-Radians -Degrees (((2306.2181 * $t) + (0.30188 * $t * $t) + (0.017998 * $t * $t * $t)) / 3600.0)
        $z = ConvertTo-Radians -Degrees (((2306.2181 * $t) + (1.09468 * $t * $t) + (0.018203 * $t * $t * $t)) / 3600.0)
        $theta = ConvertTo-Radians -Degrees (((2004.3109 * $t) - (0.42665 * $t * $t) - (0.041833 * $t * $t * $t)) / 3600.0)

        $alphaRad = ConvertTo-Radians -Degrees $raDegrees
        $deltaRad = ConvertTo-Radians -Degrees $decDegrees

        $A = [Math]::Cos($deltaRad) * [Math]::Sin($alphaRad + $zeta)
        $B = ([Math]::Cos($theta) * [Math]::Cos($deltaRad) * [Math]::Cos($alphaRad + $zeta)) - ([Math]::Sin($theta) * [Math]::Sin($deltaRad))
        $C = ([Math]::Sin($theta) * [Math]::Cos($deltaRad) * [Math]::Cos($alphaRad + $zeta)) + ([Math]::Cos($theta) * [Math]::Sin($deltaRad))

        $alphaRad = [Math]::Atan2($A, $B) + $z
        $deltaRad = [Math]::Asin($C)

        # Nutation.
        $nutation = Get-SimplifiedNutation -DateTime $DateTime
        $epsilonDegrees = (Get-MeanObliquityDegrees -DateTime $DateTime) + [double]$nutation.DeltaEpsilonDegrees
        $epsilonRad = ConvertTo-Radians -Degrees $epsilonDegrees
        $deltaPsiRad = ConvertTo-Radians -Degrees ([double]$nutation.DeltaPsiDegrees)
        $deltaEpsilonRad = ConvertTo-Radians -Degrees ([double]$nutation.DeltaEpsilonDegrees)

        $deltaAlphaNutation = (([Math]::Cos($epsilonRad) + ([Math]::Sin($epsilonRad) * [Math]::Sin($alphaRad) * [Math]::Tan($deltaRad))) * $deltaPsiRad) - ([Math]::Cos($alphaRad) * [Math]::Tan($deltaRad) * $deltaEpsilonRad)
        $deltaDeltaNutation = ([Math]::Sin($epsilonRad) * [Math]::Cos($alphaRad) * $deltaPsiRad) + ([Math]::Sin($alphaRad) * $deltaEpsilonRad)

        $alphaRad = $alphaRad + $deltaAlphaNutation
        $deltaRad = $deltaRad + $deltaDeltaNutation

        # Annual aberration (compact practical approximation).
        $solar = Get-SolarEclipticLongitude -DateTime $DateTime
        $lambdaRad = ConvertTo-Radians -Degrees ([double]$solar.TrueLongitudeDegrees)
        $perihelionRad = ConvertTo-Radians -Degrees ([double]$solar.PerihelionLongitudeDegrees)
        $kappaRad = ConvertTo-Radians -Degrees (20.49552 / 3600.0)
        $e = [double]$solar.Eccentricity

        $cosAlpha = [Math]::Cos($alphaRad)
        $sinAlpha = [Math]::Sin($alphaRad)
        $cosDelta = [Math]::Cos($deltaRad)
        $sinDelta = [Math]::Sin($deltaRad)
        $tanDelta = [Math]::Tan($deltaRad)
        $tanEpsilon = [Math]::Tan($epsilonRad)

        $deltaAlphaAberration = ((-$kappaRad) * (($cosAlpha * [Math]::Cos($lambdaRad) * [Math]::Cos($epsilonRad)) + ($sinAlpha * [Math]::Sin($lambdaRad))) / $cosDelta) + (($e * $kappaRad) * (($cosAlpha * [Math]::Cos($perihelionRad) * [Math]::Cos($epsilonRad)) + ($sinAlpha * [Math]::Sin($perihelionRad))) / $cosDelta)

        $common1 = ($tanEpsilon * $cosDelta) - ($sinAlpha * $sinDelta)
        $deltaDeltaAberration = ((-$kappaRad) * (([Math]::Cos($lambdaRad) * [Math]::Cos($epsilonRad) * $common1) + ($cosAlpha * $sinDelta * [Math]::Sin($lambdaRad)))) + (($e * $kappaRad) * (([Math]::Cos($perihelionRad) * [Math]::Cos($epsilonRad) * $common1) + ($cosAlpha * $sinDelta * [Math]::Sin($perihelionRad))))

        $alphaRad = $alphaRad + $deltaAlphaAberration
        $deltaRad = $deltaRad + $deltaDeltaAberration

        $outRaDegrees = Normalize-Angle -Degrees (ConvertTo-Degrees -Radians $alphaRad)
        $outDecDegrees = ConvertTo-Degrees -Radians $deltaRad

        [pscustomobject]@{
            RightAscensionHours = (Convert-RightAscensionDegreesToHours -RightAscensionDegrees $outRaDegrees)
            Declination = $outDecDegrees
            Stage = 2
            AppliedCorrections = @('ProperMotion', 'Precession', 'Nutation', 'Aberration')
            Engine = 'PowerShellCompactAstrometry'
        }
    }
}



function Import-AetherScopePrecisionHelper {
<#
.SYNOPSIS
Loads the AetherScope precision helper assembly.
.DESCRIPTION
Loads the helper DLL used by precision stage 3. If no path is supplied, the
function looks for AetherScopePrecisionHelper.dll beside this script.
.PARAMETER Path
Path to the helper DLL.
.PARAMETER Quiet
Suppresses non-terminating errors and returns $false on failure.
.EXAMPLE
Import-AetherScopePrecisionHelper
.EXAMPLE
Import-AetherScopePrecisionHelper -Path .\AetherScopePrecisionHelper.dll -Quiet
.INPUTS
None
.OUTPUTS
System.Boolean
.NOTES
This helper provides a stable DLL boundary so the internal implementation can be
replaced later with SOFA/ERFA or NOVAS-backed code.
#>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([bool])]
    param(
        [Parameter()]
        [string]$Path,

        [Parameter()]
        [switch]$Quiet
    )

    process {
        if ('AetherScopePrecision.PrecisionTransforms' -as [type]) {
            return $true
        }

        if ([string]::IsNullOrWhiteSpace($Path)) {
            $Path = Join-Path -Path $PSScriptRoot -ChildPath 'AetherScopePrecisionHelper.dll'
        }

        if (-not (Test-Path -LiteralPath $Path)) {
            if (-not $Quiet) {
                Write-Error ("Helper assembly not found: {0}" -f $Path)
            }
            return $false
        }

        if ($PSCmdlet.ShouldProcess($Path, 'Load AetherScope precision helper assembly')) {
            try {
                Add-Type -Path $Path -ErrorAction Stop
                return $true
            }
            catch {
                if (-not $Quiet) {
                    Write-Error ("Failed to load helper assembly '{0}': {1}" -f $Path, $_.Exception.Message)
                }
                return $false
            }
        }

        return $false
    }
}



function Get-AetherScopeStarCatalog {
<#
.SYNOPSIS
Gets the built-in fixed star catalog with optional proper motion metadata.
.DESCRIPTION
Returns a small built-in bright-star catalog with J2000-era coordinates and
practical proper-motion values used by the precision fixed-star pipeline.
.EXAMPLE
Get-AetherScopeStarCatalog
.INPUTS
None
.OUTPUTS
System.Management.Automation.PSCustomObject
.NOTES
The proper-motion values are included to make stage-2 and stage-3 precision
tracking practical. For serious astrometry, prefer an external catalog and a
precision engine behind the helper DLL boundary.
#>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([pscustomobject])]
    param()

    begin {
        $catalog = @(
            [pscustomobject]@{ PSTypeName='AetherScope.FixedStar'; Name='Polaris'; RightAscensionHours=2.5303028; Declination=89.2641111; Constellation='Ursa Minor'; Magnitude=1.98; CoordinateEpoch='J2000'; ReferenceEpochJulianYear=2000.0; ProperMotionRaMasPerYear=198.8; ProperMotionDecMasPerYear=-15.6 },
            [pscustomobject]@{ PSTypeName='AetherScope.FixedStar'; Name='Sirius'; RightAscensionHours=6.7524769; Declination=-16.7161167; Constellation='Canis Major'; Magnitude=-1.46; CoordinateEpoch='J2000'; ReferenceEpochJulianYear=2000.0; ProperMotionRaMasPerYear=-546.0; ProperMotionDecMasPerYear=-1223.1 },
            [pscustomobject]@{ PSTypeName='AetherScope.FixedStar'; Name='Vega'; RightAscensionHours=18.6156490; Declination=38.7836889; Constellation='Lyra'; Magnitude=0.03; CoordinateEpoch='J2000'; ReferenceEpochJulianYear=2000.0; ProperMotionRaMasPerYear=200.9; ProperMotionDecMasPerYear=286.2 },
            [pscustomobject]@{ PSTypeName='AetherScope.FixedStar'; Name='Betelgeuse'; RightAscensionHours=5.9195293; Declination=7.4070639; Constellation='Orion'; Magnitude=0.50; CoordinateEpoch='J2000'; ReferenceEpochJulianYear=2000.0; ProperMotionRaMasPerYear=27.5; ProperMotionDecMasPerYear=10.9 },
            [pscustomobject]@{ PSTypeName='AetherScope.FixedStar'; Name='Rigel'; RightAscensionHours=5.2422978; Declination=-8.2016389; Constellation='Orion'; Magnitude=0.13; CoordinateEpoch='J2000'; ReferenceEpochJulianYear=2000.0; ProperMotionRaMasPerYear=1.9; ProperMotionDecMasPerYear=0.6 }
        )
    }

    process {
        foreach ($star in $catalog) {
            if ($PSCmdlet.ShouldProcess($star.Name, 'Return fixed star definition')) {
                $star
            }
        }
    }
}



function Get-AetherScopeStarPosition {
<#
.SYNOPSIS
Gets the altitude and azimuth of a fixed star for an observer location.
.DESCRIPTION
Calculates horizontal coordinates for a fixed star using a staged precision
pipeline. Stage 1 uses catalog coordinates only. Stage 2 applies compact
PowerShell corrections. Stage 3 uses the helper DLL when available.
.PARAMETER StarName
Built-in fixed star name.
.PARAMETER RightAscensionHours
Catalog right ascension in decimal hours.
.PARAMETER Declination
Catalog declination in decimal degrees.
.PARAMETER PrecisionStage
Precision stage to apply.
.PARAMETER ProperMotionRaMasPerYear
Proper motion in right ascension as milli-arcseconds per Julian year.
.PARAMETER ProperMotionDecMasPerYear
Proper motion in declination as milli-arcseconds per Julian year.
.PARAMETER ReferenceEpochJulianYear
Reference epoch, usually 2000.0.
.PARAMETER HelperAssemblyPath
Optional path to AetherScopePrecisionHelper.dll.
.EXAMPLE
Get-AetherScopeStarPosition -StarName Vega -Coordinate '30.2752,-89.7812' -PrecisionStage 2
.EXAMPLE
Get-AetherScopeStarPosition -StarName Polaris -Coordinate '30.2752,-89.7812' -PrecisionStage 3 -WhatIf
.INPUTS
System.Object
.OUTPUTS
System.Management.Automation.PSCustomObject
.NOTES
Stage 2 is a practical approximation. Stage 3 keeps the PowerShell surface area
stable while allowing a future SOFA or NOVAS-grade implementation behind the DLL.
.LINK
https://www.iausofa.org/
.LINK
https://aa.usno.navy.mil/downloads/novas/NOVAS_C3.1_Guide.pdf
#>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([pscustomobject])]
    param(
        [Parameter()]
        [string]$StarName,
        [Parameter()]
        [Nullable[Double]]$RightAscensionHours,
        [Parameter()]
        [Nullable[Double]]$Declination,
        [Parameter()]
        [Nullable[Double]]$Latitude,
        [Parameter()]
        [Nullable[Double]]$Longitude,
        [Parameter(ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [AllowNull()]
        [Object]$Coordinate,
        [Parameter()]
        [datetime]$DateTime = (Get-Date),
        [Parameter()]
        [ValidateSet(1,2,3)]
        [int]$PrecisionStage = 2,
        [Parameter()]
        [double]$ProperMotionRaMasPerYear = 0.0,
        [Parameter()]
        [double]$ProperMotionDecMasPerYear = 0.0,
        [Parameter()]
        [double]$ReferenceEpochJulianYear = 2000.0,
        [Parameter()]
        [string]$HelperAssemblyPath
    )

    process {
        $resolved = Resolve-AetherScopeCoordinate -Latitude $Latitude -Longitude $Longitude -Coordinate $Coordinate
        if ($null -eq $resolved) { return }

        $effectiveRaHours = $RightAscensionHours
        $effectiveDeclination = $Declination
        $effectiveName = $StarName
        $constellation = $null
        $magnitude = $null
        $epoch = 'Custom'

        if (-not [string]::IsNullOrWhiteSpace($StarName)) {
            $star = Resolve-FixedStarDefinition -Name $StarName
            if ($null -eq $star) { return }
            $effectiveRaHours = [double]$star.RightAscensionHours
            $effectiveDeclination = [double]$star.Declination
            $effectiveName = [string]$star.Name
            $constellation = [string]$star.Constellation
            $magnitude = [double]$star.Magnitude
            $epoch = [string]$star.CoordinateEpoch
            $ProperMotionRaMasPerYear = [double]$star.ProperMotionRaMasPerYear
            $ProperMotionDecMasPerYear = [double]$star.ProperMotionDecMasPerYear
            $ReferenceEpochJulianYear = [double]$star.ReferenceEpochJulianYear
        }

        if (($effectiveRaHours -eq $null) -or ($effectiveDeclination -eq $null)) {
            Write-Error 'Provide -StarName, or specify both -RightAscensionHours and -Declination.'
            return
        }

        if (-not $PSCmdlet.ShouldProcess($effectiveName, 'Calculate fixed star altitude and azimuth')) {
            return
        }

        $apparent = Convert-StarCatalogToApparentPlace -RightAscensionHours ([double]$effectiveRaHours) -Declination ([double]$effectiveDeclination) -DateTime $DateTime -PrecisionStage $PrecisionStage -ProperMotionRaMasPerYear $ProperMotionRaMasPerYear -ProperMotionDecMasPerYear $ProperMotionDecMasPerYear -ReferenceEpochJulianYear $ReferenceEpochJulianYear -HelperAssemblyPath $HelperAssemblyPath
        if ($null -eq $apparent) { return }

        $utc = $DateTime.ToUniversalTime()
        $lst = Get-LocalSiderealTime -DateTime $utc -Longitude $resolved.Longitude
        $rightAscensionDegrees = Convert-RightAscensionHoursToDegrees -RightAscensionHours ([double]$apparent.RightAscensionHours)
        $hourAngle = Normalize-Angle -Degrees ($lst - $rightAscensionDegrees)
        if ($hourAngle -gt 180.0) { $hourAngle -= 360.0 }

        $latitudeRad = ConvertTo-Radians -Degrees $resolved.Latitude
        $declinationRad = ConvertTo-Radians -Degrees ([double]$apparent.Declination)
        $hourAngleRad = ConvertTo-Radians -Degrees $hourAngle

        $altitude = ConvertTo-Degrees -Radians ([Math]::Asin(([Math]::Sin($declinationRad) * [Math]::Sin($latitudeRad)) + ([Math]::Cos($declinationRad) * [Math]::Cos($latitudeRad) * [Math]::Cos($hourAngleRad))))
        $azimuth = ConvertTo-Degrees -Radians ([Math]::Atan2([Math]::Sin($hourAngleRad), ([Math]::Cos($hourAngleRad) * [Math]::Sin($latitudeRad)) - ([Math]::Tan($declinationRad) * [Math]::Cos($latitudeRad))))
        $azimuth = Normalize-Angle -Degrees ($azimuth + 180.0)

        [pscustomobject]@{
            PSTypeName = 'AetherScope.FixedStarPosition'
            Body = 'Star'
            Name = $effectiveName
            Latitude = $resolved.Latitude
            Longitude = $resolved.Longitude
            DateTime = $DateTime
            UtcDateTime = $utc
            Azimuth = [Math]::Round($azimuth, 2)
            Altitude = [Math]::Round($altitude, 2)
            RightAscensionHours = [Math]::Round([double]$apparent.RightAscensionHours, 6)
            RightAscensionDegrees = [Math]::Round($rightAscensionDegrees, 6)
            Declination = [Math]::Round([double]$apparent.Declination, 6)
            HourAngle = [Math]::Round($hourAngle, 6)
            IsAboveHorizon = ([double]$altitude -ge 0.0)
            CoordinateSource = $resolved.Source
            Constellation = $constellation
            Magnitude = $magnitude
            CoordinateEpoch = $epoch
            PrecisionStage = $PrecisionStage
            PrecisionEngine = $apparent.Engine
            AppliedCorrections = ($apparent.AppliedCorrections -join ',')
        }
    }
}



function Get-AetherScopePrecisionStarPosition {
<#
.SYNOPSIS
Convenience wrapper for staged precision fixed-star tracking.
.DESCRIPTION
Calls Get-AetherScopeStarPosition with the precision pipeline enabled.
.EXAMPLE
Get-AetherScopePrecisionStarPosition -StarName Polaris -Coordinate '30.2752,-89.7812' -PrecisionStage 3
#>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([pscustomobject])]
    param(
        [Parameter()]
        [string]$StarName,
        [Parameter()]
        [Nullable[Double]]$RightAscensionHours,
        [Parameter()]
        [Nullable[Double]]$Declination,
        [Parameter()]
        [Nullable[Double]]$Latitude,
        [Parameter()]
        [Nullable[Double]]$Longitude,
        [Parameter(ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [AllowNull()]
        [Object]$Coordinate,
        [Parameter()]
        [datetime]$DateTime = (Get-Date),
        [Parameter()]
        [ValidateSet(1,2,3)]
        [int]$PrecisionStage = 3,
        [Parameter()]
        [string]$HelperAssemblyPath
    )

    process {
        Get-AetherScopeStarPosition -StarName $StarName -RightAscensionHours $RightAscensionHours -Declination $Declination -Latitude $Latitude -Longitude $Longitude -Coordinate $Coordinate -DateTime $DateTime -PrecisionStage $PrecisionStage -HelperAssemblyPath $HelperAssemblyPath
    }
}



function Get-AetherScopeStarReferenceSet {
<#
.SYNOPSIS
Gets a built-in reference set of bright stars for tracker validation.
.DESCRIPTION
Returns one or more built-in star profiles that are useful for validating
fixed-star dashboard output, azimuth/altitude conversion logic, and rotator
tracking behavior. The default profile returns Polaris, Sirius, and Vega as a
balanced north/south/high-altitude reference set for many northern observers.
.PARAMETER Profile
Named built-in reference profile.
.PARAMETER IncludeDefinitions
Returns the full built-in star catalog objects for the selected reference set
instead of returning only star names.
.EXAMPLE
Get-AetherScopeStarReferenceSet
.EXAMPLE
Get-AetherScopeStarReferenceSet -Profile BrightReference -IncludeDefinitions
.EXAMPLE
Start-AetherScopeDashboard -Coordinate '30.2752,-89.7812' -Body Sun,Moon,ISS -StarName (Get-AetherScopeStarReferenceSet)
.EXAMPLE
(Get-AetherScopeStarReferenceSet -IncludeDefinitions).Name | ForEach-Object {
    Get-AetherScopeStarPosition -StarName $_ -Coordinate '30.2752,-89.7812'
}
.INPUTS
None
.OUTPUTS
System.String
System.Management.Automation.PSCustomObject
.NOTES
Default profile members:
- Polaris: near the north celestial pole; excellent for north-pointing sanity checks.
- Sirius: bright southern-sky star for rise/set and southern tracking checks.
- Vega: bright northern-sky star that often reaches high altitude.
This helper is intended for practical tracker validation rather than as a formal
astronomical catalog query surface.
#>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([string], [pscustomobject])]
    param(
        [Parameter()]
        [ValidateSet('BrightReference', 'NorthernAlignment', 'SeasonalMixed')]
        [string]$Profile = 'BrightReference',

        [Parameter()]
        [switch]$IncludeDefinitions
    )

    begin {
        $profileMap = @{
            BrightReference = @('Polaris', 'Sirius', 'Vega')
            NorthernAlignment = @('Polaris', 'Vega')
            SeasonalMixed = @('Polaris', 'Betelgeuse', 'Rigel', 'Sirius', 'Vega')
        }
    }

    process {
        $selectedNames = $profileMap[$Profile]
        if ($null -eq $selectedNames) {
            Write-Error ('Unknown star reference profile: {0}' -f $Profile)
            return
        }

        if ($IncludeDefinitions) {
            $catalog = @(Get-AetherScopeStarCatalog)
            foreach ($name in $selectedNames) {
                $match = $catalog | Where-Object { $_.Name -eq $name } | Select-Object -First 1
                if ($null -ne $match) {
                    if ($PSCmdlet.ShouldProcess($name, 'Return star reference definition')) {
                        $match
                    }
                }
                else {
                    Write-Error ('Built-in star reference ''{0}'' was not found in the current fixed star catalog.' -f $name)
                }
            }
        }
        else {
            foreach ($name in $selectedNames) {
                if ($PSCmdlet.ShouldProcess($name, 'Return star reference name')) {
                    $name
                }
            }
        }
    }
}



function Get-AetherScopePosition {
<#
.SYNOPSIS
Gets the position of a supported celestial body for an observer.
.DESCRIPTION
Provides a single entry point for Sun, Moon, or ISS position queries so callers
do not need to remember the body-specific function names.
.PARAMETER Body
Body to calculate: Sun, Moon, or ISS.
.PARAMETER Latitude
Observer latitude in decimal degrees.
.PARAMETER Longitude
Observer longitude in decimal degrees.
.PARAMETER Coordinate
Flexible observer coordinate input.
.PARAMETER DateTime
Date and time for Sun or Moon calculations. For ISS current look angles, the
current API position is used.
.PARAMETER ObserverAltitudeKm
Observer altitude in kilometers.
.EXAMPLE
Get-AetherScopePosition -Body Sun -Coordinate '30.2752,-89.7812'
.EXAMPLE
Get-AetherScopePosition -Body ISS -Coordinate '30.2752,-89.7812' -WhatIf
.INPUTS
System.Object
.OUTPUTS
System.Management.Automation.PSCustomObject
.NOTES
For ISS, this wrapper currently calls the current-position workflow.
#>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Sun', 'Moon', 'ISS')]
        [string]$Body,

        [Parameter()]
        [Nullable[Double]]$Latitude,

        [Parameter()]
        [Nullable[Double]]$Longitude,

        [Parameter(ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [AllowNull()]
        [Object]$Coordinate,

        [Parameter()]
        [datetime]$DateTime = (Get-Date),

        [Parameter()]
        [double]$ObserverAltitudeKm = 0.0
    )

    begin {
    }

    process {
        if (-not $PSCmdlet.ShouldProcess($Body, 'Get celestial position')) {
            return
        }

        switch ($Body) {
            'Sun' {
                Get-AetherScopeSunPosition -Latitude $Latitude -Longitude $Longitude -Coordinate $Coordinate -DateTime $DateTime
            }
            'Moon' {
                Get-AetherScopeMoonPosition -Latitude $Latitude -Longitude $Longitude -Coordinate $Coordinate -DateTime $DateTime
            }
            'ISS' {
                Get-AetherScopeIssObserverPosition -Latitude $Latitude -Longitude $Longitude -Coordinate $Coordinate -ObserverAltitudeKm $ObserverAltitudeKm
            }
        }
    }

    end {
    }
}



function Start-AetherScopeDashboard {
<#
.SYNOPSIS
Continuously tracks Sun, Moon, and ISS in a fixed console region.
.DESCRIPTION
Builds a live console dashboard that refreshes the same area of the screen rather
than writing a new line for each update. This is useful for manual monitoring of
azimuth and altitude while preserving a stable terminal layout. The dashboard can
show any combination of Sun, Moon, and ISS, and it can refresh coordinates from
an attached GPS receiver on each cycle.
.PARAMETER Body
One or more supported bodies to display. Defaults to Sun, Moon, and ISS.
.PARAMETER Latitude
Observer latitude in decimal degrees.
.PARAMETER Longitude
Observer longitude in decimal degrees.
.PARAMETER Coordinate
Flexible coordinate input.
.PARAMETER ObserverAltitudeKm
Observer altitude in kilometers. Primarily relevant for ISS tracking.
.PARAMETER IntervalSeconds
Refresh interval between samples.
.PARAMETER MaxSamples
Maximum number of refresh cycles to display. Use 0 for continuous display.
.PARAMETER UseGpsSerial
Reads a fresh GPS fix from a serial port before each refresh cycle.
.PARAMETER GpsPortName
Serial port used when -UseGpsSerial is specified.
.PARAMETER GpsBaudRate
GPS serial baud rate.
.PARAMETER Title
Optional title shown at the top of the dashboard.
.PARAMETER PassThru
Emits one summary object per refresh cycle in addition to updating the console.
.EXAMPLE
Start-AetherScopeDashboard -Coordinate '30.2752,-89.7812' -IntervalSeconds 2 -MaxSamples 20
.EXAMPLE
Start-AetherScopeDashboard -Body Sun,Moon -Coordinate '30.2752,-89.7812' -IntervalSeconds 1 -MaxSamples 10 -WhatIf
.INPUTS
System.Object
.OUTPUTS
System.Management.Automation.PSCustomObject
.NOTES
This function is intended for interactive console use. It uses a fixed console
origin and rewrites that region on each cycle so the display behaves more like a
dashboard than a scrolling shell transcript. Press Ctrl+C to stop a continuous run.
#>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([pscustomobject])]
    param(
        [Parameter()]
        [ValidateSet('Sun', 'Moon', 'ISS')]
        [string[]]$Body = @('Sun', 'Moon', 'ISS'),

        [Parameter()]
        [Nullable[Double]]$Latitude,

        [Parameter()]
        [Nullable[Double]]$Longitude,

        [Parameter(ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [AllowNull()]
        [Object]$Coordinate,

        [Parameter()]
        [double]$ObserverAltitudeKm = 0.0,

        [Parameter()]
        [ValidateRange(1, 3600)]
        [int]$IntervalSeconds = 2,

        [Parameter()]
        [ValidateRange(0, 100000)]
        [int]$MaxSamples = 0,

        [Parameter()]
        [switch]$UseGpsSerial,

        [Parameter()]
        [string]$GpsPortName,

        [Parameter()]
        [ValidateRange(110, 115200)]
        [int]$GpsBaudRate = 4800,

        [Parameter()]
        [string]$Title = 'Celestial Tracking Dashboard',

        [Parameter()]
        [switch]$PassThru
    )

    begin {
        $sampleCount = 0
        $previousLineCount = 0
        $originLeft = 0
        $originTop = 0
        $cursorWasVisible = $true
    }

    process {
        if ($UseGpsSerial.IsPresent -and [string]::IsNullOrWhiteSpace($GpsPortName)) {
            Write-Error 'GpsPortName is required when -UseGpsSerial is specified.'
            return
        }

        if (-not $PSCmdlet.ShouldProcess('Console dashboard', 'Start celestial console tracking loop')) {
            return
        }

        try {
            $originLeft = [Console]::CursorLeft
            $originTop = [Console]::CursorTop
        }
        catch {
            $originLeft = 0
            $originTop = 0
        }

        try {
            $cursorWasVisible = [Console]::CursorVisible
            [Console]::CursorVisible = $false
        }
        catch {
        }

        try {
            while (($MaxSamples -le 0) -or ($sampleCount -lt $MaxSamples)) {
                $activeCoordinate = $Coordinate
                $activeLatitude = $Latitude
                $activeLongitude = $Longitude
                $resolved = $null

                if ($UseGpsSerial.IsPresent) {
                    $gpsFix = Get-AetherScopeGpsCoordinate -PortName $GpsPortName -BaudRate $GpsBaudRate -ReadCount 1 | Select-Object -First 1
                    if ($null -eq $gpsFix) {
                        $frame = @(
                            $Title,
                            ('Updated: {0}' -f (Get-Date)),
                            'GPS: no fix available for this refresh cycle.',
                            ('Waiting {0} second(s) before next retry. Press Ctrl+C to stop.' -f $IntervalSeconds)
                        )
                        Write-ConsoleFrameInPlace -Line $frame -OriginLeft $originLeft -OriginTop $originTop -PreviousLineCount $previousLineCount
                        $previousLineCount = $frame.Count
                        Start-Sleep -Seconds $IntervalSeconds
                        continue
                    }

                    $activeCoordinate = $gpsFix
                    $activeLatitude = $null
                    $activeLongitude = $null
                }

                $resolved = Resolve-AetherScopeCoordinate -Latitude $activeLatitude -Longitude $activeLongitude -Coordinate $activeCoordinate
                if ($null -eq $resolved) {
                    return
                }

                $positions = @()
                foreach ($currentBody in $Body) {
                    $position = $null
                    try {
                        $position = Get-AetherScopePosition -Body $currentBody -Latitude $resolved.Latitude -Longitude $resolved.Longitude -Coordinate $resolved -DateTime (Get-Date) -ObserverAltitudeKm $ObserverAltitudeKm
                    }
                    catch {
                        Write-Verbose ("Failed to update {0}: {1}" -f $currentBody, $_.Exception.Message)
                    }

                    $positions += [pscustomobject]@{
                        Body = $currentBody
                        Position = $position
                    }
                }

                try {
                    $frameWidth = [Math]::Max(60, $Host.UI.RawUI.WindowSize.Width - $originLeft)
                }
                catch {
                    $frameWidth = 120
                }

                $separator = ''.PadRight([Math]::Min($frameWidth, 120), '=')
                $frame = @()
                $frame += $Title
                $frame += $separator
                $frame += ('Updated: {0}    Interval: {1}s    Sample: {2}' -f (Get-Date), $IntervalSeconds, ($sampleCount + 1))
                $frame += ('Observer: Lat {0:N6}  Lon {1:N6}  Source: {2}' -f $resolved.Latitude, $resolved.Longitude, $resolved.Source)
                $frame += $separator
                $frame += ('{0,-6} {1,10} {2,10} {3,11} {4,8} {5,26}' -f 'Body', 'Azimuth', 'Altitude', 'RangeKm', 'Visible', 'Status')
                $frame += ('{0,-6} {1,10} {2,10} {3,11} {4,8} {5,26}' -f '----', '-------', '--------', '-------', '-------', '------')

                foreach ($entry in $positions) {
                    $currentBody = $entry.Body
                    $position = $entry.Position
                    if ($null -eq $position) {
                        $frame += ('{0,-6} {1,10} {2,10} {3,11} {4,8} {5,26}' -f $currentBody, 'n/a', 'n/a', 'n/a', 'n/a', 'No data')
                        continue
                    }

                    $rangeText = 'n/a'
                    $visibleText = 'No'
                    $statusText = ''

                    if ($currentBody -eq 'ISS') {
                        if ($position.PSObject.Properties['RangeKm']) {
                            $rangeText = ('{0:N1}' -f [double]$position.RangeKm)
                        }
                        if ($position.PSObject.Properties['IsAboveHorizon']) {
                            if ([bool]$position.IsAboveHorizon) {
                                $visibleText = 'Yes'
                            }
                        }
                        if ($position.PSObject.Properties['Visibility']) {
                            $statusText = [string]$position.Visibility
                        }
                    }
                    else {
                        if ([double]$position.Altitude -ge 0.0) {
                            $visibleText = 'Yes'
                        }
                        if ($position.PSObject.Properties['Zenith']) {
                            $statusText = ('Zenith {0:N2}°' -f [double]$position.Zenith)
                        }
                        elseif ($position.PSObject.Properties['DistanceEarthRadii']) {
                            $statusText = ('Dist {0:N2} ER' -f [double]$position.DistanceEarthRadii)
                        }
                    }

                    $frame += ('{0,-6} {1,10} {2,10} {3,11} {4,8} {5,26}' -f $currentBody, ('{0:N2}°' -f [double]$position.Azimuth), ('{0:N2}°' -f [double]$position.Altitude), $rangeText, $visibleText, $statusText)
                }

                $frame += $separator
                $frame += 'Display updates in place. Press Ctrl+C to stop.'

                Write-ConsoleFrameInPlace -Line $frame -OriginLeft $originLeft -OriginTop $originTop -Width $frameWidth -PreviousLineCount $previousLineCount
                $previousLineCount = $frame.Count
                $sampleCount += 1

                if ($PassThru.IsPresent) {
                    [pscustomobject]@{
                        PSTypeName = 'AetherScope.ConsoleDashboardSnapshot'
                        TimeStamp = Get-Date
                        Latitude = $resolved.Latitude
                        Longitude = $resolved.Longitude
                        CoordinateSource = $resolved.Source
                        Bodies = $positions
                        SampleNumber = $sampleCount
                    }
                }

                if (($MaxSamples -gt 0) -and ($sampleCount -ge $MaxSamples)) {
                    break
                }

                Start-Sleep -Seconds $IntervalSeconds
            }
        }
        finally {
            try {
                $finalBufferWidth = [Console]::BufferWidth
                $finalBufferHeight = [Console]::BufferHeight
                $finalLeft = [Math]::Max(0, [Math]::Min($originLeft, [Math]::Max(0, $finalBufferWidth - 1)))
                $finalTop = [Math]::Max(0, [Math]::Min(($originTop + $previousLineCount), [Math]::Max(0, $finalBufferHeight - 1)))
                [Console]::SetCursorPosition($finalLeft, $finalTop)
            }
            catch {
            }

            try {
                [Console]::CursorVisible = $cursorWasVisible
            }
            catch {
            }
        }
    }

    end {
    }
}
