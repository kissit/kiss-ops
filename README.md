# kiss-ops

A collection of various scripts, helpers, and monitoring tools that I've developed over the years.  Most items have instructions included at the top in comments. 

Feel free to reach out to me with any questions or if you find issues or would like to request enhancements.

## ansible

Various Ansible tasks & playbooks.  Nothing fancy here.

## backups

Should be self explanatory...backup related scripts

## database

Should be self explanatory...database related scripts

## monitoring

Various plugins for both Munin and Nagios to fill in some gaps.

## helpers

Various helpers I've created to function exactly how I like when doing development.
* **kissdb.php** - A simple db class to provide access to MySQL via mysqli.  Includes optional built in caching via redis as well as "lazy connecting" to avoid opening the database connection unless a query needs to be run at the database level.
* **kisslog.php** - A simple logging class for errors and messages.  Can also send email notifications for errors.  This is not meant to be a replacement error handling class but just something called in code for producing consistent log output.

