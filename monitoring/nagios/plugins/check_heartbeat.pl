#!/usr/bin/env perl
use strict;
use Getopt::Long;
use DBI;
require Carp;

my $options = { 'H' => 'localhost', 'r' => 3306, 'w' => 180, 'c' => 300 , 'u' => 'monitor', 'p' => 'password', 'd' => 'percona' };

GetOptions($options, "H=s", "r=i", "w=i", "c=i", "u=s", "p=s", "d=s", "help");

if (defined $options->{'help'}) {
        print <<INFO;
$0: Use the Percona heartbeat utility (pt-heartbeat) to check replication heartbeat.

 check_heartbeat.pl [ -H <hostname> ] [ -r <port> ] [ -w <position> ] [ -c <position> ]
 [ -u <user> ] [ -p <pass> ] [ -d <percona_database> ]

  -H <hostname>                 - MySQL instance running as a slave server (default: localhost)
  -r <port>                     - Port number MySQL is listening on (default: 3306)
  -w <position>                 - Time lag for warning state in seconds (default: 180)
  -c <position>                 - Time lag for critical state in seconds (default: 300)
  -u <user>                     - Username (default: root)
  -p <pass>                     - Password (default: password)
  -d <percona_database>         - Database containing the percona heartbeat table (default: percona)
  --help                        - This help page

INFO
exit;
}

# Make the call to get the replication lag time
get_replication_lag( $options->{'H'} );

sub get_replication_lag
{
        # Connect to the slave server
        my $host = shift;
        Carp::cluck "host" if !defined $host;
        Carp::cluck "port" if !defined $options->{'r'};
        Carp::cluck "dbuser" if !defined $options->{'u'};
        Carp::cluck "dbpass" if !defined $options->{'p'};
        my $dbh = DBI->connect("DBI:mysql:host=$host;port=$options->{'r'}", $options->{'u'}, $options->{'p'});
        if (not $dbh) {
                print "UNKNOWN: cannot connect to $host\n";
                exit 3;
        }

        # Query the heartbeat table
        my $sql = "SELECT UNIX_TIMESTAMP(ts) AS slave_timestamp FROM ".$options->{'d'}.".heartbeat";
        my $sth = $dbh->prepare($sql);
        my $res = $sth->execute;
        if (not $res) {
                print "UNKNOWN: No results from database\n";
                exit 3;
        }
        my $row = $sth->fetchrow_hashref;
        $sth->finish;
        $dbh->disconnect;

        # Check for the lag from the current time & return our status accordingly
        my $current_timestamp = time;
        my $slave_timestamp = $row->{'slave_timestamp'};
        my $lag = $current_timestamp - $slave_timestamp;
        if ($lag < $options->{'w'}) {
                # Retun OK
                print "REPLICATION OK: Slave $lag seconds behind master\n";
                exit 0;
        } elsif ($lag < $options->{'c'}) {
                #return WARNING
                print "REPLICATION WARN: Slave $lag seconds behind master\n";
                exit 1;
        } else {
                #return CRITICAL
                print "REPLICATION CRITICAL: Slave $lag seconds behind master\n";
                exit 2;
        }
}