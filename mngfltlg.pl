#!/usr/bin/perl

use 5.10.0;

#use strict;
#use warnings;

use XML::LibXML;
use Getopt::Long;
use Date::Parse;

use CGI;
use CGI::Carp qw ( fatalsToBrowser );

use JSON;

package main;

my $scriptName = $0;
#possible values: add, list, read, delete

my $caction = "read";
my $json = 1;
my $glogFile = "./flights/flightLog.txt";
my $postdata;
my $request_method;

my @allflights;
my @allids;
my $highestid = 0;
my $highestidx;
my $plane = "DEEBU";


GetOptions ("debug=s" => \$debug,
            "action=s" => \$caction,
            "json!" => \$json
);


$isCGI = isCGI($scriptName);

my $cgi_query = initCGI($isCGI);

$action = getAction($isCGI);
say "ACTION=$action" if $debug;

$actionParam = getActionParams($isGCI, $action);
say "ACTIONPARAM=$postdata" if $debug;

readLog($glogFile);

if ($action eq "read"){
        print STDERR "READ";
        my $JS = JSON->new->utf8;
        $JS->convert_blessed(1);
        my $logArray = $JS->encode(\@allflights);
        say "$logArray";

}

if ($action  eq "add" && $request_method eq "POST"){
    my $flight = flogEntry->read_json($postdata);
    $flight->print("FLIGHT") if $debug;
    print "FLIGHTS before $#allflights\n" if $debug;
    addLogEntry($flight);
    print "FLIGHTS after $#allflights\n" if $debug;
    writeLog($glogFile);
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
        $debug = $cgi_query->url_param('debug');
        $action = $cgi_query->url_param('action');
        $request_method = $cgi_query->request_method();
        
        if ($action eq "add"){
            $postdata = $cgi_query->param('POSTDATA');
        }
        
        if ($json == 1){
            print $cgi_query->header('application/json');
        } else {
            print $cgi_query->header('text/html');
        }
                
        return $cgi_query;
    }
}

sub getAction {
    my $lisCGI = shift;
    
    if ($lisCGI){
        return $action;
    }
    else
    {
        return $caction;
    }
}

sub getActionParams {
    my $lisCGI = shift;
    my $laction = shift;
    my $larg;
    
    if ($lisCGI){
        $larg = $postdata;
    } else {
        $larg = $ARGV[0];
    }

    return $larg;
}

sub readLog {
    my $logFile = shift;
    open (LOGFILE, "<$logFile") || warn "unable to open logfile: $logFile: $!";
    while (<LOGFILE>){
        next unless (/\d+;\w+;/);
        my ( $id, $pilot, $departure, $destination, $takeoff, $arrival, $landings ) = split(/;/);
        chop($landings);
        my $flight = new flogEntry ($plane, $pilot, $departure, $destination, $takeoff, $arrival, $landings);
        push @allflights,$flight;
        push @allids, $id;
        if ($id >= $highestid){
            $highestid = $id;
        }
    }
    close (LOGFILE);
}

sub writeLog {
    my $logFile = shift;
    my $line, $id;
    open (LOGFILE, ">$logFile") || die "unable to open logfile: $logFile: $!";
    for (my $i = 0; $i <= $#allflights; $i++){
        $id = $allids[$i];
        print "ID: $id I: $i $allflights[$i]\n" if $debug;
        $line = $allflights[$i]->logFileEntry("$id");
        print LOGFILE "$line\n";
    }
    close (LOGFILE);

}

sub addLogEntry {
    my $flight = shift;
    my $IDX=-1;
    my $result = validateFlight($flight);
    
    if ($result != 1){
        print "invalid flight: " . $flight->print() if $debug;
        return 0;
    }

    if ($#allflights == -1){
        print "new flightlog\n" if $debug;
        push(@allflights, $flight);
        push(@allids,$highestid + 1);
        return 1;
    }
    
    for (my $i = $#allflights; $i >= 0; $i--){
        my $takeoff = $allflights[$i]->takeoffTime_seconds;
        if ($flight->takeoffTime_seconds > $takeoff){
            $IDX = $i;
            $flight->print("Insert after $IDX");
            $i = -1;
        }
    }

    splice (@allflights, $IDX +1, 0, $flight);
    splice (@allids, $IDX+1, 0, $highestid + 1);
    #my $ttf = $allflights[0]->takeoffTime();
    #say "$flight ALL $#allflights" if $debug;
}

