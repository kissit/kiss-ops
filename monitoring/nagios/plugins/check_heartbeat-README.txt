Just a simple Perl script that you can call to check the status of a heartbeat from the Percona Toolkit.

Its meant to be called from NRPE but not required I guess.

Installation:

1. Pull down the script into your nagios plugin directory.

2. Set it to be executable as desired.

Example: chmod 755 /usr/lib64/nagios/plugins/check_heartbeat.pl

3. Add an entry into NRPE config on the MySQL slave(s) such as:

command[check_mysql_replication]=/opt/nagios/libexec/check_mkheartbeat.pl -H localhost -u username -p password -w 300 -c 400

4. Configure a service check in nagios server to call the NRPE check.
