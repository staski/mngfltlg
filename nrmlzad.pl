#!/usr/bin/perl
package DEFT;

use 5.10.0;
use XML::LibXML;
use Getopt::Long;
use Math::Trig;
use POSIX;# for floor etc.

my $airport = "";

GetOptions ("airportDir=s" => \$airportDirectory,
"climode=s" => \$climode,
"airport=s" => \$airport,
"debug=s" => \$debug);


readAirportDirectory();

if (!defined($lat{$airport})){
    die "undefined airport $airport\n";
}

getDistances($airport);
writeDirectoryByDistanceFrom($airport);

sub getDistances {
    my $icao = shift;
    $edfmpt = Point->new($lat{$icao}, $lon{$icao});

    foreach my $ic (keys %p_name) {
        my $pt = Point->new($lat{$ic}, $lon{$ic});
    
        $distance{$ic} = $pt->distance($edfmpt);
        $distance = ceil($distance{$ic} / 1852);
        say $ic . " DISTANCE: " . $distance if ($debug);
    }
}

sub writeDirectoryByDistanceFrom {
    my $icao = shift;
    my $filename = "world_airports_by_distance_from_$icao";
    
    open(APDIR, ">$filename") || die "can't open $filename: $!";
    my @airports = sort { $distance{$a} <=> $distance{$b} } keys %distance;
    my $i = 0;
    print APDIR "addbbdfi1.1;ap=$airport";
    foreach $ap (@airports){
        if ($i == 1000){
            my $distance = ceil($distance{$ap}/1000);
            print APDIR ";$distance";
            $i = 0;
        }
        $i++
    }
    
    print APDIR "\n";
    foreach $ap (@airports) {
        $distance = ceil($distance{$ap}/1000);
        print APDIR "$ap;$p_name{$ap};$lat{$ap};$lon{$ap};$alt_ft{$ap};$distance;$iso_country{$ap}\n";
        say $ap . " " . $distance if $debug;
    }
    close APDIR;
}

package Point;

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
        
        my $ap_name = $airportLine[3];
        if ($airportLine[3] =~ /^\"/){
            my $i = 0;
            while ($airportLine[$i+3] !~ /\"$/){
                $i++;
                $ap_name .= $airportLine[$i+3];
                
            }
            print "$ICAO = $ap_name num $i\n" if $debug;
            splice @airportLine, 3, $i + 1, $ap_name;
        }
        $p_name = trimName($ap_name);
        $pn_name = normalizeName($p_name);
        $ICAO{$pn_name}  = $ICAO;
        $lat = $airportLine[4];
        $lon = $airportLine[5];
        $alt_ft = $airportLine[6];
        $iso_country = $airportLine[8];
        
        $lat{$ICAO} = $lat;
        $lon{$ICAO} = $lon;
        $alt_ft{$ICAO} = $alt_ft;
        $iso_country{$ICAO} = $iso_country;
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
    $name =~ s/;/,/g;
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
