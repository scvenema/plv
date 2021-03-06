#!/bin/sh

# Defaults
INSTALL_ROOT=$PWD
PACKAGE_NAME=""
REPO_FILE="/etc/yum.repos.d/polyverse.repo"

usage() {
cat >&2 <<-EOF

Recursively scans all the executables from the current directory and compares
the relative path/filename to the executables in an .rpm. If there's a match,
the current binary is replaced with the one from the .rpm file. You do not need
to have the rpm downloaded; the baseurl from the repo file is used as the
source from which this script will download the rpm file.

Usage:

  plv extract-rpm <rpm_filename> [<options>]

Options:

  --install-root         Specify a starting directory other than current.
  --repo-file            Override default /etc/yum.repos.d/polyverse.repo

Example:

  $ wget -qO- https://git.io/plv | sh -s extract-rpm nano-2.3.1-10.el7.x86_64.rpm --repo-file /etc/yum.repos.d/CentOS-Base.repo --install-root /usr/bin

EOF
}

while [ $# -gt 0 ]; do
        case "$1" in
                --install-root)
                        shift
                        INSTALL_ROOT="$1"
                        ;;
                --repo-file)
			shift
			REPO_FILE="$1"
                        ;;
		--help)
			usage
			;;
                *)
			if [ -z "$PACKAGE_NAME" ]; then
				PACKAGE_NAME="$1"
				shift
				continue
			fi

			echo "Unhandled argument '$1'."
			exit 1
        esac
        shift
done

if [ -z "$PACKAGE_NAME" ]; then
	usage
	exit 1
fi

type wget >/dev/null 2>&1
if [ $? -ne 0 ]; then
	echo "Please install wget."
	exit 1
fi

