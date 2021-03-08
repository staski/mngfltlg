#!/usr/bin/perl

use 5.10.0;

#use strict;
#use warnings;

use XML::LibXML;
use Getopt::Long;
use Date::Parse;

use Math::Trig;
#use Math::Round;
use POSIX;# for floor etc.
use File::Temp;
use File::Copy;
use File::Path;


use CGI;
use CGI::Carp qw ( fatalsToBrowser );

use JSON;

package main;

my $scriptName = $0;
#possible values: add, list, read, delete

my $caction = "read";
my $json = 1;
$flightdir = "./flights";
my $glogFile = $flightdir . "/flightLog.txt";

my $postdata;
my $request_method;

my $gpxName = 'ttfExample.gpx';
my $sapt;

my $highestid = 0;
my $highestidx;

my $plane = "DEEBU";
my $pilot = "CP";
my $rules = "VFR";
my $function = "PIC";

$version_major = 0;
$version_minor = 92;

#the highest id *ever* found in the log. This number is strictly increasing
#over time
$loghighestid = 0;
$debug_var;
$tracefile =  $flightdir . "/trace.log";

use constant {
    FEET_FOR_M => 3.28084,
    KM_FOR_NM => 1.852,
};

%pilot_for_user = (
        axel => "Axel",
        markus => "Markus",
        cp => "CP",
        test => "TestPilot",
        testPilot => "TestPilot"
);

$headerpilot = "";
$headerplane = "";
$headerrules = "";
$headerfunction = "";

@trkpts = [];
$trkptcnt = 0;

GetOptions ("debug=s" => \$debug,
            "action=s" => \$caction,
            "gpxName=s" => \$gpxName,
            "json!" => \$json
);

$isCGI = isCGI($scriptName);

my $cgi_query = initCGI($isCGI);

$l_username = $ENV{'REDIRECT_REMOTE_USER'} || $ENV{'REMOTE_USER'};

if ($l_username eq "test"){
        $glogFile = "flights/test-flightLog.txt";
} elsif ($l_username eq "testint"){
    $glogFile = "flights/testint-flightLog.txt";
}
    
$action = getAction($isCGI);
say MYDEBUG "ACTION=$action" if $debug;


$actionParam = getActionParams($isGCI, $action);
say MYDEBUG  "ACTIONPARAM=$postdata" if $debug;

readLog($glogFile);

$mystart = time;

if ($action eq "read"){
        my $JS = JSON->new->utf8;
        $JS->convert_blessed(1);
        my $logArray = $JS->encode(\@allflights);
        say "$logArray";

}


if ($action  eq "update" && $request_method eq "POST"){
    my $flight = flogEntry->read_json($postdata);
    $flight->print("FLIGHT") if $debug;
    print MYDEBUG  "FLIGHTS before $#allflights\n" if $debug;
    updateLogEntry($flight);
    print MYDEBUG  "FLIGHTS after $#allflights\n" if $debug;
    writeLog($glogFile);
}

if ($action  eq "delete" && $request_method eq "POST"){
    my $flight = flogEntry->read_json($postdata);
#    $flight->print("FLIGHT") if $debug;
    print MYDEBUG  "FLIGHTS before $#allflights\n" if $debug;
    deleteLogEntry($flight);
    print MYDEBUG  "FLIGHTS after $#allflights\n" if $debug;
    writeLog($glogFile);
}

if ($action eq "create"){
#    foreach my $key (sort(keys(%ENV))) {
#        $l_username .= "$key = $ENV{$key} || ";
#    }

    my $l_username = $ENV{'REDIRECT_REMOTE_USER'};
    $pilot = length ($headerpilot) ? $headerpilot : defined($pilot_for_user{$l_username}) ? $pilot_for_user{$l_username} : "$l_username";
    $plane = length ($headerplane) ? $headerplane : $plane;
    $rules = length ($headerrules) ? $headerrules : $rules;
    $function = length ($headerfunction) ? $headerfunction : $function,
    
    say MYDEBUG "using pilot: $pilot ($headerpilot)" if $debug;
    say MYDEBUG "using plane: $plane ($headerplane)" if $debug;
    say MYDEBUG "using rules: $rules ($headerrules)" if $debug;
    say MYDEBUG "using function: $function ($headerfunction)" if $debug;

    my $source = readAirportDirectory();
    $sapt = gpxPoint->new({lat=>$lat{$source},lon=>$lon{$source}});

    my @flightSegments = readGpxFile($gpxName);
    if ($#flightSegments < 0){
        die "not a valid flight found in $gpxName";
    }

    # join those entries where the takeoff is from the same AP as the landing of the previous and this
    # one
    joinFlights(@flightSegments);

    foreach my $flight (@jap) {
        $flight->setPilot($pilot);
        my $result = addLogEntry($flight);
        if ($result > 0){
                $flight->setId($result);
                print MYDEBUG  "LogEntry exists ID: " . $result . "\n" if $debug;
        }
        else {
            cleanupDirForFlight($flight);
            my $dir = createDirForFlight($flight);
            my $dest = $dir . "/" . "track.gpx";
            copy ($gpxName, $dest) || die "can't copy $gpxName to $ dest: $!";

            # check if directory 'flights/yearofflight exists
            # create directory flights/yearofflight/flight->id
            # copy gpxFile to flights/aearofFlight/flight->id
            # write: timestamp AND log-entry into file log.txt
            # write: file details.txt (containing ...)
        
            my $jsparser = JSON->new->utf8;
            $jsparser->convert_blessed(1);
            my $jsstats = $jsparser->encode($flight->{stats});
            say MYDEBUG "$jsstats" if $debug;   
            my $statfile = $dir . "/" . "stats1.txt";
            open (STATFILE, ">$statfile") || warn "can't open statfile $statfile: $!";
            say STATFILE "$jsstats";
            close (STATFILE);  
        }
    }
    
    writeLog($glogFile);
    
    my $JS = JSON->new->utf8;
    $JS->convert_blessed(1);
    my $jsoutput = $JS->encode(\@jap);
    say "$jsoutput";
    
}

