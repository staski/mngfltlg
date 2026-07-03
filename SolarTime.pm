package SolarTime;

# Shared solar-geometry routines used by gpx2fltlog.pl (night-time / night-landing
# calculation) and eot.pl (validation harness against api.sunrise-sunset.org).
#
# Keep this the single source of truth: eot.pl exists to test exactly this code.

use strict;
use warnings;

use Exporter 'import';
use DateTime;
use Math::Trig;

our @EXPORT_OK = qw(sunrise_sunset is_daytime hhmm);

our $debug = 0;   # set true to emit sunrise/sunset debug to STDERR

# Is $time_epoch during daylight at the given location?
#
# $below_horizon_deg selects the "day" threshold (see sunrise_sunset); it
# defaults to 6, i.e. civil twilight — the aviation definition of night is the
# period the sun is more than 6 deg below the horizon.
#
# Returns 1 (day), 0 (night), or undef (polar day / polar night).
sub is_daytime {
    my ($lat, $lon, $time_epoch, $below_horizon_deg) = @_;
    $below_horizon_deg //= 6;   # civil twilight

    my ($sunrise, $sunset) = sunrise_sunset($lat, $lon, $time_epoch, $below_horizon_deg);
    return undef unless defined $sunrise;   # polar day or night

    return $time_epoch >= $sunrise && $time_epoch < $sunset ? 1 : 0;
}

# Returns UTC epoch timestamps of sunrise and sunset for a given location and day.
#
# $lat               – latitude in decimal degrees  (+N / -S)
# $lon               – longitude in decimal degrees (+E / -W)
# $day_epoch         – Unix timestamp of any moment on the day of interest
# $below_horizon_deg – degrees the sun's centre is below the horizon at the
#                      target event:
#                        0     = geometric sunrise/sunset
#                        0.833 = standard sunrise (refraction + disc radius)
#                        6     = civil twilight
#                       12     = nautical twilight
#                       18     = astronomical twilight
#
# Returns ($sunrise_epoch, $sunset_epoch) in UTC,
# or undef if the sun never reaches that angle (polar day / polar night).
sub sunrise_sunset {
    my ($lat, $lon, $day_epoch, $below_horizon_deg) = @_;

    # Approximate the local solar date by shifting with the longitude offset.
    # This is the only date information derivable from lat/lon alone, and it
    # keeps the returned epochs anchored to the correct calendar day at far
    # eastern/western longitudes.
    my $lon_offset_s = int($lon / 15 * 3600 + 0.5);
    my $dt_local = DateTime->from_epoch(epoch => $day_epoch + $lon_offset_s);
    my $dayoy = $dt_local->day_of_year;

    my $day_start = DateTime->new(
        year      => $dt_local->year,
        month     => $dt_local->month,
        day       => $dt_local->day,
        time_zone => 'UTC',
    );

    my $latr = deg2rad($lat);
    my $h    = deg2rad(-$below_horizon_deg);   # convert to elevation angle

    # solar declination in radians
    my $decl = 0.4095 * sin(0.016906 * ($dayoy - 80.086));

    # equation of time in hours — https://www.astronomie.info/zeitgleichung/
    my $eot = -0.171 * sin(0.0337 * $dayoy + 0.465)
             - 0.1299 * sin(0.01787 * $dayoy - 0.168);

    # cosine of the hour angle at the target solar elevation
    my $cos_H = (sin($h) - sin($latr) * sin($decl))
              / (cos($latr) * cos($decl));

    return undef if abs($cos_H) > 1;   # polar day or polar night

    my $half_span = 12 * acos($cos_H) / pi;   # hours from noon to sunrise/sunset

    # mean solar time -> UTC: subtract longitude offset (15 deg = 1 hour)
    my $sr_utc = 12 - $half_span - $eot - $lon / 15;
    my $ss_utc = 12 + $half_span - $eot - $lon / 15;

    printf STDERR "SUNRISE %s, SUNSET %s\n", hhmm($sr_utc), hhmm($ss_utc)
        if $debug;

    return (
        $day_start->epoch + int($sr_utc * 3600 + 0.5),
        $day_start->epoch + int($ss_utc * 3600 + 0.5),
    );
}

# Format a decimal-hours value as HH:MM (rounded to the minute).
sub hhmm {
    my $hours_f   = shift;
    my $total_min = int($hours_f * 60 + 0.5);
    return sprintf("%02d:%02d", int($total_min / 60), $total_min % 60);
}

1;
