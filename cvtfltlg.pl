#!/usr/bin/perl

use 5.10.0;

#use strict;
#use warnings;

use XML::LibXML;
use Getopt::Long;
use Math::Trig;
use POSIX;# for floor etc.
use Date::Parse;
use File::Temp;

use CGI;
use CGI::Carp qw ( fatalsToBrowser );


package main;

my $scriptName = $0;
my $gpxName = 'ttfExample.gpx';
my $airportDirectory = "ap_from_edfm.txt";
my $takeoffSpeed = 60;
my $landingSpeed = 57;
my $feet_for_m = 3.28084;
my $sourceAirport = "";

GetOptions ("airportDir=s" => \$airportDirectory,
"pilot=s" => \$pilot,
"gpxName=s" => \$gpxName,
"debug=s" => \$debug);

$isCGI = isCGI($scriptName);
say $isCGI if $debug;
my $cgi_query = initCGI($isCGI);

say $cgi_query if $debug;

$gpxName = getGpxName($cgi_query);
say $gpxName if $debug;
# this sets the "sourceAirport". The directory is sorted by distance from this airport
readAirportDirectory();
$sapt = gpxPoint->new($lat{$sourceAirport},$lon{$sourceAirport});

#read in the given GPX File
my @to = readGpxFile($gpxName);
if ($#to < 0){
    die "not a valid flight found in $gpxName";
}

#create flight log entries from the parsed result. One entry for each pair takeoff - landing
@allFlights = createFlights(@to);

# join those entries where the takeoff is from the same AP as the landing of the previous and this
# one
push @jap, $allFlights[0];
$prev= $allFlights[0];
for (my $i = 1; $i <= $#allFlights; $i++) {
    my $this = $allFlights[$i];
    #my $prev = $allFlights[$i - 1];
    $prev->print("PREV") if ($debug);
    $this->print("THIS") if ($debug);
    if ($prev->landingAirport eq $this->departureAirport &&
        $this->landingAirport eq $this->departureAirport){
            say "HIT" if ($debug);
            $prev->setLandingTime($this->landingTime);
            $prev->setLandingAirport($this->landingAirport);
            $prev->setLandingCount($prev->landingCount + $this->landingCount);
            $prev->setDuration($prev->duration + $this->duration);
    }
    else {
        $prev = $this;
        push @jap, $this;
    }
}

foreach $flight (@jap){
    $flight->print("Flight") || die "ERROR";
}

sub isCGI {
    my $name = shift;
    if ($name =~ /.+\.cgi/){
        return 1;
    }
    else {
        return 0;
    }
}

sub initCGI {
    my $lisCGI = shift;
    if ($lisCGI){
        my $cgi_query = CGI->new();
        $debug = $cgi_query->param('debug');
     
        print $cgi_query->header;
        print $cgi_query->start_html;
        

        return $cgi_query;
    }
}

sub getGpxName {
    my $query = shift;
    my $gName = $gpxName;
    
    if ($isCGI == 0){
        return $gName;
    }
    
    my $lfh  = $query->upload('theFile');
    $tmpfile = File::Temp->new();
    $gName = $tmpfile->filename;
    say $gName if $debug;
    if (defined $lfh) {
        # Upgrade the handle to one compatible with IO::Handle:
        my $io_handle = $lfh->handle;
        
        while ($bytesread = read($io_handle, $buffer, 1024)) {
            print $tmpfile $buffer;
        }
        close $tmpfile;
        return $gName;
    }
}

sub createFlights {
    my @takeOff = @_;
    my $isFlying = 0;
    
    if ($takeOff[0] =~ /^landing/){
        $isFlying = 1;
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
            $flightDuration = $timeseconds - $takeoffepoch;
            #$flightHours = floor($flightDurationMinutes/60);
            #$flightMinutes = $flightDurationMinutes - 60*$flightHours;
            $landingAirport = $ap;
            $landingTime = "$hour:$min";
            my $flogEntry = flogEntry->new("DEEBU", $dayofFlight,$pilot,$departureAirport,$landingAirport, $takeoffTime,$landingTime, $flightDuration, 1);

            $flogEntry->print("FLIGHT") if ($debug);
            push @allFlights, $flogEntry;
            #print "$dayofFlight | $pilot | $departureAirport | $landingAirport | $takeoffTime | $landingTime | $flightDurationMinutes ($flightHours:$flightMinutes)\n";
        }
        
    }
    return @allFlights;
}