my $duration = time - $mystart;
say MYDEBUG "FINISHED after $duration seconds\n" if $debug;

sub createDirForId {
    my $year = shift;
    my $id = shift;

    my $dir = $flightdir . "/" . "$year";
    if (!(-d "$dir")){
        mkdir $dir;
    }
    $dir = $dir . "/$id";
    if (!(-d "$dir")){
        mkdir $dir;
    }
    return $dir; 
}

sub createDirForFlight {
    my $flight = shift;
    my $year = $flight->yearOfFlight;
    my $id = $flight->id;
    
    return createDirForId($year, $id);
}

sub getDirForId {
    my $year = shift;
    my $id = shift;

    return "$flightdir" . "/" . "$year" . "/" . "$id";
}

sub getDirForFlight {
    my $flight = shift;
    my $year = $flight->yearOfFlight;
    my $id = $flight->id;

    return getDirForId( $year, $id);
}

sub cleanupDirForFlight {
    my $flight = shift;

    my $dir = getDirForFlight($flight);

    if (-d $dir){
        say MYDEBUG "Directory $dir exists" if ($debug);
    }

    rmtree $dir;

    if (!-d $dir){
        say MYDEBUG "Directory $dir deleted" if ($debug);
    }
}

sub readStatsForFlight {
    my $flight = shift;
    my $dir = getDirForFlight($flight);
    my $statfile = $dir . "/" . "stats1.txt";
    my $flightstats;

    say MYDEBUG "$statfile" if $debug;
    
    my $handle = open (STATFILE, "<$statfile");
    if ($handle)
    {
        my $json_text = <STATFILE>;
        close (STATFILE);
        $flightstats = flogStats->read_json($json_text);
        say MYDEBUG "STATS $flightstats" if $debug;
    }
    else
    {
        say MYDEBUG "WARNING: can't open statfile $statfile: $!";
    }
    return $flightstats;
}

