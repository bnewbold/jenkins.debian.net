#!/bin/bash

# Copyright © 2015 Holger Levsen <holger@layer-acht.org>
# released under the GPLv=2

DEBUG=false
. /srv/jenkins/bin/common-functions.sh
common_init "$@"

# common code defining db access
. /srv/jenkins/bin/reproducible_common.sh

TARGET_DIR=/srv/reproducible-results/node-information/
mkdir -p $TARGET_DIR
TMPFILE_SRC=$(mktemp)
TMPFILE_NODE=$(mktemp)

for NODE in $BUILD_NODES jenkins.debian.net ; do
	if [ "$NODE" = "jenkins.debian.net" ] ; then
		echo "$(date -u) - Trying to update $TARGET_DIR/$NODE."
		/srv/jenkins/bin/reproducible_info.sh > $TARGET_DIR/$NODE
		echo "$(date -u) - $TARGET_DIR/$NODE updated:"
		cat $TARGET_DIR/$NODE
		continue
	fi
	# call jenkins_master_wrapper.sh so we only need to track different ssh ports in one place
	# jenkins_master_wrapper.sh needs NODE_NAME and JOB_NAME
	export NODE_NAME=$NODE
	export JOB_NAME=$JOB_NAME
	echo "$(date -u) - Trying to update $TARGET_DIR/$NODE."
	/srv/jenkins/bin/jenkins_master_wrapper.sh /srv/jenkins/bin/reproducible_info.sh > $TMPFILE_SRC
	for KEY in $BUILD_ENV_VARS ; do
		VALUE=$(egrep "^$KEY=" $TMPFILE_SRC | cut -d "=" -f2-)
		if [ ! -z "$VALUE" ] ; then
			echo "$KEY=$VALUE" >> $TMPFILE_NODE
		fi
	done
	if [ -s $TMPFILE_NODE ] ; then
		mv $TMPFILE_NODE $TARGET_DIR/$NODE
		echo "$(date -u) - $TARGET_DIR/$NODE updated:"
		cat $TARGET_DIR/$NODE
	fi
	rm -f $TMPFILE_SRC $TMPFILE_NODE
done

