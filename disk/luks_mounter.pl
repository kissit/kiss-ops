#!/usr/bin/env perl
#
## luks_mounter.pl
##
## This is a script used to dynamically mount external USB HDD's, some of which
## are encrypted using LUKS.  This makes the devices less than easy to determine
## what they are and where they should be mounted.  An example use case for this
## script (my current use case) is an offsite backup rotation where you have 
## one or more drives rotating.  This script was developed to ensure the drives
## could be plugged in, in any order and be uniquely identified based on a 
## specific formatting detailed here: 
## kissitconsulting.com/blog/post/a-slick-option-for-dynamically-mounting-luks-encrypted-external-hard-drives
##
## However, a quick example here also.  Lets say you have a HDD that you want
## to encrypt.  Create two partitions, the first being a standard unencrypted
## partition that you create a filesystem label for when you create the filesystem.
## This device will then show up as /dev/disk/by-label/label.  Create a 2nd partition
## and configure it as a LUKS device accessible by a key file.  Create your filesystem
## of choice on this device.  Then configure this script to mount it based on the 
## label of the first partition.

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
##     yum install perl-MIME-Lite perl-Config-Simple
## 2. Configure your mounts/devices as needed in the ini file.  Documentation and examples are provided in the example file.
## 3. Run the script as root passing your desired options
##
use strict;
use MIME::Lite;
use Config::Simple;
use File::Basename;
use Getopt::Long;

## Get our command line options
my $dirname = dirname(__FILE__);
my @status_msg;
my $status = 0;
my $help = 0;
my $clean = 0;
my $do_mount = 0;
my $do_unmount = 0;
my $state = '';
my $config = "$dirname/luks_mounter.ini";
GetOptions("help" => \$help, "clean" => \$clean, "mount" => \$do_mount, "unmount" => \$do_unmount, "config=s" => \$config);

if ($help) {
        print <<INFO;
$0: Mount or unmount the devices as configured in the config file
 Usage: luks_mounter.pl --mount | --unmount [ --clean ] [ --config ]
    --mount         - Mount the devices in the config file
    --unmount       - Unmount the devices in the config file
    --clean         - Run the cleanups as configured (Default: no cleanups)
    --config        - Alternate config file (Default: $config)
    --help          - This help page
INFO
exit;
}

## Check that we have our required options and setup for what we're doing
if ($do_mount == 1) {
    $do_unmount = 0;
    $state = 'Mount';
} elsif($do_unmount == 1) {
    $do_mount = 0;
    $state = 'Unmount';
} else {
	print "Invalid input.  You must specify one of --mount or --unmount\n";
	exit 3;
}

## Load our config file and base vars
my $cfg = new Config::Simple($config) or die Config::Simple->error(); 
my $key_file = $cfg->param("base.key_file");
my $set_user = $cfg->param("base.set_user");
my $set_group = $cfg->param("base.set_group");
my @mount_tasks = $cfg->param("base.mount_tasks");
my @unmount_tasks = $cfg->param("base.unmount_tasks");

## Before going any further, validate that we have mounts configured
my @mounts = $cfg->param("base.mounts");
if(!@mounts) {
    die "No mounts configured, nothing to do."
}

## Clear a previous error log if one exists
my $error_log = $cfg->param("base.error_log");
if(-e $error_log) {
	run_system_cmd("rm $error_log");
}

## Run any pre tasks we may have

## Force a refresh of the disk devices (only if we are mounting)
if ($do_mount == 1) {

    my $device_refresh_wait = $cfg->param("base.device_refresh_wait");
    run_system_cmd("partprobe > /dev/null 2>&1");
    push(@status_msg, "Refreshed disk devices using partprobe");
    if (length($device_refresh_wait) > 0 && $device_refresh_wait > 0) {
        push(@status_msg, "Sleeping $device_refresh_wait seconds to allow the devices to stabilize");
        sleep($device_refresh_wait);
    }
}

## If we're unmounting, run any unmount tasks before we do
if ($do_unmount == 1) {
    for my $task (@unmount_tasks) {
        run_system_cmd("$task > /dev/null 2>&1");
        push(@status_msg, "Ran unmount task $task before processing the unmounts");
    }
}

