#!/bin/sh

apk_list() {
	INSTALLED="$(apk info 2>/dev/null)"

	for PACKAGE in $INSTALLED; do
		POLICY="$(apk policy $PACKAGE 2>/dev/null | grep lib/apk/db/installed -A 1 -B 1)"
		VERSION="$(echo "$POLICY" | grep lib/apk/db/installed -A 1 -B 1 | head -n 1 | tail -n 1 | awk -F: '{print $1}' | xargs)"
		REPO_SOURCE="$(echo "$POLICY" | grep lib/apk/db/installed -A 1 -B 1 | head -n 3 | tail -n 1 | grep http | sed -e 's/alpine.*@//g' | xargs)"
		if [ "$REPO_SOURCE" = "" ]; then
			REPO_SOURCE="(local)"
		fi
		echo "$PACKAGE $VERSION $REPO_SOURCE" | tee -a $TEMP_FILE
	done
}

apt_list() {
	INSTALLED="$(apt list --installed 2>/dev/null | tail -n +2 | awk -F/ '{print $1}')"

	for PACKAGE in $INSTALLED; do
		POLICY="$(apt-cache policy $PACKAGE)"
		VERSION="$(echo "$POLICY" | grep Installed: | awk '{print $2}')"
		REPO_SOURCE="$(echo "$POLICY" | awk '/\*\*\*/,/100 /' | grep http | awk '{print $2}' | xargs | sed 's/ /,/g')"
		if [ "$REPO_SOURCE" = "" ]; then
			REPO_SOURCE="(local)"
		fi
		echo "$PACKAGE $VERSION $REPO_SOURCE" | tee -a $TEMP_FILE
	done
}

yum_list() {
	INSTALLED="$(yum list installed | sed -n '/^Installed Packages/,$p' | tail -n +2 | awk '{print $1}')"

	for PACKAGE in $INSTALLED; do
		INFO="$(yum info -v $PACKAGE | sed -n '/^Installed Packages/,/^$/p')"
		VERSION="$(echo "$INFO" | grep "^Version" | awk -F: '{print $2}')"; VERSION="$(echo $VERSION)"
		RELEASE="$(echo "$INFO" | grep "^Release" | awk -F: '{print $2}')"; RELEASE="$(echo $RELEASE)"
		REPO_SOURCE="$(echo "$INFO" | grep "^From repo" | awk -F: '{print $2}')"; REPO_SOURCE="$(echo $REPO_SOURCE)"
		echo "$PACKAGE $VERSION-$RELEASE $REPO_SOURCE" | tee -a $TEMP_FILE
	done
}

case $PLV_DISTRO in
	alpine)
		LIST_FUNC="apk_list"
		;;
	centos | fedora)
		LIST_FUNC="yum_list"
		;;
	ubuntu)
		LIST_FUNC="apt_list"
		;;
	*)
		(>&2 echo "Error: unsupported distro [Distro: '$PLV_DISTRO', Release: '$PLV_RELEASE', Arch: '$PLV_ARCH']" )
		exit 1
		;;
esac

TEMP_FILE=`mktemp`

eval "$LIST_FUNC"
EXIT_CODE=$?

PACKAGES_FROM_PV="$(cat $TEMP_FILE | grep polyverse | wc -l)"
TOTAL_PACKAGES="$(cat $TEMP_FILE | wc -l)"

(>&2 echo "Packages from repo.polyverse.io: $PACKAGES_FROM_PV/$TOTAL_PACKAGES" )
rm $TEMP_FILE 2>/dev/null || true

exit $EXIT_CODE
