#!/usr/bin/env perl
#
## check_gearmand.pl
##
## Copyright (C) 2015 KISS IT Consulting <http://www.kissitconsulting.com/>
## Redistribution and use in source and binary forms, with or without
## modification, are permitted provided that the following conditions
## are met:
## 
## 1. Redistributions of source code must retain the above copyright
##    notice, this list of conditions and the following disclaimer.
## 2. Redistributions in binary form must reproduce the above
##    copyright notice, this list of conditions and the following
##    disclaimer in the documentation and/or other materials
##    provided with the distribution.
## 
## THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
## "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
## LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
## A PARTICULAR PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL ANY
## CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
## EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
## PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
## PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY
## OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
## NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
## SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
##
## Just a simple Perl script that you can call to check the status of a gearman worker for Nagios
##
## Installation:
## - Pull down the script into your nagios plugin directory.
## - Install the Net::Telnet CPAN module if not already installed
## - Set it to be executable as desired, for instance:
##      chmod 755 /usr/lib64/nagios/plugins/check_gearmand.pl
## - Add an check command such as
##      define command {
##          command_name    check_gearmand
##          command_line    $USER1$/check_gearmand.pl -H $HOSTADDRESS$ -k $ARG1$ -w $ARG2$ -c $ARG3$
##      }
## - Configure a matching service check in nagios server.
##
use strict;
use Getopt::Long;
use Net::Telnet;

my $options = {'k' => '', 'H' => 'localhost', 'r' => 4730, 'w' => 25, 'c' => 50};

GetOptions($options, "k=s", "H=s", "r=i", "w=i", "c=i", "help");

if (defined $options->{'help'}) {
        print <<INFO;
$0: Check the status of gearmand job queues.

 check_gearmand.pl -k workername [ -H <hostname> ] [ -r <port> ] [ -w <warning> ] [ -c <critical> ]

    -k <workername>     - Name of the worker to check
    -H <hostname>       - Host where gearmand is running (default: localhost)
    -r <port>           - Port number gearmand is listening on (default: 4730)
    -w <position>	    - Number of jobs in queue for warning state (default: 25)
    -c <position>       - Number of jobs in queue for critical state (default: 50)
    --help              - This help page

INFO
exit;
}

if ( !defined $options->{'k'} || !defined $options->{'H'} || !defined $options->{'r'} || !defined $options->{'w'} || !defined $options->{'c'} ) {
	print "ERROR: invalid input";
	exit 3;
}

my $worker = $options->{'k'};
my $host = $options->{'H'};
my $port = $options->{'r'};
my $warn_threshold = $options->{'w'};
my $critical_threshold = $options->{'c'};
my $return_status = 2;
my $return_string = "GEARMAND CRITICAL: Worker not registered with server\n";

# Connect to the gearmand server
my $telnet = new Net::Telnet(Host => $host, Port => $port , Timeout => 10, Errmode => sub{&telnet_error});
$telnet->print("status");
my ($status) = $telnet->waitfor('/\./');
$telnet->close;

# Process the output from telnet
my @rows = split(/\n/, $status);
foreach (@rows) {
    my @line = split(/\t/);
    my $line_worker = $line[0];

    if ($line_worker eq $worker) {
        my $queued = $line[1];
        my $running = $line[2];
        my $available = $line[3];

        if ($queued < $warn_threshold) {
            # set OK
            $return_status = 0;
            $return_string = "GEARMAND OK: $line_worker -> avail: $available, run: $running, queue: $queued\n";
        } elsif ($queued < $critical_threshold) {
            # set warning
            $return_status = 1;
            $return_string = "GEARMAND WARN: $line_worker -> avail: $available, run: $running, queue: $queued\n";
        } else {
            # set critical
            $return_status = 2;
            $return_string = "GEARMAND CRITICAL: $line_worker -> avail: $available, run: $running, queue: $queued\n";
        }
        last;
    }
}

# Return our findings to nagios
print $return_string;
exit $return_status;

sub telnet_error
{
    print "ERROR: Telnet Connection Failed!\n";
    exit 2;
}
