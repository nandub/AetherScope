using System;

namespace AetherScopePrecision
{
    public sealed class ApparentCoordinateResult
    {
        public double RightAscensionHours { get; set; }
        public double DeclinationDegrees { get; set; }
    }

    public static class PrecisionTransforms
    {
        private static double DegToRad(double d) { return d * Math.PI / 180.0; }
        private static double RadToDeg(double r) { return r * 180.0 / Math.PI; }
        private static double NormalizeAngle(double degrees)
        {
            double result = degrees % 360.0;
            if (result < 0.0) result += 360.0;
            return result;
        }

        public static ApparentCoordinateResult Transform(double julianDateUtc, double rightAscensionHours, double declinationDegrees, double properMotionRaMasPerYear, double properMotionDecMasPerYear, double referenceEpochJulianYear)
        {
            double yearsSinceEpoch = ((julianDateUtc - 2451545.0) / 365.25) - (referenceEpochJulianYear - 2000.0);
            double raDegrees = rightAscensionHours * 15.0;
            double decDegrees = declinationDegrees;

            raDegrees += ((properMotionRaMasPerYear / 1000.0) / 3600.0) * yearsSinceEpoch;
            decDegrees += ((properMotionDecMasPerYear / 1000.0) / 3600.0) * yearsSinceEpoch;

            double t = (julianDateUtc - 2451545.0) / 36525.0;
            double zeta = DegToRad(((2306.2181 * t) + (0.30188 * t * t) + (0.017998 * t * t * t)) / 3600.0);
            double z = DegToRad(((2306.2181 * t) + (1.09468 * t * t) + (0.018203 * t * t * t)) / 3600.0);
            double theta = DegToRad(((2004.3109 * t) - (0.42665 * t * t) - (0.041833 * t * t * t)) / 3600.0);

            double alphaRad = DegToRad(raDegrees);
            double deltaRad = DegToRad(decDegrees);

            double A = Math.Cos(deltaRad) * Math.Sin(alphaRad + zeta);
            double B = (Math.Cos(theta) * Math.Cos(deltaRad) * Math.Cos(alphaRad + zeta)) - (Math.Sin(theta) * Math.Sin(deltaRad));
            double C = (Math.Sin(theta) * Math.Cos(deltaRad) * Math.Cos(alphaRad + zeta)) + (Math.Cos(theta) * Math.Sin(deltaRad));
            alphaRad = Math.Atan2(A, B) + z;
            deltaRad = Math.Asin(C);

            double omega = NormalizeAngle(125.04452 - (1934.136261 * t) + (0.0020708 * t * t) + ((t * t * t) / 450000.0));
            double sunMeanLongitude = NormalizeAngle(280.4665 + (36000.7698 * t));
            double moonMeanLongitude = NormalizeAngle(218.3165 + (481267.8813 * t));
            double omegaRad = DegToRad(omega);
            double sunMeanLongitudeRad = DegToRad(sunMeanLongitude);
            double moonMeanLongitudeRad = DegToRad(moonMeanLongitude);
            double deltaPsiArcSec = (-17.20 * Math.Sin(omegaRad)) - (1.32 * Math.Sin(2.0 * sunMeanLongitudeRad)) - (0.23 * Math.Sin(2.0 * moonMeanLongitudeRad)) + (0.21 * Math.Sin(2.0 * omegaRad));
            double deltaEpsilonArcSec = (9.20 * Math.Cos(omegaRad)) + (0.57 * Math.Cos(2.0 * sunMeanLongitudeRad)) + (0.10 * Math.Cos(2.0 * moonMeanLongitudeRad)) - (0.09 * Math.Cos(2.0 * omegaRad));

            double seconds = 21.448 - (46.8150 * t) - (0.00059 * t * t) + (0.001813 * t * t * t);
            double epsilonDegrees = 23.0 + (26.0 / 60.0) + (seconds / 3600.0) + (deltaEpsilonArcSec / 3600.0);
            double epsilonRad = DegToRad(epsilonDegrees);
            double deltaPsiRad = DegToRad(deltaPsiArcSec / 3600.0);
            double deltaEpsilonRad = DegToRad(deltaEpsilonArcSec / 3600.0);

            double deltaAlphaNutation = ((Math.Cos(epsilonRad) + (Math.Sin(epsilonRad) * Math.Sin(alphaRad) * Math.Tan(deltaRad))) * deltaPsiRad) - (Math.Cos(alphaRad) * Math.Tan(deltaRad) * deltaEpsilonRad);
            double deltaDeltaNutation = (Math.Sin(epsilonRad) * Math.Cos(alphaRad) * deltaPsiRad) + (Math.Sin(alphaRad) * deltaEpsilonRad);
            alphaRad += deltaAlphaNutation;
            deltaRad += deltaDeltaNutation;

            double L0 = NormalizeAngle(280.46646 + (36000.76983 * t) + (0.0003032 * t * t));
            double M = NormalizeAngle(357.52911 + (35999.05029 * t) - (0.0001537 * t * t));
            double Mrad = DegToRad(M);
            double Csun = ((1.914602 - (0.004817 * t) - (0.000014 * t * t)) * Math.Sin(Mrad)) + ((0.019993 - (0.000101 * t)) * Math.Sin(2.0 * Mrad)) + (0.000289 * Math.Sin(3.0 * Mrad));
            double lambdaRad = DegToRad(NormalizeAngle(L0 + Csun));
            double eccentricity = 0.016708634 - (0.000042037 * t) - (0.0000001267 * t * t);
            double perihelionRad = DegToRad(NormalizeAngle(102.93735 + (1.71946 * t) + (0.00046 * t * t)));
            double kappaRad = DegToRad(20.49552 / 3600.0);

            double cosAlpha = Math.Cos(alphaRad);
            double sinAlpha = Math.Sin(alphaRad);
            double cosDelta = Math.Cos(deltaRad);
            double sinDelta = Math.Sin(deltaRad);
            double tanEpsilon = Math.Tan(epsilonRad);
            double common1 = (tanEpsilon * cosDelta) - (sinAlpha * sinDelta);

            double deltaAlphaAberration = ((-kappaRad) * ((cosAlpha * Math.Cos(lambdaRad) * Math.Cos(epsilonRad)) + (sinAlpha * Math.Sin(lambdaRad))) / cosDelta)
                + ((eccentricity * kappaRad) * ((cosAlpha * Math.Cos(perihelionRad) * Math.Cos(epsilonRad)) + (sinAlpha * Math.Sin(perihelionRad))) / cosDelta);
            double deltaDeltaAberration = ((-kappaRad) * ((Math.Cos(lambdaRad) * Math.Cos(epsilonRad) * common1) + (cosAlpha * sinDelta * Math.Sin(lambdaRad))))
                + ((eccentricity * kappaRad) * ((Math.Cos(perihelionRad) * Math.Cos(epsilonRad) * common1) + (cosAlpha * sinDelta * Math.Sin(perihelionRad))));

            alphaRad += deltaAlphaAberration;
            deltaRad += deltaDeltaAberration;

            return new ApparentCoordinateResult
            {
                RightAscensionHours = NormalizeAngle(RadToDeg(alphaRad)) / 15.0,
                DeclinationDegrees = RadToDeg(deltaRad)
            };
        }
    }
}
