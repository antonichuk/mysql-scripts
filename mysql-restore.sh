#!/bin/bash
#===============================================================================
#
#          FILE: mysql-restore.sh
# 
#         USAGE: ./mysql-restore.sh -p <path to backup to restore> -d <database name to restore> -t <table name to restore>
# 
#   DESCRIPTION: This is script for restore databases from full or incremental backups
# 
#       OPTIONS: ---
#  REQUIREMENTS: Percona XtraBackup
#          BUGS: ---
#         NOTES: ---
#        AUTHOR: Volodymyr Antonichuk (antonichuk), antonichuk@gmail.com
#  ORGANIZATION: Lviv, Ukraine
#       CREATED: 01.09.14 01:45
#      REVISION: 1.0 
#===============================================================================

set -o nounset                              # Treat unset variables as an error
# Define variables
#INNOBACKUPEX=innobackupex-1.5.1
INNOBACKUPEX=innobackupex
INNOBACKUPEXFULL=/usr/bin/$INNOBACKUPEX
TMPFILE="/tmp/mysql-restore.$$.tmp"
MYCNF=/data/db/my.cnf # We must you another my.cnf file for restoring db's, where we provide path to datadir to - /data/db/restore
BACKUPDIR=/data/db # Backups base directory
DAILYBACKUP=$BACKUPDIR/full # Full backups directory
HOURLYBACKUP=$BACKUPDIR/hour # Incremental backups directory
MEMORY=1024M # Amount of memory to use when preparing the backup
START=`date +%s`
USEROPTIONS="--user=root --password=moIj>Ob;bIm;wyiT%"
RESTOREDDIR=/data/db/restored
RESTORE=
DATABASE=
TABLE=
LAST_INCR_BACKUP=
REALPATH=
DEFAULTDB=binpress

# Print usage info
usage() {
    cat<<EOF >&2
    How to use:
    $0 -p <path to backup to restore> -d <database name to restore> -t <table name to restore>
    When -d (database) not set, default db name for restore wiil be use
    Tou can change it in $DEFAULTDB variable
    When -t (table name) not set, all tables from database will be restored
    For restore some table, you must set database name from which it will be restored,
    and table name that will be restored.
EOF
}

# Display error message and exit
error()
{
    echo "$@"
    exit 1
}

# Check for errors in innobackupex output#
check_innobackupex_error()
{
    if [ -z "`tail -1 $TMPFILE | grep 'completed OK!'`" ] ; then
        echo "$INNOBACKUPEX failed:"; echo
        echo "---------- ERROR OUTPUT from $INNOBACKUPEX ----------"
        cat $TMPFILE
        rm -f $TMPFILE
        exit 1
    fi
}

# Check options before proceeding
if [ ! -x $INNOBACKUPEXFULL ]; then
    error "$INNOBACKUPEXFULL does not exist. You must install Percona XtraBackup"
fi

# Check for arguments, if no arguments, then show usage and exit
if [ $# = 0 ]; then
    usage
    exit 1
fi

while getopts ":lp:d:t:" OPTION; do
    case $OPTION in
        l )
            LAST_INCR_BACKUP=latest
            ;;
        p )
            RESTORE=$OPTARG
            ;;
        d )
            DATABASE=$OPTARG
            ;;
        t )
            TABLE=$OPTARG
            ;;
        ?)
            usage
            exit 1
            ;;
    esac
done

#if [[ -z $RESTORE ]]
#then
#	echo
#	echo "You must select path to direcotory with backups!!!"
#	echo "Or you can use --latest options to restore from latest incremenatlal backup"
#	echo "Please, read usage instuction!!!"
#	echo
#	usage
#	echo
#	exit 1
#fi

# Ask user to continiue or not
read -p "Are you sure that you want to restore databases? Press "Y" to continiue or any key to exit" -n 1 -r
if [[ ! $REPLY =~ ^[Yy]$ ]]
then
    echo
    echo "OK!"
    echo "Try next time when you will be ready"
    exit 1