sub validateFlight {
    my $flight = shift;
    my $takeoff_s = $flight->takeoffTime_seconds;
    my $tmp_s;
    
    for (my $i = 0; $i < $#allflights; $i++){

        $l_tot_s = $allflights[$i]->takeoffTime_seconds;
        $l_lt_s = $allflights[$i]->landingTime_seconds;
        if ($takeoff_s >= $l_tot_s && $takeoff_s <= $l_lt_s){
                say "conflicting flight" if $debug;
                push @returnLogs, $allflights[$i];
                return 0;
        }
    }
    return 1;
}

sub logToJSON {
    
}
# the class representing a single flight in a flight log
package flogEntry;
use 5.10.0;
use POSIX;

our $debug;

sub new {
    my $class = shift;
    my ( $plane, $pilot, $dap, $lap, $tot, $lat, $lc ) = @_;
    my $self = bless {
        plane => $plane,
        pilot => $pilot,
        departureAirport => $dap,
        landingAirport => $lap,
        takeoffTime => $tot,
        landingTime => $lat,
        landingCount => $lc,
    }, $class;
    
    return $self;
}


sub fromString {
    my $self = shift;
    my $text = shift;
    my @flogArray = split (/;/, $text);
    my $flEntry =  flogEntry->new(@flogArray);
    return $flEntry;

}

sub dayofFlight {
    my $self = shift;
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) =
                                                   gmtime($self->takeoffTime);
    $mon++; $year += 1900;
    $mon = ($mon >= 10 ? $mon : "0" . $mon);
    $mday = ($mday >= 10 ? $mday : "0" . $mday);
    
    return "$mday" . ":" . $mon . ":" . $year ;
}

sub departureAirport {
    my $self = shift;
    return $self->{'departureAirport'};
}

sub takeoffTime {
    my $self = shift;
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) =
    gmtime($self->{'takeoffTime'});
    $hour = ($hour >= 10 ? $hour : "0" . $hour);
    $min = ($min >= 10 ? $min : "0" . $min);
    return $hour . ":" . $min;
}

sub takeoffTime_seconds {
    my $self = shift;
    return $self->{'takeoffTime'};
}

sub landingAirport {
    my $self = shift;
    return $self->{'landingAirport'};
}

sub landingTime {
    my $self = shift;
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) =
    gmtime($self->{'landingTime'});
    $hour = ($hour >= 10 ? $hour : "0" . $hour);
    $min = ($min >= 10 ? $min : "0" . $min);
    return $hour . ":" . $min;
}

sub landingTime_seconds {
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
    return $self->{'landingTime'} - $self->{'takeOffTime'};
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

sub TO_JSON { return { %{ shift() } }; }

sub print_json {
    my $self = shift;
    my $JSON = JSON->new->utf8;
    $JSON->convert_blessed(1);
 
    my $json = $JSON->encode($self);
    say $json;
}

sub read_json {
    my $self = shift;
    my $json_text = shift;
    my $ref = JSON->new->utf8->decode("$json_text");
    bless $ref;
    return $ref;
}



sub logFileEntry {
    my $self = shift;
    my $text = shift;
    $text .= ";" . $self->pilot .
    ";" . $self->departureAirport .
    ";" . $self->landingAirport .
    ";" . $self->takeoffTime_seconds() .
    ";" . $self->landingTime_seconds() .
    ";" . $self->landingCount;
    return $text;
}

sub print {
    my $self = shift;
    my $text = shift;
    
    
    $text .= $self->pilot .
    ";" . $self->departureAirport .
    ";" . $self->takeoffTime_seconds .
    ";" . $self->landingAirport .
    ";" . $self->landingTime_seconds .
    ";" . $self->landingCount;
    
    say "$text";
}


