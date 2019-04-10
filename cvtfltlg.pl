#!/usr/bin/perl

use 5.10.0;
#use strict;
#use warnings;
use XML::LibXML;
use Getopt::Long;
use Math::Trig;
use POSIX;# for floor etc.
use Date::Parse;

package gpxPoint;
use 5.10.0;
our $debug;

sub new {
    my $class = shift;
    my ( $lat, $lon ) = @_;
    my $self = bless {
        lat => $lat,
        lon => $lon,
    }, $class;
    
    return $self;
}

sub print {
    my $self = shift;
    my $text = shift;
    say "($text) LAT: " . $self->{'lat'} . " LON: " . $self->{'lon'};
}

sub lon {
    my $self = shift;
    return $self->{lon};
}

sub lat {
    my $self = shift;
    return $self->{lat};
}


sub distance {
    my $self = shift;
    my $other = shift;
    
    
    $self->print("SELF") if ($debug);
    $other->print("OTHER") if ($debug);
    
    my $lon2 = Math::Trig::deg2rad($other->lon);
    my $lon1 = Math::Trig::deg2rad($self->lon);
    my $lat2 = Math::Trig::deg2rad(90 - $other->lat);
    my $lat1 = Math::Trig::deg2rad(90 - $self->lat);
 
    my $distance = Math::Trig::great_circle_distance($lon1,$lat1,$lon2,$lat2) * 6367 * 1000;
 
    $distance = POSIX::ceil($distance);
    say "DISTANCE $distance" if ($debug);
    
    return $distance;
}

package main;

my $gpxName = 'ttfExample.gpx';
my $airportDirectory = "ap_from_edfm.txt";
my $takeoffSpeed = 60;
my $landingSpeed = 50;
my $feet_for_m = 3.28084;
my $sourceAirport = "";

GetOptions ("airportDir=s" => \$airportDirectory,
"pilot=s" => \$pilot,
"climode=s" => \$climode,
"gpxName=s" => \$gpxName,
"debug=s" => \$debug);


readAirportDirectory();
$sapt = gpxPoint->new($lat{$sourceAirport},$lon{$sourceAirport});

my $tmpFile = XML::LibXML->load_xml(location => $gpxName);
my $xpc = XML::LibXML::XPathContext->new($tmpFile);
$xpc->registerNs('g', 'http://www.topografix.com/GPX/1/1');

my $isFlying = 0;
my $count = 0;

foreach my $gpx ($xpc->findnodes('//g:trkpt')) {
    $lat = $gpx->getAttribute('lat');
    $lon = $gpx->getAttribute('lon');
    
    $xpc->setContextNode($gpx);
    $xpc->registerNs('g', 'http://www.topografix.com/GPX/1/1');

    $ele = ceil($xpc->findvalue('g:ele') * $feet_for_m);
    $speed = ceil($xpc->findvalue('g:speed') * 3600/1852);
    $time = $xpc->findvalue('g:time');
    
    if ($isFlying == 0 && $speed > $takeoffSpeed){
        $isFlying = 1;
        $takeOff[$count] = "takeoff;$time;$lat;$lon;$ele;$speed";
        $count++;
        say $takeOff[$count] if ($debug);
    }
    if ($isFlying == 1 && $speed < $landingSpeed){
        $isFlying = 0;
        $takeOff[$count] = "landing;$time;$lat;$lon;$ele;$speed";
        $count++;
        say $takeOff[$count] if ($debug);
    }
}

if ($takeOff[0] =~ /^landing/){
    $isFlying = 1;
} else {
    $isFlying = 0;
}

