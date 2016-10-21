#!/usr/bin/env perl
#
## backup_sync.pl
##
## This is a script used to sync two directories using rsync or plain cp.  The
## intention of it is to have a single script with the directories configured
## in a separate configuration file.  Also another requirement for this process
## is to send email notifications on completion, as well as error notifications
## to a separate email for ticketing purposes.
##
## Our specific use case is to sync backups sitting on local disk on the server
## to a set of encrypted USB disks mounted using our luks_mounter tool
## outlined here: http://kissitconsulting.com/blog/post/a-slick-option-for-dynamically-mounting-luks-encrypted-external-hard-drives

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
##     yum install perl-MIME-Lite perl-Config-Simple perl-DateTime perl-LockFile-Simple
## 2. Configure your directories to sync as needed in the ini file.  Documentation and examples are provided in the example file.
## 3. Run the script as a user that has permissions to read/write as needed, passing your desired options
##
use strict;
use MIME::Lite;
use Config::Simple;
use File::Basename;
use Getopt::Long;
use DateTime;
use Data::Dumper;
use LockFile::Simple qw(lock trylock unlock);

## Get our command line options
my $dirname = dirname(__FILE__);
my @status_msg;
my $status = 0;
my $help = 0;
my $config = "$dirname/backup_sync.ini";
my $dirs = '';
GetOptions("help" => \$help, "dirs=s" => \$dirs, "config=s" => \$config);

if ($help) {
        print <<INFO;
$0: sync two directories using rsync or plain cp based on the provided configuration file
 Usage: backup_sync.pl [--dirs=test1,test2] [ --config ]
    --dirs          - Comma separated list of directory configurations from the config file to process. (Default: all configured directories)
    --config        - Alternate config file (Default: $config)
    --help          - This help page
INFO
exit;
}

## Load our config file and base vars
my $cfg = new Config::Simple($config) or die Config::Simple->error(); 
my $cp_path = $cfg->param("base.cp_path");
my $rsync_path = $cfg->param("base.rsync_path");
my $rsync_options = $cfg->param("base.rsync_options");

## Before going any further, validate that we have dirs configured
my @config_dirs = $cfg->param("base.dirs");
if(!@config_dirs) {
    die "No directories configured, nothing to do."
}

## Next try to get a lock for our state, if we don't that means another process is already running (or something is wrong)
my $lockfile = $cfg->param("base.lock_file");
my $lockmgr = LockFile::Simple->make(-hold => 0, -max => 1, -delay => 1, -stale => 0);
if(!$lockmgr->lock($lockfile)) {
    die "Could not lock process, another is either running or failed.  Lock file: $lockfile";
    exit 3;
}

## And then if we have some passed in, we need to validate them, if not, we simply take all that are configured
my @final_dirs;
my @dirs = split /,/, $dirs;
my %valid_config_dirs = map { $_ => 1 } @config_dirs;
if(@dirs) {
    foreach(@dirs) {
        if(exists($valid_config_dirs{$_})) {
            push @final_dirs, $_;
        }
    }
} else {
    @final_dirs = @config_dirs;
}


## Clear a previous error log if one exists
my $error_log = $cfg->param("base.error_log");
if(-e $error_log) {
	run_system_cmd("rm $error_log");
}

## Alright, lets start processing our directories to sync
for my $dir (@final_dirs) {
    my $check = 0;
    my $rsync = $cfg->param("$dir.rsync");
    my $sudo = $cfg->param("$dir.sudo");
    my $source = $cfg->param("$dir.source");
    my $validate_source = $cfg->param("$dir.validate_source");
    my $dest = $cfg->param("$dir.dest");
    my $validate_dest = $cfg->param("$dir.validate_dest");
    my $rsync_exclude = $cfg->param("$dir.rsync_exclude");
    push(@status_msg, "\nProcessing directory $dir (source: $source, dest: $dest, rsync: $rsync)");

    ## Check that our source directory is valid
    if (!$validate_source || -d $validate_source) {
        ## Check that our dest directory is valid
        if(!$validate_dest || -d $validate_dest) {
            push(@status_msg, "Directories are valid, starting to sync");

            ## Run our sync based on our type.  Keep track of our timings for log/output.
            if($sudo eq 'yes') {
                $sudo = 'sudo';
            } else  {
                $sudo = '';
            }

            my $start = DateTime->now;
            if($rsync eq 'yes') {
                if(length($rsync_exclude) > 0) {
                    $rsync_exclude = "--exclude '$rsync_exclude'";
                } else {
                    $rsync_exclude = "";
                }
                $check = run_system_cmd( "$sudo $rsync_path $rsync_options $rsync_exclude $source $dest >> $error_log 2>&1" );
            } else {
                $source =~ s/(.*\/)$/$source\*/;
                $check = run_system_cmd( "$sudo $cp_path -a $source $dest >> $error_log 2>&1" );
            }
            my $end = DateTime->now;
            my $diff = $end->subtract_datetime($start);
            my $timestr = $diff->in_units('hours') . ":" . $diff->in_units('minutes') . ":" . $diff->in_units('seconds');
            if($check == 0) {
                push (@status_msg, "Successfully synced $source to $dest.  Time: $timestr");
            } else {
                $status = 1;
                push (@status_msg, "Failed syncing $source to $dest.  Time: $timestr");
            }
        } else {
            $status = 1;
            push(@status_msg, "Destination directory $validate_dest not found, skipping this sync.");
        }
    } else {
        $status = 1;
        push(@status_msg, "Source directory $validate_source not found, skipping this sync.");
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

## Unlock our process
$lockmgr->unlock($lockfile);

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
