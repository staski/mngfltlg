#!/usr/bin/perl
package DEFT;

use 5.10.0;
use XML::LibXML;
use Getopt::Long;
use Math::Trig;
use POSIX;# for floor etc.

my $sourceAirport ="";

GetOptions ("airportDir=s" => \$airportDirectory,
"pilot=s" => \$pilot,
"climode=s" => \$climode,
"writeAPDir=s" => \$sourceAirport,
"debug=s" => \$debug);


readAirportDirectory();
getDistances('EDFM');

if ($sourceAirport ne ""){
    writeDirectoryByDistanceFrom($sourceAirport);
}

my $filename = 'ttfExample.gpx';
my $tmpFile = XML::LibXML->load_xml(location => $filename);
my $xpc = XML::LibXML::XPathContext->new($tmpFile);
$xpc->registerNs('g', 'http://www.topografix.com/GPX/1/1');


foreach my $gpx ($xpc->findnodes('//g:trkpt')) {
    $lat = $gpx->getAttribute('lat');
    $lon = $gpx->getAttribute('lon');
    
    $xpc->setContextNode($gpx);
    $xpc->registerNs('g', 'http://www.topografix.com/GPX/1/1');

    $ele = $xpc->findvalue('g:ele');
    $speed = $xpc->findvalue('g:speed') * 3600/1852;
    $time = $xpc->findvalue('g:time');
    
    say $time . ": " . "($lat,$lon) at $ele m [$speed kts]" if ($debug);
}

sub getDistances {
    my $icao = shift;
    $edfmpt = Point->new($lat{$icao}, $lon{$icao});

    foreach my $ic (keys %p_name) {
        my $pt = Point->new($lat{$ic}, $lon{$ic});
    
        $distance{$ic} = $pt->distance($edfmpt);
        $distance = ceil($distance{$ic} / 1852);
        say $ic . " DISTANCE: " . $distance;
    }
}

sub writeDirectoryByDistanceFrom {
    my $icao = shift;
    my $filename = "world_airports_by_discance_from_$icao";
    
    open(APDIR, ">$filename") || die "can't open $filename: $!";
    my @airports = sort { $distance{$a} <=> $distance{$b} } keys %distance;
    foreach $ap (@airports) {
        $distance = ceil($distance{$ap} / 1852);
        print APDIR "$ap;$p_name{$ap};$lat{$ap};$lon{$ap};$alt_ft{$ap};$distance{$ap}\n";
        say $ap . " " . $distance if $debug;
    }
    close APDIR;
}

#$debug = 1;

package Point;

$one_sea_mile = 1852;
$one_deg_in_m = $one_sea_mail * 60; #60 min = 1 deg

sub new {
    my $class = shift;
    my ( $lat, $lon ) = @_;
    my $self = bless {
        lat => $lat,
        lon => $lon,
    }, $class;
    return $self;
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
    
    say "SELF: " . $self->lat . " " . $self->lon  . " OTHER:  " . $other->lat . " " . $other->lon if ($debug);
    
    my $lon2 = Math::Trig::deg2rad($other->lon);
    my $lon1 = Math::Trig::deg2rad($self->lon);
    my $lat2 = Math::Trig::deg2rad(90 - $other->lat);
    my $lat1 = Math::Trig::deg2rad(90 - $self->lat);
    
    say "PT1: " . $lat1 . " " . $lon1 ." PT2 " . $lat2 . " " . $lon2 if ($debug);
    
    my $distance = Math::Trig::great_circle_distance($lon1,$lat1,$lon2,$lat2) * 6367 * 1000;
    
    say "DISTANCE $distance" if ($debug);
    
    return $distance;
}

package DEFT;

sub readAirportDirectory {
    open (ALLAIRPORTS, "<$airportDirectory" ) || die "can't open file $airportDirectory: $!";

    @firstLine = split(/,/, <ALLAIRPORTS>);
    $tabsize = $#firstLine + 1;

    for ($i=0; $i <= $#firstLine; $i++){
        $firstLine[$i] =~ /(\w+)\((.*)\)/;
        $column[$i] = $1;
        $unit[$i] = $2;
    }

    while (<ALLAIRPORTS>)
    {
        @airportLine = split (/,/);
    
        $ICAO = $airportLine[1];
        $ap_name = $airportLine[3];
        $p_name = trimName($ap_name);
        $pn_name = normalizeName($p_name);
        $ICAO{$pn_name}  = $ICAO;
        $lat = $airportLine[4];
        $lon = $airportLine[5];
        $alt_ft = $airportLine[6];
        
        $lat{$ICAO} = $lat;
        $lon{$ICAO} = $lon;
        $alt_ft{$ICAO} = $alt_ft;
        $p_name{$ICAO} = $p_name;
    }
}

sub getICAO {
    my $name = shift;
    my $dashname = normalizeName($name);
    return $ICAO{$name} || $ICAO{$dashname} ||  "$name";
}

#strip off any decoration in the name of the world airport database
sub trimName {
    my $name = shift;
    $name =~ s/"(.*)"/$1/;
    $name =~ s/ Airport//;
    $name =~ s/ Heliport//;
    $name =~ s/ Airfield//;
    $name =~ s/Flugplatz //;
    $name =~ s/Airport //;
    $name =~ s/Aviosuperficie //;
    return $name;
}

#remove any ambiguos spelling options
sub normalizeName {
    my $name = shift;
    $name =~ s/ä/ae/g;
    $name =~ s/ü/ue/g;
    $name =~ s/ö/oe/g;
    $name =~ s/ß/ss/g;
    $name =~ s/é/e/g;
    $name =~ s/-//g;
    $name =~ s/ //g;
    $name =~s/\///g;
    $name = lc($name);
    return $name;
}

sub printUsageAndExit(){
	print "exit now ARGV = $#ARGV\n";
	exit(0);
}
