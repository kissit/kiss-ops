#!/usr/bin/env perl
#
## mysql_purge_binlogs.pl
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
## Perl script that can be scheduled via Cron to be run to intelligently purge binary logs
## from a MySQL master based on what files are still needed by the slave(s)
##
## Installation:
## - Change the following variables at the top of the script
##      - $master_host - This is the hostname/IP of the MySQL master
##      - $slaves - This is a hash of one or more slave hostname/IP combinations.  NOTE: you must set the value of each to X as shown.
##      - $options - You can set the default username/password here if you don't want to pass it on the cmd line.
## - Set it to be executable as desired, for instance:
## - Schedule to be run as desired via cron
##

use strict;
use Getopt::Long;
use DBI;

## DB Settings - Configure these for your environment
my $master_host = 'localhost';
my $slaves = {'1.1.1.1' => 'X', '2.2.2.2' => 'X', '3.3.3.3' => 'X'};
my $options = {'u' => 'username', 'p' => 'password'};

GetOptions($options, "u=s", "p=s", "help");

if (defined $options->{'help'}) {
        print <<INFO;
$0: Intelligently purge bin logs in a MySQL replication environment

 mysql purge_binlogs.pl [ -u <user> ] [ -p <pass> ]
  -u <user>                     - Username
  -p <pass>                     - Password
  --help                        - This help page

INFO
exit;
}

# Process each slave
my $bin_log_name = '';
my $bin_log_number = '99999999999'; # This should hopefully be a safe high water mark :-)
foreach my $slave (keys %{$slaves}) {
    print "Checking slave: $slave\n";
    my $position = get_slave_position($slave);
    print "Slave $slave currently on binlog: $position\n";

    my @parts = split(/\./, $position);
    if($bin_log_name eq '') {
        $bin_log_name = $parts[0];
    }

    my $check1 = $bin_log_number + 0;
    my $check2 = $parts[1] + 0;
    if($check2 <= $check1) {
        $bin_log_number = $parts[1];
    }
    print "Binlog name: $bin_log_name, minimum binlog number: $bin_log_number\n";
}

if($bin_log_name ne '' && $bin_log_number ne '99999999999') {
    # Lets do the purge
    my $purge_file = "$bin_log_name.$bin_log_number";
    print "Purging binlogs to: $purge_file\n";
    purge_binlogs($purge_file);
}

# Function to get the slave position
sub get_slave_position {
    my $return = 0;

    # Connect to the slave server
    my $host = shift;
    my $dbh = DBI->connect("DBI:mysql:host=$host;port=3306", $options->{'u'}, $options->{'p'});
    if (not $dbh) {
        print "ERROR: cannot connect to $host\n";
        return 3;
    }

    # Query the heartbeat table
    my $sql = "SHOW SLAVE STATUS";
    my $sth = $dbh->prepare($sql);
    my $res = $sth->execute;
    if (not $res) {
        print "ERROR: No results from database\n";
        return 3;
    }
    my $row = $sth->fetchrow_hashref;

    $sth->finish;
    $dbh->disconnect;

    if($row->{'Master_Log_File'}) {
        $return = $row->{'Master_Log_File'};
    }
    return $return;
}

# Function to purge the binlogs
sub purge_binlogs {
    my $binlog = shift;
    if(length($binlog) > 0) {
        my $dbh = DBI->connect("DBI:mysql:host=$master_host;port=3306", $options->{'u'}, $options->{'p'});
        if (not $dbh) {
            print "ERROR: cannot connect to $master_host\n";
            return 3;
        }
        my $sql = "PURGE BINARY LOGS TO '$binlog'";
        my $sth = $dbh->prepare($sql);
        my $res = $sth->execute;
        if (not $res) {
            print "ERROR: No results from database\n";
            return 3;
        }
    }
    return 0;
}