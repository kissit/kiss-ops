#!/usr/bin/env perl
#
## check_redis_cluster.pl
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
## Just a simple Perl script that you can call to check the status of a redis cluster.
## Its meant to be called from NRPE but not required I guess.
##
## Requirements:
## - The redis-trib.rb script installed and functioning on the host where you are running the check from
##
## Installation:
## - Pull down the script into your nagios plugin directory.
## - Change the path below to redis-trib.rb to match your system.
## - Set it to be executable as desired, for instance:
##      chmod 755 /usr/lib64/nagios/plugins/check_redis_cluster.pl
## - Add an entry into NRPE config on the instances to monitor such as:
##      command[check_redis_cluster]=/usr/lib64/nagios/plugins/check_redis_cluster.pl
## - Configure a service check in nagios server to call the NRPE check.
##
use strict;
use Getopt::Long;

my $check_cmd = '/usr/local/bin/redis-trib.rb';
my $options = {'H' => 'localhost', 'p' => '6379'};

GetOptions($options, "H=s", "p=i", "help");

if (defined $options->{'help'}) {
        print <<INFO;
$0: Use the redis-trib.rb tool to check the health of a redis cluster

 check_redis_cluster.pl [ -H <Host/IP> -p <port>]

  -H <Host/IP>      - Hostname or IP of one of the cluster nodes (default: localhost)
  -p <port>         - Redis port to connect to (default: 6379)

INFO
exit;
}

# Make the call to the function to run the check
get_cluster_status($options->{'H'}, $options->{'p'});

sub get_cluster_status {
    my $hostname = shift;
    my $port = shift;
    my $status_msg = "Redis cluster is healthy";
    my $return_code = 0;

    # Run the check
    my $status = `$check_cmd check $hostname:$port`;

    # Process the output
    my @rows = split(/\n/, $status);
    foreach (@rows) {
        if(/\[ERR\]\s(.*)/) {
            $status_msg = $1;
            $return_code = 1;
            last;
        }
    }

    # output for Rackspace
    print "$status_msg\n";
    exit $return_code;
}