## Alright, lets start processing our mounts
for my $mount (@mounts) {
    my $check = 0;
    my $luks = $cfg->param("$mount.luks");
    my $fs_type = $cfg->param("$mount.type");
    my $mount_point = $cfg->param("$mount.mount");
    my $mount_options = $cfg->param("$mount.mount_options");
    my $mount_check = $cfg->param("$mount.check");
    my $config_device = $cfg->param("$mount.device");
    my $mount_map = $cfg->param("$mount.map");
    my $nagios_check = $cfg->param("$mount.nagios_check");
    my $mount_device = 'x';
    my $physical_dev = 'x';
    my @clean = $cfg->param("$mount.clean");
    push(@status_msg, "\nProcessing mount $mount (state: $state, type: $fs_type, mount_point: $mount_point)");

    if ($do_mount == 1) {
        ### Mount the devices
        ## First a check to make sure its not already mounted
        if(-d $mount_check) {
            push(@status_msg, "$mount_point is already mounted, nothing to do");
        } else {
            push(@status_msg, "$mount_point is not mounted, attempting to mount it as a $fs_type filesystem");
            
            if($luks eq 'yes') {
                push(@status_msg, "$mount_point is a LUKS device, attempting to determine its device name and open it");
                
                ## Here we determine our device ID based on the first, unencrypted partition with our configured label
                my $devcheck = `ls -l $config_device`;
                if(length($devcheck)) {
                    ($devcheck) = $devcheck =~ /\/([a-z]*)[0-9]$/;
                    if(-b "/dev/$devcheck") {
                        $physical_dev = "/dev/$devcheck"."2";
                    }
                }

                ## Check if our physical device is valid, and open it if so
                if(-b $physical_dev) {
                    push(@status_msg, "Determined $mount_point to be physical device $physical_dev");
                    run_system_cmd("/sbin/cryptsetup luksOpen --key-file $key_file $physical_dev $mount_map > /dev/null 2>&1");
                    $mount_device = "/dev/mapper/$mount_map";
                }
                
            } else {
                ## Since this is not a luks device, we just take the configured device as is
                $mount_device = $config_device
            }

            ## $mount_device is now either a standard device or an open LUKS device, vadlidate it before mounting
            if(-b $mount_device) {
                ## Device is valid, now mount it based on the fs_type
                if($fs_type eq 'ext4') {
                    $check = run_system_cmd("mount $mount_options $mount_device $mount_point >> $error_log 2>&1");
                } elsif ($fs_type eq 'zfs') {
                    $check = run_system_cmd("zpool import $mount_map >> $error_log 2>&1");
                }

                ## If our mount returned good continue with setup/cleanup
                if($check == 0) {
                    push (@status_msg, "$mount_point is successfully mounted as a $fs_type filesystem");
                    if($clean == 1 && @clean) {
                        foreach my $cleandir (@clean) {
                            push(@status_msg, "Deleting contents of directory: $cleandir");
                            run_system_cmd("mkdir -p $cleandir >> $error_log 2>&1");
                            run_system_cmd("chown $set_user:$set_group $cleandir >> $error_log 2>&1");
                            run_system_cmd("rm -rf $cleandir/* >> $error_log 2>&1");
                        }
                    }

                    if(length($nagios_check)) {
                        push(@status_msg, "Creating nagios check file: $nagios_check");
                        run_system_cmd("touch $nagios_check >> $error_log 2>&1");
                        run_system_cmd("chown $set_user:$set_group $nagios_check >> $error_log 2>&1");
                    }
                } else {
                    $status = 1;
                    push (@status_msg, "Failed mounting $mount_point");
                }
            } else {
                $status = 1;
                push (@status_msg, "Invalid block device $mount_device, will not attempt to mount it");
            }
        }
    } elsif($do_unmount == 1) {
        ### Unmount the devices
        ## First a check to make sure its already mounted before trying to unmount
        if(-d $mount_check) {
            push(@status_msg, "$mount_point is currently mounted, attempting to unmount it");
            if($fs_type eq 'ext4') {
                $check = run_system_cmd("umount $mount_point >> $error_log 2>&1");
            } elsif ($fs_type eq 'zfs') {
                $check = run_system_cmd("zpool export $mount_map >> $error_log 2>&1");
            }

            ## If our unmount returned good continue with rest of cleanup as needed
            if($check == 0) {
                push (@status_msg, "$mount_point successfully unmounted");
                if($luks eq 'yes') {
                    push (@status_msg, "Mount $mount is a LUKS device, close the mapping");
                    $mount_device = "/dev/mapper/$mount_map";
                    run_system_cmd("/sbin/cryptsetup luksClose $mount_device >> $error_log 2>&1");
                    if(-b $mount_device) {
                        push (@status_msg, "Failed closing LUKS device $mount_device");
                        $status = 1;
                    } else {
                        push (@status_msg, "LUKS device $mount_device successfully closed");
                    }
                }
            } else {
                push (@status_msg, "Failed unmounting $mount_point");
                $status = 1;
            }
        } else {
            push(@status_msg, "$mount_point is not mounted, nothing to do");
        }
    }
}

## If we're mounting, run any mount tasks after we do
if ($do_mount == 1) {
    for my $task (@mount_tasks) {
        run_system_cmd("$task > /dev/null 2>&1");
        push(@status_msg, "Ran mount task $task after processing the unmounts");
    }
}

## When unmounting, based on status make a final note about drive removal
if($do_unmount == 1) {
    if($status == 0) {
        push (@status_msg, "\nIt is safe to remove the drives");
    } else {
        push (@status_msg, "\nERROR: A problem was encountered. The drives can still be removed but should be investigated.");
    }
}

## Send a status email and an error email if warranted (and configured)
my $email_to = $cfg->param("mail.status_email");
my $error_email = $cfg->param("mail.error_email");
my $email_subject = $cfg->param("mail.email_subject");
my $email_data = '';
if(-e $error_log) {
	my $log_data = `cat $error_log`;
	if(length($log_data) > 0) {
		$email_data = "The following is the contents of the error log:\n\n" . $log_data;
		$status = 1;
	}
}
$email_data = $email_data . join("\n", @status_msg);

if($status != 0) {
    if(length($error_email) > 0) {
	    $email_to = "$email_to, $error_email";
    }
	$email_subject = "$email_subject - $state (ERROR)"; 
} else {
	$email_subject = "$email_subject - $state (OK)"; 
}

if(length($email_to) > 0) {
    my $msg = MIME::Lite->new(	From => $cfg->param("mail.from_address"),
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
