#!/bin/bash

# Copyright 2014-2015 Holger Levsen <holger@layer-acht.org>
#         © 2015 Mattia Rizzolo <mattia@mapreri.org>
# released under the GPLv=2

DEBUG=false
. /srv/jenkins/bin/common-functions.sh
common_init "$@"

# common code defining db access
. /srv/jenkins/bin/reproducible_common.sh

set -e

# build for different architectures
ARCHS="sparc64" # FIXME: actually use this...

cleanup_tmpdirs() {
	cd
	rm -r $TMPDIR
	rm -r $TMPBUILDDIR
}

create_results_dirs() {
	mkdir -p $BASE/netbsd/dbd
}

save_netbsd_results(){
	RUN=$1
	cd obj/releasedir/sparc64/
	mkdir -p $TMPDIR/$RUN/
	cp -pr * $TMPDIR/$RUN/
	cd ../../..
	rm obj/releasedir/sparc64/ -r
}

#
# main
#
TMPBUILDDIR=$(mktemp --tmpdir=/srv/workspace/chroots/ -d -t netbsd-XXXXXXXX)  # used to build on tmpfs
TMPDIR=$(mktemp --tmpdir=/srv/reproducible-results -d)  # accessable in schroots, used to compare results
DATE=$(date -u +'%Y-%m-%d')
START=$(date +'%s')
trap cleanup_tmpdirs INT TERM EXIT

cd $TMPBUILDDIR
echo "============================================================================="
echo "$(date -u) - Cloning the netbsd git repository (which is autosynced with their CVS repository)"
echo "============================================================================="
git clone https://github.com/jsonn/src
mv src netbsd
cd netbsd
NETBSD="$(git log -1)"
NETBSD_VERSION=$(git describe --always)
echo "This is netbsd $NETBSD_VERSION."
echo
git log -1

echo "============================================================================="
echo "$(date -u) - Building netbsd ${NETBSD_VERSION} - first build run."
echo "============================================================================="
export TZ="/usr/share/zoneinfo/Etc/GMT+12"
# actually build everything
ionice -c 3 nice \
	./build.sh -j $NUM_CPU -U -u -m sparc64 release
# save results in b1
save_netbsd_results b1

echo "============================================================================="
echo "$(date -u) - Building netbsd - second build run."
echo "============================================================================="
export TZ="/usr/share/zoneinfo/Etc/GMT-14"
export LANG="fr_CH.UTF-8"
export LC_ALL="fr_CH.UTF-8"
export PATH="/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:/i/capture/the/path"
export CAPTURE_ENVIRONMENT="I capture the environment"
umask 0002
# use allmost all cores for second build
NEW_NUM_CPU=$(echo $NUM_CPU-1|bc)
ionice -c 3 nice \
	linux64 --uname-2.6 \
	./build.sh -j $NEW_NUM_CPU -U -u -m sparc64 release

# reset environment to default values again
export LANG="en_GB.UTF-8"
unset LC_ALL
export TZ="/usr/share/zoneinfo/UTC"
export PATH="/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:"
umask 0022

# save results in b2
save_netbsd_results b2

# clean up builddir to save space on tmpfs
rm -r $TMPBUILDDIR/netbsd

# run debbindiff on the results
TIMEOUT="30m"
DBDSUITE="unstable"
DBDVERSION="$(schroot --directory /tmp -c source:jenkins-reproducible-${DBDSUITE}-debbindiff debbindiff -- --version 2>&1)"
echo "============================================================================="
echo "$(date -u) - Running $DBDVERSION on netbsd..."
echo "============================================================================="
FILES_HTML=$(mktemp --tmpdir=$TMPDIR)
echo "       <ul>" > $FILES_HTML
BAD_FILES=0
GOOD_FILES=0
ALL_FILES=0
create_results_dirs
cd $TMPDIR/b1
tree .
for i in * ; do
	cd $i
	echo "       <table><tr><th>Release files for <code>$i</code></th></tr>" >> $FILES_HTML
	for j in $(find * -type f |sort -u ) ; do
		let ALL_FILES+=1
		call_debbindiff_on_any_file $i $j
		SIZE="$(du -h -b $j | cut -f1)"
		SIZE="$(echo $SIZE/1024|bc)"
		if [ -f $TMPDIR/$i/$j.html ] ; then
			mkdir -p $BASE/netbsd/dbd/$i/$(dirname $j)
			mv $TMPDIR/$i/$j.html $BASE/netbsd/dbd/$i/$j.html
			echo "         <tr><td><a href=\"dbd/$i/$j.html\"><img src=\"/userContent/static/weather-showers-scattered.png\" alt=\"unreproducible icon\" /> $j</a> (${SIZE}K) is unreproducible.</td></tr>" >> $FILES_HTML
		else
			SHASUM=$(sha256sum $j|cut -d " " -f1)
			echo "         <tr><td><img src=\"/userContent/static/weather-clear.png\" alt=\"reproducible icon\" /> $j ($SHASUM, ${SIZE}K) is reproducible.</td></tr>" >> $FILES_HTML
			let GOOD_FILES+=1
			rm -f $BASE/netbsd/dbd/$i/$j.html # cleanup from previous (unreproducible) tests - if needed
		fi
	done
	cd ..
	echo "       </table>" >> $FILES_HTML
done
GOOD_PERCENT=$(echo "scale=1 ; ($GOOD_FILES*100/$ALL_FILES)" | bc)
BAD_PERCENT=$(echo "scale=1 ; ($BAD_FILES*100/$ALL_FILES)" | bc)
# are we there yet?
if [ "$GOOD_PERCENT" = "100.0" ] ; then
	MAGIC_SIGN="!"
else
	MAGIC_SIGN="?"
fi

#
#  finally create the webpage
#
cd $TMPDIR ; mkdir netbsd
PAGE=netbsd/netbsd.html
cat > $PAGE <<- EOF
<!DOCTYPE html>
<html lang="en-US">
  <head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width">
    <title>NetBSD</title>
    <link rel='stylesheet' id='twentyfourteen-style-css'  href='landing_style.css?ver=4.0' type='text/css' media='all' />
  </head>
  <body>
    <div class="content">
      <div class="page-content">
EOF
write_page "       <h1>Reproducible NetBSD</h1>"
write_page_intro NetBSD
write_page "       <p>$GOOD_FILES ($GOOD_PERCENT%) out of $ALL_FILES built netbsd files were reproducible in our test setup"
if [ "$GOOD_PERCENT" = "100.0" ] ; then
	write_page "!"
else
	write_page ", while $BAD_FILES ($BAD_PERCENT%) failed to build from source."
fi
write_page "        These tests were last run on $DATE for version ${NETBSD_VERSION}.</p>"
write_explaination_table NetBSD
cat $FILES_HTML >> $PAGE
write_page "     <p><pre>"
echo -n "$NETBSD" >> $PAGE
write_page "     </pre></p>"
write_page "    </div></div>"
write_page_footer NetBSD
publish_page
rm -f $FILES_HTML 

# the end
calculate_build_duration
print_out_duration
irc_message "$REPRODUCIBLE_URL/netbsd/ has been updated. ($GOOD_PERCENT% reproducible)"
echo "============================================================================="

# remove everything, we don't need it anymore...
cleanup_tmpdirs
trap - INT TERM EXIT