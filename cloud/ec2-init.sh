#!/bin/bash
## ec2-init.sh
## 
## Simple bash script to use during boot for a AWS instance to dynamically set the hostname
## from a value provided as userdata.
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
## Usage:
## 1. Download to your system somewhere, say /usr/local/bin/ec2-init.sh
## 2. Make it executable: chmod 755 /usr/local/bin/ec2-init.sh
## 3. Add it to /etc/rc.local so it gets run at boot, like so:
##      ## Run our custom ec2-init script
##      /usr/local/bin/ec2-init.sh
## 4. Set your desired hostname in the EC2 instance user-data field
## 5. Reboot.  Include this setup in custom images, pass in your hostname when building instances from the API, things will have friendly names

## Set domain to suit your needs
DOMAIN=kissitconsulting.com
CHECK="^<.*"

## Set our hostname on boot (if we have one)
HOSTNAME=`/usr/bin/curl -s http://169.254.169.254/latest/user-data`
if [[ ! $HOSTNAME =~ $CHECK ]]; then
        echo "Setting hostname to $HOSTNAME.$DOMAIN"
        hostname $HOSTNAME.$DOMAIN
fi
exit 0