#TODO : Check if first event is landing
foreach $event (@takeOff){
    my ($evt,$time,$lat,$lon,$ele,$speed) = split (/;/, $event);
    say "EVT: $evt $time $lat $lon $ele $speed" if ($debug);
    
    my $loc = gpxPoint->new($lat,$lon);
    my $dist = ceil($loc->distance($sapt)/1000);
    
    say "FIND NEAREST HINT: $dist" if ($debug);
    my $ap = findNearestAirport($loc, $dist);
    say "$evt on AP $ap" if ($debug);
    my $distance = $loc->distance(gpxPoint->new($lat{$ap},$lon{$ap}));
    #next unless ($distance < 5000);
    if ($distance > 5000){
        $ap = "Unknown";
    }
    my ($sec,$min,$hour,$day,$month, $year, $zone) = strptime($time);
    $year += 1900;
    $month++;
    my $timeseconds = str2time($time);
    
    if ($evt eq "takeoff"){
        if ($isFlying == 1){
            say "WARNING: takeoff but Flying - $event";
        }
        $isFlying = 1;
        $dayofFlight = "$day.$month.$year";
        $takeoffTime = "$hour:$min";
        $takeoffepoch = $timeseconds;
        $departureAirport = $ap;
    } else {
        if ($isFlying == 0){
            say "WARNING: landing but not flying - $event";
        }
        $isFlying = 0;
        $flightDurationMinutes = floor(($timeseconds - $takeoffepoch)/60);
        $flightHours = floor($flightDurationMinutes/60);
        $flightMinutes = $flightDurationMinutes - 60*$flightHours;
        $landingAirport = $ap;
        $landingTime = "$hour:$min";
        print "$dayofFlight | $pilot | $departureAirport | $landingAirport | $takeoffTime | $landingTime | $flightDurationMinutes ($flightHours:$flightMinutes)\n";
    }
    
}

sub findNearestAirport {
    my $target = shift;
    my $hint = shift;
    my $i; $start;
    my $nearest = 100000000;
    my $dist;
    my $nix = 0;
    
    for ($i = 0; $i < $#distances && ($hint > $distances[$i]); $i++){
        say "IDX $i DISTANCE $distances[$i]" if ($debug);
    }
    
    $start = 0;
    $end = ($i + 1) * 1000;
    if ($end > $#allairports){
        $end = $#allairports;
    }

    say "SEARCH between $start and $end" if ($debug);
    for ($i = $start; $i < $end; $i++){
        my $lat = $lat{$allairports[$i]};
        my $lon = $lon{$allairports[$i]};
        my $ap = gpxPoint->new($lat, $lon);
        $dist = $target->distance($ap);
        say "idx $i $dist ($nearest): $allairports[$i]" if ($debug);
        if ($dist < $nearest){
            $nix = $i;
            $nearest = $dist;
            say "NEAREST $nix $dist" if ($debug);
        }
    }
    say "FOUND NEAREST $allairports[$nix] DIST $nearest" if ($debug);
    return $allairports[$nix];
}

sub readAirportDirectory {
    open (ALLAIRPORTS, "<$airportDirectory" ) || die "can't open file $airportDirectory: $!";

    @firstLine = split(/;/, <ALLAIRPORTS>);
    my $version=$firstLine[0];
    $sourceAirport =$firstLine[1];

    $sourceAirport =~ s/ap=(.+)/$1/;
    say "Source Airport: $sourceAirport" if ($debug);
    
    if ($version =~ /addbbdfi(\d+)\.(\d+)/){
        my ($major, $minor) = ($1,$2);
        say "VERSION $major . $minor" if ($debug);
    } else {
        die "invalid airport directory file $airportDirectory ($version)";
    }
    
    for ($i=2; $i <= $#firstLine; $i++){
        $distances[$i-2] = $firstLine[$i];
    }

    while (<ALLAIRPORTS>)
    {
        @airportLine = split (/;/);
    
        $ICAO = $airportLine[0];
        $ap_name = $airportLine[1];
        $lat = $airportLine[2];
        $lon = $airportLine[3];
        $alt_ft = $airportLine[4];
        $dist_km = $airportLine[5];
        
        $lat{$ICAO} = $lat;
        $lon{$ICAO} = $lon;
        $alt_ft{$ICAO} = $alt_ft;
        $p_name{$ICAO} = $ap_name;
        $dist_km{$ICAO} = $dist_km;
        
        push @allairports, $ICAO;
    }
}

