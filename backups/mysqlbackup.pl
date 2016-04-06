#!/usr/bin/env perl
#
## mysqlbackup.pl
##
## This is a script used to backup a MySQL database using mysqldump in various ways.
##
## Copyright (C) 2016 KISS IT Consulting <http://www.kissitconsulting.com/>
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
## Instructions
## 1. Install required CPAN modules, on CentOS 6.x:
##     yum install perl-MIME-Lite perl-Config-Simple perl-DateTime perl-DBI perl-DBD-MySQL
## 2. Configure your backups to run as needed in the ini file.  Documentation and examples are provided in the example file.
## 3. Run the script as a user that has permissions to read/write as needed, passing your desired options
##
use strict;
use DateTime;
use Getopt::Long;
use DBI;
use MIME::Lite;
use Config::Simple;
use File::Basename;

## Get our command line options
my $dirname = dirname(__FILE__);
my @status_msg;
my $status = 0;
my $help = 0;
my $config = "$dirname/mysqlbackup.ini";
my $backups = '';
GetOptions("help" => \$help, "backups=s" => \$backups, "config=s" => \$config);

if ($help) {
        print <<INFO;
$0: Backup MySQL databases as configured in the config file
 Usage: luks_mounter.pl [--backups=localhost,ex2] [ --config ]
    --backups       - Comma separated list of backup configurations from the config file to process. (Default: all configured backups)
    --config        - Alternate config file (Default: $config)
    --help          - This help page
INFO
exit;
}

## Load our config file and base vars
my $cfg = new Config::Simple($config) or die Config::Simple->error(); 
my $gzip = $cfg->param("base.gzip");
my $mysqldump = $cfg->param("base.mysqldump");
my $main_backup_dir = $cfg->param("base.backup_dir");
my $mysqldump_error_log = $cfg->param("base.mysqldump_error_log");

## Check that our backup directory is valid
if (! -d $main_backup_dir) {
    die "Invalid backup_dir configured."
}

## Before going any further, validate that we have dirs configured
my @config_backups = $cfg->param("base.backups");
if(!@config_backups) {
    die "No backups configured, nothing to do."
}

## And then if we have some passed in, we need to validate them, if not, we simply take all that are configured
my @final_backups;
my @backups = split /,/, $backups;
my %valid_config_backups = map { $_ => 1 } @config_backups;
if(@backups) {
    foreach(@backups) {
        if(exists($valid_config_backups{$_})) {
            push @final_backups, $_;
        }
    }
} else {
    @final_backups = @config_backups;
}

## Clear a previous error log if one exists
my $error_log = $cfg->param("base.error_log");
if(-e $error_log) {
	run_system_cmd("rm $error_log");
}

