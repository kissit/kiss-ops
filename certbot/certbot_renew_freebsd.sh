#!/usr/bin/env bash
######################################################################################################
## This is a post-hook script to use with Certbot for renewals to send an email when a cert is renewed
## For example, you'd put something like this in your crontab (must run as root though!)
## Certs will only be renewed if they are getting close to expiration.  LE actually recommends running
## renewals at least weekly but even daily.  They recommend choosing a random hour/minute to avoid everything
## being run at the same time
##
## This is a FreeBSD version of the script.  It requires the heirloom-mailx package to be installed:
##      pkg install heirloom-mailx
##
## 32 1 * * * /usr/local/bin/certbot renew --post-hook /usr/local/bin/certbot_renew.sh > /tmp/certbot.log 2>&1
######################################################################################################

## Email addresses that should get the notifications
EMAIL_TO="name@email.com"
EMAIL_FROM="no-reply@email.com"

## Paths to our log files
APACHE_LOGFILE=/var/log/httpd-error.log
LOGFILE=/tmp/certbot.log
MAILFILE=/tmp/certbot.mail

## Start our ouput file for the email
echo "------------------------------------------------------------------------------------------------" > $MAILFILE
echo " Certbot post renewal notification hook.  Restarting httpd..." >> $MAILFILE
echo "------------------------------------------------------------------------------------------------" >> $MAILFILE

## Restart apache
service apache24 restart

## Output our log and such to use for cron to send an email
echo "------------------------------------------------------------------------------------------------" >> $MAILFILE
echo " httpd status after restart " >> $MAILFILE
echo "------------------------------------------------------------------------------------------------" >> $MAILFILE
tail $APACHE_LOGFILE >> $MAILFILE 2>&1

echo "------------------------------------------------------------------------------------------------" >> $MAILFILE
echo " Certbot log information " >> $MAILFILE
echo "------------------------------------------------------------------------------------------------" >> $MAILFILE
cat $LOGFILE >> $MAILFILE

## Send our email
cat $MAILFILE | /usr/local/bin/mailx -s "Certbot auto renew - $HOSTNAME" -r "$EMAIL_FROM" "$EMAIL_TO"

rm $MAILFILE
exit 0;