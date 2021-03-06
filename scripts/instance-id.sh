#!/bin/sh

# Defaults
REPO_FILE="/etc/yum.repos.d/polyverse.repo"

usage() {
cat >&2 <<-EOF

Retrieves the instance_id of the unique scrambled instance.

Usage:

  plv instance-id [<options>]

Options:

  --help                 Display usage

EOF
}

while [ $# -gt 0 ]; do
        case "$1" in
                --help)
                        usage
                        ;;
                *)
                        echo "Unhandled argument '$1'."
                        exit 1
        esac
        shift
done

type curl >/dev/null 2>&1
if [ $? -ne 0 ]; then
        echo "Please install curl."
        exit 1
fi

ARCH="$(uname -m)"
RELEASE=$(cat /etc/os-release 2>/dev/null | grep "VERSION_ID=" | cut -d "=" -f2 | tr -d '"')

BASEURL="$(cat $REPO_FILE  2>/dev/null | awk '/^'$ESCAPED'/,/^$/' | grep baseurl | awk -F= '{print $2}' | sed 's/\$basearch/'$ARCH'/g' | sed 's/\$releasever/'$RELEASE'/g')"
USERNAME="$(cat $REPO_FILE 2>/dev/null | awk '/^'$ESCAPED'/,/^$/' | grep ^username | sed 's/^username=//g' | head -n 1)"
PASSWORD="$(cat $REPO_FILE 2>/dev/null | awk '/^'$ESCAPED'/,/^$/' | grep ^password | sed 's/^password=//g' | head -n 1)"

# handle urls with and without trailing forward slash
BASEURL="$(echo ${BASEURL%/})/"

RESULT="$(curl -i -s https://$USERNAME:$PASSWORD@repo.polyverse.io/centos/$RELEASE/os/$ARCH/repodata/repomd.xml 2>/dev/null | grep Instance-Id)"
if [ "$RESULT" = "" ]; then
	echo "error: unable to determine instance_id."
	exit 1
fi
echo "$RESULT" | awk -F':' '{print $2}' | xargs
