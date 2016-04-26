#!/bin/bash - 
#===============================================================================
#
#          FILE: mysql-backup.sh
# 
#         USAGE: ./mysql-backup.sh 
# 
#   DESCRIPTION: Script for backup all databases using percona backup tool
# 
#       OPTIONS: ---
#  REQUIREMENTS: innobackupex-1.5.1
#          BUGS: ---
#         NOTES: ---
#        AUTHOR: Volodymyr Antonichuk (antonichuk), antonichuk@gmail.com
#  ORGANIZATION: Lviv, Ukraine
#       CREATED: 01.09.14 16:17
#      REVISION: 1.0
#===============================================================================

set -o nounset                              # Treat unset variables as an error

INNOBACKUPEX=innobackupex-1.5.1
INNOBACKUPEXFULL=/usr/bin/$INNOBACKUPEX
USEROPTIONS="--user=root --password=moIj>Ob;bIm;wyiT%"
TMPFILE="/tmp/backup.$$.tmp"
MYCNF=/etc/my.cnf
MYSQL=/usr/bin/mysql
MYSQLADMIN=/usr/bin/mysqladmin
BACKUPDIR=/data/db # Backups base directory
DAILYBACKUPFULL=$BACKUPDIR/daily # Full daily backups directory
HOURLYBACKUP=$BACKUPDIR/hourly # Hourly nncremental backups directory
FULLBACKUPLIFE=86400 # Lifetime of the latest full daily backup in seconds
KEEP=7 # Number of full backups and its incrementals to keep

# Take start time
STARTED_AT=`date +%s`

# Display error message and exit #
error()
{
    echo "$1" 1>&2
    exit 1
}

# Check options before proceeding
if [ ! -x $INNOBACKUPEXFULL ]; then
    error "$INNOBACKUPEXFULL does not exist."
fi

if [ ! -d $BACKUPDIR ]; then
    error "Backup destination folder: $BACKUPDIR does not exist."
fi

if [ -z "`$MYSQLADMIN $USEROPTIONS status | grep 'Uptime'`" ] ; then
    error "ERROR: MySQL does not appear to be running."
fi

if ! `echo 'exit' | $MYSQL -s $USEROPTIONS` ; then
    error "ERROR: Supplied mysql username or password appears to be incorrect."
fi

# Some info output
echo "$0 started at: `date`"

# Create full daily and hourly incr backup directories if they not exist.
mkdir -p $DAILYBACKUPFULL
mkdir -p $HOURLYBACKUP

# Find latest full backup
LATEST_FULL=`find $DAILYBACKUPFULL -mindepth 1 -maxdepth 1 -type d -printf "%P\n" | sort -nr | head -1`
# Get latest backup last modification time
LATEST_FULL_CREATED_AT=`stat -c %Y $DAILYBACKUPFULL/$LATEST_FULL`

# Run an incremental backup if latest full is still valid. Otherwise, run a new full one.
if [ "$LATEST_FULL" -a `expr $LATEST_FULL_CREATED_AT + $FULLBACKUPLIFE + 5` -ge $STARTED_AT ] ; then
    # Create incremental backups dir if not exists.
    TMPINCRDIR=$HOURLYBACKUP/$LATEST_FULL
    mkdir -p $TMPINCRDIR
    # Find latest incremental backup.
    LATEST_INCR=`find $TMPINCRDIR -mindepth 1 -maxdepth 1 -type d | sort -nr | head -1`
    # If this is the first incremental, use the full as base. Otherwise, use the latest incremental as base.
    if [ ! $LATEST_INCR ] ; then
        INCRBASEDIR=$DAILYBACKUPFULL/$LATEST_FULL
    else
        INCRBASEDIR=$LATEST_INCR
    fi
    echo "Running new incremental backup using $INCRBASEDIR as base."
    $INNOBACKUPEXFULL --defaults-file=$MYCNF $USEROPTIONS --incremental $TMPINCRDIR --incremental-basedir $INCRBASEDIR > $TMPFILE 2>&1
else
    echo "Running new full backup."
    $INNOBACKUPEXFULL --defaults-file=$MYCNF $USEROPTIONS $DAILYBACKUPFULL > $TMPFILE 2>&1
fi

if [ -z "`tail -1 $TMPFILE | grep 'completed OK!'`" ] ; then
    echo "$INNOBACKUPEX failed:"; echo
    echo "---------- ERROR OUTPUT from $INNOBACKUPEX ----------"
    cat $TMPFILE
    rm -f $TMPFILE
    exit 1
fi

THISBACKUP=`awk -- "/Backup created in directory/ { split( \\\$0, p, \"'\" ) ; print p[2] }" $TMPFILE`
rm -f $TMPFILE
echo "Databases backed up successfully to: $THISBACKUP"
echo

# Cleanup
echo "Cleanup. Keeping $KEEP full daily backups and its incrementals."
AGE=$(($FULLBACKUPLIFE * $KEEP / 60))
find $DAILYBACKUPFULL -maxdepth 1 -type d -mmin +$AGE -execdir echo "removing: "$DAILYBACKUPFULL/{} \; -execdir rm -rf $DAILYBACKUPFULL/{} \; -execdir echo "removing: "$HOURLYBACKUP/{} \; -execdir rm -rf $HOURLYBACKUP/{} \;
echo
echo "Completed at: `date`"
exit 0