fi

# Check if used "-l" and "-p", we can't use -l and -p option
if [[ ! -z $LAST_INCR_BACKUP ]] && [[ ! -z $RESTORE ]]
then
    echo "We can't use both options -l and -p"
    usage
    exit 1
fi

# Check folder with backups for existing
if [ ! -d $RESTORE ]; then
    error "Backup to restore: $RESTORE does not exis."
fi

# Some info output
echo "Script $0 started at: `date`"

full_to_incr() {
    PARENT_DIR=`dirname $RESTORE`
    if [ $PARENT_DIR = $DAILYBACKUP ]
    then
        FULLBACKUP=$RESTORE
        echo "Restore `basename $FULLBACKUP`"
        echo
    else
        if [ `dirname $PARENT_DIR` = $HOURLYBACKUP ]
        then
            INCR=`basename $RESTORE`
            FULL=`basename $PARENT_DIR`
            FULLBACKUP=$DAILYBACKUP/$FULL
            if [ ! -d $FULLBACKUP ]
            then
                error "Full backup: $FULLBACKUP does not exist."
            fi
            echo "Restore $FULL up to incremental $INCR"
            echo "Replay committed transactions on full backup"
            $INNOBACKUPEXFULL --defaults-file=$MYCNF --apply-log --redo-only --use-memory=$MEMORY $FULLBACKUP > $TMPFILE 2>&1
            check_innobackupex_error
            # Apply incrementals to base backup
            for i in `find $PARENT_DIR -mindepth 1 -maxdepth 1 -type d -printf "%P\n" | sort -n`; do
                echo "Applying $i to full ..."
                $INNOBACKUPEXFULL --defaults-file=$MYCNF --apply-log --redo-only --use-memory=$MEMORY $FULLBACKUP --incremental-dir=$PARENT_DIR/$i > $TMPFILE 2>&1
                check_innobackupex_error
                if [ $INCR = $i ]
                then
                    break # break. we are restoring up to this incremental.
                fi
            done
        else
            error "Unknown backup type"
        fi
    fi
}

# Preparing databse to restore
prepare_databases() {
    echo "Preparing to restoring ..."
    $INNOBACKUPEXFULL --defaults-file=$MYCNF --apply-log --use-memory=$MEMORY $FULLBACKUP > $TMPFILE 2>&1
    check_innobackupex_error
}

# Restoring all databases
restore_all_db() {
    echo "Restoring all databases"
    $INNOBACKUPEXFULL --defaults-file=$MYCNF --copy-back $FULLBACKUP > $TMPFILE 2>&1
    check_innobackupex_error
    rm -f $TMPFILE
}

# Restoring defined databse
restore_db() {
    echo "Restoring only $DATABASE database"
    $INNOBACKUPEXFULL $USEROPTIONS --include=$DATABASE $FULLBACKUP > $TMPFILE 2>&1
    check_innobackupex_error
    rm -f $TMPFILE
}

# Restoring default databse
restore_default_db() {
    echo "Restoring default $DEFAULTDB database"
    $INNOBACKUPEXFULL $USEROPTIONS --include=$DEFAULTDB $FULLBACKUP > $TMPFILE 2>&1
    check_innobackupex_error
    rm -f $TMPFILE
}

# Restoring table from database
restore_table() {
    echo "Restoring only table $TABLE from $DATABASE database"
    $INNOBACKUPEXFULL $USEROPTIONS --include $DATABASE.$TABLE $FULLBACKUP > $TMPFILE 2>&1
    check_innobackupex_error
    rm -f $TMPFILE
}

# Find last incremental backup
last_incr () {
    echo "Finding last incremental backup"
    LATEST_INCR=`find $HOURLYBACKUP -mindepth 1 -maxdepth 2 -type d -printf "%P\n" | sort -nr | head -1`
    RESTORE=$HOURLYBACKUP/$LATEST_INCR
}