sub joinFlights {
    my @af = @_;
    my $prev= $af[0];

    push @jap, $prev;
    for (my $i = 1; $i <= $#af; $i++) {
        my $this = $af[$i];
        $prev->print("PREV: ") if ($debug);
        $this->print("THIS: ") if ($debug);
        if ($prev->landingAirport eq $this->departureAirport &&
            $this->landingAirport eq $this->departureAirport && ($this->takeoffTime_seconds - $prev->landingTime_seconds < 60)){
                say MYDEBUG  "HIT" if ($debug);
                $prev->setLandingTime($this->landingTime_seconds);
                $prev->setOnBlockTime($this->onBlock_seconds);
                $prev->setLandingAirport($this->landingAirport);
                $prev->setLandingCount($prev->landingCount + $this->landingCount);
                $prev->stats()->merge($this->stats());
        }
        else {
            $prev = $this;
            push @jap, $this;
        }
    }
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
        
        open (MYDEBUG, ">$tracefile") || die "can't open mem file: $!";
                
        my $cgi_query = CGI->new();
        $debug = $cgi_query->url_param('debug');
        $action = $cgi_query->url_param('action');
        $request_method = $cgi_query->request_method();
        
        if ($action eq "update" || $action eq "delete"){
            $postdata = $cgi_query->param('POSTDATA');
        }

        if ($action eq "create"){
            $headerpilot = $cgi_query->param('pilot');
            $headerplane = $cgi_query->param('plane');
            $headerrules = $cgi_query->param('rules');
            $headerfunction = $cgi_query->param('function');
            $gpxName = getGpxName($cgi_query);
            
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
    my $logversion_major = 0;
    my $logversion_minor = 0;

    my $id, $pilot, $plane, $departure, $destination, 
                $offblock, $takeoff, $arrival, $onblock, $landings,
                $rules, $function;
    open (LOGFILE, "<$logFile") || warn "unable to open logfile: $logFile: $!";
    while (<LOGFILE>){
        if (/FLTLGHDR;(\d+)\.(\d+);(\d+)/){
            $logversion_major = $1;
            $logversion_minor = $2;
            $loghighestid = $3;
            $highestid = $loghighestid;
        }
        next unless (/\d+;\w+;/);
        if ($logversion_major == 0 && $logversion_minor <= 90)
        { 
            ( $id, $pilot, $departure, $destination, $takeoff, $arrival, $landings ) = split(/;/);
            $offblock = $takeoff;
            $onblock = $arrival;
            $rules ="VFR";
            $function ="PIC";
        }
        elsif ($logversion_major == 0 && $logversion_minor <= 91)
        {
            ( $id, $pilot, $plane, $departure, $destination, 
                $offblock, $takeoff, $arrival, $onblock, $landings ) = split(/;/);
            $rules ="VFR";
            $function ="PIC";

        }
        else
        {
            ( $id, $pilot, $plane, $departure, $destination,
                $offblock, $takeoff, $arrival, $onblock,
                $rules, $function, $landings ) = split(/;/);

        }
        chop($landings);
        my $flight = new flogEntry ($id, $pilot, $plane, $departure, $destination, 
            $offblock, $takeoff, $arrival, $onblock, $rules, $function, $landings);
        
        my $flightstats = readStatsForFlight($flight);
        if ($flightstats){
            $flight->setStats($flightstats);
        }
        
        say MYDEBUG $flight->departureAirport . "$departure" if $debug;
        
        push @allflights,$flight;
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
    print LOGFILE "FLTLGHDR;$version_major.$version_minor;$highestid\n";
    for (my $i = 0; $i <= $#allflights; $i++){
        print MYDEBUG  "I: $i $allflights[$i]\n" if $debug;
        $line = $allflights[$i]->logFileEntry("");
        print LOGFILE "$line\n";
    }
    close (LOGFILE);

}

sub addLogEntry {
    my $flight = shift;
    my $IDX=-1;
    my $result = validateFlight($flight);
    
    if ($result != 0){
        print MYDEBUG  "invalid flight: " . $flight->logFileEntry() . "\n" if $debug;
        return $result;
    }

    $flight->setId($highestid + 1); $highestid++;
    if ($#allflights == -1){
        print MYDEBUG  "new flightlog\n" if $debug;
        push(@allflights, $flight);
        return 0;
    }
    
    for (my $i = $#allflights; $i >= 0; $i--){
        my $takeoff = $allflights[$i]->takeoffTime_seconds;
        if ($flight->takeoffTime_seconds > $takeoff){
            $IDX = $i;
#            $flight->print("Insert after $IDX");
            $i = -1;
        }
    }

    splice (@allflights, $IDX +1, 0, $flight);
    return 0;
}

sub updateLogEntry {
    my $flight = shift;
    my $result = validateFlight($flight);
    my $IDX = -1;
    
    if ($result == 0){
        print MYDEBUG  "invalid flight: " . $flight->print() if $debug;
        return 0;
    }

    for (my $i = $#allflights; $i >= 0; $i--){
        if ($flight->id == $allflights[$i]->id){
            $IDX = $i;
            $i = -1;
        }
    }

    if ($IDX >= 0){
        splice (@allflights, $IDX, 1, $flight);
        return 1;
    }
    else
    {
        say MYDEBUG "no valid flight found with ID: " .  "$flight->id()";
        return 0;
    }
    return 1;
}

sub deleteLogEntry {
    my $flight = shift;
    my $result = validateFlight($flight);
    my $IDX = -1;
    
    if ($result == 0){
        print MYDEBUG  "invalid flight: " . $flight->print() if $debug;
        return 0;
    }

    for (my $i = $#allflights; $i >= 0; $i--){
        if ($flight->id == $allflights[$i]->id)
        {
            $allflights[$i]->print("MATCH ") if $debug;
            $IDX = $i;
            $i = -1;
        }
    }

    if ($IDX >= 0){
        cleanupDirForFlight($flight);
        splice (@allflights, $IDX, 1);
        return 1;
    }
    else
    {
        say MYDEBUG "no valid flight found with ID: " .  "$flight->id()";
        return 0;
    }
}

#check a given flight if it already exists
#return id if it's id is not initial
#return id if it's departure time is in between any other flight
#return  0 otherwise

sub validateFlight {
    my $flight = shift;
    my $takeoff_s = $flight->takeoffTime_seconds;
    my $tmp_s;
    
    if ($flight->hasValidId() == 1){
        print MYDEBUG "flight already has ID: " . $flight->id() . "\n" if $debug;
        return $flight->id();
    }
    
    #  TODO: when storing flights, timers might get rounded to the next minute
    #  this might interfere with this heuristic
    #  
    for (my $i = 0; $i <= $#allflights; $i++){
        $l_tot_s = $allflights[$i]->offBlock_seconds;
        $l_lt_s = $allflights[$i]->onBlock_seconds;
          if ($takeoff_s >= $l_tot_s && $takeoff_s < $l_lt_s){
                my $lid = $allflights[$i]->id;
                say MYDEBUG  "conflicting flight $lid $l_tot_s <= $takeoff_s < $l_lt_s\n" if $debug;

                if ($takeoff_s == $l_tot_s) {
                    $flight->setId($lid);
                }
                push @returnLogs, $allflights[$i];
                return $lid;
        }
    }
    return 0;
}

sub logToJSON {
    
}

sub getGpxName {
    my $query = shift;
    my $gName = $gpxName;

    if ($isCGI == 1){
    
        my $lfh  = $query->upload('file');
        say MYDEBUG "PILOT $headerpilot" if $debug;
        $tmpfile = File::Temp->new();
        $gName = $tmpfile->filename;
        say MYDEBUG  $gName if $debug;
        if (defined $lfh) {
            # Upgrade the handle to one compatible with IO::Handle:
            my $io_handle = $lfh->handle;
        
            while ($bytesread = read($io_handle, $buffer, 1024)) {
                print $tmpfile $buffer;
            }
            close $tmpfile;
        }
    }
    return $gName;
}

use constant {
    TI_UNIT => 30,
    TI_PER_MINUTE => 2,
};

sub readGpxFile {
    my $likelytakeoffspeed = 50;
    my $takeoffSpeed = 70;
    my $landingSpeed = 60;
    my $taxiSpeed = 5;
    my $feet_for_m = 3.28084;

    my $fname = shift;
    my @newSegments;
    my $tmpFile = XML::LibXML->load_xml(location => $fname);
    my $xpc = XML::LibXML::XPathContext->new($tmpFile);
    $xpc->registerNs('g', 'http://www.topografix.com/GPX/1/1');

    my $count = 0;
    my $i= 0;
    
    my $offblock_i = -1, $takeoff_i = -1, $landing_i = -1, $onblock_i = -1;
    
    use constant {
        AT_REST => 0,
        TAXI => 1,
        LIKELY_FLYING => 2,
        FLYING => 3,
        LIKELY_TAXI => 4,
    };
    
    my $state = AT_REST;
    
    @trkpts = [];
    $trkptcnt = 0;
    
    my @fpm = [];
    my @speed_avg = [];
    my @alt_avg = [];
    
    my $avg_cnt = 0;
    my $elapsed = 0;
    my $elapsed_minutes = 0;
    
    $lastele = 0;
    
    #read GPX-File
    my @allnodes = $xpc->findnodes('//g:trkpt');

    #create Pivot-Element (index 0)
    my $gpx = shift @allnodes;
    my $lat = $gpx->getAttribute('lat');
    my $lon = $gpx->getAttribute('lon');
    
    
    my $ele = ceil($xpc->findvalue('g:ele', $gpx) * FEET_FOR_M);
    my $speed = ceil($xpc->findvalue('g:speed', $gpx) * (3.6/KM_FOR_NM));
    my $time = str2time($xpc->findvalue('g:time', $gpx));
    
    my $starttime = $time;
    
    my $loc = $trkpts[$i] = gpxPoint->new({lat=>$lat,
                                lon=>$lon,
                                ele=>$ele,
                                speed=>$speed,
                                gpxtime=>$time});
    $i++;

    my $ap = findNearestAirport($loc);
    my $alt_ft, $distance;
    my $flight, $nextFlight;

    $alt_ft = $alt_ft{$ap};
    $distance = $loc->distance(gpxPoint->new({lat=>$lat{$ap},lon=>$lon{$ap}}));

    if ($distance > 5000){
        $count++;

        $state = FLYING;
        $distance = int(($distance /(1000 * KM_FOR_NM)) + 0.5);
        say MYDEBUG "Log starts in flight $distance NMs from $ap, ALT = $ele, SPEED = $speed)" if ($debug);

        $ap = "Unknown";
        $flight = flogEntry->new(-1, $pilot, $plane, $ap ,"",
                                    $time, $time, 0,0, $rules, $function, 1);

    }
    else
    {
        say MYDEBUG "START on AP $ap (DIST = $distance, ALT = $alt_ft)" if ($debug);
        $flight = flogEntry->new(-1, $pilot, $plane, $ap ,"",
                                    0, 0, 0,0, $rules, $function, 1);
    }

    $speed_avg[$elapsed_minutes] = $speed;
    $alt_avg[$elapsed_minutes] = $ele;

    $distance = 0;
    $lastele = $ele;
    
    
    
GPXPOINT:
    foreach $gpx (@allnodes) {
        my $lat = $gpx->getAttribute('lat');
        my $lon = $gpx->getAttribute('lon');
        my $timestr;
                
        $ele = ceil($xpc->findvalue('g:ele', $gpx) * $feet_for_m);
        $speed = ceil($xpc->findvalue('g:speed', $gpx) * 3600/1852);
        my @speedArray = $xpc->findnodes('g:speed', $gpx);
        my $speedExists = @speedArray;
        
        $timestr = $xpc->findvalue('g:time', $gpx);
        $time = str2time($timestr);
        
        my $prev = $loc;

        #adapt general statistics
        if ($speed > $speed_max)
        {
            $speed_max = $speed;
        }
        
        if ($ele > $alt_max)
        {
            $alt_max = $ele;
        }
        
        $loc = gpxPoint->new({lat=>$lat,
                                    lon=>$lon,
                                    ele=>$ele,
                                    speed=>$speed,
                                    gpxtime=>$time});
        
        $timediff = $loc->{gpxtime} - $prev->{gpxtime};
        
        if ($timediff == 0){
            #say MYDEBUG "SKIP" if ($debug);
            $loc = $prev;
            next GPXPOINT;
        }
        
        $elapsed += $timediff;
        
        $distance += $loc->distance($prev);
        $track = $prev->bearing($loc);
        $fpm = ($loc->ele() - $prev->ele()) * 60 / $timediff;

        if ($speedExists == 0)
        {
            $speed = $loc->distance($prev) / $timediff;
            $speed = $speed * 3600 / 1852;
            say MYDEBUG "speed from GPX file was $speedExists, using $speed kts from coordinates instead" if ($debug);
        }
        
        $speed_avg[$elapsed_minutes] += $speed;
        $alt_avg[$elapsed_minutes] += $ele;
        $avg_cnt++;
        
        if ($elapsed > TI_UNIT){
            my $alt_diff = $loc->ele() - $lastele;
            $fpm[$elapsed_minutes] = $alt_diff * 60 / $elapsed;
            $speed_avg[$elapsed_minutes] /= $avg_cnt;
            $alt_avg[$elapsed_minutes] /= $avg_cnt;

            my $fpm = $fpm[$elapsed_minutes];
            my $speed = $speed_avg[$elapsed_minutes];
            if ($fpm < -100)
            {
                    $descend_minutes++;
                    $total_descend += $alt_diff;
                    $flying_minutes++;
            }
            elsif ($fpm > 100)
            {
                    $climb_minutes++;
                    $total_climb += $alt_diff;
                    $flying_minutes++;
            }
            elsif ($state == FLYING)
            {
                $straightlevel_minutes++;
                $flying_minutes++;
            }
            elsif ($flight->offBlock_seconds() != 0)
            {
                if ($state == TAXI)
                { 
                    $taxi_minutes++
                }
                else
                {
                    $rest_minutes++;
                }   
            }

            
            my $text = $timestr . ": (count = " . $avg_cnt . "), elapsed: " . $elapsed_minutes / TI_PER_MINUTE  . ", FPM: " . $fpm[$elapsed_minutes] . ", SPEED AVG: " .
                $speed_avg[$elapsed_minutes] . ", ALT AVG: " . $alt_avg[$elapsed_minutes] . 
                " REST/TAXI/FLYING: " . "$rest_minutes / $taxi_minutes / $flying_minutes"  ;
            say MYDEBUG $text if $debug;


            $lastele = $ele;
            $elapsed_minutes++;
            $elapsed -= TI_UNIT;
            $avg_cnt = 0;
            
            #todo: that's not quite right -- all climb is associated to the first timeslot
            while ($elapsed > TI_UNIT) {
                $fpm[$elapsed_minutes] = 0;
                $speed_avg[$elapsed_minutes] = $speed_avg[$elapsed_minutes - 1];
                $alt_avg[$elapsed_minutes] = $alt_avg[$elapsed_minutes - 1];
                $elapsed_minutes++;
                $elapsed -= TI_UNIT;
            }
        }
        
        #todo: $elapsed is wrong here ...
        $loc->setTrackFpmDistance($track, $fpm, $distance, $elapsed);
        
        $trkpts[$i] = $loc;
        
        if ($state == AT_REST)
        {
            if ($speed > $taxiSpeed)
            {
                $state = TAXI;

                if ($flight->offBlock_seconds == 0)
                {
                    $flight->setOffBlockTime($time);
                }
                else
                {
                    #if we do a landing, then taxi, then takeoff again, the first flight has onblock time equeal to
                    #takeoff time of the second flight, and equal to offblocktime of that flight
                }
                $flight->print("EVENT: AT_REST->TAXI ");
                $count++;

            }
        }
        elsif ($state == TAXI)
        {
            if ($speed > $takeoffSpeed){
                $state = FLYING;

                if ($flight->landingTime_seconds() != 0)
                {
                    if (!defined($nextFlight))
                    {
                        $nextFlight = flogEntry->new(-1, $pilot, $plane, $ap ,"",
                            $time, $time, 0,0, $rules, $function, 1);
                        $flight->setOnBlockTime($time);
                    }

                    my $stats = flogStats->new($distance / (1000 * KM_FOR_NM), $elapsed_minutes / TI_PER_MINUTE, 
                    $rest_minutes / TI_PER_MINUTE, $taxi_minutes / TI_PER_MINUTE,
                    $flying_minutes / TI_PER_MINUTE, $climb_minutes /TI_PER_MINUTE, $straightlevel_minutes / TI_PER_MINUTE, 
                    $descend_minutes / TI_PER_MINUTE, $total_climb, $total_descend); 
                    $flight->setStats($stats);
                    $flight->{stats}->print() if $debug;

                    $distance = 0; $elapsed_minutes = 0; $climb_minutes = 0; $straightlevel_minutes = 0; $descend_minutes = 0;
                    $total_climb = 0; $total_descend = 0;
                    $rest_minutes = 0; $taxi_minutes = 0; $flying_minutes =0;
     
                    push @newSegments, $flight;
                    $flight = $nextFlight;
                    undef $nextFlight;
                }
                else
                {
                        $flight->setTakeoffTime($time);
                }

                $count++;
                
                $flight->print("EVENT: TAXI->FLYING ");

            }
            elsif ($speed > $likelytakeoffspeed)
            {
                    $state = LIKELY_FLYING;
                    $flight->print("EVENT: TAXI->LIKELY_FLYING ");
            }
            
            if ($speed < $taxiSpeed)
            {
                $state = AT_REST;
                
                $flight->setOnBlockTime($time);

                $flight->print("EVENT: TAXI->AT_REST  ");

                $count++;
            }
        }
        elsif ($state == LIKELY_FLYING)
        {
            $ap = findNearestAirportWithHint($loc, $ap);
            $alt_ft = $alt_ft{$ap};
            if ($speed > $takeoffSpeed || ($ele - $alt_ft) > 50){
                $state = FLYING;
                
                if ($debug){
                    if ($speed > $takeoffSpeed){
                        $reason = " reached takeoff speed ($speed kts > $takeoffSpeed kts) ELE: $ele (AP: $alt_ft)";
                    }
                    else
                    {
                        $reason = " positive climb ($speed kts > $takeoffSpeed kts) ELE: $ele (AP: $alt_ft)";
                    }
                }

                if ($flight->landingTime_seconds() != 0)
                {
                    if (!defined($nextFlight))
                    {
                        $nextFlight = flogEntry->new(-1, $pilot, $plane, $ap ,"", $time, $time, 0,0, $rules, $function, 1);
                        $flight->setOnBlockTime($time);
                    }

                    my $stats = flogStats->new($distance / (1000 * KM_FOR_NM), $elapsed_minutes / TI_PER_MINUTE, 
                    $rest_minutes / TI_PER_MINUTE, $taxi_minutes / TI_PER_MINUTE,
                    $flying_minutes / TI_PER_MINUTE, $climb_minutes /TI_PER_MINUTE, $straightlevel_minutes / TI_PER_MINUTE, 
                    $descend_minutes / TI_PER_MINUTE, $total_climb, $total_descend);
                    
                    $flight->setStats($stats);

                    $flight->{stats}->print() if $debug;

                    $distance = 0; $elapsed_minutes = 0; $climb_minutes = 0; $straightlevel_minutes = 0; $descend_minutes = 0;
                    $total_climb = 0; $total_descend = 0;
                    $rest_minutes = 0; $taxi_minutes = 0; $flying_minutes =0;

                    push @newSegments, $flight;
                    $flight = $nextFlight;
                    undef $nextFlight;
                }
                else
                {
                        $flight->setTakeoffTime($time);
                }
                $reason = "EVENT: LIKELY_FLYING->FLYING ($reason)";
                $flight->print($reason);

                $count++;
            }
            elsif ($speed < $landingSpeed)
            {
                $state = TAXI;
                $flight->print("EVENT: LIKELY_FLYING->TAXI");
            }
            
        }
        elsif ($state == FLYING)
        {
            if ($speed < $landingSpeed)
            {
                $ap = findNearestAirportWithHint($loc, $ap);
                $alt_ft = $alt_ft{$ap};

                if ($ele - $alt_ft <= 50)
                {
                    $state = TAXI;
                    
                
                    $flight->setLandingTime($time);
                    $flight->setLandingAirport($ap);
                
                    $landing_i = $i;
                
                    $flight->print("EVENT: FLYING->TAXI ");

                    $count++;
                } else
                {
                    say MYDEBUG "no landing: SPEED is $speed but ALT is $ele (>$alt_ft at $ap)" if $debug;
                }
                
            }
        }
        $i++;
    }
    
    if ($state == AT_REST)
    {
        my $stats = flogStats->new($distance / (1000 * KM_FOR_NM), $elapsed_minutes / TI_PER_MINUTE, 
                    $rest_minutes / TI_PER_MINUTE, $taxi_minutes / TI_PER_MINUTE,
                    $flying_minutes / TI_PER_MINUTE, $climb_minutes /TI_PER_MINUTE, $straightlevel_minutes / TI_PER_MINUTE, 
                    $descend_minutes / TI_PER_MINUTE, $total_climb, $total_descend);
        $flight->setStats($stats);
        $flight->{stats}->print() if $debug;
        
        $distance = 0; $elapsed_minutes = 0; $climb_minutes = 0; $straightlevel_minutes = 0; $descend_minutes = 0;
        $total_climb = 0; $total_descend = 0;
        $rest_minutes = 0; $taxi_minutes = 0; $flying_minutes =0;

        push @newSegments, $flight;
        $flight->print("EVENT: FINAL AT_REST");

        $count++;
    }

    if ($state == TAXI)
    {
        $flight->setOnBlockTime($time);
        push @newSegments, $flight;
        $flight->print("EVENT: FINAL TAXI->AR_REST ");

        $count++;
    }

    $minutes = $elapsed_minutes / 2;
    $climb_minutes /= 2;
    $straightlevel_minutes /= 2;
    $descend_minutes /= 2;
    $distance /= 1000;
    
    $flightstats = "total time: $minutes minutes, distance: $distance km, climb: $climb_minutes minutes ($total_climb ft), " .
        "straight level flight: $straightlevel_minutes, descend: $descend_minutes minutes ($total_descend feet)";
    
    say MYDEBUG $flightstats if $debug;
    #return @fa;
    return @newSegments;
}

sub findNearestAirportWithHint {
    my $target = shift;
    my $hint = shift;
    my $lat = $lat{$hint};
    my $lon = $lon{$hint};

    my $dist = $target->distance(gpxPoint->new({lat=>$lat, lon=>$lon}));
    
    if ($dist < 5000)
    {
        return $hint;
    }
    
    return findNearestAirport($target);
}


#find the airtport closest to point target,
sub findNearestAirport {
    my $target = shift;
    my $i; $start;
    my $nearest = 100000000;
    my $nix = 0;
    
    #distance to home airport ($apt) serves as a hint indes into airport directory
    my $dist = ceil($target->distance($sapt)/1000);
    for ($i = 0; $i < $#distances && ($dist > $distances[$i]); $i++){
        #say MYDEBUG "IDX $i DISTANCE $distances[$i]" if ($debug);
    }
    
    $start = 0;
    $end = ($i + 1) * 1000;
    if ($end > $#allairports){
        $end = $#allairports;
    }

    say MYDEBUG "SEARCH between $start and $end" if ($debug);
    for ($i = $start; $i < $end; $i++){
        my $lat = $lat{$allairports[$i]};
        my $lon = $lon{$allairports[$i]};
        my $ap = gpxPoint->new({lat=>$lat, lon=>$lon});
        $dist = $target->distance($ap);
        #say MYDEBUG "idx $i $dist ($nearest): $allairports[$i]" if ($debug);
        if ($dist < $nearest){
            $nix = $i;
            $nearest = $dist;
            #say MYDEBUG "NEAREST $nix $dist" if ($debug);
            if ($dist < 2000) {
                #say MYDEBUG "PERFECT match -> break LOOP" if ($debug);
                last;
            }
        }
    }
    say MYDEBUG "FOUND NEAREST $allairports[$nix] DIST $nearest" if ($debug);
    return $allairports[$nix];
}

sub readAirportDirectory {
    my $airportDirectory = "ap_from_edfm.txt";
    my $sourceAirport;

    open (ALLAIRPORTS, "<$airportDirectory" ) || die "can't open file $airportDirectory: $!";

    @firstLine = split(/;/, <ALLAIRPORTS>);
    my $version=$firstLine[0];
    $sourceAirport =$firstLine[1];

    $sourceAirport =~ s/ap=(.+)/$1/;
    say MYDEBUG "Source Airport: $sourceAirport" if ($debug);
    
    if ($version =~ /addbbdfi(\d+)\.(\d+)/){
        my ($major, $minor) = ($1,$2);
        say MYDEBUG "VERSION $major . $minor" if ($debug);
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
    
    close ALLAIRPORTS;
    
    return $sourceAirport;
}


# the class representing a point on earth
package gpxPoint;
use 5.10.0;
#our $debug;

sub new {
    my ($class, $args ) = @_;
    my $self = {
        lat  => $args->{lat},
        lon => $args->{lon},
        ele  => $args->{ele} || 0,
        speed => $args->{speed} || 0,
        gpxtime => $args->{gpxtime} || "",
        track => 0,
        fpm => 0,
        timediff => 0,
       };
       return bless $self, $class;
}

sub setTrackFpmDistance {
    my $self = shift;
    my $track = shift;
    my $fpm = shift;
    my $distance = shift;
    my $timediff = shift;
    
    $self->{'track'} = $track;
    $self->{'fpm'} = $fpm;
    $self->{'distance'} = $distance;
    $self->{'timediff'} = $timediff;
}

sub printdebug {
    my $self = shift;
    my $text = shift;
    
    my $outp = "($text) TIME: " . $self->gpxtime() . ", LAT: " . $self->{'lat'} . ", LON: " . $self->{'lon'} . ", ALT: " . $self->{'ele'} . ", SPEED: " . $self->speed() . ", TRACK: " . $self->track() . ", FPM: " . $self->fpm() . ", TOTAL: " . $self->trackDistance();
    
    say main::MYDEBUG $outp;
}
sub print {
    my $self = shift;
    my $text = shift;
    say "($text) LAT: " . $self->{'lat'} . " LON: " . $self->{'lon'};
}

sub lon {
    my $self = shift;
    return $self->{'lon'};
}

sub lat {
    my $self = shift;
    return $self->{'lat'};
}

sub ele {
    my $self = shift;
    return $self->{'ele'};
}

sub speed {
    my $self = shift;
    return $self->{'speed'};
}

sub gpxtime {
    my $self = shift;
    return $self->{'gpxtime'};
}

sub track {
    my $self = shift;
    return $self->{'track'};
}

sub fpm {
    my $self = shift;
    return $self->{'fpm'};
}

sub trackDistance {
    my $self = shift;
    return $self->{'distance'};
}



#returns the distance between two points in meters
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
    say main::MYDEBUG "DISTANCE $distance" if ($debug);
    
    return $distance;
}

sub bearing {
    my $self = shift;
    my $other = shift;
    
    
    $self->print("SELF") if ($debug);
    $other->print("OTHER") if ($debug);
    
    my $lon2 = Math::Trig::deg2rad($other->lon);
    my $lon1 = Math::Trig::deg2rad($self->lon);
    my $lat2 = Math::Trig::deg2rad(90 - $other->lat);
    my $lat1 = Math::Trig::deg2rad(90 - $self->lat);
    
    my $bearing = Math::Trig::rad2deg(Math::Trig::great_circle_bearing($lon1,$lat1,$lon2,$lat2));
    
    say MYDEBUG "BEARING $bearing" if ($debug);
    
    return $bearing;
}

sub timediff {
    my $self = shift;
    my $other = shift;
    
    $self->gpxtime - $other->gpxtime;
    
}

package flogStats;
use 5.10.0;
use POSIX;
#use Math::Round;

our $debug;



sub new 
{
    my $class = shift;
    my ($flightDistanceNM, $elapsedMinutes, $restMinutes, $taxiMinutes, $flyingMinutes, $climbMinutes, $levelMinutes, $descendMinutes,$totalClimbFt, $totalDescendFt) = @_;
    my $self = bless 
    {
        flightDistanceNM => int($flightDistanceNM + 0.5),
        elapsedMinutes => $elapsedMinutes,
        restMinutes => $restMinutes,
        taxiMinutes => $taxiMinutes,
        flyingMinutes => $flyingMinutes,
        climbMinutes => $climbMinutes,
        levelMinutes => $levelMinutes,
        descendMinutes => $descendMinutes,
        totalClimbFt => $totalClimbFt,
        totalDescendFt => $totalDescendFt,
    }, $class;
    
    return $self;

}

sub merge {
    my $self = shift;
    my $other = shift;

    $self->{flightDistanceNM} += $other->{flightDistanceNM};
    $self->{elapsedMinutes} += $other->{elapsedMinutes};
    $self->{restMinutes} += $other->{restMinutes};
    $self->{taxiMinutes} += $other->{taxiMinutes};
    $self->{flyingMinutes} += $other->{flyingMinutes};
    $self->{climbMinutes} += $other->{climbMinutes};
    $self->{levelMinutes} += $other->{levelMinutes};
    $self->{descendMinutes} += $other->{descendMinutes};
    $self->{totalClimbFt} += $other->{totalClimbFt};
    $self->{totalDescendFt} += $other->{totalDescendFt};    
}

sub print 
{
    my $self = shift;
    say main::MYDEBUG "Total time: $self->{elapsedMinutes} min";
    say main::MYDEBUG "Rest time: $self->{restMinutes} min";
    say main::MYDEBUG "Taxi time: $self->{taxiMinutes} min";
    say main::MYDEBUG "Flight time: $self->{flyingMinutes} min";
    say main::MYDEBUG "Climb: $self->{climbMinutes} min";
    say main::MYDEBUG "Level flight: $self->{levelMinutes} min";
    say main::MYDEBUG "Descend: $self->{descendMinutes} min";
    say main::MYDEBUG "Total distance $self->{flightDistanceNM} NM";
    say main::MYDEBUG "Total Climb: $self->{totalClimbFt} ft";
    say main::MYDEBUG "Total descend: $self->{totalDescendFt} ft";

}

sub TO_JSON { 
    return { %{ shift() } }; 
}

sub read_json {
    my $self = shift;
    my $json_text = shift;
    my $ref = JSON->new->utf8->decode("$json_text");
    bless $ref;
    return $ref;
}


# the class representing a single flight in a flight log
package flogEntry;
use 5.10.0;
use POSIX;

our $debug;


sub new {
    my $class = shift;
    my ( $id, $pilot, $plane, $dap, $lap, $offblock, $tot, $lat, $onblock, $rls, $fctn, $lc ) = @_;
    my $self = bless {
        id => $id,
        plane => $plane,
        pilot => $pilot,
        departureAirport => $dap,
        landingAirport => $lap,
        offBlock => $offblock,
        takeoffTime => $tot,
        landingTime => $lat,
        onBlock => $onblock,
        rules => $rls,
        function => $fctn,
        landingCount => $lc,
    }, $class;
    
    return $self;
}

sub setStats 
{
    my $self = shift;
    $self->{stats} = shift;
}

sub stats 
{
    my $self = shift;
    return $self->{stats};
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

sub yearOfFlight {
    my $self = shift;
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) =
    gmtime($self->{'offBlock'});
    $mon++; $year += 1900;
    return $year;
}

sub departureAirport {
    my $self = shift;
    return $self->{'departureAirport'};
}

sub offBlock {
    my $self = shift;
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) =
    gmtime($self->{'offBlock'});
    $hour = ($hour >= 10 ? $hour : "0" . $hour);
    $min = ($min >= 10 ? $min : "0" . $min);
    return $hour . ":" . $min;
}

sub offBlock_seconds {
    my $self = shift;
    return $self->{'offBlock'};
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

sub onblock {
    my $self = shift;
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) =
    gmtime($self->{'onBlock'});
    $hour = ($hour >= 10 ? $hour : "0" . $hour);
    $min = ($min >= 10 ? $min : "0" . $min);
    return $hour . ":" . $min;
}

sub onBlock_seconds {
    my $self = shift;
    return $self->{'onBlock'};
}

sub pilot {
    my $self = shift;
    return $self->{'pilot'};
}

sub id {
    my $self = shift;
    return $self->{'id'};
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

sub rules {
    my $self = shift;
    return $self->{'rules'};
}

sub function {
    my $self = shift;
    return $self->{'function'};
}

sub setRules {
        my $self = shift;
        my $rules = shift;
        $self->{'rules'} = $rules;
}

sub setFuntion {
        my $self = shift;
        my $function = shift;
        $self->{'function'} = $function;
}

sub setPilot {
        my $self = shift;
        my $pilot = shift;
        $self->{'pilot'} = $pilot;
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

sub setOffBlockTime {
    my $self = shift;
    my $obt = shift;
    $self->{'offBlock'} = $obt;
}

sub setTakeoffTime {
    my $self = shift;
    my $tot = shift;
    $self->{'takeoffTime'} = $tot;
}

sub setLandingTime {
    my $self = shift;
    my $lt = shift;
    $self->{'landingTime'} = $lt;
}

sub setOnBlockTime {
    my $self = shift;
    my $lt = shift;
    $self->{'onBlock'} = $lt;
}

sub setId {
    my $self = shift;
    my $mid = shift;
    $self->{'id'} = "$mid";
}

sub hasValidId {
    my $self = shift;
    return $self->{'id'} < 0 ? 0 : 1;
}

sub TO_JSON { 
    return { %{ shift() } }; 
}

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
    $text .=
    $self->id .
    ";" . $self->pilot .
    ";" . $self->plane .  
    ";" . $self->departureAirport .
    ";" . $self->landingAirport .
    ";" . $self->offBlock_seconds() .
    ";" . $self->takeoffTime_seconds() .
    ";" . $self->landingTime_seconds() .
    ";" . $self->onBlock_seconds() .
    ";" . $self->rules .
    ";" . $self->function .
    ";" . $self->landingCount;

    say "$text" if $debug;
    return $text;
}

sub print {
    my $self = shift;
    my $text = shift;
    
    
    $text .= $self->pilot .
    ";" . $self->plane . 
    ";" . $self->departureAirport .
    ";" . $self->offBlock_seconds .
    ";" . $self->takeoffTime_seconds .
    ";" . $self->landingAirport .
    ";" . $self->landingTime_seconds .
    ";" . $self->onBlock_seconds .
    ";" . $self->rules .
    ";" . $self->function .
    ";" . $self->landingCount;
    
    say main::MYDEBUG "$text\n";
}


