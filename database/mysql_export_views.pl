#!/usr/bin/env perl
#
## mysql_export_views.pl
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
## Perl script that will dump out all create view statements from a given database
##

use strict;
use Getopt::Long;
use DBI;

my $options = {'d' => '', 'h' => 'localhost', 'u' => 'root', 'p' => ''};
GetOptions($options, "h=s", "d=s", "u=s", "p=s", "help");

if (defined $options->{'help'}) {
        print <<INFO;
$0: Dump out all create view statements for a given database

 mysql_export_views.pl -d <database> [-h <host>] [ -u <user> ] [ -p <pass> ]
  -d <database>     - Database name (required)
  -h <host>         - Hostname (default: localhost)
  -u <user>         - Username (default: root)
  -p <pass>         - Password (default: empty)
  --help            - This help page

INFO
exit;
}

# We require a database name
if($options->{'d'} eq "") {
    print "You must pass a database name\n";
    exit 2;
}
my $db = $options->{'d'};

# Pull out our remaining opts
my $host = $options->{'h'};
my $user = $options->{'u'};
my $pass = $options->{'p'};

# Try to open our connection
my $dbh = DBI->connect("DBI:mysql:database=$db;host=$host;port=3306", $user, $pass);
if (not $dbh) {
    print "ERROR: cannot connect to database $db on host $host\n";
    exit 2;
}

# Get a list of our views for the database
my $viewlist = $dbh->prepare("SHOW FULL TABLES WHERE TABLE_TYPE LIKE 'VIEW'");
$viewlist->execute;
if ($viewlist->rows <= 0) {
    print "No views found in database $db, nothing to do\n";
    exit 2;
}

# Loop through our list of views and get our create statement for each
while (my @row = $viewlist->fetchrow_array) {
    my $view = $row[0];
    my $createview = $dbh->prepare("SHOW CREATE VIEW $view");
    $createview->execute;
    if ($viewlist->rows != 1) {
        print "Somethine went wrong retrieving the create view statement for view $view\n";
        exit 2;
    }

    my $view_row = $createview->fetchrow_hashref;
    $createview->finish;
    if($view_row->{'Create View'}) {
        print "\n";
        print "--\n";
        print "-- Create View statement for $view\n";
        print "--\n";
        print $view_row->{'Create View'} . ";\n";
    }
}
$viewlist->finish;

# Close our DB
$dbh->disconnect;
exit 0;