# If use key "-l" and no path to backup, no database name, no table to restore, will be restored default db from lates incr.
if [[ ! -z $LAST_INCR_BACKUP ]] && [[ -z $DATABASE ]] && [[ -z $TABLE ]]
then
    last_incr
    echo "Will be restored deault $DEFAULTDB database from last incremental backup from: $RESTORE"
    full_to_incr
    prepare_databases
    restore_default_db
    SPENT=$((`date +%s` - $START))
    echo "Took $SPENT seconds"
    echo "Completed at: `date`"
    exit 0
else
    # If use key "-l" and Database "ALL", all db's from lates incremental backup will be restored.
    if [[ ! -z $LAST_INCR_BACKUP ]] && [[ $DATABASE="ALL" ]] && [[ -z $TABLE ]]
    then
        last_incr
        echo "All database will be restored..."
        full_to_incr
        prepare_databases
        restore_all_db
        SPENT=$((`date +%s` - $START))
        echo "Took $SPENT seconds"
        echo "Completed at: `date`"
        echo
        echo "All db's has been restored from latest backup"
        echo "You can copy it to MySQL data dir, usualy it is in /var/lib/mysql"
        echo "Verify files ownership in mysql data dir."
        echo "You can fix permission by this command: chown -R mysql:mysql /var/lib/mysql"
        echo "You are able to start MySQL server now"
        exit 0
    else
        # If use key "-l" and no path to backup, no table to restore, defined database with all tables will be restored from lates incr.
        if [[ ! -z $LAST_INCR_BACKUP ]] && [[ ! -z $DATABASE ]] && [[ -z $TABLE ]]
        then
            last_incr
            echo "Database $DATABASE from latest incremental backup will be restored"
            full_to_incr
            prepare_databases
            restore_db
            SPENT=$((`date +%s` - $START))
            echo "Took $SPENT seconds"
            echo "Completed at: `date`"
            exit 0
        else
            # If use key "-l" -d <database> -t <table>, then it will restore table from database from lates incr.
            if [[ ! -z $LAST_INCR_BACKUP ]] && [[ ! -z $DATABASE ]] && [[ ! -z $TABLE ]]
            then
                last_incr
                echo "Database $TABLE from database $DATABASE using latest incremental backup will be restored"
                full_to_incr
                prepare_databases
                restore_table
                SPENT=$((`date +%s` - $START))
                echo "Took $SPENT seconds"
                echo "Completed at: `date`"
                exit 0
            else
                # Restore default db from path
                if [[ ! -z $RESTORE ]] && [[ -z $DATABASE ]] && [[ -z $TABLE ]]
                then
                    full_to_incr
                    prepare_databases
                    restore_db
                    echo "Database $DATABASE has been restored"
                    SPENT=$((`date +%s` - $START))
                    echo
                    echo "Took $SPENT seconds"
                    echo "Completed at: `date`"
                    exit 0
                else
                    # Restore ALL db's from path
                    if [[ ! -z $RESTORE ]] && [[ $DATABASE="ALL" ]] && [[ -z $TABLE ]]
                    then
                        full_to_incr
                        prepare_databases
                        restore_all_db
                        echo "Table $TABLE from $DATABASE has been restored"
                        SPENT=$((`date +%s` - $START))
                        echo
                        echo "Took $SPENT seconds"
                        echo "Completed at: `date`"
                        exit 0
                    else
                        # Restore database from path
                        if [[ ! -z $RESTORE ]] && [[ ! -z $DATABASE ]] && [[ -z $TABLE ]]
                        then
                            full_to_incr
                            prepare_databases
                            restore__db
                            echo "Table database $DATABASE from $RESTORE has been restored"
                            SPENT=$((`date +%s` - $START))
                            echo
                            echo "Took $SPENT seconds"
                            echo "Completed at: `date`"
                            exit 0
                        fi
                    fi
                fi
            fi
        fi
    fi
fi