echo "Checking for $INSTALL_ROOT/$PACKAGE_NAME..."
if [ ! -f "$INSTALL_ROOT/$PACKAGE_NAME" ]; then
	echo "--> Package not found. Attempting to download it..."
	echo "--> Parsing repo file '$REPO_FILE'..."
	COMPONENTS="$(cat $REPO_FILE | grep "^\[")"
	echo "----> Attempting to download '$PACKAGE_NAME'..."
	for COMPONENT in $COMPONENTS; do
		ESCAPED="$(echo "$COMPONENT" | sed 's/\[/\\\[/g' | sed 's/\]/\\\]/g')"

		ARCH="$(uname -m)"
		RELEASE=$(cat /etc/os-release 2>/dev/null | grep "VERSION_ID=" | cut -d "=" -f2 | tr -d '"')

		BASEURL="$(cat $REPO_FILE  | awk '/^'$ESCAPED'/,/^$/' | grep baseurl | awk -F= '{print $2}' | sed 's/\$basearch/'$ARCH'/g' | sed 's/\$releasever/'$RELEASE'/g')"
		#BASEURL="$(cat $REPO_FILE  | awk '/^'$ESCAPED'/,/^$/' | grep ^baseurl | awk -F= '{print $2}' | sed 's/\$basearch/'$ARCH'/g' | sed 's/\$releasever/'$RELEASE'/g')"
		USERNAME="$(cat $REPO_FILE  | awk '/^'$ESCAPED'/,/^$/' | grep ^username | sed 's/^username=//g')"
		PASSWORD="$(cat $REPO_FILE  | awk '/^'$ESCAPED'/,/^$/' | grep ^password | sed 's/^password=//g')"

		if [ "$BASEURL" = "" ]; then
			echo "----> $COMPONENT: no baseurl found."
			continue
		fi

		# handle urls with and without trailing forward slash
		BASEURL="$(echo ${BASEURL%/})/"

		echo "Trying ${BASEURL}Packages/$PACKAGE_NAME..."

		wget --user=$USERNAME --password=$PASSWORD -qO $INSTALL_ROOT/$PACKAGE_NAME ${BASEURL}Packages/$PACKAGE_NAME
		if [ $? -eq 0 ]; then
			echo "----> Successfully downloaded to: $INSTALL_ROOT/$PACKAGE_NAME"
			break
		fi
		rm $INSTALL_ROOT/$PACKAGE_NAME
		echo "----> Didn't find it."
	done
else
	echo "--> Found."
fi

if [ ! -f "$INSTALL_ROOT/$PACKAGE_NAME" ]; then
        echo "Package $PACKAGE_NAME not found."
        exit 1
fi

debugln() {
	if [ "$PLV_DEBUG" != "" ]; then
		echo "$1"
	fi
}

RPM_CONTENTS="$(rpm -qlpv $INSTALL_ROOT/$PACKAGE_NAME)"
debugln "--> RPM CONTENTS: $RPM_CONTENTS <--"

# get a recursive directory listing of $INSTALL_ROOT
echo "Scanning $INSTALL_ROOT..."
find $INSTALL_ROOT -name \* -print | while read line; do
	TARGET="$(echo $line | sed 's|'$INSTALL_ROOT'/||g')"
	if [ "$INSTALL_ROOT" = "$TARGET" ]; then
		continue
	fi

	debugln "$INSTALL_ROOT/$TARGET ($TARGET)"
	#echo "$INSTALL_ROOT/$TARGET"

	FORMAT="$(stat --format %F "$INSTALL_ROOT/$TARGET")"
	debugln "--> format: $FORMAT"
	if [ "$FORMAT" != "regular file" ]; then
		debugln "--> not regular file. skipping..."
		continue
	fi

	STAT="$(stat --format "%A" "$INSTALL_ROOT/$TARGET")"
	debugln "--> stat: $STAT"
	if [ "$(echo "$STAT" | grep "^-.*x")" = "" ]; then
		debugln "--> not executable. skipping..."
		continue
	fi

        ELF_COMMENTS="$(readelf --string-dump=.comment $INSTALL_ROOT/$TARGET 2>/dev/null)"
        if [ $? -ne 0 ]; then
                debugln "--> not elf file. skipping..."
		continue
        fi

	PACKAGED_FILES="$(echo "$RPM_CONTENTS" | grep \/$TARGET\$ 2>/dev/null | awk '{print $9}')"
        if [ "$PACKAGED_FILES" = "" ]; then
		debugln "--> file not found in package. skipping..."
                continue
        fi

	if [ $(echo "$PACKAGED_FILE" | wc -l | xargs) -gt 1 ]; then
		echo "There is more than 1 match for '$INSTALL_ROOT/$TARGET': $(echo "$PACKAGED_FILE" | xargs). Skipping to be safe..."
		continue
	fi

	#for PACKAGED_FILE in $PACKAGED_FILES; do
	#	if [ "$PACKAGED_FILE" = "$INSTALL_ROOT/$TARGET" ]; then
	#		debugln "--> exact match."
	#		break
	#	fi
	#done

        echo "*** Extracting [$PACKAGE_NAME] $PACKAGED_FILE --> $INSTALL_ROOT/$TARGET ***"

	# grab key file attributes since extracting/redirecting doesn't preserve
	CHMOD="$(stat --format "%a" "$INSTALL_ROOT/$TARGET")"
	OWNER="$(stat --format "%U" "$INSTALL_ROOT/$TARGET")"
	GROUP="$(stat --format "%G" "$INSTALL_ROOT/$TARGET")"

	# extract out the specific file from package
	rpm2cpio $INSTALL_ROOT/$PACKAGE_NAME | cpio -iv --to-stdout .$PACKAGED_FILE 2>/dev/null > $INSTALL_ROOT/$TARGET.pv

	# restore original file attributes
	chmod $CHMOD $INSTALL_ROOT/$TARGET.pv
	chown $OWNER:$GROUP $INSTALL_ROOT/$TARGET.pv
	cp $INSTALL_ROOT/$TARGET $INSTALL_ROOT/$TARGET.old
	mv $INSTALL_ROOT/$TARGET.pv $INSTALL_ROOT/$TARGET
	if [ $? -ne 0 ]; then
		echo "Error occurred moving $INSTALL_ROOT/$TARGET.pv to $INSTALL_ROOT/$TARGET."
	fi
	debugln "--> end of loop"
done
