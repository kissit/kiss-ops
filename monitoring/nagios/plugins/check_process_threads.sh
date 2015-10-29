#!/usr/bin/env bash
#
## check_process_threads.sh
##
## Copyright (C) 2015 KISS IT Consulting <http://www.kissitconsulting.com/>
##
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
##
##
## These are the default settings used if not passed in via the options.  Change if desired.
PIDFILE=
PROCNAME=
PIDCHECK=0
WARN=100
CRIT=200

##################################################################################
## Nothing below here should need changed for normal cases
##################################################################################
usage()
{
cat << EOF
usage: $0 options

This nagios plugin can be used to check that a) a process is running and b) the number of threads its using

OPTIONS:
   -h   Show this message
   -p   PID file to use (One of -p or -n is required)
   -n   Process name to use (One of -p or -n is required)
   -w   Warning threshold for threads
   -c   Critical threshold for threads
EOF
}

while getopts "hp:n:w:c:" OPTION
do
     case $OPTION in
         h)
             usage
             exit 1
             ;;
         p)
             PIDFILE=$OPTARG
             ;;
         n)
             PROCNAME=$OPTARG
             ;;
         w)
             WARN=$OPTARG
             ;;
         c)
             CRIT=$OPTARG
             ;;
         ?)
             usage
             exit 0
             ;;
     esac
done

if [[ -z $PIDFILE ]] && [[ -z $PROCNAME ]]; then
     usage
     exit 0
fi

if [ -n "$PIDFILE" ]; then
    # Use the PID from the PID File if it exists and we can read it
    if [ -r "$PIDFILE" ]; then
        PIDCHECK=`cat $PIDFILE`
    else
        echo "ERROR: PID File cannot be read"
        exit 2;
    fi
else
    # Try to find the PID from the process name.
    PIDCHECK=`pgrep -o $PROCNAME`
fi

if [[ -z $PIDCHECK ]]; then
    echo "CRITICAL: process not running"
    exit 2;
else
    THREADS=`ps -T -p $PIDCHECK | sed 1d | wc -l`
    if [ "$THREADS" -ge "$CRIT" ]; then
        echo "CRITICAL: $THREADS threads running"
        exit 2;
    elif [ "$THREADS" -ge "$WARN" ]; then
        echo "WARNING: $THREADS threads running"
        exit 1;
    else
        echo "OK: $THREADS threads running"
        exit 0;
    fi
fi