## Alright, lets start processing our directories to sync
for my $backup (@final_backups) {
    my $check = 0;
    my $status = 0;
    my $mysqldump_cmd = "";
    my $server_dbs = undef;
    my $dbs_tables = undef;
    my $qry = undef;
    my @do_dbs = undef;
    my $db = undef;
    my $login_path = $cfg->param("$backup.login_path");
    my $username = $cfg->param("$backup.username");
    my $password = $cfg->param("$backup.password");
    my @databases = $cfg->param("$backup.databases");
    my $hostname = $cfg->param("$backup.hostname");
    my $retention_days = $cfg->param("$backup.retention_days");
    my $retention_months = $cfg->param("$backup.retention_months");
    my $start = DateTime->now;

    push(@status_msg, "\nProcessing backup configuration: $backup");
    push(@status_msg, "---------------------------------------------------------------------------------------");

    ## Determine our base mysqldump command to use for the config
    if (length($login_path) > 0) {
        $mysqldump_cmd = "$mysqldump --login-path=$login_path -h $hostname";
    } else {
        $mysqldump_cmd = "$mysqldump -h $hostname -u $username";
        if($password) {
            $mysqldump_cmd = $mysqldump_cmd . " -p$password";
        }
    }

    ## Clear out an existing mysqldump error log if needed
    if(-e $mysqldump_error_log) {
        run_system_cmd("rm $mysqldump_error_log");
    }

    ## Connect to mysql server to lookup information to use for the backup
    my $dsn = "DBI:mysql:database=information_schema;host=$hostname;port=3306";
    if($password) {
        $db = DBI->connect($dsn, $username, $password);
    } else {
        $db = DBI->connect($dsn, $username);
    }

    if(!$db) {
        $status = 1;
        push (@status_msg, "Could not connect to database: $DBI::errstr");
    } else {
        ## Figure out our list of databases to backup
        if(@databases) {
            ## We were provided a list of databases
            foreach my $do_db (@databases) {
                $server_dbs->{$do_db}->{'Database'} = $do_db;
            }
        } else {
            ## We need to lookup all databases
            $qry = $db->prepare("SHOW DATABASES");
            $qry->execute();
            if($qry->rows > 0) {
                $server_dbs = $qry->fetchall_hashref('Database');
            }
            $qry->finish;
        }

        ## Get a list of tables for each db excluding views
        if($server_dbs) {
            foreach my $key (keys %$server_dbs) {
                my $db_name = $server_dbs->{$key}->{'Database'};
                if($db_name !~ /information_schema|lost\+found|performance_schema/i) {
                    $qry = $db->prepare("SELECT TABLE_NAME, TABLE_TYPE, ENGINE FROM information_schema.TABLES WHERE TABLE_SCHEMA LIKE '$db_name';" );
                    $qry->execute();
                    if($qry->rows > 0) {		
                        $dbs_tables->{$db_name} = $qry->fetchall_hashref ('TABLE_NAME');
                    }
                    $qry->finish;
                }
            }	
        } else {
            $status = 1;
            push (@status_msg, "No databases found to backup");	
        }

        # We are done with the database connection
        $db->disconnect();
    }

    # Now process each database & table that was selected
    if($status == 0 && $dbs_tables) {
        my $dt = DateTime->now->set_time_zone("US/Eastern");
        my $ymd = $dt->ymd;
        my $hms = $dt->hms('');
        my $day = $dt->day;
        my $ym = $dt->strftime('%Y%m');

        ## This is our main, daily, backup directory for the current backup (excluding the DB name)
        my $day_backup_dir = "$main_backup_dir/$backup/daily";
        my $todays_backup_dir = "$day_backup_dir/${ymd}_${hms}";
        foreach my $db_name (keys %$dbs_tables) {
            my $db_dir = "$todays_backup_dir/$db_name";
            push(@status_msg, "STARTING BACKUP OF DATABASE $db_name to directory $db_dir");
            $check = run_system_cmd("mkdir -p $db_dir");
            if($check == 0) {
                foreach my $table (sort(keys(%{$dbs_tables->{$db_name}}))) {
                    if(lc($dbs_tables->{$db_name}->{$table}->{'TABLE_TYPE'}) eq 'view') {
                        push(@status_msg, "SKIPPING VIEW: $table");
                    } elsif(lc($dbs_tables->{$db_name}->{$table}->{'ENGINE'}) eq 'federated') {
                        push(@status_msg, "SKIPPING FEDERATED TABLE: $table");
                    } else {
                        my $dumpfile = "$db_dir/$table.sql";
                        $check = run_system_cmd("$mysqldump_cmd --single-transaction --log-error=$mysqldump_error_log $db_name $table | $gzip > $dumpfile.gz");
                        if($check == 0) {
                            push (@status_msg, "Successfully backed up $db_name.$table");
                        } else {
                            $status = 1;
                            push (@status_msg, "An error occurred while backing up $db_name.$table");
                        }
                    }
                }
            } else {
                $status = 1;
                push (@status_msg, "Failed to create backup directory: $db_dir");
            }
        }
        
        push (@status_msg, "\nSTARTING RETENTION CLEANUP PROCESSING" );

        ## If we have a day retention set, lets handle the cleanup
        if($status == 0 && $retention_days > 0) {
            push (@status_msg, "Doing cleanup of $day_backup_dir older than $retention_days days" );
            $check = run_system_cmd("find $day_backup_dir -maxdepth 1 -type d -mtime +$retention_days -exec rm -rf {} \\;");
            if($check == 0) {
                push (@status_msg, "Successfully cleaned up directory $day_backup_dir");
            } else {
                $status = 1;
                push (@status_msg, "An error occurred while cleaning up directory $day_backup_dir");
            }
        } else {
            push (@status_msg, "Daily retention not configured, will not purge old backups");
        }

        ## Now, if today is the first of the month and we're keeping monthly snaps process those retentions
        if($status == 0 && $retention_months > 0 && $day == 1) {
            ## Here is where our montly backups are
            my $month_backup_dir = "$main_backup_dir/$backup/monthly";

            ## First cleanup anything that exceeds our retention
            $check = run_system_cmd("find $month_backup_dir -maxdepth 1 -type d -mtime +$retention_months -exec rm -rf {} \\;");
            if($check == 0) {
                push (@status_msg, "Successfully cleaned up directory $month_backup_dir");
            } else {
                $status = 1;
                push (@status_msg, "An error occurred while cleaning up directory $month_backup_dir");
            }

            ## Next, copy over today's backup to keep for the monthly
            $check = run_system_cmd("cp -a $todays_backup_dir $month_backup_dir/");
            if($check == 0) {
                push (@status_msg, "Successfully copied today's backup to $month_backup_dir");
            } else {
                $status = 1;
                push (@status_msg, "An error occurred while copying today's backup to $month_backup_dir");
            }

        } else {
            push (@status_msg, "Monthly retention not applicable, will not process monthly retentions");
        }

        my $end = DateTime->now;
        my $diff = $end->subtract_datetime($start);
        my $timestr = $diff->in_units('hours') . ":" . $diff->in_units('minutes') . ":" . $diff->in_units('seconds');
        push(@status_msg, "\nFINISHED BACKUP CONFIGURATION: $backup in $timestr");
        push(@status_msg, "---------------------------------------------------------------------------------------");
    } else {
        $status = 1;
        push (@status_msg, "No tables found to backup");
    }
}

## Send a status email and an error email if warranted (and configured)
my $email_to = $cfg->param("mail.status_email");
my $email_from = $cfg->param("mail.from_address");
my $error_email = $cfg->param("mail.error_email");
my $email_subject = $cfg->param("mail.email_subject");
my $email_data = join("\n", @status_msg);
if(-e $error_log) {
	my $log_data = `cat $error_log`;
	if(length($log_data) > 0) {
		$email_data = $email_data . "\n\nThe following is the contents of the log file:\n" . $log_data;
	}
}

if($status != 0) {
    if(length($error_email) > 0) {
	    $email_to = "$email_to, $error_email";
    }
	$email_subject = "$email_subject (ERROR)"; 
} else {
	$email_subject = "$email_subject (OK)"; 
}

if(length($email_to) > 0 && length($email_from) > 0) {
    my $msg = MIME::Lite->new(	From => $email_from,
								To => $email_to,
								Subject => $email_subject,
								Data => $email_data);
    $msg->send;
}

exit 0;

## Function to run a system command and return the status (return code)
sub run_system_cmd {
	my $cmd = $_[0];
	my $return = 0;
	system($cmd);
	if ($? == -1) {
	    $return = -1
	} elsif ($? & 127) {
	    $return = -1
	} else {
	    $return = $? >> 8;
	}
	return $return;
}