sub readGpxFile {
    my $fname = shift;
    my @fa;
    my $tmpFile = XML::LibXML->load_xml(location => $fname);
    my $xpc = XML::LibXML::XPathContext->new($tmpFile);
    $xpc->registerNs('g', 'http://www.topografix.com/GPX/1/1');

    my $count = 0;
    my $isFlying = 0;
    foreach my $gpx ($xpc->findnodes('//g:trkpt')) {
        my $lat = $gpx->getAttribute('lat');
        my $lon = $gpx->getAttribute('lon');
        
        $xpc->setContextNode($gpx);
        $xpc->registerNs('g', 'http://www.topografix.com/GPX/1/1');
        
        $ele = ceil($xpc->findvalue('g:ele') * $feet_for_m);
        $speed = ceil($xpc->findvalue('g:speed') * 3600/1852);
        $time = $xpc->findvalue('g:time');
        
        if ($isFlying == 0 && $speed > $takeoffSpeed){
            $isFlying = 1;
            $fa[$count] = "takeoff;$time;$lat;$lon;$ele;$speed";
            $count++;
            say $fa[$count] if ($debug);
        }
        if ($isFlying == 1 && $speed < $landingSpeed){
            $isFlying = 0;
            $fa[$count] = "landing;$time;$lat;$lon;$ele;$speed";
            $count++;
            say $fa[$count] if ($debug);
        }
    }
    return @fa;
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
            if ($dist < 5000) {
                say "PERFECT match -> break LOOP" if ($debug);
                last;
            }
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

# the class representing a point on earth
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

# the class representing a single flight in a flight log
package flogEntry;
use 5.10.0;
use POSIX;

our $debug;

sub new {
    my $class = shift;
    my ( $plane, $dof, $pilot, $dap, $lap, $tot, $lat, $duration, $lc ) = @_;
    my $self = bless {
        plane => $plane,
        dayofFlight => $dof,
        pilot => $pilot,
        departureAirport => $dap,
        landingAirport => $lap,
        takeoffTime => $tot,
        landingTime => $lat,
        landingCount => $lc,
        duration => $duration
    }, $class;
    
    return $self;
}

sub dayofFlight {
    my $self = shift;
    return $self->{'dayofFlight'};
}

sub departureAirport {
    my $self = shift;
    return $self->{'departureAirport'};
}

sub takeoffTime {
    my $self = shift;
    return $self->{'takeoffTime'};
}

sub landingAirport {
    my $self = shift;
    return $self->{'landingAirport'};
}

sub landingTime {
    my $self = shift;
    return $self->{'landingTime'};
}

sub pilot {
    my $self = shift;
    return $self->{'pilot'};
}

sub plane {
    my $self = shift;
    return $self->{'plane'};
}

sub duration {
    my $self = shift;
    return $self->{'duration'};
}

sub landingCount {
    my $self = shift;
    return $self->{'landingCount'};
}

sub setDepartureAirport {
    my $self = shift;
    my $ap = shift;
    $self->{'departureAirport'} = $ap;
}

sub setLandingAirport {
    my $self = shift;
    my $ap = shift;
    $self->{'landingAirport'} = $ap;
}

sub setLandingCount {
    my $self = shift;
    my $lc = shift;
    $self->{'landingCount'} = $lc;
}

sub setLandingTime {
    my $self = shift;
    my $lt = shift;
    $self->{'landingTime'} = $lt;
}

sub setDuration {
    my $self = shift;
    my $duration = shift;
    $self->{'duration'} = $duration;
}


sub print {
    my $self = shift;
    my $text = shift;
    $text .= " " . $self->dayofFlight .
    " | " . $self->pilot .
    " | " . $self->departureAirport .
    " | " . $self->takeoffTime .
    " | " . $self->landingAirport .
    " | " . $self->landingTime .
    " | " . ceil($self->duration/60) .
    " | " . $self->landingCount;
    
    say "$text";
}


