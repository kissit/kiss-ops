#!/bin/bash
############################################################################################################
#### Give credit where credit is due...the source of this plugin is:
#### http://www.linuxquestions.org/questions/linux-software-2/nagios-check-ram-usage-on-remote-server-747531/
############################################################################################################
#
# Determine memory usage percentage on Linux servers.
# Original write for RHEL3 for PC1 Project - jlightner 05-Jul-2005
#
# Modified for RHEL5 on mailservers.
# -Some of the escapes previously required for RHEL3's ksh not needed on RHEL5.
# -Changed comparisons to allow for decimal rather than integer values.
# jlightner 23-Jan-2009
#

# Usage:  check_mem.sh WARNING CRITICAL
#         Where WARNING and CRITICAL are the integer only portions of the
#         percentage for the level desired.
#         (i.e. 85% Warning & 95% Critical should be input only as "85 95".)

# Define Levels based on input
#
WARNLEVEL=$1
CRITLEVEL=$2

# Setup standard Nagios/NRPE return codes
#
UNKNOWN_STATE=3
CRITICAL_STATE=2
WARNING_STATE=1
OK_STATE=0

# Give full paths to commands - Nagios can't determine location otherwise
#
BC=/usr/bin/bc
GREP=/bin/grep
AWK=/bin/awk
FREE=/usr/bin/free
TAIL=/usr/bin/tail
HEAD=/usr/bin/head

# Get memory information from the "free" command - output of top two lines
# looks like:
#                 total       used       free     shared    buffers     cached
#    Mem:       8248768    6944444    1304324          0     246164    5647524
# The set command will get everything from the second line and put it into
# posiional variables $1 through $7.
#
set `$FREE |$HEAD -2 |$TAIL -1`

# Now give variable names to the positional variables we set above
#
MEMTOTAL=$2
MEMUSED=$3
MEMFREE=$4
MEMBUFFERS=$6
MEMCACHED=$7

# Do calculations based on what we got from free using the variables defined
#
REALMEMUSED=`echo $MEMUSED - $MEMBUFFERS - $MEMCACHED | $BC`
USEPCT=`echo "scale=3; $REALMEMUSED / $MEMTOTAL * 100" |$BC -l`
#USEPCT=`echo scale=3 "\n" $REALMEMUSED \/ $MEMTOTAL \* 100 |$BC -l |$AWK -F\. '{print $1}'`

# Compare the Used percentage to the Warning and Critical levels input at
# command line.  Issue message and set return code as appropriate for each
# level.  Nagios web page will use these to determine alarm level and message.
#
#if [ `echo "5.0 > 5" |bc` -eq 1 ]
#then echo it is greater
#else echo it is not greater
#fi
if [ `echo "$USEPCT > $CRITLEVEL" |bc` -eq 1 ]
then echo "CRITICAL - Memory usage is ${USEPCT}%"
     exit ${CRITICAL_STATE}
elif [ `echo "$USEPCT > $WARNLEVEL" |bc` -eq 1 ]
then echo "WARNING - Memory usage is ${USEPCT}%"
     exit ${WARNING_STATE}
elif [ `echo "$USEPCT < $WARNLEVEL" |bc` -eq 1 ]
then echo "OK - Memory usage is ${USEPCT}%"
     exit ${OK_STATE}
else echo "Unable to determine memory usage."
     exit ${UNKNOWN_STATE}
fi
echo "Unable to determine memory usage."
