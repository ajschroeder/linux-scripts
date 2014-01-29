#!/bin/sh
#
# Written by AJ Schroeder
# Script heavily borrowed from Marcus Mattern
#
# Define variables
FILE_WEBSVN_CONF="/path/to/dav_svn.authz"
#
# This script expects a structured LDAP group naming scheme.
# Specifically, PREFIX_RepoName is the preferred format since
# all the regex in this script is built to read that.
# The next two variables define parts of the group name to
# avoid having to modify regex constantly.
#
# Define the PREFIX for the groupname:
LDAP_GROUP_PREFIX="PREFIX"
# Define the delimiter used for LDAP groups. (e.g. Group name of SVN_SomeRepo would be
# a delimiter of "_" used for the regex in the script.
LDAP_GROUP_DELIMITER="_"
IFS_TEMP=$IFS
LDAP_BASEDN="DC=example,DC=com"
LDAP_BIND_USER="binduser@example.com"
LDAP_BIND_PASS="password"
LDAP_GROUPNAME_PREFIX=("PREFIX_RepoName1" "PREFIX_RepoName2")
LDAP_SEARCH=`which ldapsearch`
# This is a standard LDAP URI, use 'ldaps://' and port '636' for SSL connections.
# Extra setup is required for SSL connections.
LDAP_URI="ldap://ldap-server.example.com:389"
MAIL_RECIPIENTS="admin@example.com"

# Define functions
function print_repo() {
    echo "[$1:/]"
}

function show_output() {
  echo "[$repo:/]"
  for k in $user; do
    echo -e "${k} = rw"
  done
  user=""
  repo=""
}

function print_root_repo() {
    echo "[/]" >> $1
    echo -e "* = r\n" >> $1
}

# Change the field separator to a newline in order to process
# results from the ldapsearch command.
IFS=$'\n'

# Check to see if the target output file exists.
# Move it to a backup file if it does.
if [ -f "$FILE_WEBSVN_CONF" ]; then
    mv "$FILE_WEBSVN_CONF" "$FILE_WEBSVN_CONF.old"
fi

# Print the root repo
if print_root_repo $FILE_WEBSVN_CONF; then

    for i in ${LDAP_GROUPNAME_PREFIX[@]}
    do
        LDAP_FILTER="(&(objectClass=group)(cn=$i))"
        #repo=`echo $i | sed -e "s/\([A-Za-z0-9]*\)$LDAP_GROUP_DELIMITER\([A-Za-z0-9]\)/\2/"`

        res=`$LDAP_SEARCH -H $LDAP_URI -b $LDAP_BASEDN -u -x -LLL -D "$LDAP_BIND_USER" -w "$LDAP_BIND_PASS" "$LDAP_FILTER" cn member`

        for x in $res; do
            [ -n "$x" ] || continue
            # grep attribute
            j=`echo "$x" | grep -Eo "(^.*)(:)"`
            case $j in

            "ufn:")
                if [[ "$newds" -ne 0 ]]; then
                    show_output
                fi
            ;;

            "cn:")
                # Extract the repo name from the LDAP group name
                repo=`echo "$x" | sed "s#^.*: ##g; s#^$LDAP_GROUP_PREFIX$LDAP_GROUP_DELIMITER##g" `
                print_repo $repo >> $FILE_WEBSVN_CONF
                repo=""
            ;;

            "member:")
                user=${user}`echo "$x" | sed -e "s#^.*: ##g" | sed -e "s/^[Cc][Nn]=\([A-Za-z0-9$LDAP_GROUP_DELIMITER]*\).*/\1/"`$''
                echo "$user = rw" >> $FILE_WEBSVN_CONF
                user=""
            ;;

            *)
                continue
            ;;
            esac
        done
        # This line explicitly denies users from the repo in the authz file.
        # Change it to "* = r" if you wish to allow anonymous read access.
        echo -e "* =\n" >> $FILE_WEBSVN_CONF
    done
else
    `echo "Could not open $FILE_WEBWVN_CONF" | mail -s "Can't open the SVN authz file!" "$MAIL_RECIPIENTS"`
    exit 1 # Exit with failure
fi

# Change field separator back to what it was before
IFS=$IFS_TEMP

exit 0 # Exit with success